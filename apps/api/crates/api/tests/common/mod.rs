//! Shared helpers for integration tests.

use axum::Router;
use sqlx::PgPool;
use uuid::Uuid;

use dems_api::auth::{self, TokenKind};
use dems_api::{config::Config, password, routes, state::AppState};
use dems_core::models::UserRole;

pub fn test_config() -> Config {
    Config {
        database_url: "unused-by-tests".into(),
        host: "127.0.0.1".into(),
        port: 0,
        jwt_secret: "test-jwt-secret-please-change".into(),
        jwt_access_ttl_secs: 900,
        jwt_refresh_ttl_secs: 2_592_000,
        enable_docs: true,
    }
}

pub fn build_app(pool: PgPool) -> Router {
    routes::router(AppState::new(pool, test_config()))
}

/// Mint a JWT for integration tests. Bypasses the login flow when the test
/// only cares about what a given role can reach.
pub fn token_for(user_id: Uuid, role: UserRole, ttl: i64, kind: TokenKind) -> String {
    auth::issue(&test_config().jwt_secret, user_id, role, ttl, kind, 0).unwrap()
}

/// Mint a token embedding an explicit `token_version` claim — used by refresh
/// revocation tests that need a stale version.
#[allow(dead_code)]
pub fn token_for_version(
    user_id: Uuid,
    role: UserRole,
    ttl: i64,
    kind: TokenKind,
    token_version: i32,
) -> String {
    auth::issue(
        &test_config().jwt_secret,
        user_id,
        role,
        ttl,
        kind,
        token_version,
    )
    .unwrap()
}

/// Insert a user; password is argon2-hashed. Returns the user id.
pub async fn insert_user(
    pool: &PgPool,
    email: &str,
    full_name: &str,
    role: &str,
    password_plain: &str,
    is_active: bool,
) -> Uuid {
    let id = Uuid::new_v4();
    let hash = password::hash(password_plain).unwrap();
    sqlx::query(
        r#"INSERT INTO users (id, email, full_name, role, password_hash, is_active)
           VALUES ($1, $2, $3, $4::user_role, $5, $6)"#,
    )
    .bind(id)
    .bind(email)
    .bind(full_name)
    .bind(role)
    .bind(&hash)
    .bind(is_active)
    .execute(pool)
    .await
    .expect("insert user");
    id
}

/// Insert an active admin and return `(id, bearer_token)`.
pub async fn admin(pool: &PgPool) -> (Uuid, String) {
    let id = insert_user(pool, "admin@test.mx", "Admin Test", "admin", "pw", true).await;
    let tok = token_for(id, UserRole::Admin, 900, TokenKind::Access);
    (id, tok)
}

/// Insert an active jurado and return `(id, bearer_token)`.
pub async fn jurado(pool: &PgPool) -> (Uuid, String) {
    let id = insert_user(pool, "jurado@test.mx", "Jurado Test", "jurado", "pw", true).await;
    let tok = token_for(id, UserRole::Jurado, 900, TokenKind::Access);
    (id, tok)
}

/// Insert an edition and return its id. Inactive by default because the
/// partial unique index `idx_editions_one_active` forbids more than one
/// active edition at a time, which would bite any test that needs two.
pub async fn seed_edition(pool: &PgPool, year: i32) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(r#"INSERT INTO editions (id, year, name, active) VALUES ($1, $2, $3, false)"#)
        .bind(id)
        .bind(year)
        .bind(format!("Edición {year}"))
        .execute(pool)
        .await
        .expect("insert edition");
    id
}

/// Force an edition into a given phase ('preparacion' | 'evaluacion' | 'cerrada').
pub async fn set_edition_phase(pool: &PgPool, edition_id: Uuid, phase: &str) {
    sqlx::query("UPDATE editions SET phase = $2::edition_phase WHERE id = $1")
        .bind(edition_id)
        .bind(phase)
        .execute(pool)
        .await
        .expect("set edition phase");
}

/// Insert a prototipo and return its id.
pub async fn insert_prototipo(pool: &PgPool, edition_id: Uuid, folio: &str, nombre: &str) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO prototipos (id, edition_id, folio, nombre)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(id)
    .bind(edition_id)
    .bind(folio)
    .bind(nombre)
    .execute(pool)
    .await
    .expect("insert prototipo");
    id
}

/// Assign a jurado to a prototipo under a specific rubric template.
pub async fn assign_jurado(pool: &PgPool, jurado_id: Uuid, prototipo_id: Uuid, template_id: Uuid) {
    sqlx::query(
        r#"INSERT INTO assignments (jurado_id, prototipo_id, template_id)
           VALUES ($1, $2, $3)"#,
    )
    .bind(jurado_id)
    .bind(prototipo_id)
    .bind(template_id)
    .execute(pool)
    .await
    .expect("insert assignment");
}

/// Insert a minimal rubric template (empty tree) and return its id.
pub async fn seed_rubric_template(
    pool: &PgPool,
    edition_id: Uuid,
    nombre: &str,
    tipo: &str,
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_templates (id, edition_id, nombre, tipo, activo)
           VALUES ($1, $2, $3, $4::rubric_type, true)"#,
    )
    .bind(id)
    .bind(edition_id)
    .bind(nombre)
    .bind(tipo)
    .execute(pool)
    .await
    .expect("insert rubric_template");
    id
}

/// Insert a section with a single criterion and return (section_id, criterion_id).
pub async fn seed_section_with_criterion(
    pool: &PgPool,
    template_id: Uuid,
    section_orden: i32,
    criterion_texto: &str,
    max_score: i32,
) -> (Uuid, Uuid) {
    let section_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_sections (id, template_id, nombre, orden)
           VALUES ($1, $2, 'S', $3)"#,
    )
    .bind(section_id)
    .bind(template_id)
    .bind(section_orden)
    .execute(pool)
    .await
    .expect("insert section");

    let criterion_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_criteria (id, section_id, texto, orden, max_score, kind)
           VALUES ($1, $2, $3, 1, $4, 'scale'::criterion_kind)"#,
    )
    .bind(criterion_id)
    .bind(section_id)
    .bind(criterion_texto)
    .bind(max_score)
    .execute(pool)
    .await
    .expect("insert criterion");

    (section_id, criterion_id)
}

/// Insert a categoría and return its id.
pub async fn seed_categoria(pool: &PgPool, slug: &str, nombre: &str) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(r#"INSERT INTO categorias (id, slug, nombre, orden) VALUES ($1, $2, $3, 1)"#)
        .bind(id)
        .bind(slug)
        .bind(nombre)
        .execute(pool)
        .await
        .expect("insert categoria");
    id
}

/// Attach a prototipo to a categoría.
pub async fn attach_categoria(pool: &PgPool, prototipo_id: Uuid, categoria_id: Uuid) {
    sqlx::query(r#"INSERT INTO prototipo_categorias (prototipo_id, categoria_id) VALUES ($1, $2)"#)
        .bind(prototipo_id)
        .bind(categoria_id)
        .execute(pool)
        .await
        .expect("insert prototipo_categoria");
}

/// Insert an already-submitted evaluación with the given per-criterion scores.
/// Bypasses the assignment check — only call this from tests.
pub async fn seed_submitted_evaluacion(
    pool: &PgPool,
    prototipo_id: Uuid,
    jurado_id: Uuid,
    template_id: Uuid,
    scores: &[(Uuid, i32)],
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id, submitted_at)
           VALUES ($1, $2, $3, $4, NOW())"#,
    )
    .bind(id)
    .bind(prototipo_id)
    .bind(jurado_id)
    .bind(template_id)
    .execute(pool)
    .await
    .expect("insert evaluacion");

    for (criterion_id, score) in scores {
        sqlx::query(
            r#"INSERT INTO evaluacion_scores (evaluacion_id, criterion_id, score)
               VALUES ($1, $2, $3)"#,
        )
        .bind(id)
        .bind(criterion_id)
        .bind(score)
        .execute(pool)
        .await
        .expect("insert evaluacion_score");
    }
    id
}

/// Insert a draft (unsubmitted) evaluación with scores. Bypasses ACL.
pub async fn seed_draft_evaluacion(
    pool: &PgPool,
    prototipo_id: Uuid,
    jurado_id: Uuid,
    template_id: Uuid,
    scores: &[(Uuid, i32)],
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)"#,
    )
    .bind(id)
    .bind(prototipo_id)
    .bind(jurado_id)
    .bind(template_id)
    .execute(pool)
    .await
    .expect("insert evaluacion");

    for (criterion_id, score) in scores {
        sqlx::query(
            r#"INSERT INTO evaluacion_scores (evaluacion_id, criterion_id, score)
               VALUES ($1, $2, $3)"#,
        )
        .bind(id)
        .bind(criterion_id)
        .bind(score)
        .execute(pool)
        .await
        .expect("insert evaluacion_score");
    }
    id
}
