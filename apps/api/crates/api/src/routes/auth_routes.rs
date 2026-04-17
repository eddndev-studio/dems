use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use dems_core::models::UserRole;

use crate::auth::{self, TokenKind};
use crate::error::{ApiError, ApiResult};
use crate::extractors::CurrentUser;
use crate::password;
use crate::state::AppState;

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 1))]
    pub password: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct LoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub user: UserView,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct UserView {
    pub id: Uuid,
    pub email: String,
    pub full_name: String,
    pub role: UserRole,
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> ApiResult<Json<LoginResponse>> {
    req.validate()
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    let row = sqlx::query_as::<_, (Uuid, String, String, UserRole, String, bool)>(
        r#"SELECT id, email, full_name, role, password_hash, is_active
           FROM users WHERE email = $1"#,
    )
    .bind(&req.email)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let Some((id, email, full_name, role, password_hash, is_active)) = row else {
        return Err(ApiError::Core(dems_core::CoreError::Unauthorized));
    };
    if !is_active {
        return Err(ApiError::Core(dems_core::CoreError::Unauthorized));
    }
    let ok = password::verify(&req.password, &password_hash).map_err(ApiError::Internal)?;
    if !ok {
        return Err(ApiError::Core(dems_core::CoreError::Unauthorized));
    }

    let access_token = auth::issue(
        &state.cfg.jwt_secret,
        id,
        role,
        state.cfg.jwt_access_ttl_secs,
        TokenKind::Access,
    )
    .map_err(|e| ApiError::Internal(anyhow::anyhow!(e)))?;
    let refresh_token = auth::issue(
        &state.cfg.jwt_secret,
        id,
        role,
        state.cfg.jwt_refresh_ttl_secs,
        TokenKind::Refresh,
    )
    .map_err(|e| ApiError::Internal(anyhow::anyhow!(e)))?;

    Ok(Json(LoginResponse {
        access_token,
        refresh_token,
        user: UserView {
            id,
            email,
            full_name,
            role,
        },
    }))
}

pub async fn me(user: CurrentUser) -> Json<UserView> {
    Json(UserView {
        id: user.id,
        email: user.email,
        full_name: user.full_name,
        role: user.role,
    })
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RefreshResponse {
    pub access_token: String,
    pub refresh_token: String,
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(req): Json<RefreshRequest>,
) -> ApiResult<Json<RefreshResponse>> {
    // Solo aceptamos tokens kind=refresh — un access token robado no debe
    // poder renovar tokens indefinidamente.
    let claims = auth::verify_kind(
        &state.cfg.jwt_secret,
        &req.refresh_token,
        TokenKind::Refresh,
    )
    .map_err(|_| ApiError::Core(dems_core::CoreError::Unauthorized))?;

    // Confirmamos que el usuario sigue activo: un admin que desactiva a
    // un jurado debe cortarle la renovación de tokens.
    let is_active = sqlx::query_scalar::<_, bool>(r#"SELECT is_active FROM users WHERE id = $1"#)
        .bind(claims.sub)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    if is_active != Some(true) {
        return Err(ApiError::Core(dems_core::CoreError::Unauthorized));
    }

    let access_token = auth::issue(
        &state.cfg.jwt_secret,
        claims.sub,
        claims.role,
        state.cfg.jwt_access_ttl_secs,
        TokenKind::Access,
    )
    .map_err(|e| ApiError::Internal(anyhow::anyhow!(e)))?;
    // Rotamos también el refresh: limita el impacto si un refresh se filtra.
    let refresh_token = auth::issue(
        &state.cfg.jwt_secret,
        claims.sub,
        claims.role,
        state.cfg.jwt_refresh_ttl_secs,
        TokenKind::Refresh,
    )
    .map_err(|e| ApiError::Internal(anyhow::anyhow!(e)))?;

    Ok(Json(RefreshResponse {
        access_token,
        refresh_token,
    }))
}
