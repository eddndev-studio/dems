//! Integration tests for DELETE /admin/rubric-templates/:id.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, insert_user, jurado, seed_edition};

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
    serde_json::from_slice(&resp.into_body().collect().await.unwrap().to_bytes()).unwrap()
}

async fn delete(pool: PgPool, id: &str, tok: Option<&str>) -> StatusCode {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("DELETE")
        .uri(format!("/admin/rubric-templates/{id}"));
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    app.oneshot(req.body(Body::empty()).unwrap())
        .await
        .unwrap()
        .status()
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_removes_template_with_no_evaluations(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &tok,
        json!({
            "edition_id": edition_id,
            "nombre": "R",
            "tipo": "exhibicion",
            "sections": [{
                "nombre": "A", "orden": 1,
                "criteria": [{ "texto": "x", "orden": 1, "max_score": 3, "kind": "scale" }]
            }]
        }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let status = delete(pool.clone(), &id, Some(&tok)).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    // Cascada: secciones y criterios también borradas por ON DELETE CASCADE.
    let t: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM rubric_templates WHERE id = $1::uuid")
        .bind(Uuid::parse_str(&id).unwrap())
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(t, 0);
    let s: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM rubric_sections WHERE template_id = $1::uuid")
            .bind(Uuid::parse_str(&id).unwrap())
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(s, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_returns_409_when_evaluaciones_exist(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &tok,
        json!({ "edition_id": edition_id, "nombre": "R", "tipo": "exhibicion" }),
    )
    .await;
    let template_id: Uuid = created["id"].as_str().unwrap().parse().unwrap();

    // Sembramos: jurado, prototipo, evaluación.
    let jurado_id = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let prototipo_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO prototipos (id, edition_id, folio, nombre)
           VALUES ($1, $2, 'F-01', 'Proto')"#,
    )
    .bind(prototipo_id)
    .bind(edition_id)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(Uuid::new_v4())
    .bind(prototipo_id)
    .bind(jurado_id)
    .bind(template_id)
    .execute(&pool)
    .await
    .unwrap();

    let status = delete(pool.clone(), &template_id.to_string(), Some(&tok)).await;
    assert_eq!(status, StatusCode::CONFLICT);

    // La rúbrica sigue ahí — la auditoría está intacta.
    let still: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM rubric_templates WHERE id = $1")
        .bind(template_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(still, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_returns_404_for_unknown_id(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4().to_string();
    let status = delete(pool, &ghost, Some(&tok)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_is_403_for_jurado(pool: PgPool) {
    let (_, admin_tok) = admin(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let created = post_create(
        pool.clone(),
        &admin_tok,
        json!({ "edition_id": edition_id, "nombre": "R", "tipo": "exhibicion" }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (_, j_tok) = jurado(&pool).await;
    let status = delete(pool, &id, Some(&j_tok)).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_is_401_without_token(pool: PgPool) {
    let ghost = Uuid::new_v4().to_string();
    let status = delete(pool, &ghost, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
