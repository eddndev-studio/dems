//! Integration tests for PATCH /evaluaciones/:id.

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

async fn patch_eval(pool: PgPool, id: &str, tok: Option<&str>, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("PATCH")
        .uri(format!("/evaluaciones/{id}"))
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
async fn owner_can_update_scores(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C1", 3).await;
    let (_, c2) = seed_section_with_criterion(&pool, r, 2, "C2", 3).await;
    assign_jurado(&pool, j_id, p, r).await;

    let created = post_eval(
        pool.clone(),
        &tok,
        json!({
            "prototipo_id": p, "template_id": r,
            "scores": [{ "criterion_id": c1, "score": 1 }]
        }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    // Cambiamos score de c1 y agregamos score para c2.
    let (status, body) = patch_eval(
        pool.clone(),
        &id,
        Some(&tok),
        json!({
            "observaciones": "revisado",
            "scores": [
                { "criterion_id": c1, "score": 3 },
                { "criterion_id": c2, "score": 2 }
            ]
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["observaciones"], "revisado");
    let scores = body["scores"].as_array().unwrap();
    assert_eq!(scores.len(), 2);
    // Sólo una fila por criterion en la DB.
    let rows: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM evaluacion_scores WHERE evaluacion_id = $1::uuid")
            .bind(Uuid::parse_str(&id).unwrap())
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(rows, 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_metadata_only_leaves_scores_untouched(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
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

    let (status, body) = patch_eval(pool, &id, Some(&tok), json!({ "opinion_personal": 90 })).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["opinion_personal"], 90);
    assert_eq!(body["scores"].as_array().unwrap().len(), 1);
    assert_eq!(body["scores"][0]["score"], 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_is_409_after_submit(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j_id, p, r).await;
    let created = post_eval(
        pool.clone(),
        &tok,
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    // Marcamos como enviada directamente en la DB para aislar este test
    // del endpoint /submit (aún no TDD-eado en este ciclo).
    sqlx::query("UPDATE evaluaciones SET submitted_at = NOW() WHERE id = $1::uuid")
        .bind(Uuid::parse_str(&id).unwrap())
        .execute(&pool)
        .await
        .unwrap();

    let (status, _) = patch_eval(pool, &id, Some(&tok), json!({ "observaciones": "tarde" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn other_jurado_gets_403(pool: PgPool) {
    let (j1, t1) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j1, p, r).await;
    let created = post_eval(
        pool.clone(),
        &t1,
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;
    let t2 = token_for(j2, UserRole::Jurado, 900, TokenKind::Access);

    let (status, _) = patch_eval(pool, &id, Some(&t2), json!({ "observaciones": "ajeno" })).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_rejects_invalid_score(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    let created = post_eval(
        pool.clone(),
        &tok,
        json!({ "prototipo_id": p, "template_id": r }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, _) = patch_eval(
        pool.clone(),
        &id,
        Some(&tok),
        json!({ "scores": [{ "criterion_id": c1, "score": 99 }] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Rollback: no quedó parcialmente aplicado.
    let rows: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM evaluacion_scores WHERE evaluacion_id = $1::uuid")
            .bind(Uuid::parse_str(&id).unwrap())
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(rows, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_returns_404_for_unknown_id(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let ghost = Uuid::new_v4().to_string();
    let (status, _) = patch_eval(pool, &ghost, Some(&tok), json!({})).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
