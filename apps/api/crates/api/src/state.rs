use sqlx::PgPool;

use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub cfg: Config,
}

impl AppState {
    pub fn new(pool: PgPool, cfg: Config) -> Self {
        Self { pool, cfg }
    }
}
