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
    }
}

pub fn build_app(pool: PgPool) -> Router {
    routes::router(AppState::new(pool, test_config()))
}

/// Mint a JWT for integration tests. Bypasses the login flow when the test
/// only cares about what a given role can reach.
pub fn token_for(user_id: Uuid, role: UserRole, ttl: i64, kind: TokenKind) -> String {
    auth::issue(&test_config().jwt_secret, user_id, role, ttl, kind).unwrap()
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
    sqlx::query(
        r#"INSERT INTO editions (id, year, name, active) VALUES ($1, $2, $3, false)"#,
    )
    .bind(id)
    .bind(year)
    .bind(format!("Edición {year}"))
    .execute(pool)
    .await
    .expect("insert edition");
    id
}

/// Insert a categoría and return its id.
pub async fn seed_categoria(pool: &PgPool, slug: &str, nombre: &str) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO categorias (id, slug, nombre, orden) VALUES ($1, $2, $3, 1)"#,
    )
    .bind(id)
    .bind(slug)
    .bind(nombre)
    .execute(pool)
    .await
    .expect("insert categoria");
    id
}
