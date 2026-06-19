//! Verifica que VARIOS jurados pueden evaluar el MISMO prototipo y que el
//! resultado promedia entre ellos.
//!
//! Origen: reporte "la app solo permite que un jurado evalúe el prototipo".
//! La unicidad de `evaluaciones` es por terna `(prototipo, jurado, template)`,
//! es decir **por jurado** — dos jurados distintos NO chocan. El mensaje de la
//! violación de unicidad ("evaluation already exists for this prototipo/
//! template") puede leerse mal, pero sólo dispara para el MISMO jurado.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;

use common::{
    admin, assign_jurado, attach_categoria, build_app, insert_prototipo, insert_user,
    seed_categoria, seed_edition, seed_rubric_template, seed_section_with_criterion,
    set_edition_phase, token_for,
};
use dems_core::models::UserRole;

async fn request(
    pool: PgPool,
    method: &str,
    path: &str,
    tok: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json");
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let body = match body {
        Some(v) => Body::from(v.to_string()),
        None => Body::empty(),
    };
    let resp = app.oneshot(req.body(body).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

#[sqlx::test(migrations = "../../migrations")]
async fn dos_jurados_evaluan_el_mismo_prototipo_y_se_promedia(pool: PgPool) {
    // --- Edición en fase de evaluación con un prototipo y una rúbrica con un
    //     criterio (máx 10), en una categoría. ---
    let e = seed_edition(&pool, 2026).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "APE001", "Proto").await;
    let r = seed_rubric_template(&pool, e, "Exhibición", "exhibicion").await;
    let (_sec, crit) = seed_section_with_criterion(&pool, r, 1, "Innovación", 10).await;
    let cat = seed_categoria(&pool, "aplicacion-empresa", "Aplicación Empresa").await;
    attach_categoria(&pool, p, cat).await;

    // --- Tres jurados, todos asignados al MISMO (prototipo, template). ---
    let j1 = insert_user(&pool, "j1@x.mx", "Jurado Uno", "jurado", "pw", true).await;
    let j2 = insert_user(&pool, "j2@x.mx", "Jurado Dos", "jurado", "pw", true).await;
    let j3 = insert_user(&pool, "j3@x.mx", "Jurado Tres", "jurado", "pw", true).await;
    for j in [j1, j2, j3] {
        assign_jurado(&pool, j, p, r).await;
    }
    let t1 = token_for(j1, UserRole::Jurado, 900, dems_api::auth::TokenKind::Access);
    let t2 = token_for(j2, UserRole::Jurado, 900, dems_api::auth::TokenKind::Access);
    let t3 = token_for(j3, UserRole::Jurado, 900, dems_api::auth::TokenKind::Access);

    // --- Cada jurado CREA su evaluación del mismo prototipo. El 2.º y 3.º NO
    //     deben recibir 409: la unicidad es por jurado. ---
    let mut eval_ids = Vec::new();
    for (tok, score) in [(&t1, 8), (&t2, 6), (&t3, 10)] {
        let (status, body) = request(
            pool.clone(),
            "POST",
            "/evaluaciones",
            Some(tok),
            Some(json!({
                "prototipo_id": p,
                "template_id": r,
                "scores": [{ "criterion_id": crit, "score": score }],
            })),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::CREATED,
            "el jurado debería poder crear su evaluación; body: {body}"
        );
        eval_ids.push(body["id"].as_str().unwrap().to_string());
    }
    // Tres evaluaciones distintas para el mismo prototipo.
    assert_eq!(eval_ids.len(), 3);
    assert_eq!(
        eval_ids
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len(),
        3,
        "las tres evaluaciones deben ser distintas"
    );

    // --- Marcamos las tres como enviadas (submitted) para que cuenten en el
    //     ranking, y consultamos resultados. ---
    sqlx::query("UPDATE evaluaciones SET submitted_at = NOW() WHERE prototipo_id = $1")
        .bind(p)
        .execute(&pool)
        .await
        .unwrap();

    let (_, tok_admin) = admin(&pool).await;
    let (status, body) = request(
        pool.clone(),
        "GET",
        &format!(
            "/admin/results/categoria/aplicacion-empresa?edition_id={e}&rubric_type=exhibicion"
        ),
        Some(&tok_admin),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");

    let proto = &body["prototipos"][0];
    assert_eq!(proto["n_jurados"], json!(3), "deben contarse los 3 jurados");
    // Promedio = (8 + 6 + 10) / 3 = 8.0
    assert_eq!(proto["promedio"], json!(8.0), "promedio de los 3 totales");
}
