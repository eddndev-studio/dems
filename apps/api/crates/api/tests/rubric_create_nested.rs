//! Integration tests for POST /admin/rubric-templates with a nested
//! sections + criteria payload.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, seed_categoria, seed_edition};

async fn post_create(pool: PgPool, tok: &str, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri("/admin/rubric-templates")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let value: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, value)
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_with_sections_and_criteria_persists_tree(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "software", "Desarrollo de Software").await;

    let (status, body) = post_create(
        pool.clone(),
        &tok,
        json!({
            "edition_id": edition_id,
            "nombre": "Exhibición 2024",
            "tipo": "exhibicion",
            "categorias": [cat],
            "sections": [
                {
                    "nombre": "Aplicabilidad",
                    "orden": 1,
                    "criteria": [
                        { "texto": "Funciona sin fallas.", "orden": 1, "max_score": 3, "kind": "scale" },
                        { "texto": "Se sometió a pruebas.", "orden": 2, "max_score": 3, "kind": "scale" }
                    ]
                },
                {
                    "nombre": "Cartel",
                    "orden": 2,
                    "peso_pct": null,
                    "criteria": [
                        { "texto": "El cartel es creativo.", "orden": 1, "max_score": 1, "kind": "scale" }
                    ]
                }
            ]
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {body}");

    // Respuesta eco-estructurada.
    let sections = body["sections"].as_array().unwrap();
    assert_eq!(sections.len(), 2);
    assert_eq!(sections[0]["nombre"], "Aplicabilidad");
    assert_eq!(sections[0]["orden"], 1);
    assert_eq!(sections[0]["criteria"].as_array().unwrap().len(), 2);
    assert_eq!(sections[1]["nombre"], "Cartel");
    assert_eq!(sections[1]["criteria"].as_array().unwrap().len(), 1);
    assert_eq!(body["categorias"].as_array().unwrap().len(), 1);
    assert_eq!(body["categorias"][0], json!(cat));

    // Persistencia real en DB.
    let template_id: Uuid = body["id"].as_str().unwrap().parse().unwrap();
    let sec_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM rubric_sections WHERE template_id = $1")
            .bind(template_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(sec_count, 2);
    let crit_count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM rubric_criteria c
           JOIN rubric_sections s ON s.id = c.section_id
           WHERE s.template_id = $1"#,
    )
    .bind(template_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(crit_count, 3);
    let cat_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM rubric_template_categorias WHERE template_id = $1",
    )
    .bind(template_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(cat_count, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rolls_back_when_section_order_duplicated(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;

    let (status, _) = post_create(
        pool.clone(),
        &tok,
        json!({
            "edition_id": edition_id,
            "nombre": "Dup",
            "tipo": "exhibicion",
            "sections": [
                { "nombre": "A", "orden": 1, "criteria": [] },
                { "nombre": "B", "orden": 1, "criteria": [] }
            ]
        }),
    )
    .await;

    // 422 por integridad (UNIQUE en template_id + orden).
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Nada quedó persistido — la transacción hizo rollback.
    let templates: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM rubric_templates")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(templates, 0, "template must not be persisted on rollback");
    let sections: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM rubric_sections")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(sections, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_unknown_categoria(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let ghost = Uuid::new_v4();

    let (status, _) = post_create(
        pool.clone(),
        &tok,
        json!({
            "edition_id": edition_id,
            "nombre": "x",
            "tipo": "exhibicion",
            "categorias": [ghost]
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let templates: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM rubric_templates")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(templates, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_accepts_all_criterion_kinds(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;

    let (status, body) = post_create(
        pool,
        &tok,
        json!({
            "edition_id": edition_id,
            "nombre": "Kinds",
            "tipo": "exhibicion",
            "sections": [{
                "nombre": "Varios",
                "orden": 1,
                "criteria": [
                    { "texto": "A", "orden": 1, "max_score": 3, "kind": "scale" },
                    { "texto": "B", "orden": 2, "max_score": 1, "kind": "boolean" },
                    { "texto": "C", "orden": 3, "max_score": 0, "kind": "text_key" }
                ]
            }]
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    let criteria = &body["sections"][0]["criteria"];
    assert_eq!(criteria[0]["kind"], "scale");
    assert_eq!(criteria[1]["kind"], "boolean");
    assert_eq!(criteria[2]["kind"], "text_key");
}
