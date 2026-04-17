//! Integration tests for POST /admin/rubric-templates.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;

use common::{admin, build_app, jurado, seed_edition};

async fn post_create(
    pool: PgPool,
    bearer: Option<&str>,
    body: Value,
) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("POST")
        .uri("/admin/rubric-templates")
        .header("content-type", "application/json");
    if let Some(t) = bearer {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app
        .oneshot(req.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let value: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, value)
}

#[sqlx::test(migrations = "../../migrations")]
async fn admin_creates_minimal_rubric(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;

    let (status, body) = post_create(
        pool,
        Some(&tok),
        json!({
            "edition_id": edition_id,
            "nombre": "Rúbrica de prueba",
            "tipo": "exhibicion"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert!(body["id"].is_string());
    assert_eq!(body["edition_id"], json!(edition_id));
    assert_eq!(body["nombre"], "Rúbrica de prueba");
    assert_eq!(body["tipo"], "exhibicion");
    assert_eq!(body["activo"], true);
    assert!(body["sections"].is_array());
    assert_eq!(body["sections"].as_array().unwrap().len(), 0);
    assert!(body["categorias"].is_array());
}

#[sqlx::test(migrations = "../../migrations")]
async fn admin_creates_memoria_type(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;

    let (status, body) = post_create(
        pool,
        Some(&tok),
        json!({ "edition_id": edition_id, "nombre": "Memoria", "tipo": "memoria" }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body["tipo"], "memoria");
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_unknown_edition(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = uuid::Uuid::new_v4();

    let (status, _) = post_create(
        pool,
        Some(&tok),
        json!({ "edition_id": ghost, "nombre": "x", "tipo": "exhibicion" }),
    )
    .await;

    // Edición fantasma: 422 (payload inválido a nivel de integridad).
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_invalid_tipo(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;

    let (status, _) = post_create(
        pool,
        Some(&tok),
        json!({ "edition_id": edition_id, "nombre": "x", "tipo": "cartel" }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_missing_nombre(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;

    let (status, _) = post_create(
        pool,
        Some(&tok),
        json!({ "edition_id": edition_id, "tipo": "exhibicion" }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;

    let (status, _) = post_create(
        pool,
        Some(&tok),
        json!({ "edition_id": edition_id, "nombre": "x", "tipo": "exhibicion" }),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_is_401_without_token(pool: PgPool) {
    let edition_id = seed_edition(&pool, 2024).await;
    let (status, _) = post_create(
        pool,
        None,
        json!({ "edition_id": edition_id, "nombre": "x", "tipo": "exhibicion" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
