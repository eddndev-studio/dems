//! Integration tests for GET /evaluaciones/:id.

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
    seed_rubric_template, seed_section_with_criterion, set_edition_phase, token_for,
};
use dems_api::auth::TokenKind;
use dems_core::models::UserRole;

async fn post_eval(pool: PgPool, tok: &str, body: Value) -> Value {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri("/evaluaciones")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

async fn get_eval(pool: PgPool, id: &str, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("GET")
        .uri(format!("/evaluaciones/{id}"));
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
async fn owner_jurado_gets_200(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;

    let created = post_eval(
        pool.clone(),
        &tok,
        json!({
            "prototipo_id": p, "template_id": r,
            "scores": [{ "criterion_id": c1, "score": 2 }]
        }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, body) = get_eval(pool, &id, Some(&tok)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["id"], json!(id));
    // El árbol de scores también regresa.
    assert_eq!(body["scores"].as_array().unwrap().len(), 1);
    assert_eq!(body["scores"][0]["score"], 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn other_jurado_gets_403(pool: PgPool) {
    let (j1_id, t1) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j1_id, p, r).await;

    let created = post_eval(
        pool.clone(),
        &t1,
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let j2_id = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;
    let t2 = token_for(j2_id, UserRole::Jurado, 900, TokenKind::Access);

    let (status, _) = get_eval(pool, &id, Some(&t2)).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn admin_can_read_any_evaluation(pool: PgPool) {
    let (j_id, t1) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j_id, p, r).await;

    let created = post_eval(
        pool.clone(),
        &t1,
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (_, admin_tok) = admin(&pool).await;
    let (status, body) = get_eval(pool, &id, Some(&admin_tok)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_is_404_for_unknown_id(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let ghost = Uuid::new_v4().to_string();
    let (status, _) = get_eval(pool, &ghost, Some(&tok)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_is_401_without_token(pool: PgPool) {
    let id = Uuid::new_v4().to_string();
    let (status, _) = get_eval(pool, &id, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
