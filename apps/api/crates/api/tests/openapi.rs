//! Integration tests for the OpenAPI document and Swagger UI mount.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;

use common::build_app;

async fn get(pool: PgPool, path: &str) -> (StatusCode, String, Value) {
    let app = build_app(pool);
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(path)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let ct = resp
        .headers()
        .get("content-type")
        .map(|v| v.to_str().unwrap_or("").to_string())
        .unwrap_or_default();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let json = serde_json::from_slice::<Value>(&bytes).unwrap_or(Value::Null);
    (status, ct, json)
}

#[sqlx::test(migrations = "../../migrations")]
async fn openapi_json_is_served(pool: PgPool) {
    let (status, ct, body) = get(pool, "/openapi.json").await;
    assert_eq!(status, StatusCode::OK);
    assert!(ct.starts_with("application/json"), "ct: {ct}");
    assert!(body["openapi"].as_str().unwrap_or("").starts_with("3."));
    assert_eq!(body["info"]["title"], "DEMS API");
    assert!(body["info"]["version"].is_string());
}

#[sqlx::test(migrations = "../../migrations")]
async fn openapi_includes_known_paths(pool: PgPool) {
    let (status, _, body) = get(pool, "/openapi.json").await;
    assert_eq!(status, StatusCode::OK);
    let paths = body["paths"].as_object().expect("paths object");
    // Sanidad: hay al menos un puñado de paths anotados.
    assert!(paths.contains_key("/auth/login"), "missing /auth/login");
    assert!(paths.contains_key("/me"), "missing /me");
    assert!(paths.contains_key("/evaluaciones"), "missing /evaluaciones");
    assert!(
        paths.contains_key("/admin/results/categoria/{slug}"),
        "missing results path: {:?}",
        paths.keys().collect::<Vec<_>>()
    );
}
