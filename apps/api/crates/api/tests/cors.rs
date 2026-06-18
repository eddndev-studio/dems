//! Integration test for the CORS layer (#10).
//!
//! La auth es por Bearer (sin cookies) ⇒ no hay CSRF ⇒ AllowOrigin::any es
//! seguro y desbloquea el build web y la LAN.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use sqlx::PgPool;
use tower::ServiceExt;

use common::build_app;

#[sqlx::test(migrations = "../../migrations")]
async fn responses_carry_permissive_cors_header(pool: PgPool) {
    let app = build_app(pool);
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/healthz")
                .header("origin", "https://app.example.com")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let allow_origin = resp
        .headers()
        .get("access-control-allow-origin")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();
    assert_eq!(allow_origin, "*", "expected permissive CORS allow-origin");
}

#[sqlx::test(migrations = "../../migrations")]
async fn preflight_options_is_allowed(pool: PgPool) {
    let app = build_app(pool);
    let resp = app
        .oneshot(
            Request::builder()
                .method("OPTIONS")
                .uri("/evaluaciones")
                .header("origin", "https://app.example.com")
                .header("access-control-request-method", "POST")
                .header(
                    "access-control-request-headers",
                    "authorization,content-type",
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    // tower_http::cors responde el preflight con 200 y los headers permitidos.
    assert!(
        resp.status().is_success(),
        "preflight rejected: {:?}",
        resp.status()
    );
    let allow_origin = resp
        .headers()
        .get("access-control-allow-origin")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();
    assert_eq!(allow_origin, "*");
}
