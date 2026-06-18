//! Integration tests for the edition-phase gate on create/submit/patch
//! (#6). Las operaciones de evaluación sólo se permiten cuando la edición del
//! prototipo está en fase `evaluacion`; en `preparacion` o `cerrada` → 409.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    assign_jurado, build_app, insert_prototipo, jurado, seed_draft_evaluacion, seed_edition,
    seed_rubric_template, seed_section_with_criterion, seed_submitted_evaluacion,
    set_edition_phase,
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
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn patch_eval(pool: PgPool, id: Uuid, tok: &str, body: Value) -> (StatusCode, Value) {
    let app = build_app(pool);
    let req = Request::builder()
        .method("PATCH")
        .uri(format!("/evaluaciones/{id}"))
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::from(body.to_string()))
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn submit(pool: PgPool, id: Uuid, tok: &str) -> (StatusCode, Value) {
    let app = build_app(pool);
    let req = Request::builder()
        .method("POST")
        .uri(format!("/evaluaciones/{id}/submit"))
        .header("authorization", format!("Bearer {tok}"))
        .body(Body::empty())
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

// ---------------------------------------------------------------------------
// CREATE
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn create_blocked_in_preparacion(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await; // default = preparacion
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j_id, p, r).await;

    let (status, body) =
        post_eval(pool, &tok, json!({ "prototipo_id": p, "template_id": r })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "edition_closed", "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_blocked_when_cerrada(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "cerrada").await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j_id, p, r).await;

    let (status, body) =
        post_eval(pool, &tok, json!({ "prototipo_id": p, "template_id": r })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "edition_closed", "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_ok_in_evaluacion(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    assign_jurado(&pool, j_id, p, r).await;

    let (status, _) = post_eval(pool, &tok, json!({ "prototipo_id": p, "template_id": r })).await;
    assert_eq!(status, StatusCode::CREATED);
}

// ---------------------------------------------------------------------------
// PATCH
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn patch_blocked_in_preparacion(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await; // preparacion
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    // Sembramos el draft directo en la DB (bypassa el gate).
    let id = seed_draft_evaluacion(&pool, p, j_id, r, &[(c1, 1)]).await;

    let (status, body) = patch_eval(pool, id, &tok, json!({ "observaciones": "x" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "edition_closed", "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_blocked_when_cerrada(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    let id = seed_draft_evaluacion(&pool, p, j_id, r, &[(c1, 1)]).await;
    set_edition_phase(&pool, e, "cerrada").await;

    let (status, body) = patch_eval(pool, id, &tok, json!({ "observaciones": "x" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "edition_closed", "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_ok_in_evaluacion(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    let id = seed_draft_evaluacion(&pool, p, j_id, r, &[(c1, 1)]).await;
    set_edition_phase(&pool, e, "evaluacion").await;

    let (status, _) = patch_eval(pool, id, &tok, json!({ "observaciones": "x" })).await;
    assert_eq!(status, StatusCode::OK);
}

// ---------------------------------------------------------------------------
// SUBMIT
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn submit_blocked_in_preparacion(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await; // preparacion
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    let id = seed_draft_evaluacion(&pool, p, j_id, r, &[(c1, 3)]).await;

    let (status, body) = submit(pool, id, &tok).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "edition_closed", "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn submit_blocked_when_cerrada(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    let id = seed_draft_evaluacion(&pool, p, j_id, r, &[(c1, 3)]).await;
    set_edition_phase(&pool, e, "cerrada").await;

    let (status, body) = submit(pool, id, &tok).await;
    assert_eq!(status, StatusCode::CONFLICT);
    // El draft NO está enviado, así que aquí sí gana el gate de fase.
    assert_eq!(body["code"], "edition_closed", "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn submit_ok_in_evaluacion(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    let id = seed_draft_evaluacion(&pool, p, j_id, r, &[(c1, 3)]).await;
    set_edition_phase(&pool, e, "evaluacion").await;

    let (status, _) = submit(pool, id, &tok).await;
    assert_eq!(status, StatusCode::OK);
}

// ---------------------------------------------------------------------------
// REORDEN: submitted_at se chequea ANTES del gate de fase
// ---------------------------------------------------------------------------
// El punto del reorden: un replay de algo YA enviado debe devolver
// `already_submitted` aunque la edición esté 'cerrada' —no `edition_closed`.
// Sin estos tests el reorden quedaría sin cobertura y un refactor lo
// regresaría en silencio.

#[sqlx::test(migrations = "../../migrations")]
async fn submit_already_submitted_wins_over_closed_edition(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    // Evaluación YA enviada + edición cerrada: ambos gates aplicarían, pero el
    // de "ya enviada" corre primero.
    let id = seed_submitted_evaluacion(&pool, p, j_id, r, &[(c1, 3)]).await;
    set_edition_phase(&pool, e, "cerrada").await;

    let (status, body) = submit(pool, id, &tok).await;
    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "already_submitted", "body: {body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_already_submitted_wins_over_closed_edition(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j_id, p, r).await;
    let id = seed_submitted_evaluacion(&pool, p, j_id, r, &[(c1, 3)]).await;
    set_edition_phase(&pool, e, "cerrada").await;

    let (status, body) = patch_eval(pool, id, &tok, json!({ "observaciones": "x" })).await;
    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "already_submitted", "body: {body}");
}
