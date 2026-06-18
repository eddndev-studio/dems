//! Integration tests for the `peso` field on rubric templates (#20 contract).
//!
//! CONTRATO #20: la clave JSON `"peso"` (entero 0..100) aparece en create,
//! patch, get y list. Default 100 si se omite en create.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;

use common::{admin, build_app, seed_edition};

async fn send(pool: PgPool, method: &str, uri: &str, tok: &str, body: Option<Value>) -> Value {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {tok}"));
    let body = match body {
        Some(b) => {
            req = req.header("content-type", "application/json");
            Body::from(b.to_string())
        }
        None => Body::empty(),
    };
    let resp = app.oneshot(req.body(body).unwrap()).await.unwrap();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_defaults_peso_to_100(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    let body = send(
        pool.clone(),
        "POST",
        "/admin/rubric-templates",
        &tok,
        Some(json!({ "edition_id": e, "nombre": "R", "tipo": "exhibicion" })),
    )
    .await;
    assert_eq!(body["peso"], 100, "default peso must be 100: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_accepts_explicit_peso(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    let body = send(
        pool.clone(),
        "POST",
        "/admin/rubric-templates",
        &tok,
        Some(json!({ "edition_id": e, "nombre": "R", "tipo": "exhibicion", "peso": 60 })),
    )
    .await;
    assert_eq!(body["peso"], 60);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_peso_out_of_range(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    let app = build_app(pool);
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/admin/rubric-templates")
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {tok}"))
                .body(Body::from(
                    json!({ "edition_id": e, "nombre": "R", "tipo": "exhibicion", "peso": 101 })
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_changes_peso_and_get_reflects_it(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    let created = send(
        pool.clone(),
        "POST",
        "/admin/rubric-templates",
        &tok,
        Some(json!({ "edition_id": e, "nombre": "R", "tipo": "memoria", "peso": 50 })),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    // PATCH peso=70.
    let patched = send(
        pool.clone(),
        "PATCH",
        &format!("/admin/rubric-templates/{id}"),
        &tok,
        Some(json!({ "peso": 70 })),
    )
    .await;
    assert_eq!(patched["peso"], 70);

    // GET refleja el nuevo peso.
    let got = send(
        pool,
        "GET",
        &format!("/admin/rubric-templates/{id}"),
        &tok,
        None,
    )
    .await;
    assert_eq!(got["peso"], 70);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_includes_peso(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    send(
        pool.clone(),
        "POST",
        "/admin/rubric-templates",
        &tok,
        Some(json!({ "edition_id": e, "nombre": "R", "tipo": "exhibicion", "peso": 60 })),
    )
    .await;

    let list = send(
        pool,
        "GET",
        &format!("/admin/rubric-templates?edition_id={e}"),
        &tok,
        None,
    )
    .await;
    let arr = list.as_array().expect("list array");
    assert_eq!(arr.len(), 1);
    assert_eq!(arr[0]["peso"], 60, "list must expose peso: {list}");
}
