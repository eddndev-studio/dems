//! Integration tests for GET /admin/rubric-templates/:id.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, jurado, seed_categoria, seed_edition};

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

async fn get_by_id(pool: PgPool, id: &str, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("GET")
        .uri(format!("/admin/rubric-templates/{id}"));
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app.oneshot(req.body(Body::empty()).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let body: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, body)
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_returns_full_tree(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Software").await;

    // Creamos insertando secciones desordenadas para verificar que el GET
    // las devuelve ordenadas por `orden`.
    let created = post_create(
        pool.clone(),
        &tok,
        json!({
            "edition_id": edition_id,
            "nombre": "R1",
            "tipo": "exhibicion",
            "descripcion": "prueba",
            "categorias": [cat],
            "sections": [
                {
                    "nombre": "Segunda",
                    "orden": 2,
                    "criteria": [
                        { "texto": "c2", "orden": 1, "max_score": 3, "kind": "scale" }
                    ]
                },
                {
                    "nombre": "Primera",
                    "orden": 1,
                    "criteria": [
                        { "texto": "c1b", "orden": 2, "max_score": 3, "kind": "scale" },
                        { "texto": "c1a", "orden": 1, "max_score": 3, "kind": "scale" }
                    ]
                }
            ]
        }),
    )
    .await;
    let id = created["id"].as_str().unwrap();

    let (status, body) = get_by_id(pool, id, Some(&tok)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["id"], json!(id));
    assert_eq!(body["nombre"], "R1");
    assert_eq!(body["tipo"], "exhibicion");
    assert_eq!(body["descripcion"], "prueba");
    assert_eq!(body["activo"], true);
    assert_eq!(body["categorias"], json!([cat]));

    let sections = body["sections"].as_array().unwrap();
    assert_eq!(sections.len(), 2);
    assert_eq!(sections[0]["nombre"], "Primera", "sections must be sorted by orden");
    assert_eq!(sections[1]["nombre"], "Segunda");

    // Criterios dentro de cada sección también ordenados.
    let primera_criteria = sections[0]["criteria"].as_array().unwrap();
    assert_eq!(primera_criteria.len(), 2);
    assert_eq!(primera_criteria[0]["texto"], "c1a");
    assert_eq!(primera_criteria[1]["texto"], "c1b");
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_returns_404_for_unknown_id(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4().to_string();
    let (status, _) = get_by_id(pool, &ghost, Some(&tok)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_is_403_for_jurado(pool: PgPool) {
    let (_, admin_tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &admin_tok,
        json!({ "edition_id": edition_id, "nombre": "x", "tipo": "exhibicion" }),
    )
    .await;
    let id = created["id"].as_str().unwrap();

    let (_, j_tok) = jurado(&pool).await;
    let (status, _) = get_by_id(pool, id, Some(&j_tok)).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
