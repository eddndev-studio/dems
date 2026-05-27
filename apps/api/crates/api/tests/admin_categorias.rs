//! Integration tests for GET /admin/categorias.
//!
//! Admin UI needs the full catalog (id + slug + nombre + orden) to populate
//! the multi-select on the prototipos form. The endpoint returns rows sorted
//! by `orden` so the UI doesn't have to re-sort.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;

use common::{admin, build_app, jurado, seed_categoria};

async fn get(pool: PgPool, path: &str, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder().method("GET").uri(path);
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app.oneshot(req.body(Body::empty()).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_returns_catalog_ordered(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    // Insert out of order on purpose; endpoint must sort by `orden`.
    sqlx::query("INSERT INTO categorias (slug, nombre, orden) VALUES ('b', 'Beta', 2)")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO categorias (slug, nombre, orden) VALUES ('a', 'Alpha', 1)")
        .execute(&pool)
        .await
        .unwrap();

    let (status, body) = get(pool, "/admin/categorias", Some(&tok)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["slug"], "a");
    assert_eq!(items[0]["nombre"], "Alpha");
    assert_eq!(items[0]["orden"], 1);
    assert!(items[0]["id"].is_string());
    assert_eq!(items[1]["slug"], "b");
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_empty_when_no_categorias(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (status, body) = get(pool, "/admin/categorias", Some(&tok)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_requires_admin(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let _ = seed_categoria(&pool, "x", "X").await;
    let (status, _) = get(pool, "/admin/categorias", Some(&tok)).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_requires_auth(pool: PgPool) {
    let (status, _) = get(pool, "/admin/categorias", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
