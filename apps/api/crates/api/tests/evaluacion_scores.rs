//! Integration tests for POST /evaluaciones with a nested scores payload.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    assign_jurado, build_app, insert_prototipo, jurado, seed_edition, seed_rubric_template,
    seed_section_with_criterion, set_edition_phase,
};

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

async fn setup(pool: &PgPool) -> (Uuid, String, Uuid, Uuid, Uuid, Uuid) {
    let (jurado_id, tok) = jurado(pool).await;
    let edition_id = seed_edition(pool, 2024).await;
    set_edition_phase(pool, edition_id, "evaluacion").await;
    let p = insert_prototipo(pool, edition_id, "F-01", "P").await;
    let r = seed_rubric_template(pool, edition_id, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(pool, r, 1, "C1", 3).await;
    let (_, c2) = seed_section_with_criterion(pool, r, 2, "C2", 3).await;
    assign_jurado(pool, jurado_id, p, r).await;
    (jurado_id, tok, p, r, c1, c2)
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_persists_nested_scores(pool: PgPool) {
    let (_, tok, p, r, c1, c2) = setup(&pool).await;

    let (status, body) = post_eval(
        pool.clone(),
        &tok,
        json!({
            "prototipo_id": p,
            "template_id": r,
            "observaciones": "todo bien",
            "acompanamiento_asesor": true,
            "opinion_personal": 85,
            "scores": [
                { "criterion_id": c1, "score": 2 },
                { "criterion_id": c2, "score": 3 }
            ]
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert_eq!(body["observaciones"], "todo bien");
    assert_eq!(body["acompanamiento_asesor"], true);
    assert_eq!(body["opinion_personal"], 85);

    let stored: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM evaluacion_scores es
           JOIN evaluaciones e ON e.id = es.evaluacion_id
           WHERE e.prototipo_id = $1 AND e.template_id = $2"#,
    )
    .bind(p)
    .bind(r)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(stored, 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_score_above_max(pool: PgPool) {
    let (_, tok, p, r, c1, _) = setup(&pool).await;

    let (status, _) = post_eval(
        pool.clone(),
        &tok,
        json!({
            "prototipo_id": p,
            "template_id": r,
            "scores": [{ "criterion_id": c1, "score": 5 }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Rollback: no evaluation persisted.
    let stored: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM evaluaciones")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_negative_score(pool: PgPool) {
    let (_, tok, p, r, c1, _) = setup(&pool).await;

    let (status, _) = post_eval(
        pool,
        &tok,
        json!({
            "prototipo_id": p, "template_id": r,
            "scores": [{ "criterion_id": c1, "score": -1 }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_criterion_from_different_template(pool: PgPool) {
    let (jurado_id, tok) = jurado(&pool).await;
    let edition_id = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, edition_id, "evaluacion").await;
    let p = insert_prototipo(&pool, edition_id, "F-01", "P").await;
    let r1 = seed_rubric_template(&pool, edition_id, "R1", "exhibicion").await;
    let r2 = seed_rubric_template(&pool, edition_id, "R2", "exhibicion").await;
    let (_, c_from_r2) = seed_section_with_criterion(&pool, r2, 1, "C", 3).await;
    assign_jurado(&pool, jurado_id, p, r1).await;

    let (status, _) = post_eval(
        pool.clone(),
        &tok,
        json!({
            "prototipo_id": p,
            "template_id": r1,
            "scores": [{ "criterion_id": c_from_r2, "score": 2 }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let stored: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM evaluaciones")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_text_answer_on_scale_criterion(pool: PgPool) {
    let (_, tok, p, r, c1, _) = setup(&pool).await;

    // c1 es 'scale'; mandar texto sin score debería fallar la CHECK.
    let (status, _) = post_eval(
        pool,
        &tok,
        json!({
            "prototipo_id": p, "template_id": r,
            "scores": [{ "criterion_id": c1, "text_answer": "hola" }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_duplicate_criterion_id(pool: PgPool) {
    // #13: dos entradas para el mismo criterion_id en el payload deben dar 422
    // (body inválido), no 500 por la PK (evaluacion_id, criterion_id).
    let (_, tok, p, r, c1, _c2) = setup(&pool).await;

    let (status, _) = post_eval(
        pool.clone(),
        &tok,
        json!({
            "prototipo_id": p, "template_id": r,
            "scores": [
                { "criterion_id": c1, "score": 1 },
                { "criterion_id": c1, "score": 2 }
            ]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Rollback total: nada persistido.
    let stored: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM evaluaciones")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn db_check_rejects_negative_score(pool: PgPool) {
    // #12: la columna evaluacion_scores.score tiene CHECK (score IS NULL OR
    // score >= 0). Un INSERT directo con score=-1 (no-null, así no toca la otra
    // CHECK) debe fallar a nivel DB — defensa en profundidad.
    let (jurado_id, _, p, r, c1, _c2) = setup(&pool).await;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(id)
    .bind(p)
    .bind(jurado_id)
    .bind(r)
    .execute(&pool)
    .await
    .unwrap();

    let res = sqlx::query(
        r#"INSERT INTO evaluacion_scores (evaluacion_id, criterion_id, score)
           VALUES ($1, $2, -1)"#,
    )
    .bind(id)
    .bind(c1)
    .execute(&pool)
    .await;
    let err = res.expect_err("negative score must violate the CHECK constraint");
    match err {
        sqlx::Error::Database(db) => assert!(
            db.is_check_violation(),
            "expected a CHECK violation, got: {db}"
        ),
        other => panic!("expected a database CHECK error, got: {other}"),
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_allows_partial_scores(pool: PgPool) {
    // El jurado puede guardar una evaluación parcial (solo algunos rubros).
    // El submit posterior validará completitud.
    let (_, tok, p, r, c1, _c2) = setup(&pool).await;

    let (status, body) = post_eval(
        pool,
        &tok,
        json!({
            "prototipo_id": p, "template_id": r,
            "scores": [{ "criterion_id": c1, "score": 2 }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
}
