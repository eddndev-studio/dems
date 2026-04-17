//! Integration tests for admin CRUD on /admin/editions.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, jurado, seed_edition, seed_rubric_template};

async fn request(
    pool: PgPool,
    method: &str,
    path: &str,
    tok: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json");
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let body = match body {
        Some(v) => Body::from(v.to_string()),
        None => Body::empty(),
    };
    let resp = app.oneshot(req.body(body).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_edition(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (status, body) = request(
        pool,
        "POST",
        "/admin/editions",
        Some(&tok),
        Some(json!({ "year": 2025, "name": "Edición 2025", "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert_eq!(body["year"], 2025);
    assert_eq!(body["active"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_duplicate_year(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let _ = seed_edition(&pool, 2024).await;

    let (status, _) = request(
        pool,
        "POST",
        "/admin/editions",
        Some(&tok),
        Some(json!({ "year": 2024, "name": "dup" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn activate_only_one_edition_at_a_time(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e1 = seed_edition(&pool, 2024).await;
    let e2 = seed_edition(&pool, 2025).await;

    // Activamos la 2024.
    let (s1, _) = request(
        pool.clone(),
        "PATCH",
        &format!("/admin/editions/{e1}"),
        Some(&tok),
        Some(json!({ "active": true })),
    )
    .await;
    assert_eq!(s1, StatusCode::OK);

    // Al activar la 2025, la 2024 queda inactiva automáticamente.
    let (s2, body) = request(
        pool.clone(),
        "PATCH",
        &format!("/admin/editions/{e2}"),
        Some(&tok),
        Some(json!({ "active": true })),
    )
    .await;
    assert_eq!(s2, StatusCode::OK, "body: {body}");
    assert_eq!(body["active"], true);

    // 2024 ahora es inactiva.
    let (_, body1) = request(
        pool,
        "GET",
        &format!("/admin/editions/{e1}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(body1["active"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_editions(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let _ = seed_edition(&pool, 2024).await;
    let _ = seed_edition(&pool, 2025).await;

    let (status, body) = request(pool, "GET", "/admin/editions", Some(&tok), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_edition_with_no_references(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, _) = request(
        pool,
        "DELETE",
        &format!("/admin/editions/{e}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_edition_rejected_when_has_rubrics(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let _ = seed_rubric_template(&pool, e, "R", "exhibicion").await;

    let (status, _) = request(
        pool,
        "DELETE",
        &format!("/admin/editions/{e}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn editions_crud_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let (s1, _) = request(
        pool.clone(),
        "POST",
        "/admin/editions",
        Some(&tok),
        Some(json!({ "year": 2025, "name": "x" })),
    )
    .await;
    assert_eq!(s1, StatusCode::FORBIDDEN);
    let (s2, _) = request(pool, "GET", "/admin/editions", Some(&tok), None).await;
    assert_eq!(s2, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_updates_name(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, body) = request(
        pool,
        "PATCH",
        &format!("/admin/editions/{e}"),
        Some(&tok),
        Some(json!({ "name": "Renombrada" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["name"], "Renombrada");
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_unknown_edition_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4();
    let (status, _) = request(
        pool,
        "GET",
        &format!("/admin/editions/{ghost}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
