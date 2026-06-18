use anyhow::Context;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub host: String,
    pub port: u16,
    pub jwt_secret: String,
    pub jwt_access_ttl_secs: i64,
    pub jwt_refresh_ttl_secs: i64,
    /// Si `false`, no se monta Swagger UI ni `/openapi.json`. Fail-safe: el
    /// default es `false`, así que un despliegue que olvida la variable NO
    /// expone el esquema. Sólo se activa con `ENABLE_DOCS` in {"true","1"}
    /// (el `.env.example` lo pone en `true` para dev).
    pub enable_docs: bool,
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
            // Fail-safe: default false. Sólo se habilita con un opt-in
            // explícito ("true" o "1"); cualquier otro valor —o la ausencia de
            // la variable— deja la documentación apagada.
            enable_docs: parse_enable_docs(std::env::var("ENABLE_DOCS").ok().as_deref()),
        })
    }

    /// Emite un `warn!` prominente si el `JWT_SECRET` es débil (vacío, el
    /// placeholder de plantilla, o < 32 bytes). No falla el arranque: dev y
    /// tests usan deliberadamente un secreto corto.
    pub fn warn_if_weak_jwt_secret(&self) {
        if jwt_secret_is_weak(&self.jwt_secret) {
            tracing::warn!(
                "JWT_SECRET is weak (empty, placeholder, or < 32 bytes). \
                 Set a strong random secret in production — tokens are forgeable otherwise."
            );
        }
    }
}

/// `true` si el secreto JWT es débil: vacío, el placeholder de plantilla, o
/// menor a 32 bytes.
pub fn jwt_secret_is_weak(secret: &str) -> bool {
    secret.is_empty() || secret == "change-me-in-production" || secret.len() < 32
}

/// Fail-safe parse de `ENABLE_DOCS`: sólo `"true"` o `"1"` habilitan la
/// documentación. Ausencia (`None`) o cualquier otro valor → `false`, para que
/// un despliegue que olvida la variable no exponga el esquema por accidente.
fn parse_enable_docs(raw: Option<&str>) -> bool {
    matches!(raw, Some("true") | Some("1"))
}

#[cfg(test)]
mod tests {
    use super::{jwt_secret_is_weak, parse_enable_docs};

    #[test]
    fn enable_docs_defaults_to_false() {
        // #14 fail-safe: ausencia de la variable ⇒ docs apagadas.
        assert!(!parse_enable_docs(None));
    }

    #[test]
    fn enable_docs_only_opt_in_values_enable() {
        assert!(parse_enable_docs(Some("true")));
        assert!(parse_enable_docs(Some("1")));
        // Cualquier otro valor (incluido el viejo "false"/"0", pero también
        // ruido) deja docs apagadas.
        assert!(!parse_enable_docs(Some("false")));
        assert!(!parse_enable_docs(Some("0")));
        assert!(!parse_enable_docs(Some("TRUE")));
        assert!(!parse_enable_docs(Some("yes")));
        assert!(!parse_enable_docs(Some("")));
    }

    #[test]
    fn weak_secrets_are_flagged() {
        assert!(jwt_secret_is_weak(""));
        assert!(jwt_secret_is_weak("change-me-in-production"));
        assert!(jwt_secret_is_weak("short"));
        // 31 bytes — justo por debajo del umbral.
        assert!(jwt_secret_is_weak(&"a".repeat(31)));
    }

    #[test]
    fn strong_secret_is_accepted() {
        // 32 bytes aleatorios.
        assert!(!jwt_secret_is_weak("0123456789abcdef0123456789abcdef"));
        assert!(!jwt_secret_is_weak(&"x".repeat(64)));
    }
}
