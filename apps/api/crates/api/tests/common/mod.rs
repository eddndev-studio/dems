//! Shared helpers for integration tests.

use axum::Router;
use sqlx::PgPool;
use uuid::Uuid;

use dems_api::{config::Config, password, routes, state::AppState};

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

/// Insert a user and return its id. Password is hashed with argon2.
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
