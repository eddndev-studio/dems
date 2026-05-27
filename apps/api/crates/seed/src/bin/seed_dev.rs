//! Seed dev-only fixtures: un jurado de prueba, prototipos en dos categorías,
//! y asignaciones (una memoria + dos exhibición) para ver la UI móvil con datos.
//!
//! Idempotente: corre `just seed-dev` las veces que quieras. Asume que
//! `just db-seed` ya corrió antes (edición activa + categorías + templates).

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;

use dems_seed::dev;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt().with_env_filter("info").init();

    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL missing")?;
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&database_url)
        .await?;

    dev::run(&pool).await?;

    tracing::info!(
        "seed-dev listo. Login como jurado: {} / {}",
        dev::JURADO_EMAIL,
        dev::JURADO_PASSWORD
    );
    Ok(())
}
