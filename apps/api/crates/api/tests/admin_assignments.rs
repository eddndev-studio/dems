//! Integration tests for admin CRUD on /admin/assignments.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, build_app, insert_prototipo, insert_user, jurado, seed_edition, seed_rubric_template,
};

async fn request(
    pool: PgPool,
    method: &str,
    path: &str,
    tok: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let app = build_app(pool);
    let mut req = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json");
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let body = match body {
        Some(v) => Body::from(v.to_string()),
        None => Body::empty(),
    };
    let resp = app.oneshot(req.body(body).unwrap()).await.unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

async fn setup(pool: &PgPool) -> (Uuid, Uuid, Uuid) {
    let e = seed_edition(pool, 2024).await;
    let p = insert_prototipo(pool, e, "F-01", "P").await;
    let r = seed_rubric_template(pool, e, "R", "exhibicion").await;
    (p, r, e)
}

#[sqlx::test(migrations = "../../migrations")]
async fn assign_jurado_to_prototipo(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (p, r, _) = setup(&pool).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;

    let (status, body) = request(
        pool.clone(),
        "POST",
        "/admin/assignments",
        Some(&tok),
        Some(json!({ "jurado_id": j, "prototipo_id": p, "template_id": r })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert_eq!(body["jurado_id"], json!(j));
    assert_eq!(body["prototipo_id"], json!(p));
    assert_eq!(body["template_id"], json!(r));

    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM assignments
           WHERE jurado_id = $1 AND prototipo_id = $2 AND template_id = $3"#,
    )
    .bind(j)
    .bind(p)
    .bind(r)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn assign_rejects_non_jurado_user(pool: PgPool) {
    // Admin no puede ser asignado como jurado.
    let (admin_id, tok) = admin(&pool).await;
    let (p, r, _) = setup(&pool).await;

    let (status, _) = request(
        pool,
        "POST",
        "/admin/assignments",
        Some(&tok),
        Some(json!({ "jurado_id": admin_id, "prototipo_id": p, "template_id": r })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn assign_is_idempotent_for_same_triple(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (p, r, _) = setup(&pool).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;

    let body = json!({ "jurado_id": j, "prototipo_id": p, "template_id": r });
    let (s1, _) = request(pool.clone(), "POST", "/admin/assignments", Some(&tok), Some(body.clone())).await;
    assert_eq!(s1, StatusCode::CREATED);

    // Segunda vez: 200 (no duplica), porque ya existe la fila exacta.
    let (s2, _) = request(pool.clone(), "POST", "/admin/assignments", Some(&tok), Some(body)).await;
    assert_eq!(s2, StatusCode::OK);

    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM assignments")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn assign_rejects_mismatched_edition(pool: PgPool) {
    // jurado asignado a un prototipo de 2024 con una rúbrica de 2025 —
    // la rúbrica y el prototipo deben pertenecer a la misma edición.
    let (_, tok) = admin(&pool).await;
    let e1 = seed_edition(&pool, 2024).await;
    let e2 = seed_edition(&pool, 2025).await;
    let p = insert_prototipo(&pool, e1, "F", "P").await;
    let r = seed_rubric_template(&pool, e2, "R", "exhibicion").await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;

    let (status, _) = request(
        pool,
        "POST",
        "/admin/assignments",
        Some(&tok),
        Some(json!({ "jurado_id": j, "prototipo_id": p, "template_id": r })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_assignments_for_a_prototipo(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (p, r, _) = setup(&pool).await;
    let j1 = insert_user(&pool, "j1@x.mx", "J1", "jurado", "pw", true).await;
    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;

    for j in &[j1, j2] {
        let _ = request(
            pool.clone(),
            "POST",
            "/admin/assignments",
            Some(&tok),
            Some(json!({ "jurado_id": j, "prototipo_id": p, "template_id": r })),
        )
        .await;
    }

    let (status, body) = request(
        pool,
        "GET",
        &format!("/admin/prototipos/{p}/assignments"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 2);
    // Cada item trae el nombre del jurado — útil para la UI.
    assert!(items[0]["jurado"]["full_name"].is_string());
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_assignment_when_no_evaluation(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (p, r, _) = setup(&pool).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let _ = request(
        pool.clone(),
        "POST",
        "/admin/assignments",
        Some(&tok),
        Some(json!({ "jurado_id": j, "prototipo_id": p, "template_id": r })),
    )
    .await;

    let (status, _) = request(
        pool.clone(),
        "DELETE",
        &format!("/admin/assignments?jurado_id={j}&prototipo_id={p}&template_id={r}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM assignments")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_rejected_when_evaluation_exists(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (p, r, _) = setup(&pool).await;
    let j = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let _ = request(
        pool.clone(),
        "POST",
        "/admin/assignments",
        Some(&tok),
        Some(json!({ "jurado_id": j, "prototipo_id": p, "template_id": r })),
    )
    .await;

    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(Uuid::new_v4())
    .bind(p)
    .bind(j)
    .bind(r)
    .execute(&pool)
    .await
    .unwrap();

    let (status, _) = request(
        pool,
        "DELETE",
        &format!("/admin/assignments?jurado_id={j}&prototipo_id={p}&template_id={r}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn assignments_crud_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let (p, r, _) = setup(&pool).await;
    let (status, _) = request(
        pool,
        "POST",
        "/admin/assignments",
        Some(&tok),
        Some(json!({ "jurado_id": Uuid::new_v4(), "prototipo_id": p, "template_id": r })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
