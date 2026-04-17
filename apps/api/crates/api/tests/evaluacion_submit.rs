//! Integration tests for POST /evaluaciones/:id/submit.

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

async fn submit(pool: PgPool, id: &str, tok: Option<&str>) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method("POST")
        .uri(format!("/evaluaciones/{id}/submit"));
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
async fn submit_sets_submitted_at_when_all_scored(pool: PgPool) {
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
            "scores": [
                { "criterion_id": c1, "score": 2 },
                { "criterion_id": c2, "score": 3 }
            ]
        }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, body) = submit(pool.clone(), &id, Some(&tok)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["submitted_at"].is_string());

    // Persistido.
    let row: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("SELECT submitted_at FROM evaluaciones WHERE id = $1::uuid")
            .bind(Uuid::parse_str(&id).unwrap())
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(row.is_some());
}

#[sqlx::test(migrations = "../../migrations")]
async fn submit_is_409_when_unscored_criterion(pool: PgPool) {
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C1", 3).await;
    let (_, _c2) = seed_section_with_criterion(&pool, r, 2, "C2", 3).await; // no scored
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

    let (status, _) = submit(pool.clone(), &id, Some(&tok)).await;
    assert_eq!(status, StatusCode::CONFLICT);

    // submitted_at sigue en null.
    let row: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("SELECT submitted_at FROM evaluaciones WHERE id = $1::uuid")
            .bind(Uuid::parse_str(&id).unwrap())
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(row.is_none());
}

#[sqlx::test(migrations = "../../migrations")]
async fn submit_is_409_when_already_submitted(pool: PgPool) {
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

    let (s1, _) = submit(pool.clone(), &id, Some(&tok)).await;
    assert_eq!(s1, StatusCode::OK);

    let (s2, _) = submit(pool, &id, Some(&tok)).await;
    assert_eq!(s2, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn other_jurado_cant_submit(pool: PgPool) {
    let (j1, t1) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    assign_jurado(&pool, j1, p, r).await;
    let created = post_eval(
        pool.clone(),
        &t1,
        json!({
            "prototipo_id": p, "template_id": r,
            "scores": [{ "criterion_id": c1, "score": 2 }]
        }),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;
    let t2 = token_for(j2, UserRole::Jurado, 900, TokenKind::Access);

    let (status, _) = submit(pool, &id, Some(&t2)).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn submit_ignores_text_key_criteria(pool: PgPool) {
    // Las preguntas clave (kind=text_key) no puntúan — no deberían bloquear
    // el submit si el jurado no llenó el texto.
    let (j_id, tok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C", 3).await;
    // Insertamos una pregunta clave manualmente.
    let tk_id = Uuid::new_v4();
    let sec = sqlx::query_scalar::<_, Uuid>(
        r#"INSERT INTO rubric_sections (id, template_id, nombre, orden)
           VALUES ($1, $2, 'Clave', 99) RETURNING id"#,
    )
    .bind(Uuid::new_v4())
    .bind(r)
    .fetch_one(&pool)
    .await
    .unwrap();
    sqlx::query(
        r#"INSERT INTO rubric_criteria (id, section_id, texto, orden, max_score, kind)
           VALUES ($1, $2, 'Clave', 1, 0, 'text_key'::criterion_kind)"#,
    )
    .bind(tk_id)
    .bind(sec)
    .execute(&pool)
    .await
    .unwrap();
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

    let (status, _) = submit(pool, &id, Some(&tok)).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "text_key criteria must not block submit"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn submit_is_404_for_unknown_id(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let ghost = Uuid::new_v4().to_string();
    let (status, _) = submit(pool, &ghost, Some(&tok)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
