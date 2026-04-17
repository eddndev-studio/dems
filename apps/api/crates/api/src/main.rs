use std::net::SocketAddr;

use anyhow::Context;

mod config;
mod error;
mod state;
mod auth;
mod password;
mod routes;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "dems_api=debug,tower_http=debug,sqlx=warn".into()),
        )
        .init();

    let cfg = config::Config::from_env().context("loading config")?;

    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(16)
        .connect(&cfg.database_url)
        .await
        .context("connecting to postgres")?;

    sqlx::migrate!("../../migrations")
        .run(&pool)
        .await
        .context("running migrations")?;

    let state = state::AppState::new(pool, cfg.clone());

    let app = routes::router(state);

    let addr: SocketAddr = format!("{}:{}", cfg.host, cfg.port).parse()?;
    tracing::info!("listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
