//! Integration tests for the admin-only gate. We use /admin/rubric-templates
//! as the canary route — any admin-scoped handler should be 403 for jurado,
//! 401 for no/invalid token, and reachable for admin.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use sqlx::PgPool;
use tower::ServiceExt;

use common::{admin, build_app, jurado};

async fn get_admin_rubrics(pool: PgPool, bearer: Option<&str>) -> StatusCode {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("GET")
        .uri("/admin/rubric-templates");
    if let Some(t) = bearer {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    app.oneshot(req.body(Body::empty()).unwrap())
        .await
        .unwrap()
        .status()
}

#[sqlx::test(migrations = "../../migrations")]
async fn admin_route_is_401_without_token(pool: PgPool) {
    let status = get_admin_rubrics(pool, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn admin_route_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let status = get_admin_rubrics(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn admin_route_is_reachable_for_admin(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let status = get_admin_rubrics(pool, Some(&tok)).await;
    // The handler is not implemented yet, but an admin must not be rejected
    // by the auth gate itself; anything other than 401/403 is acceptable
    // for this test.
    assert_ne!(status, StatusCode::UNAUTHORIZED);
    assert_ne!(status, StatusCode::FORBIDDEN);
}
