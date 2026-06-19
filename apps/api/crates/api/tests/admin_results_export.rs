//! Integration tests for GET /admin/results/edition/:id/export.xlsx.
//!
//! Exporta un libro de Excel (.xlsx) con los prototipos de la edición y sus
//! promedios. El endpoint reemplazó al antiguo CSV (PR #5): el cuerpo es binario
//! (zip OOXML), así que aquí verificamos auth/validación, los headers, y que se
//! produce un .xlsx válido — no el contenido celda a celda.

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, attach_categoria, build_app, insert_prototipo, insert_user, jurado, seed_categoria,
    seed_edition, seed_rubric_template, seed_section_with_criterion, seed_submitted_evaluacion,
};

/// GET helper que devuelve (status, headers, cuerpo en bytes).
async fn get(
    pool: PgPool,
    path: &str,
    tok: Option<&str>,
) -> (StatusCode, Vec<(String, String)>, Vec<u8>) {
    let app = build_app(pool);
    let mut req = Request::builder().method("GET").uri(path);
    if let Some(t) = tok {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app.oneshot(req.body(Body::empty()).unwrap()).await.unwrap();
    let status = resp.status();
    let headers: Vec<(String, String)> = resp
        .headers()
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
        .collect();
    let bytes = resp
        .into_body()
        .collect()
        .await
        .unwrap()
        .to_bytes()
        .to_vec();
    (status, headers, bytes)
}

fn header<'a>(headers: &'a [(String, String)], key: &str) -> &'a str {
    headers
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.as_str())
        .unwrap_or("")
}

/// Un .xlsx es un zip OOXML: empieza con la firma local de zip "PK\x03\x04".
fn is_xlsx(bytes: &[u8]) -> bool {
    bytes.len() > 4 && bytes[0] == b'P' && bytes[1] == b'K'
}

#[sqlx::test(migrations = "../../migrations")]
async fn requires_auth(pool: PgPool) {
    let e = seed_edition(&pool, 2024).await;
    let (status, _, _) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.xlsx"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn jurado_forbidden(pool: PgPool) {
    let (_, jtok) = jurado(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, _, _) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.xlsx"),
        Some(&jtok),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn unknown_edition_is_404(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let ghost = Uuid::new_v4();
    let (status, _, _) = get(
        pool,
        &format!("/admin/results/edition/{ghost}/export.xlsx"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn invalid_rubric_type_is_400(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, _, _) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.xlsx?rubric_type=bogus"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[sqlx::test(migrations = "../../migrations")]
async fn empty_edition_exports_valid_xlsx(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, headers, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.xlsx"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let ct = header(&headers, "content-type");
    assert!(ct.contains("spreadsheetml.sheet"), "content-type was: {ct}");
    let cd = header(&headers, "content-disposition");
    assert!(cd.contains("attachment"));
    assert!(cd.contains("2024"));
    assert!(cd.contains("exhibicion"));
    assert!(cd.contains(".xlsx"));
    assert!(
        is_xlsx(&body),
        "body is not a valid xlsx ({} bytes)",
        body.len()
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn exports_valid_xlsx_with_data(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Software").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C1", 3).await;
    let (_, c2) = seed_section_with_criterion(&pool, r, 2, "C2", 3).await;
    let p1 = insert_prototipo(&pool, e, "F1", "Uno").await;
    let p2 = insert_prototipo(&pool, e, "F2", "Sin evaluar").await;
    attach_categoria(&pool, p1, cat).await;
    attach_categoria(&pool, p2, cat).await;
    let j1 = insert_user(&pool, "j1@x.mx", "J1", "jurado", "pw", true).await;
    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;
    seed_submitted_evaluacion(&pool, p1, j1, r, &[(c1, 3), (c2, 3)]).await;
    seed_submitted_evaluacion(&pool, p1, j2, r, &[(c1, 1), (c2, 1)]).await;

    let (status, headers, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.xlsx"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(header(&headers, "content-type").contains("spreadsheetml.sheet"),);
    assert!(
        is_xlsx(&body),
        "body is not a valid xlsx ({} bytes)",
        body.len()
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn filters_by_rubric_type_in_filename(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;

    let (s1, h1, b1) = get(
        pool.clone(),
        &format!("/admin/results/edition/{e}/export.xlsx?rubric_type=exhibicion"),
        Some(&tok),
    )
    .await;
    assert_eq!(s1, StatusCode::OK);
    assert!(header(&h1, "content-disposition").contains("exhibicion"));
    assert!(is_xlsx(&b1));

    let (s2, h2, b2) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.xlsx?rubric_type=memoria"),
        Some(&tok),
    )
    .await;
    assert_eq!(s2, StatusCode::OK);
    assert!(
        header(&h2, "content-disposition").contains("memoria"),
        "filename should reflect tipo"
    );
    assert!(is_xlsx(&b2));
}
