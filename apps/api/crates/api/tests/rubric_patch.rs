//! Integration tests for PATCH /admin/rubric-templates/:id.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, jurado, seed_edition};

async fn post_create(pool: PgPool, tok: &str, body: Value) -> Value {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri("/admin/rubric-templates")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    serde_json::from_slice(&resp.into_body().collect().await.unwrap().to_bytes()).unwrap()
}

async fn patch(pool: PgPool, id: &str, tok: Option<&str>, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("PATCH")
        .uri(format!("/admin/rubric-templates/{id}"))
        .header("content-type", "application/json");
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app
        .oneshot(req.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_updates_nombre(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": edition_id, "nombre": "Original", "tipo": "exhibicion" }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, body) = patch(
        pool.clone(),
        &id,
        Some(&tok),
        json!({ "nombre": "Editado" }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["nombre"], "Editado");
    assert_eq!(body["id"], json!(id));
    // activo no se tocó — sigue siendo true.
    assert_eq!(body["activo"], true);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_updates_activo_and_descripcion(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": edition_id, "nombre": "R", "tipo": "exhibicion" }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, body) = patch(
        pool,
        &id,
        Some(&tok),
        json!({ "activo": false, "descripcion": "archivada" }),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["activo"], false);
    assert_eq!(body["descripcion"], "archivada");
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_empty_body_returns_current_state(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": edition_id, "nombre": "R", "tipo": "exhibicion" }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, body) = patch(pool, &id, Some(&tok), json!({})).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["nombre"], "R");
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_returns_404_for_unknown_id(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4().to_string();
    let (status, _) = patch(pool, &ghost, Some(&tok), json!({ "nombre": "x" })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_is_403_for_jurado(pool: PgPool) {
    let (_, admin_tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &admin_tok,
        json!({ "edition_id": edition_id, "nombre": "R", "tipo": "exhibicion" }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (_, j_tok) = jurado(&pool).await;
    let (status, _) = patch(pool, &id, Some(&j_tok), json!({ "nombre": "x" })).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_rejects_empty_nombre(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": edition_id, "nombre": "R", "tipo": "exhibicion" }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, _) = patch(pool, &id, Some(&tok), json!({ "nombre": "" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}
