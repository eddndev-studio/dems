//! Integration tests for POST /auth/login.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;

use common::{build_app, insert_user};

async fn post_login(pool: PgPool, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri("/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let value: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, value)
}

#[sqlx::test(migrations = "../../migrations")]
async fn login_returns_tokens_on_valid_credentials(pool: PgPool) {
    let user_id = insert_user(
        &pool,
        "jurado@dems.local",
        "Jurado Uno",
        "jurado",
        "super-secreto",
        true,
    )
    .await;

    let (status, body) = post_login(
        pool,
        json!({ "email": "jurado@dems.local", "password": "super-secreto" }),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert!(body["access_token"].is_string(), "body: {body}");
    assert!(body["refresh_token"].is_string(), "body: {body}");
    assert_eq!(body["user"]["id"], user_id.to_string());
    assert_eq!(body["user"]["role"], "jurado");
    assert_eq!(body["user"]["email"], "jurado@dems.local");
    // Nunca filtrar el hash.
    assert!(
        body.get("password_hash").is_none() && body["user"].get("password_hash").is_none(),
        "password hash must not leak: {body}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn login_rejects_wrong_password(pool: PgPool) {
    insert_user(
        &pool,
        "admin@dems.local",
        "Admin",
        "admin",
        "correcto",
        true,
    )
    .await;

    let (status, _) = post_login(
        pool,
        json!({ "email": "admin@dems.local", "password": "incorrecto" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn login_rejects_unknown_email(pool: PgPool) {
    let (status, _) = post_login(
        pool,
        json!({ "email": "nadie@dems.local", "password": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn login_rejects_inactive_user(pool: PgPool) {
    insert_user(
        &pool,
        "ex@dems.local",
        "Ex Jurado",
        "jurado",
        "pw",
        false, // inactivo
    )
    .await;

    let (status, _) = post_login(pool, json!({ "email": "ex@dems.local", "password": "pw" })).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn login_requires_email_and_password(pool: PgPool) {
    let (status, _) = post_login(pool, json!({ "email": "x@y.z" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}
