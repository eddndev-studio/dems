//! Integration tests for GET /admin/results/edition/:id/export.csv.
//!
//! Devuelve un CSV con todos los prototipos de la edición y sus promedios,
//! agrupados por categoría. Una fila por (categoria, prototipo).

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use common::{
    admin, attach_categoria, build_app, insert_prototipo, insert_user, jurado, seed_categoria,
    seed_draft_evaluacion, seed_edition, seed_rubric_template, seed_section_with_criterion,
    seed_submitted_evaluacion,
};

async fn get(
    pool: PgPool,
    path: &str,
    tok: Option<&str>,
) -> (StatusCode, Vec<(String, String)>, String) {
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
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let body = String::from_utf8_lossy(&bytes).to_string();
    (status, headers, body)
}

#[sqlx::test(migrations = "../../migrations")]
async fn requires_auth(pool: PgPool) {
    let e = seed_edition(&pool, 2024).await;
    let (status, _, _) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.csv"),
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
        &format!("/admin/results/edition/{e}/export.csv"),
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
        &format!("/admin/results/edition/{ghost}/export.csv"),
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
        &format!("/admin/results/edition/{e}/export.csv?rubric_type=bogus"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[sqlx::test(migrations = "../../migrations")]
async fn empty_edition_returns_only_header(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let (status, headers, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.csv"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let ct = headers
        .iter()
        .find(|(k, _)| k == "content-type")
        .map(|(_, v)| v.as_str())
        .unwrap_or("");
    assert!(ct.starts_with("text/csv"), "content-type was: {ct}");
    let cd = headers
        .iter()
        .find(|(k, _)| k == "content-disposition")
        .map(|(_, v)| v.as_str())
        .unwrap_or("");
    assert!(cd.contains("attachment"));
    assert!(cd.contains("2024"));
    assert!(cd.contains("exhibicion"));
    let lines: Vec<&str> = body.lines().collect();
    assert_eq!(lines.len(), 1, "header only: {body:?}");
    assert_eq!(
        lines[0],
        "categoria_slug,categoria,folio,prototipo,n_jurados,promedio,max_total"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn lists_one_row_per_categoria_prototipo(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat_a = seed_categoria(&pool, "soft", "Software").await;
    let cat_b = seed_categoria(&pool, "salud", "Salud").await;
    let r = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let (_, c1) = seed_section_with_criterion(&pool, r, 1, "C1", 3).await;
    let (_, c2) = seed_section_with_criterion(&pool, r, 2, "C2", 3).await;

    let p1 = insert_prototipo(&pool, e, "F1", "Uno").await;
    let p2 = insert_prototipo(&pool, e, "F2", "Dos").await;
    let p_multi = insert_prototipo(&pool, e, "F3", "MultiCat").await;
    attach_categoria(&pool, p1, cat_a).await;
    attach_categoria(&pool, p2, cat_b).await;
    attach_categoria(&pool, p_multi, cat_a).await;
    attach_categoria(&pool, p_multi, cat_b).await;

    let j1 = insert_user(&pool, "j1@x.mx", "J1", "jurado", "pw", true).await;
    let j2 = insert_user(&pool, "j2@x.mx", "J2", "jurado", "pw", true).await;
    seed_submitted_evaluacion(&pool, p1, j1, r, &[(c1, 3), (c2, 3)]).await; // 6
    seed_submitted_evaluacion(&pool, p1, j2, r, &[(c1, 1), (c2, 1)]).await; // 2 → avg 4
    seed_submitted_evaluacion(&pool, p2, j1, r, &[(c1, 2), (c2, 2)]).await; // 4 → avg 4
    seed_submitted_evaluacion(&pool, p_multi, j1, r, &[(c1, 0), (c2, 0)]).await; // 0 → avg 0
    seed_draft_evaluacion(&pool, p_multi, j2, r, &[(c1, 3)]).await; // ignored

    let (status, _, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.csv"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let lines: Vec<&str> = body.lines().collect();
    // 1 header + 4 rows (p1-soft, p2-salud, p_multi-soft, p_multi-salud)
    assert_eq!(lines.len(), 5, "lines:\n{body}");

    // Helper para encontrar fila.
    let find_row = |slug: &str, folio: &str| {
        lines
            .iter()
            .find(|l| l.starts_with(&format!("{slug},")) && l.contains(&format!(",{folio},")))
            .copied()
            .unwrap_or_else(|| panic!("row not found {slug}/{folio} in:\n{body}"))
    };

    let row_p1 = find_row("soft", "F1");
    assert!(row_p1.contains(",2,4,6"), "row: {row_p1}");
    let row_p2 = find_row("salud", "F2");
    assert!(row_p2.contains(",1,4,6"), "row: {row_p2}");
    let row_multi_a = find_row("soft", "F3");
    assert!(row_multi_a.contains(",1,0,6"), "row: {row_multi_a}");
    let row_multi_b = find_row("salud", "F3");
    assert!(row_multi_b.contains(",1,0,6"), "row: {row_multi_b}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn includes_prototipos_without_evaluations(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Software").await;
    let _ = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let p = insert_prototipo(&pool, e, "F", "P").await;
    attach_categoria(&pool, p, cat).await;

    let (status, _, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.csv"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let row = body
        .lines()
        .find(|l| l.contains(",F,"))
        .unwrap_or_else(|| panic!("body: {body}"));
    // n_jurados=0, promedio vacío.
    assert!(row.ends_with(",0,,0"), "row: {row}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn quotes_fields_with_commas_or_quotes(pool: PgPool) {
    let (_, tok) = admin(&pool).await;
    let e = seed_edition(&pool, 2024).await;
    let cat = seed_categoria(&pool, "soft", "Software, S.A.").await;
    let _ = seed_rubric_template(&pool, e, "R", "exhibicion").await;
    let p = insert_prototipo(&pool, e, "F", r#"Robot "Mecha", v2"#).await;
    attach_categoria(&pool, p, cat).await;

    let (status, _, body) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.csv"),
        Some(&tok),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // El nombre de la categoría tiene coma → debe ir entre comillas.
    assert!(
        body.contains(r#""Software, S.A.""#),
        "missing quoted categoria: {body}"
    );
    // El nombre del prototipo tiene comilla y coma → comillas y escape doble.
    assert!(
        body.contains(r#""Robot ""Mecha"", v2""#),
        "missing quoted prototipo: {body}"
    );
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

    let (_, _, body_exhi) = get(
        pool.clone(),
        &format!("/admin/results/edition/{e}/export.csv?rubric_type=exhibicion"),
        Some(&tok),
    )
    .await;
    let row_e = body_exhi.lines().nth(1).unwrap();
    assert!(row_e.ends_with(",1,3,3"), "exhi row: {row_e}");

    let (_, headers, body_mem) = get(
        pool,
        &format!("/admin/results/edition/{e}/export.csv?rubric_type=memoria"),
        Some(&tok),
    )
    .await;
    let row_m = body_mem.lines().nth(1).unwrap();
    assert!(row_m.ends_with(",1,1,3"), "mem row: {row_m}");
    let cd = headers
        .iter()
        .find(|(k, _)| k == "content-disposition")
        .map(|(_, v)| v.as_str())
        .unwrap_or("");
    assert!(cd.contains("memoria"), "filename should reflect tipo: {cd}");
}
