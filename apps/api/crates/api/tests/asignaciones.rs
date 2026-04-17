//! Integration tests for GET /me/asignaciones.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, assign_jurado, build_app, insert_prototipo, insert_user, jurado, seed_edition,
    seed_rubric_template, token_for,
};
use dems_api::auth::TokenKind;
use dems_core::models::UserRole;

async fn get_asignaciones(pool: PgPool, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder().method("GET").uri("/me/asignaciones");
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
async fn asignaciones_is_401_without_token(pool: PgPool) {
    let (status, _) = get_asignaciones(pool, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn asignaciones_empty_when_jurado_has_none(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let (status, body) = get_asignaciones(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn asignaciones_lists_assigned_prototipos(pool: PgPool) {
    let (jurado_id, tok) = jurado(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let p1 = insert_prototipo(&pool, edition_id, "F-01", "Proto Uno").await;
    let p2 = insert_prototipo(&pool, edition_id, "F-02", "Proto Dos").await;
    let r_exh = seed_rubric_template(&pool, edition_id, "Exh", "exhibicion").await;
    let r_mem = seed_rubric_template(&pool, edition_id, "Mem", "memoria").await;

    assign_jurado(&pool, jurado_id, p1, r_exh).await;
    assign_jurado(&pool, jurado_id, p1, r_mem).await; // mismo prototipo, dos rúbricas
    assign_jurado(&pool, jurado_id, p2, r_exh).await;

    let (status, body) = get_asignaciones(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::OK);
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 3, "one row per (prototipo, template) tuple");

    // Cada item trae prototipo + rubric resumido + evaluacion_id (null aún).
    let first = &items[0];
    assert!(first["prototipo"]["id"].is_string());
    assert!(first["prototipo"]["folio"].is_string());
    assert!(first["prototipo"]["nombre"].is_string());
    assert!(first["rubric"]["id"].is_string());
    assert!(first["rubric"]["nombre"].is_string());
    assert!(first["rubric"]["tipo"].is_string());
    assert!(first["evaluacion_id"].is_null(), "no evaluation yet");
    assert!(first["submitted"].is_boolean());
    assert_eq!(first["submitted"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn asignaciones_scoped_to_current_user(pool: PgPool) {
    let (j1, tok1) = jurado(&pool).await;
    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;

    let edition_id = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, edition_id, "F-01", "P").await;
    let r = seed_rubric_template(&pool, edition_id, "R", "exhibicion").await;

    assign_jurado(&pool, j1, p, r).await;
    assign_jurado(&pool, j2, p, r).await;

    let (_, body) = get_asignaciones(pool, Some(&tok1)).await;
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 1, "jurado must see only their own assignments");
}

#[sqlx::test(migrations = "../../migrations")]
async fn asignaciones_includes_existing_evaluacion_id(pool: PgPool) {
    let (jurado_id, tok) = jurado(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, edition_id, "F-01", "P").await;
    let r = seed_rubric_template(&pool, edition_id, "R", "exhibicion").await;
    assign_jurado(&pool, jurado_id, p, r).await;

    let eval_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id, submitted_at)
           VALUES ($1, $2, $3, $4, NOW())"#,
    )
    .bind(eval_id)
    .bind(p)
    .bind(jurado_id)
    .bind(r)
    .execute(&pool)
    .await
    .unwrap();

    let (_, body) = get_asignaciones(pool, Some(&tok)).await;
    let item = &body.as_array().unwrap()[0];
    assert_eq!(item["evaluacion_id"], Value::String(eval_id.to_string()));
    assert_eq!(item["submitted"], true);
}

#[sqlx::test(migrations = "../../migrations")]
async fn admin_sees_no_asignaciones(pool: PgPool) {
    // Un admin autenticado llega al endpoint pero no tiene filas — no es un
    // error, solo lista vacía. La ruta es "mis asignaciones", no
    // "asignaciones del sistema".
    let (_, tok) = admin(&pool).await;
    let (status, body) = get_asignaciones(pool, Some(&tok)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 0);
}

// Silence warnings for unused helpers imported but not used in every test.
#[allow(dead_code)]
fn _imports() {
    let _: fn(Uuid, UserRole, i64, TokenKind) -> String = token_for;
}
