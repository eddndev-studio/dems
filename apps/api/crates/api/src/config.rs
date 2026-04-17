use anyhow::Context;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub host: String,
    pub port: u16,
    pub jwt_secret: String,
    pub jwt_access_ttl_secs: i64,
    pub jwt_refresh_ttl_secs: i64,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            database_url: std::env::var("DATABASE_URL").context("DATABASE_URL missing")?,
            host: std::env::var("API_HOST").unwrap_or_else(|_| "0.0.0.0".into()),
            port: std::env::var("API_PORT")
                .unwrap_or_else(|_| "8080".into())
                .parse()?,
            jwt_secret: std::env::var("JWT_SECRET").context("JWT_SECRET missing")?,
            jwt_access_ttl_secs: std::env::var("JWT_ACCESS_TTL_SECS")
                .unwrap_or_else(|_| "900".into())
                .parse()?,
            jwt_refresh_ttl_secs: std::env::var("JWT_REFRESH_TTL_SECS")
                .unwrap_or_else(|_| "2592000".into())
                .parse()?,
        })
    }
}
