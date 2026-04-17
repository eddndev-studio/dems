//! Integration tests for admin CRUD on /admin/users.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{admin, build_app, insert_user, jurado};

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

#[sqlx::test(migrations = "../../migrations")]
async fn create_jurado(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (status, body) = request(
        pool.clone(),
        "POST",
        "/admin/users",
        Some(&tok),
        Some(json!({
            "email": "nuevo@dems.mx",
            "full_name": "Nuevo Jurado",
            "role": "jurado",
            "password": "pw-inicial-12"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert!(body["id"].is_string());
    assert_eq!(body["email"], "nuevo@dems.mx");
    assert_eq!(body["role"], "jurado");
    assert_eq!(body["is_active"], true);
    // El hash nunca sale al cliente.
    assert!(
        body.get("password").is_none() && body.get("password_hash").is_none(),
        "password must never leak: {body}"
    );

    // Persistido con hash (no plano).
    let hash: String = sqlx::query_scalar("SELECT password_hash FROM users WHERE email = $1")
        .bind("nuevo@dems.mx")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(hash.starts_with("$argon2"));
    assert!(!hash.contains("pw-inicial-12"));
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_duplicate_email(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let _ = insert_user(&pool, "dup@x.mx", "D", "jurado", "pw", true).await;
    let (status, _) = request(
        pool,
        "POST",
        "/admin/users",
        Some(&tok),
        Some(json!({
            "email": "dup@x.mx", "full_name": "D", "role": "jurado", "password": "pw-nueva-1"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_short_password(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let (status, _) = request(
        pool,
        "POST",
        "/admin/users",
        Some(&tok),
        Some(json!({
            "email": "x@y.mx", "full_name": "x", "role": "jurado", "password": "short"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_users_filters_by_role(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let _ = insert_user(&pool, "j1@x.mx", "J1", "jurado", "pw", true).await;
    let _ = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;

    let (status, body) = request(
        pool.clone(),
        "GET",
        "/admin/users?role=jurado",
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // Solo jurados: j1, j2. El admin que creamos para el token no aparece.
    assert_eq!(body.as_array().unwrap().len(), 2);

    let (_, all) = request(pool, "GET", "/admin/users", Some(&tok), None).await;
    assert_eq!(all.as_array().unwrap().len(), 3, "j1 + j2 + admin");
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_updates_name_and_active(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let jid = insert_user(&pool, "j@x.mx", "Viejo", "jurado", "pw", true).await;

    let (status, body) = request(
        pool,
        "PATCH",
        &format!("/admin/users/{jid}"),
        Some(&tok),
        Some(json!({ "full_name": "Nuevo", "is_active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["full_name"], "Nuevo");
    assert_eq!(body["is_active"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn reset_password_changes_hash(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let jid = insert_user(&pool, "j@x.mx", "J", "jurado", "viejo-pw-12", true).await;
    let before: String = sqlx::query_scalar("SELECT password_hash FROM users WHERE id = $1")
        .bind(jid)
        .fetch_one(&pool)
        .await
        .unwrap();

    let (status, _) = request(
        pool.clone(),
        "PUT",
        &format!("/admin/users/{jid}/password"),
        Some(&tok),
        Some(json!({ "password": "nueva-pw-34" })),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let after: String = sqlx::query_scalar("SELECT password_hash FROM users WHERE id = $1")
        .bind(jid)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_ne!(before, after, "password_hash must change after reset");
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_user_with_no_evaluations(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let jid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let (status, _) = request(
        pool,
        "DELETE",
        &format!("/admin/users/{jid}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_rejected_when_user_has_evaluations(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let jid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;

    // Sembrar edición + prototipo + rúbrica + evaluación para jid.
    let eid = common::seed_edition(&pool, 2024).await;
    let p = common::insert_prototipo(&pool, eid, "F", "P").await;
    let r = common::seed_rubric_template(&pool, eid, "R", "exhibicion").await;
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(Uuid::new_v4())
    .bind(p)
    .bind(jid)
    .bind(r)
    .execute(&pool)
    .await
    .unwrap();

    let (status, _) = request(
        pool,
        "DELETE",
        &format!("/admin/users/{jid}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn users_crud_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let (s1, _) = request(pool.clone(), "GET", "/admin/users", Some(&tok), None).await;
    assert_eq!(s1, StatusCode::FORBIDDEN);
    let (s2, _) = request(
        pool,
        "POST",
        "/admin/users",
        Some(&tok),
        Some(
            json!({ "email": "a@b.c", "full_name": "a", "role": "jurado", "password": "12345678" }),
        ),
    )
    .await;
    assert_eq!(s2, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_user_by_id(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let jid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    let (status, body) = request(
        pool,
        "GET",
        &format!("/admin/users/{jid}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["id"], jid.to_string());
    assert_eq!(body["email"], "j@x.mx");
}
