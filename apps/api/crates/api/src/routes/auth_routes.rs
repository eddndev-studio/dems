use std::sync::LazyLock;

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

/// Hash argon2 dummy fijo (computado una vez por proceso). Cuando el email no
/// existe verificamos la contraseña contra este hash para que el tiempo de
/// respuesta sea indistinguible del caso "email válido, contraseña errónea" y
/// no se pueda enumerar usuarios por timing.
static DUMMY_PASSWORD_HASH: LazyLock<String> =
    LazyLock::new(|| password::hash("dummy-password-for-timing-equalization").expect("dummy hash"));

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

#[utoipa::path(
    post,
    path = "/auth/login",
    tag = "auth",
    request_body = LoginRequest,
    responses(
        (status = 200, description = "Tokens emitidos", body = LoginResponse),
        (status = 401, description = "Credenciales inválidas o usuario inactivo"),
        (status = 400, description = "Body inválido"),
    ),
)]
pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> ApiResult<Json<LoginResponse>> {
    req.validate()
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    let row = sqlx::query_as::<_, (Uuid, String, String, UserRole, String, bool, i32)>(
        r#"SELECT id, email, full_name, role, password_hash, is_active, token_version
           FROM users WHERE email = $1"#,
    )
    .bind(&req.email)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let Some((id, email, full_name, role, password_hash, is_active, token_version)) = row else {
        // El email no existe. Corremos un verify contra un hash dummy fijo para
        // igualar el tiempo de respuesta del camino "email existe pero password
        // incorrecta": así un atacante no distingue ambos casos por timing (no
        // puede enumerar emails registrados).
        let _ = password::verify(&req.password, &DUMMY_PASSWORD_HASH);
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
        token_version,
    )
    .map_err(|e| ApiError::Internal(anyhow::anyhow!(e)))?;
    let refresh_token = auth::issue(
        &state.cfg.jwt_secret,
        id,
        role,
        state.cfg.jwt_refresh_ttl_secs,
        TokenKind::Refresh,
        token_version,
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

#[utoipa::path(
    get,
    path = "/me",
    tag = "auth",
    responses(
        (status = 200, description = "Usuario autenticado", body = UserView),
        (status = 401, description = "Sin token o token inválido"),
    ),
    security(("bearer_auth" = [])),
)]
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

#[utoipa::path(
    post,
    path = "/auth/refresh",
    tag = "auth",
    request_body = RefreshRequest,
    responses(
        (status = 200, description = "Nuevos tokens", body = RefreshResponse),
        (status = 401, description = "Refresh token inválido o usuario inactivo"),
    ),
)]
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

    // Confirmamos que el usuario sigue activo y que el token no fue revocado.
    // Un admin que desactiva a un jurado (o le resetea la contraseña) incrementa
    // users.token_version: el refresh viejo lleva la versión anterior en su
    // claim, así que deja de servir.
    let row = sqlx::query_as::<_, (bool, i32)>(
        r#"SELECT is_active, token_version FROM users WHERE id = $1"#,
    )
    .bind(claims.sub)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let Some((is_active, token_version)) = row else {
        return Err(ApiError::Core(dems_core::CoreError::Unauthorized));
    };
    if !is_active || claims.token_version != token_version {
        return Err(ApiError::Core(dems_core::CoreError::Unauthorized));
    }

    let access_token = auth::issue(
        &state.cfg.jwt_secret,
        claims.sub,
        claims.role,
        state.cfg.jwt_access_ttl_secs,
        TokenKind::Access,
        token_version,
    )
    .map_err(|e| ApiError::Internal(anyhow::anyhow!(e)))?;
    // Rotamos también el refresh por higiene (el cliente reemplaza su token en
    // cada renovación). Esto NO mitiga un robo por sí solo: sin denylist, el
    // refresh viejo sigue siendo válido hasta su exp. La revocación real es por
    // `token_version`: un reset de contraseña o una desactivación lo incrementan
    // y cortan TANTO el access (vía el extractor CurrentUser) COMO el refresh
    // (vía el check de arriba).
    let refresh_token = auth::issue(
        &state.cfg.jwt_secret,
        claims.sub,
        claims.role,
        state.cfg.jwt_refresh_ttl_secs,
        TokenKind::Refresh,
        token_version,
    )
    .map_err(|e| ApiError::Internal(anyhow::anyhow!(e)))?;

    Ok(Json(RefreshResponse {
        access_token,
        refresh_token,
    }))
}
