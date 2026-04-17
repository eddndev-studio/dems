use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use dems_core::models::UserRole;

use crate::auth::{self, TokenKind};
use crate::error::{ApiError, ApiResult};
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
    pub user: LoginUser,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct LoginUser {
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

    // Fetch user + hash. Unknown email vs. wrong password collapse to the
    // same 401 so attackers can't enumerate users.
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
    let ok = password::verify(&req.password, &password_hash)
        .map_err(|e| ApiError::Internal(e))?;
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
        user: LoginUser {
            id,
            email,
            full_name,
            role,
        },
    }))
}
