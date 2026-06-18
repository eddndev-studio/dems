//! Integration tests for GET /me (auth middleware + current user endpoint).

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use serde_json::json;

use common::{admin, build_app, insert_user, token_for};
use dems_api::auth::TokenKind;
use dems_core::models::UserRole;

async fn get_me(pool: PgPool, bearer: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder().method("GET").uri("/me");
    if let Some(t) = bearer {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app.oneshot(req.body(Body::empty()).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let value: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, value)
}

#[sqlx::test(migrations = "../../migrations")]
async fn me_requires_authorization_header(pool: PgPool) {
    let (status, _) = get_me(pool, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn me_rejects_malformed_bearer(pool: PgPool) {
    let (status, _) = get_me(pool, Some("not-a-jwt")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn me_rejects_expired_token(pool: PgPool) {
    let id = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let tok = token_for(id, UserRole::Jurado, -1, TokenKind::Access);
    let (status, _) = get_me(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn me_rejects_refresh_token(pool: PgPool) {
    let id = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let tok = token_for(id, UserRole::Jurado, 60, TokenKind::Refresh);
    let (status, _) = get_me(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn me_returns_current_user(pool: PgPool) {
    let id = insert_user(&pool, "a@dems.mx", "Ada Jurado", "jurado", "pw", true).await;
    let tok = token_for(id, UserRole::Jurado, 60, TokenKind::Access);
    let (status, body) = get_me(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["id"], id.to_string());
    assert_eq!(body["email"], "a@dems.mx");
    assert_eq!(body["full_name"], "Ada Jurado");
    assert_eq!(body["role"], "jurado");
}

#[sqlx::test(migrations = "../../migrations")]
async fn me_rejects_token_for_deactivated_user(pool: PgPool) {
    // Token emitido mientras activo; luego el admin desactiva al usuario.
    let id = insert_user(&pool, "ex@dems.mx", "Ex", "jurado", "pw", true).await;
    let tok = token_for(id, UserRole::Jurado, 60, TokenKind::Access);
    sqlx::query("UPDATE users SET is_active = false WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .unwrap();

    let (status, _) = get_me(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn me_rejects_access_token_after_password_reset(pool: PgPool) {
    // #9: el access token se revoca DE INMEDIATO al resetear la contraseña.
    // token_for emite con token_version 0; el reset lo lleva a 1, así que el
    // claim viejo deja de coincidir y el extractor responde 401 sin esperar el
    // TTL ni un refresh.
    let (_, atok) = admin(&pool).await;
    let uid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw12345678", true).await;
    let old_access = token_for(uid, UserRole::Jurado, 900, TokenKind::Access);

    // Sanity: antes del reset el access token sirve.
    let (before, _) = get_me(pool.clone(), Some(&old_access)).await;
    assert_eq!(before, StatusCode::OK);

    // Admin resetea la contraseña → token_version pasa a 1.
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

    // El access token viejo ya no vale.
    let (after, _) = get_me(pool, Some(&old_access)).await;
    assert_eq!(after, StatusCode::UNAUTHORIZED);
}
