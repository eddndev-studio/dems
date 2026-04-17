//! Integration tests for POST /auth/refresh.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{build_app, insert_user, token_for as mk_token};
use dems_api::auth::TokenKind;
use dems_core::models::UserRole;

async fn post_refresh(pool: PgPool, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri("/auth/refresh")
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let value: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, value)
}

fn token_for(id: Uuid, ttl: i64, kind: TokenKind) -> String {
    mk_token(id, UserRole::Jurado, ttl, kind)
}

#[sqlx::test(migrations = "../../migrations")]
async fn refresh_returns_new_access_token(pool: PgPool) {
    let id = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let refresh = token_for(id, 60, TokenKind::Refresh);

    let (status, body) = post_refresh(pool, json!({ "refresh_token": refresh })).await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["access_token"].is_string());
    // El nuevo access token debe ser distinto del refresh original y del
    // nuevo refresh (rotación opcional).
    assert_ne!(body["access_token"], json!(refresh));
}

#[sqlx::test(migrations = "../../migrations")]
async fn refresh_rejects_access_token(pool: PgPool) {
    let id = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let access = token_for(id, 60, TokenKind::Access);

    let (status, _) = post_refresh(pool, json!({ "refresh_token": access })).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn refresh_rejects_expired_token(pool: PgPool) {
    let id = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let refresh = token_for(id, -1, TokenKind::Refresh);

    let (status, _) = post_refresh(pool, json!({ "refresh_token": refresh })).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn refresh_rejects_deactivated_user(pool: PgPool) {
    let id = insert_user(&pool, "ex@x.mx", "Ex", "jurado", "pw", true).await;
    let refresh = token_for(id, 60, TokenKind::Refresh);
    sqlx::query("UPDATE users SET is_active = false WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .unwrap();

    let (status, _) = post_refresh(pool, json!({ "refresh_token": refresh })).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
