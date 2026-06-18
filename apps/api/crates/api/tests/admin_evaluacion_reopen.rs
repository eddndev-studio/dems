//! Integration tests for POST /admin/evaluaciones/:id/reopen.
//!
//! Permite a un admin "des-submitir" una evaluación (vuelve a draft) para que
//! el jurado pueda corregirla. No borra los scores.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, build_app, insert_prototipo, insert_user, jurado, seed_edition, seed_rubric_template,
    seed_section_with_criterion, seed_submitted_evaluacion, set_edition_phase,
};

async fn post(pool: PgPool, path: &str, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder().method("POST").uri(path);
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app.oneshot(req.body(Body::empty()).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

async fn setup_submitted(pool: &PgPool) -> (Uuid, Uuid) {
    // Devuelve (evaluacion_id, criterion_id) de una eval submitted.
    let e = seed_edition(pool, 2024).await;
    let p = insert_prototipo(pool, e, "F", "P").await;
    let r = seed_rubric_template(pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(pool, r, 1, "C", 3).await;
    let j = insert_user(pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let id = seed_submitted_evaluacion(pool, p, j, r, &[(c1, 3)]).await;
    (id, c1)
}

#[sqlx::test(migrations = "../../migrations")]
async fn requires_auth(pool: PgPool) {
    let (id, _) = setup_submitted(&pool).await;
    let (status, _) = post(pool, &format!("/admin/evaluaciones/{id}/reopen"), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn jurado_forbidden(pool: PgPool) {
    let (id, _) = setup_submitted(&pool).await;
    let (_, jtok) = jurado(&pool).await;
    let (status, _) = post(
        pool,
        &format!("/admin/evaluaciones/{id}/reopen"),
        Some(&jtok),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn unknown_id_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4();
    let (status, _) = post(
        pool,
        &format!("/admin/evaluaciones/{ghost}/reopen"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn reopen_clears_submitted_at_and_keeps_scores(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (id, c1) = setup_submitted(&pool).await;

    // Pre-condición: estaba submitted con un score.
    let pre: (Option<chrono::DateTime<chrono::Utc>>, i64) = sqlx::query_as(
        r#"SELECT e.submitted_at,
                  (SELECT COUNT(*) FROM evaluacion_scores WHERE evaluacion_id = e.id)
           FROM evaluaciones e WHERE e.id = $1"#,
    )
    .bind(id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(pre.0.is_some());
    assert_eq!(pre.1, 1);

    let (status, body) = post(
        pool.clone(),
        &format!("/admin/evaluaciones/{id}/reopen"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["submitted_at"].is_null());

    // Persistido: submitted_at en null, scores intactos.
    let post: (Option<chrono::DateTime<chrono::Utc>>, i64) = sqlx::query_as(
        r#"SELECT e.submitted_at,
                  (SELECT COUNT(*) FROM evaluacion_scores WHERE evaluacion_id = e.id)
           FROM evaluaciones e WHERE e.id = $1"#,
    )
    .bind(id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(post.0.is_none(), "submitted_at debe ser null tras reopen");
    assert_eq!(post.1, 1, "los scores no se borran al reopen");

    // Y el score sigue siendo el correcto.
    let s: i32 = sqlx::query_scalar(
        "SELECT score FROM evaluacion_scores WHERE evaluacion_id = $1 AND criterion_id = $2",
    )
    .bind(id)
    .bind(c1)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(s, 3);
}

#[sqlx::test(migrations = "../../migrations")]
async fn reopen_on_draft_is_409(pool: PgPool) {
    // No tiene sentido reabrir un draft — ya es editable.
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(id)
    .bind(p)
    .bind(j)
    .bind(r)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        r#"INSERT INTO evaluacion_scores (evaluacion_id, criterion_id, score)
           VALUES ($1, $2, 1)"#,
    )
    .bind(id)
    .bind(c1)
    .execute(&pool)
    .await
    .unwrap();

    let (status, _) = post(
        pool,
        &format!("/admin/evaluaciones/{id}/reopen"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn jurado_can_resubmit_after_reopen(pool: PgPool) {
    // Tras reopen, el jurado dueño puede re-enviar (no debe quedar bloqueado
    // por el unique constraint sobre (prototipo, jurado, template)).
    let (_, atok) = admin(&pool).await;

    let e = seed_edition(&pool, 2024).await;
    set_edition_phase(&pool, e, "evaluacion").await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    // Usamos el helper jurado() para poder firmar el bearer.
    let (j_id, jtok) = jurado(&pool).await;
    common::assign_jurado(&pool, j_id, p, r).await;
    let id = seed_submitted_evaluacion(&pool, p, j_id, r, &[(c1, 2)]).await;

    // Admin reabre.
    let (s_reopen, _) = post(
        pool.clone(),
        &format!("/admin/evaluaciones/{id}/reopen"),
        Some(&atok),
    )
    .await;
    assert_eq!(s_reopen, StatusCode::OK);

    // Jurado re-envía (status 200 + submitted_at no null).
    let (s_submit, body) = post(pool, &format!("/evaluaciones/{id}/submit"), Some(&jtok)).await;
    assert_eq!(s_submit, StatusCode::OK, "body: {body}");
    assert!(body["submitted_at"].is_string());
}
