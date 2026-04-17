//! Integration tests for GET /admin/rubric-templates.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, seed_edition};

async fn post_create(pool: PgPool, tok: &str, body: Value) -> Value {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri("/admin/rubric-templates")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

async fn list_rubrics(pool: PgPool, tok: &str, qs: &str) -> (StatusCode, Value) {
    let app = build_app(pool);
    let uri = if qs.is_empty() {
        "/admin/rubric-templates".to_string()
    } else {
        format!("/admin/rubric-templates?{qs}")
    };
    let req = Request::builder()
        .method("GET")
        .uri(uri)
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::empty())
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let body: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, body)
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_empty_when_no_templates(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (status, body) = list_rubrics(pool, &tok, "").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_returns_summaries_not_tree(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let _ = post_create(
        pool.clone(),
        &tok,
        json!({
            "edition_id": edition_id,
            "nombre": "Con secciones",
            "tipo": "exhibicion",
            "sections": [{
                "nombre": "A", "orden": 1,
                "criteria": [
                    { "texto": "x", "orden": 1, "max_score": 3, "kind": "scale" }
                ]
            }]
        }),
    )
    .await;

    let (status, body) = list_rubrics(pool, &tok, "").await;
    assert_eq!(status, StatusCode::OK);
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 1);
    let item = &items[0];
    assert!(item["id"].is_string());
    assert_eq!(item["nombre"], "Con secciones");
    assert_eq!(item["tipo"], "exhibicion");
    // Conteo, no árbol completo.
    assert_eq!(item["section_count"], 1);
    assert_eq!(item["criterion_count"], 1);
    assert!(item.get("sections").is_none(), "list must not embed the full tree");
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_filters_by_edition(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e1 = seed_edition(&pool, 2024).await;
    let e2 = seed_edition(&pool, 2025).await;
    let _ = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": e1, "nombre": "R-24", "tipo": "exhibicion" }),
    )
    .await;
    let _ = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": e2, "nombre": "R-25", "tipo": "exhibicion" }),
    )
    .await;

    let (status, body) =
        list_rubrics(pool, &tok, &format!("edition_id={e1}")).await;
    assert_eq!(status, StatusCode::OK);
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["nombre"], "R-24");
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_filters_by_tipo(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let _ = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": e, "nombre": "Exh", "tipo": "exhibicion" }),
    )
    .await;
    let _ = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": e, "nombre": "Mem", "tipo": "memoria" }),
    )
    .await;

    let (status, body) = list_rubrics(pool, &tok, "tipo=memoria").await;
    assert_eq!(status, StatusCode::OK);
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["nombre"], "Mem");
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_rejects_invalid_edition_param(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (status, _) = list_rubrics(pool, &tok, "edition_id=not-a-uuid").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_combines_filters(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e1 = seed_edition(&pool, 2024).await;
    let e2 = seed_edition(&pool, 2025).await;
    for (e, nombre, tipo) in &[
        (e1, "A-exh", "exhibicion"),
        (e1, "A-mem", "memoria"),
        (e2, "B-exh", "exhibicion"),
    ] {
        let _ = post_create(
            pool.clone(),
            &tok,
            json!({ "edition_id": e, "nombre": nombre, "tipo": tipo }),
        )
        .await;
    }

    let (status, body) = list_rubrics(
        pool,
        &tok,
        &format!("edition_id={e1}&tipo=exhibicion"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["nombre"], "A-exh");
    // No filtrar sólo muestra el prefijo: el id viene completo.
    let _: Uuid = items[0]["id"].as_str().unwrap().parse().unwrap();
}
