//! Integration tests for POST /evaluaciones — minimal body (no scores yet).

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, assign_jurado, build_app, insert_prototipo, insert_user, jurado, seed_edition,
    seed_rubric_template, set_edition_phase, token_for,
};
use dems_api::auth::TokenKind;
use dems_core::models::UserRole;

async fn post_eval(pool: PgPool, tok: Option<&str>, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("POST")
        .uri("/evaluaciones")
        .header("content-type", "application/json");
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app
        .oneshot(req.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_is_401_without_token(pool: PgPool) {
    let (status, _) = post_eval(
        pool,
        None,
        json!({ "prototipo_id": Uuid::new_v4(), "template_id": Uuid::new_v4() }),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_returns_201_with_evaluacion(pool: PgPool) {
    let (jurado_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, jurado_id, p, r).await;

    let (status, body) = post_eval(
        pool.clone(),
        Some(&tok),
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert!(body["id"].is_string());
    assert_eq!(body["prototipo_id"], json!(p));
    assert_eq!(body["template_id"], json!(r));
    assert_eq!(body["jurado_id"], json!(jurado_id));
    assert!(body["submitted_at"].is_null());

    let stored: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM evaluaciones
           WHERE prototipo_id = $1 AND template_id = $2 AND jurado_id = $3"#,
    )
    .bind(p)
    .bind(r)
    .bind(jurado_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(stored, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_is_403_when_jurado_not_assigned(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    // NOTE: no assignment.

    let (status, _) = post_eval(
        pool,
        Some(&tok),
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_is_403_when_another_jurados_assignment(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let other = insert_user(&pool, "o@x.mx", "O", "jurado", "pw", true).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, other, p, r).await; // asignada a otro jurado

    let (status, _) = post_eval(
        pool,
        Some(&tok),
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_is_403_for_admin_without_assignment(pool: PgPool) {
    // Admin no es jurado — no debería poder crear evaluaciones salvo que
    // esté asignado como jurado, lo cual no es su rol.
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;

    let (status, _) = post_eval(
        pool,
        Some(&tok),
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_unknown_prototipo(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let ghost_p = Uuid::new_v4();
    let ghost_r = Uuid::new_v4();
    let (status, _) = post_eval(
        pool,
        Some(&tok),
        json!({ "prototipo_id": ghost_p, "template_id": ghost_r }),
    )
    .await;
    // Sin assignment ⇒ 403 siempre, independientemente de si las ids existen.
    // No filtrar IDs desconocidos protege de enumeración.
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_missing_fields(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let (status, _) = post_eval(pool, Some(&tok), json!({})).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[allow(dead_code)]
fn _imports() {
    let _: fn(Uuid, UserRole, i64, TokenKind) -> String = token_for;
}
