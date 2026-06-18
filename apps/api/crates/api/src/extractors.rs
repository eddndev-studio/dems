//! Axum extractors.

use async_trait::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use uuid::Uuid;

use dems_core::models::UserRole;
use dems_core::CoreError;

use crate::auth::{self, TokenKind};
use crate::error::ApiError;
use crate::state::AppState;

/// The authenticated caller — populated from a Bearer access token.
///
/// Extraction fails with 401 when:
/// - no Authorization header is present
/// - the header is not a well-formed `Bearer <jwt>`
/// - the JWT is invalid, expired, or of the wrong kind (e.g. a refresh token)
/// - the referenced user does not exist or is inactive
/// - the token's `token_version` no longer matches `users.token_version`
///   (un reset de contraseña o una desactivación lo incrementan, revocando de
///   inmediato el access token —no sólo el refresh).
#[derive(Debug, Clone)]
pub struct CurrentUser {
    pub id: Uuid,
    pub email: String,
    pub full_name: String,
    pub role: UserRole,
}

#[async_trait]
impl FromRequestParts<AppState> for CurrentUser {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .ok_or(ApiError::Core(CoreError::Unauthorized))?
            .to_str()
            .map_err(|_| ApiError::Core(CoreError::Unauthorized))?;

        let token = header
            .strip_prefix("Bearer ")
            .ok_or(ApiError::Core(CoreError::Unauthorized))?;

        let claims = auth::verify_kind(&state.cfg.jwt_secret, token, TokenKind::Access)
            .map_err(|_| ApiError::Core(CoreError::Unauthorized))?;

        let row = sqlx::query_as::<_, (Uuid, String, String, UserRole, bool, i32)>(
            r#"SELECT id, email, full_name, role, is_active, token_version
               FROM users WHERE id = $1"#,
        )
        .bind(claims.sub)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

        let Some((id, email, full_name, role, is_active, token_version)) = row else {
            return Err(ApiError::Core(CoreError::Unauthorized));
        };
        if !is_active {
            return Err(ApiError::Core(CoreError::Unauthorized));
        }
        // Revocación inmediata del access token: si el usuario bumpeó su
        // token_version (reset de contraseña o desactivación), el access token
        // viejo lleva la versión anterior en su claim y deja de servir —sin
        // esperar a que expire por TTL ni a que el cliente intente refrescar.
        if claims.token_version != token_version {
            return Err(ApiError::Core(CoreError::Unauthorized));
        }

        Ok(CurrentUser {
            id,
            email,
            full_name,
            role,
        })
    }
}

/// Admin-only extractor. Rejects any authenticated caller whose role is not
/// `admin` with 403, and falls back to `CurrentUser`'s 401 on missing or
/// invalid credentials.
#[derive(Debug, Clone)]
pub struct RequireAdmin(pub CurrentUser);

#[async_trait]
impl FromRequestParts<AppState> for RequireAdmin {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let user = CurrentUser::from_request_parts(parts, state).await?;
        if !matches!(user.role, UserRole::Admin) {
            return Err(ApiError::Core(CoreError::Forbidden));
        }
        Ok(RequireAdmin(user))
    }
}
