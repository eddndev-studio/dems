//! Integration tests for GET /admin/results/categoria/:slug.
//!
//! Devuelve el ranking de prototipos para una categoría/edición/tipo de
//! rúbrica, con el promedio de los puntajes de los jurados (sólo
//! evaluaciones ya `submitted_at`).

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, attach_categoria, build_app, insert_prototipo, insert_user, jurado, seed_categoria,
    seed_draft_evaluacion, seed_edition, seed_rubric_template, seed_section_with_criterion,
    seed_submitted_evaluacion,
};

async fn get(pool: PgPool, path: &str, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder().method("GET").uri(path);
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app.oneshot(req.body(Body::empty()).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

// ---------------------------------------------------------------------------
// AuthZ
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn requires_auth(pool: PgPool) {
    let e = seed_edition(&pool, 2024).await;
    let _ = seed_categoria(&pool, "soft", "Software").await;
    let (status, _) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn jurado_forbidden(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let _ = seed_categoria(&pool, "soft", "Software").await;
    let (status, _) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn missing_edition_id_is_400(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let _ = seed_categoria(&pool, "soft", "Software").await;
    let (status, _) = get(pool, "/admin/results/categoria/soft", Some(&tok)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[sqlx::test(migrations = "../../migrations")]
async fn unknown_categoria_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, _) = get(
        pool,
        &format!("/admin/results/categoria/no-existe?edition_id={e}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn unknown_edition_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let _ = seed_categoria(&pool, "soft", "Software").await;
    let ghost = Uuid::new_v4();
    let (status, _) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={ghost}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn invalid_rubric_type_is_400(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let _ = seed_categoria(&pool, "soft", "Software").await;
    let (status, _) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}&rubric_type=bogus"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn empty_when_no_prototipos(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let _ = seed_categoria(&pool, "soft", "Software").await;
    let (status, body) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["categoria"]["slug"], "soft");
    assert_eq!(body["rubric_type"], "exhibicion"); // default
    assert_eq!(body["prototipos"], serde_json::json!([]));
    assert_eq!(body["max_total"], 0);
}

// ---------------------------------------------------------------------------
// Happy path
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn ranks_prototipos_by_promedio_desc(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Software").await;
    let r = seed_rubric_template(&pool, e, "Exhibición 2024", "exhibicion").await;
    // Dos criterios, max_score 3 c/u → max_total 6.
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C1", 3).await;
    let (_, c2) = seed_section_with_criterion(&pool, r, 2, "C2", 3).await;

    let p_low = insert_prototipo(&pool, e, "F1", "Bajo").await;
    let p_high = insert_prototipo(&pool, e, "F2", "Alto").await;
    attach_categoria(&pool, p_low, cat).await;
    attach_categoria(&pool, p_high, cat).await;

    let j1 = insert_user(&pool, "j1@x.mx", "J1", "jurado", "pw", true).await;
    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;

    // Bajo: j1 = 1+1=2, j2 = 2+2=4 → promedio 3
    seed_submitted_evaluacion(&pool, p_low, j1, r, &[(c1, 1), (c2, 1)]).await;
    seed_submitted_evaluacion(&pool, p_low, j2, r, &[(c1, 2), (c2, 2)]).await;
    // Alto: j1 = 3+3=6, j2 = 2+3=5 → promedio 5.5
    seed_submitted_evaluacion(&pool, p_high, j1, r, &[(c1, 3), (c2, 3)]).await;
    seed_submitted_evaluacion(&pool, p_high, j2, r, &[(c1, 2), (c2, 3)]).await;

    let (status, body) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["max_total"], 6);

    let protos = body["prototipos"].as_array().expect("prototipos array");
    assert_eq!(protos.len(), 2);
    // Orden: Alto antes que Bajo.
    assert_eq!(protos[0]["folio"], "F2");
    assert_eq!(protos[0]["promedio"], 5.5);
    assert_eq!(protos[0]["n_jurados"], 2);
    assert_eq!(protos[1]["folio"], "F1");
    assert_eq!(protos[1]["promedio"], 3.0);

    // El detalle por jurado viene incluido.
    let evals = protos[0]["evaluaciones"].as_array().unwrap();
    assert_eq!(evals.len(), 2);
    let totals: Vec<i64> = evals.iter().map(|v| v["total"].as_i64().unwrap()).collect();
    assert!(totals.contains(&6));
    assert!(totals.contains(&5));
}

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "../../migrations")]
async fn excludes_unsubmitted_evaluaciones(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Software").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    attach_categoria(&pool, p, cat).await;
    let j1 = insert_user(&pool, "j1@x.mx", "J1", "jurado", "pw", true).await;
    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;

    seed_submitted_evaluacion(&pool, p, j1, r, &[(c1, 3)]).await;
    seed_draft_evaluacion(&pool, p, j2, r, &[(c1, 0)]).await; // no debe contar

    let (status, body) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let protos = body["prototipos"].as_array().unwrap();
    assert_eq!(protos.len(), 1);
    assert_eq!(protos[0]["n_jurados"], 1);
    assert_eq!(protos[0]["promedio"], 3.0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn excludes_prototipos_outside_categoria(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat_a = seed_categoria(&pool, "soft", "Software").await;
    let cat_b = seed_categoria(&pool, "salud", "Salud").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    let p_in = insert_prototipo(&pool, e, "F1", "Dentro").await;
    let p_out = insert_prototipo(&pool, e, "F2", "Fuera").await;
    attach_categoria(&pool, p_in, cat_a).await;
    attach_categoria(&pool, p_out, cat_b).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    seed_submitted_evaluacion(&pool, p_in, j, r, &[(c1, 3)]).await;
    seed_submitted_evaluacion(&pool, p_out, j, r, &[(c1, 3)]).await;

    let (status, body) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let protos = body["prototipos"].as_array().unwrap();
    assert_eq!(protos.len(), 1);
    assert_eq!(protos[0]["folio"], "F1");
}

#[sqlx::test(migrations = "../../migrations")]
async fn filters_by_rubric_type(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Software").await;
    let r_exhi = seed_rubric_template(&pool, e, "Exhi", "exhibicion").await;
    let r_mem = seed_rubric_template(&pool, e, "Mem", "memoria").await;
    let (_, c_exhi) = seed_section_with_criterion(&pool, r_exhi, 1, "C", 3).await;
    let (_, c_mem) = seed_section_with_criterion(&pool, r_mem, 1, "C", 3).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    attach_categoria(&pool, p, cat).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;

    seed_submitted_evaluacion(&pool, p, j, r_exhi, &[(c_exhi, 3)]).await;
    seed_submitted_evaluacion(&pool, p, j, r_mem, &[(c_mem, 1)]).await;

    let (_, body_exhi) = get(
        pool.clone(),
        &format!("/admin/results/categoria/soft?edition_id={e}&rubric_type=exhibicion"),
        Some(&tok),
    )
    .await;
    assert_eq!(body_exhi["prototipos"][0]["promedio"], 3.0);

    let (_, body_mem) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e}&rubric_type=memoria"),
        Some(&tok),
    )
    .await;
    assert_eq!(body_mem["prototipos"][0]["promedio"], 1.0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn excludes_other_editions(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e_now = seed_edition(&pool, 2024).await;
    let e_old = seed_edition(&pool, 2023).await;
    let cat = seed_categoria(&pool, "soft", "Software").await;
    let r_now = seed_rubric_template(&pool, e_now, "R", "exhibicion").await;
    let r_old = seed_rubric_template(&pool, e_old, "R", "exhibicion").await;
    let (_, c_now) = seed_section_with_criterion(&pool, r_now, 1, "C", 3).await;
    let (_, c_old) = seed_section_with_criterion(&pool, r_old, 1, "C", 3).await;
    let p_now = insert_prototipo(&pool, e_now, "F-NOW", "P").await;
    let p_old = insert_prototipo(&pool, e_old, "F-OLD", "P").await;
    attach_categoria(&pool, p_now, cat).await;
    attach_categoria(&pool, p_old, cat).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    seed_submitted_evaluacion(&pool, p_now, j, r_now, &[(c_now, 2)]).await;
    seed_submitted_evaluacion(&pool, p_old, j, r_old, &[(c_old, 3)]).await;

    let (status, body) = get(
        pool,
        &format!("/admin/results/categoria/soft?edition_id={e_now}"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let protos = body["prototipos"].as_array().unwrap();
    assert_eq!(protos.len(), 1);
    assert_eq!(protos[0]["folio"], "F-NOW");
}
