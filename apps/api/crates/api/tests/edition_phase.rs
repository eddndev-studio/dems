//! Integration tests for the edition phase state machine
//! (POST /admin/editions/:id/phase).

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, build_app, jurado, seed_edition, seed_rubric_template, seed_section_with_criterion,
    seed_submitted_evaluacion, set_edition_phase,
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

#[sqlx::test(migrations = "../../migrations")]
async fn new_edition_defaults_to_preparacion(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (status, body) = request(
        pool,
        "POST",
        "/admin/editions",
        Some(&tok),
        Some(json!({ "year": 2025, "name": "Edición 2025" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert_eq!(body["phase"], "preparacion");
}

#[sqlx::test(migrations = "../../migrations")]
async fn advance_preparacion_to_evaluacion(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    let (status, body) = request(
        pool,
        "POST",
        &format!("/admin/editions/{e}/phase"),
        Some(&tok),
        Some(json!({ "phase": "evaluacion" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["phase"], "evaluacion");
}

#[sqlx::test(migrations = "../../migrations")]
async fn advance_evaluacion_to_cerrada(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;

    let (status, body) = request(
        pool,
        "POST",
        &format!("/admin/editions/{e}/phase"),
        Some(&tok),
        Some(json!({ "phase": "cerrada" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["phase"], "cerrada");
}

#[sqlx::test(migrations = "../../migrations")]
async fn reject_non_adjacent_jump(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    // preparacion -> cerrada salta evaluacion: no permitido.
    let (status, _) = request(
        pool,
        "POST",
        &format!("/admin/editions/{e}/phase"),
        Some(&tok),
        Some(json!({ "phase": "cerrada" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn reopen_allowed_without_evaluaciones(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;

    let (status, body) = request(
        pool,
        "POST",
        &format!("/admin/editions/{e}/phase"),
        Some(&tok),
        Some(json!({ "phase": "preparacion" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["phase"], "preparacion");
}

#[sqlx::test(migrations = "../../migrations")]
async fn reopen_blocked_when_evaluaciones_exist(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (jid, _) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let tpl = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, crit) = seed_section_with_criterion(&pool, tpl, 1, "C", 3).await;
    let proto = common::insert_prototipo(&pool, e, "F-01", "Proto").await;
    seed_submitted_evaluacion(&pool, proto, jid, tpl, &[(crit, 3)]).await;
    set_edition_phase(&pool, e, "evaluacion").await;

    let (status, _) = request(
        pool,
        "POST",
        &format!("/admin/editions/{e}/phase"),
        Some(&tok),
        Some(json!({ "phase": "preparacion" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn set_phase_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, _) = request(
        pool,
        "POST",
        &format!("/admin/editions/{e}/phase"),
        Some(&tok),
        Some(json!({ "phase": "evaluacion" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn set_phase_unknown_edition_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4();
    let (status, _) = request(
        pool,
        "POST",
        &format!("/admin/editions/{ghost}/phase"),
        Some(&tok),
        Some(json!({ "phase": "evaluacion" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
