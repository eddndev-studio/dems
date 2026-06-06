//! Integration tests for PUT /admin/rubric-templates/:id/structure
//! (full-tree replace; gated on the edition phase = preparacion).

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, build_app, jurado, seed_categoria, seed_edition, seed_rubric_template,
    seed_section_with_criterion, set_edition_phase,
};

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

fn tree(cat: Uuid) -> Value {
    json!({
        "categorias": [cat],
        "sections": [
            {
                "nombre": "Aplicabilidad",
                "orden": 1,
                "peso_pct": 60.0,
                "criteria": [
                    { "texto": "Funciona.", "orden": 1, "max_score": 3, "kind": "scale" },
                    { "texto": "Probado.", "orden": 2, "max_score": 3, "kind": "scale" }
                ]
            },
            {
                "nombre": "Cartel",
                "orden": 2,
                "peso_pct": 40.0,
                "criteria": [
                    { "texto": "Creativo.", "orden": 1, "max_score": 1, "kind": "boolean" }
                ]
            }
        ]
    })
}

#[sqlx::test(migrations = "../../migrations")]
async fn replace_succeeds_in_preparacion(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let tpl = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    // Estructura previa que debe ser reemplazada por completo.
    seed_section_with_criterion(&pool, tpl, 1, "Vieja", 3).await;
    let cat = seed_categoria(&pool, "software", "Software").await;

    let (status, body) = request(
        pool.clone(),
        "PUT",
        &format!("/admin/rubric-templates/{tpl}/structure"),
        Some(&tok),
        Some(tree(cat)),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["editable"], true);
    let sections = body["sections"].as_array().unwrap();
    assert_eq!(sections.len(), 2);
    assert_eq!(sections[0]["nombre"], "Aplicabilidad");
    assert_eq!(sections[0]["peso_pct"], 60.0);
    assert_eq!(sections[0]["criteria"].as_array().unwrap().len(), 2);
    assert_eq!(body["categorias"][0], json!(cat));

    // La sección vieja desapareció: exactamente 2 secciones quedan en DB.
    let sec_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM rubric_sections WHERE template_id = $1")
            .bind(tpl)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(sec_count, 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn replace_blocked_when_edition_in_evaluacion(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let tpl = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let cat = seed_categoria(&pool, "software", "Software").await;
    set_edition_phase(&pool, e, "evaluacion").await;

    let (status, _) = request(
        pool.clone(),
        "PUT",
        &format!("/admin/rubric-templates/{tpl}/structure"),
        Some(&tok),
        Some(tree(cat)),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Y la rúbrica se reporta como no editable.
    let (_, body) = request(
        pool,
        "GET",
        &format!("/admin/rubric-templates/{tpl}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(body["editable"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn replace_rejects_empty_section_name(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let tpl = seed_rubric_template(&pool, e, "R", "exhibicion").await;

    let (status, _) = request(
        pool,
        "PUT",
        &format!("/admin/rubric-templates/{tpl}/structure"),
        Some(&tok),
        Some(json!({
            "categorias": [],
            "sections": [{ "nombre": "", "orden": 1, "criteria": [] }]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn replace_rejects_bad_max_score(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let tpl = seed_rubric_template(&pool, e, "R", "exhibicion").await;

    let (status, _) = request(
        pool,
        "PUT",
        &format!("/admin/rubric-templates/{tpl}/structure"),
        Some(&tok),
        Some(json!({
            "categorias": [],
            "sections": [{
                "nombre": "S", "orden": 1,
                "criteria": [{ "texto": "x", "orden": 1, "max_score": 101, "kind": "scale" }]
            }]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn replace_rejects_duplicate_section_orden(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let tpl = seed_rubric_template(&pool, e, "R", "exhibicion").await;

    let (status, _) = request(
        pool.clone(),
        "PUT",
        &format!("/admin/rubric-templates/{tpl}/structure"),
        Some(&tok),
        Some(json!({
            "categorias": [],
            "sections": [
                { "nombre": "A", "orden": 1, "criteria": [] },
                { "nombre": "B", "orden": 1, "criteria": [] }
            ]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Rollback: la rúbrica sigue sin secciones.
    let sec_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM rubric_sections WHERE template_id = $1")
            .bind(tpl)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(sec_count, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn replace_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let tpl = seed_rubric_template(&pool, e, "R", "exhibicion").await;

    let (status, _) = request(
        pool,
        "PUT",
        &format!("/admin/rubric-templates/{tpl}/structure"),
        Some(&tok),
        Some(json!({ "categorias": [], "sections": [] })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn replace_unknown_template_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4();

    let (status, _) = request(
        pool,
        "PUT",
        &format!("/admin/rubric-templates/{ghost}/structure"),
        Some(&tok),
        Some(json!({ "categorias": [], "sections": [] })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
