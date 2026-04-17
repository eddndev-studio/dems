//! Integration tests for admin CRUD on /admin/prototipos.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, assign_jurado, build_app, insert_prototipo, insert_user, jurado, seed_categoria,
    seed_edition, seed_rubric_template,
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

#[sqlx::test(migrations = "../../migrations")]
async fn create_prototipo_with_categorias_and_integrantes(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat1 = seed_categoria(&pool, "software", "Software").await;
    let cat2 = seed_categoria(&pool, "salud", "Salud").await;

    let (status, body) = request(
        pool.clone(),
        "POST",
        "/admin/prototipos",
        Some(&tok),
        Some(json!({
            "edition_id": e,
            "folio": "CECYT-01-2024",
            "nombre": "Sistema X",
            "plantel": "CECyT 9",
            "eje_transversal": true,
            "descripcion": "Plataforma de foo",
            "categorias": [cat1, cat2],
            "integrantes": [
                { "nombre": "Ana", "rol": "líder" },
                { "nombre": "Luis", "rol": "desarrollo" }
            ]
        })),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    assert_eq!(body["folio"], "CECYT-01-2024");
    assert_eq!(body["eje_transversal"], true);
    assert_eq!(body["categorias"].as_array().unwrap().len(), 2);
    assert_eq!(body["integrantes"].as_array().unwrap().len(), 2);

    let p_id: Uuid = body["id"].as_str().unwrap().parse().unwrap();
    let integrantes: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM prototipo_integrantes WHERE prototipo_id = $1",
    )
    .bind(p_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(integrantes, 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_duplicate_folio_in_same_edition(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let _ = insert_prototipo(&pool, e, "F-01", "P1").await;

    let (status, _) = request(
        pool,
        "POST",
        "/admin/prototipos",
        Some(&tok),
        Some(json!({
            "edition_id": e, "folio": "F-01", "nombre": "dup"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_allows_same_folio_in_different_editions(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e1 = seed_edition(&pool, 2024).await;
    let e2 = seed_edition(&pool, 2025).await;
    let _ = insert_prototipo(&pool, e1, "F-01", "P24").await;

    let (status, _) = request(
        pool,
        "POST",
        "/admin/prototipos",
        Some(&tok),
        Some(json!({ "edition_id": e2, "folio": "F-01", "nombre": "P25" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn list_filters_by_edition(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e1 = seed_edition(&pool, 2024).await;
    let e2 = seed_edition(&pool, 2025).await;
    let _ = insert_prototipo(&pool, e1, "A", "A").await;
    let _ = insert_prototipo(&pool, e2, "B", "B").await;

    let (status, body) = request(
        pool,
        "GET",
        &format!("/admin/prototipos?edition_id={e1}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = body.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["folio"], "A");
}

#[sqlx::test(migrations = "../../migrations")]
async fn get_by_id_returns_full_tree(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Soft").await;
    let (created_status, created) = request(
        pool.clone(),
        "POST",
        "/admin/prototipos",
        Some(&tok),
        Some(json!({
            "edition_id": e, "folio": "F", "nombre": "P",
            "categorias": [cat],
            "integrantes": [{ "nombre": "Ana", "rol": "líder" }]
        })),
    )
    .await;
    assert_eq!(created_status, StatusCode::CREATED);
    let id = created["id"].as_str().unwrap();

    let (status, body) = request(
        pool,
        "GET",
        &format!("/admin/prototipos/{id}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["id"], json!(id));
    assert_eq!(body["categorias"][0], json!(cat));
    assert_eq!(body["integrantes"].as_array().unwrap().len(), 1);
    assert_eq!(body["integrantes"][0]["nombre"], "Ana");
}

#[sqlx::test(migrations = "../../migrations")]
async fn patch_updates_metadata(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let pid = insert_prototipo(&pool, e, "F", "Viejo").await;

    let (status, body) = request(
        pool,
        "PATCH",
        &format!("/admin/prototipos/{pid}"),
        Some(&tok),
        Some(json!({ "nombre": "Nuevo", "plantel": "CECyT 5" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["nombre"], "Nuevo");
    assert_eq!(body["plantel"], "CECyT 5");
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_prototipo_with_no_evaluations(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let pid = insert_prototipo(&pool, e, "F", "P").await;

    let (status, _) = request(
        pool,
        "DELETE",
        &format!("/admin/prototipos/{pid}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn delete_rejected_when_has_evaluations(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let pid = insert_prototipo(&pool, e, "F", "P").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let jid = insert_user(&pool, "j@x.mx", "J", "jurado", "pw", true).await;
    assign_jurado(&pool, jid, pid, r).await;
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(Uuid::new_v4())
    .bind(pid)
    .bind(jid)
    .bind(r)
    .execute(&pool)
    .await
    .unwrap();

    let (status, _) = request(
        pool,
        "DELETE",
        &format!("/admin/prototipos/{pid}"),
        Some(&tok),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn prototipos_crud_is_403_for_jurado(pool: PgPool) {
    let (_, tok) = jurado(&pool).await;
    let (s1, _) = request(pool.clone(), "GET", "/admin/prototipos", Some(&tok), None).await;
    assert_eq!(s1, StatusCode::FORBIDDEN);
    let (s2, _) = request(
        pool,
        "POST",
        "/admin/prototipos",
        Some(&tok),
        Some(json!({ "edition_id": Uuid::new_v4(), "folio": "x", "nombre": "x" })),
    )
    .await;
    assert_eq!(s2, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn create_rejects_unknown_categoria(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let ghost = Uuid::new_v4();

    let (status, _) = request(
        pool.clone(),
        "POST",
        "/admin/prototipos",
        Some(&tok),
        Some(json!({
            "edition_id": e, "folio": "F", "nombre": "P",
            "categorias": [ghost]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Rollback: no quedó el prototipo.
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM prototipos")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0);
}
