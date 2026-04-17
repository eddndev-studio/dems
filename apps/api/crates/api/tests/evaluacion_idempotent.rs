//! Integration tests for POST /evaluaciones idempotency via client_id.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    assign_jurado, build_app, insert_prototipo, insert_user, jurado, seed_edition,
    seed_rubric_template, seed_section_with_criterion, token_for,
};
use dems_api::auth::TokenKind;
use dems_core::models::UserRole;

async fn post_eval(pool: PgPool, tok: &str, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri("/evaluaciones")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

#[sqlx::test(migrations = "../../migrations")]
async fn repeat_with_same_client_id_returns_existing(pool: PgPool) {
    let (jurado_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, jurado_id, p, r).await;

    let client_id = "client-abc-123";
    let body = json!({
        "prototipo_id": p, "template_id": r, "client_id": client_id
    });

    let (status1, first) = post_eval(pool.clone(), &tok, body.clone()).await;
    assert_eq!(status1, StatusCode::CREATED);

    // Misma petición otra vez: 200 (no 201) con la misma id.
    let (status2, second) = post_eval(pool.clone(), &tok, body).await;
    assert_eq!(
        status2,
        StatusCode::OK,
        "replays should be idempotent, not duplicate"
    );
    assert_eq!(first["id"], second["id"]);

    // Sólo una evaluación persistida.
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM evaluaciones")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn different_client_id_same_triple_is_409(pool: PgPool) {
    // La app offline perdió su estado local y reintentó con un client_id
    // nuevo, pero el servidor ya había aceptado la evaluación original.
    // 409 obliga al cliente a resolverlo (leer la existente o avisar al
    // usuario) en lugar de crear silenciosamente un duplicado.
    let (jurado_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, jurado_id, p, r).await;

    let (_, first) = post_eval(
        pool.clone(),
        &tok,
        json!({ "prototipo_id": p, "template_id": r, "client_id": "cid-1" }),
    )
    .await;
    assert!(first["id"].is_string());

    let (status, _) = post_eval(
        pool,
        &tok,
        json!({ "prototipo_id": p, "template_id": r, "client_id": "cid-2" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn client_id_is_scoped_per_jurado(pool: PgPool) {
    // Dos jurados reutilizando el mismo client_id (cada uno en su propio
    // dispositivo) no deben colisionar.
    let (j1_id, t1) = jurado(&pool).await;
    let j2_id = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;
    let t2 = token_for(j2_id, UserRole::Jurado, 900, TokenKind::Access);

    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j1_id, p, r).await;
    assign_jurado(&pool, j2_id, p, r).await;

    let body1 = json!({ "prototipo_id": p, "template_id": r, "client_id": "same-cid" });
    let (s1, _) = post_eval(pool.clone(), &t1, body1.clone()).await;
    assert_eq!(s1, StatusCode::CREATED);

    let (s2, _) = post_eval(pool.clone(), &t2, body1).await;
    assert_eq!(s2, StatusCode::CREATED);

    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM evaluaciones")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn replay_with_scores_does_not_duplicate_them(pool: PgPool) {
    let (jurado_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, jurado_id, p, r).await;

    let body = json!({
        "prototipo_id": p, "template_id": r, "client_id": "cid-X",
        "scores": [{ "criterion_id": c1, "score": 2 }]
    });
    let (_, _) = post_eval(pool.clone(), &tok, body.clone()).await;
    let (_, _) = post_eval(pool.clone(), &tok, body).await;

    let scores: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM evaluacion_scores")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(scores, 1, "replay must not multiply score rows");
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_without_client_id_still_works(pool: PgPool) {
    let (jurado_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F-01", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, jurado_id, p, r).await;

    let (status, body) = post_eval(
        pool,
        &tok,
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert!(body["id"].is_string());
}
