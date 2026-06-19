//! Seed default data: admin user, current edition, 7 categorías, and the
//! 2024 Exhibición + 2021 Memoria Técnica rubric templates.

use anyhow::Context;
use dems_seed::{loader, rubrics};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt().with_env_filter("info").init();

    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL missing")?;
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(4)
        .connect(&database_url)
        .await?;

    let edition_id = rubrics::seed(&pool).await?;
    loader::load_data(&pool, edition_id).await?;
    tracing::info!("seed completed");
    Ok(())
}
