//! Integration tests for GET /admin/results/edition/:id/final (#20).
//!
//! Puntaje combinado ponderado por prototipo:
//!   puntaje_final = Σ_tipo (promedio_tipo / max_total_tipo) * (peso_tipo/100)
//! usando SÓLO rúbricas activas.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, build_app, insert_prototipo, insert_user, jurado, seed_edition, seed_rubric_template,
    seed_section_with_criterion, seed_submitted_evaluacion,
};

async fn get(pool: PgPool, path: &str, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder().method("GET").uri(path);
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app.oneshot(req.body(Body::empty()).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

/// Fija el peso de una rúbrica.
async fn set_peso(pool: &PgPool, template_id: Uuid, peso: i32) {
    sqlx::query("UPDATE rubric_templates SET peso = $2 WHERE id = $1")
        .bind(template_id)
        .bind(peso)
        .execute(pool)
        .await
        .unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn requires_auth(pool: PgPool) {
    let e = seed_edition(&pool, 2024).await;
    let (status, _) = get(pool, &format!("/admin/results/edition/{e}/final"), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn jurado_forbidden(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, _) = get(
        pool,
        &format!("/admin/results/edition/{e}/final"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn unknown_edition_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4();
    let (status, _) = get(
        pool,
        &format!("/admin/results/edition/{ghost}/final"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn combines_weighted_scores_and_ranks(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    // Exhibición: peso 60, max_total 6 (2 criterios x 3).
    let r_exhi = seed_rubric_template(&pool, e, "Exhi", "exhibicion").await;
    set_peso(&pool, r_exhi, 60).await;
    let (_, ce1) = seed_section_with_criterion(&pool, r_exhi, 1, "CE1", 3).await;
    let (_, ce2) = seed_section_with_criterion(&pool, r_exhi, 2, "CE2", 3).await;

    // Memoria: peso 50, max_total 3 (1 criterio x 3).
    let r_mem = seed_rubric_template(&pool, e, "Mem", "memoria").await;
    set_peso(&pool, r_mem, 50).await;
    let (_, cm1) = seed_section_with_criterion(&pool, r_mem, 1, "CM1", 3).await;

    let p_a = insert_prototipo(&pool, e, "F-A", "A").await;
    let p_b = insert_prototipo(&pool, e, "F-B", "B").await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;

    // A: exhibición total 6 (promedio 6/6=1.0 → aporte 1.0*0.6=0.6),
    //    memoria total 3 (promedio 3/3=1.0 → aporte 1.0*0.5=0.5) ⇒ 1.1
    seed_submitted_evaluacion(&pool, p_a, j, r_exhi, &[(ce1, 3), (ce2, 3)]).await;
    seed_submitted_evaluacion(&pool, p_a, j, r_mem, &[(cm1, 3)]).await;

    // B: exhibición total 3 (promedio 3/6=0.5 → aporte 0.5*0.6=0.3),
    //    sin memoria (aporte 0) ⇒ 0.3
    seed_submitted_evaluacion(&pool, p_b, j, r_exhi, &[(ce1, 2), (ce2, 1)]).await;

    let (status, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/final"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");

    let protos = body["prototipos"].as_array().expect("prototipos array");
    assert_eq!(protos.len(), 2);

    // Ranking desc: A (1.1) antes que B (0.3).
    assert_eq!(protos[0]["folio"], "F-A");
    let a_final = protos[0]["puntaje_final"].as_f64().unwrap();
    assert!((a_final - 1.1).abs() < 1e-9, "A puntaje_final = {a_final}");

    assert_eq!(protos[1]["folio"], "F-B");
    let b_final = protos[1]["puntaje_final"].as_f64().unwrap();
    assert!((b_final - 0.3).abs() < 1e-9, "B puntaje_final = {b_final}");

    // Desglose de A: 2 tipos, con su aporte.
    let desglose = protos[0]["desglose"].as_array().unwrap();
    assert_eq!(desglose.len(), 2);
    let exhi = desglose
        .iter()
        .find(|d| d["rubric_type"] == "exhibicion")
        .unwrap();
    assert_eq!(exhi["peso"], 60);
    assert_eq!(exhi["max_total"], 6);
    assert!((exhi["aporte"].as_f64().unwrap() - 0.6).abs() < 1e-9);

    // B sin memoria: aporte 0 y promedio null.
    let b_mem = protos[1]["desglose"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["rubric_type"] == "memoria")
        .unwrap();
    assert!(b_mem["promedio"].is_null());
    assert_eq!(b_mem["aporte"].as_f64().unwrap(), 0.0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn ignores_inactive_rubric(pool: PgPool) {
    // Una rúbrica inactiva no contribuye al puntaje final.
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    let r_active = seed_rubric_template(&pool, e, "Active", "exhibicion").await;
    set_peso(&pool, r_active, 60).await;
    let (_, ca) = seed_section_with_criterion(&pool, r_active, 1, "CA", 3).await;

    let r_old = seed_rubric_template(&pool, e, "Old", "exhibicion").await;
    sqlx::query("UPDATE rubric_templates SET activo = false WHERE id = $1")
        .bind(r_old)
        .execute(&pool)
        .await
        .unwrap();
    let (_, co) = seed_section_with_criterion(&pool, r_old, 1, "CO", 3).await;

    let p = insert_prototipo(&pool, e, "F", "P").await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    // Evaluación contra la activa (cuenta) y contra la inactiva (ignorada).
    seed_submitted_evaluacion(&pool, p, j, r_active, &[(ca, 3)]).await;
    seed_submitted_evaluacion(&pool, p, j, r_old, &[(co, 0)]).await;

    let (status, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/final"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    // promedio 3/3 = 1.0, peso 60 ⇒ 0.6.
    let final_score = body["prototipos"][0]["puntaje_final"].as_f64().unwrap();
    assert!((final_score - 0.6).abs() < 1e-9, "got {final_score}");
}
