//! Integration tests for POST /auth/refresh.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, insert_user, token_for as mk_token, token_for_version};
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
async fn refresh_rejects_token_after_password_reset(pool: PgPool) {
    // #9: tras un reset de contraseña (que incrementa token_version), el
    // refresh viejo (con la versión anterior en su claim) deja de servir.
    let (_, atok) = admin(&pool).await;
    let uid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw12345678", true).await;
    // Refresh emitido con token_version actual (0).
    let old_refresh = token_for(uid, 60, TokenKind::Refresh);

    // Admin resetea la contraseña vía endpoint → token_version pasa a 1.
    let app = build_app(pool.clone());
    let reset = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/admin/users/{uid}/password"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {atok}"))
                .body(Body::from(
                    json!({ "password": "nuevapass123" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(reset.status(), StatusCode::NO_CONTENT);

    // El refresh viejo ya no vale.
    let (status, _) = post_refresh(pool, json!({ "refresh_token": old_refresh })).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn refresh_rejects_stale_token_version(pool: PgPool) {
    // Refresh con un token_version desfasado (el usuario está en 2) → 401.
    let uid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    sqlx::query("UPDATE users SET token_version = 2 WHERE id = $1")
        .bind(uid)
        .execute(&pool)
        .await
        .unwrap();
    let stale = token_for_version(uid, UserRole::Jurado, 60, TokenKind::Refresh, 1);

    let (status, _) = post_refresh(pool, json!({ "refresh_token": stale })).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn refresh_accepts_token_with_current_version(pool: PgPool) {
    // El refresh cuya versión coincide con users.token_version sigue → 200.
    let uid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    sqlx::query("UPDATE users SET token_version = 5 WHERE id = $1")
        .bind(uid)
        .execute(&pool)
        .await
        .unwrap();
    let fresh = token_for_version(uid, UserRole::Jurado, 60, TokenKind::Refresh, 5);

    let (status, body) = post_refresh(pool, json!({ "refresh_token": fresh })).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["access_token"].is_string());
    assert!(body["refresh_token"].is_string());
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
