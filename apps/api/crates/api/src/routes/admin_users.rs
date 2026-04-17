//! Admin CRUD for users (admins + jurados).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use dems_core::models::UserRole;

use crate::error::{ApiError, ApiResult};
use crate::extractors::RequireAdmin;
use crate::password;
use crate::state::AppState;

#[derive(Debug, Serialize, ToSchema, sqlx::FromRow)]
pub struct UserView {
    pub id: Uuid,
    pub email: String,
    pub full_name: String,
    pub role: UserRole,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreateUserRequest {
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 1, max = 200))]
    pub full_name: String,
    pub role: UserRole,
    #[validate(length(min = 8, max = 128))]
    pub password: String,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct PatchUserRequest {
    #[serde(default)]
    #[validate(length(min = 1, max = 200))]
    pub full_name: Option<String>,
    #[serde(default)]
    pub role: Option<UserRole>,
    #[serde(default)]
    pub is_active: Option<bool>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct ResetPasswordRequest {
    #[validate(length(min = 8, max = 128))]
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct ListParams {
    pub role: Option<UserRole>,
    pub is_active: Option<bool>,
}

fn role_as_sql(r: UserRole) -> &'static str {
    match r {
        UserRole::Admin => "admin",
        UserRole::Jurado => "jurado",
    }
}

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

pub async fn create(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<CreateUserRequest>,
) -> ApiResult<impl IntoResponse> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    let hash = password::hash(&req.password).map_err(ApiError::Internal)?;
    let id = Uuid::new_v4();
    let view = sqlx::query_as::<_, UserView>(
        r#"INSERT INTO users (id, email, full_name, role, password_hash, is_active)
           VALUES ($1, $2, $3, $4::user_role, $5, true)
           RETURNING id, email, full_name, role, is_active, created_at, updated_at"#,
    )
    .bind(id)
    .bind(&req.email)
    .bind(&req.full_name)
    .bind(role_as_sql(req.role))
    .bind(&hash)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(db) = &e {
            if db.is_unique_violation() {
                return ApiError::Core(dems_core::CoreError::Conflict(
                    "email already registered".into(),
                ));
            }
        }
        ApiError::Internal(e.into())
    })?;

    Ok((StatusCode::CREATED, Json(view)))
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

pub async fn list(
    State(state): State<AppState>,
    _: RequireAdmin,
    Query(params): Query<ListParams>,
) -> ApiResult<Json<Vec<UserView>>> {
    let rows = sqlx::query_as::<_, UserView>(
        r#"SELECT id, email, full_name, role, is_active, created_at, updated_at
           FROM users
           WHERE ($1::user_role IS NULL OR role = $1)
             AND ($2::boolean IS NULL OR is_active = $2)
           ORDER BY full_name"#,
    )
    .bind(params.role)
    .bind(params.is_active)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    Ok(Json(rows))
}

// ---------------------------------------------------------------------------
// Get by id
// ---------------------------------------------------------------------------

pub async fn get_by_id(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<UserView>> {
    let row = sqlx::query_as::<_, UserView>(
        r#"SELECT id, email, full_name, role, is_active, created_at, updated_at
           FROM users WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;
    Ok(Json(row))
}

// ---------------------------------------------------------------------------
// Patch
// ---------------------------------------------------------------------------

pub async fn patch(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
    Json(req): Json<PatchUserRequest>,
) -> ApiResult<Json<UserView>> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    let role_sql = req.role.map(role_as_sql);
    let view = sqlx::query_as::<_, UserView>(
        r#"UPDATE users
           SET full_name = COALESCE($2, full_name),
               role = COALESCE($3::user_role, role),
               is_active = COALESCE($4, is_active)
           WHERE id = $1
           RETURNING id, email, full_name, role, is_active, created_at, updated_at"#,
    )
    .bind(id)
    .bind(&req.full_name)
    .bind(role_sql)
    .bind(req.is_active)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;
    Ok(Json(view))
}

// ---------------------------------------------------------------------------
// Reset password
// ---------------------------------------------------------------------------

pub async fn reset_password(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
    Json(req): Json<ResetPasswordRequest>,
) -> ApiResult<StatusCode> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    let hash = password::hash(&req.password).map_err(ApiError::Internal)?;
    let affected = sqlx::query("UPDATE users SET password_hash = $2 WHERE id = $1")
        .bind(id)
        .bind(&hash)
        .execute(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

pub async fn delete(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    // Preservamos historial: un jurado con evaluaciones no se borra, se
    // desactiva vía PATCH { is_active: false }.
    let has_evals: bool =
        sqlx::query_scalar(r#"SELECT EXISTS (SELECT 1 FROM evaluaciones WHERE jurado_id = $1)"#)
            .bind(id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;

    if has_evals {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "user has evaluations; deactivate via PATCH is_active=false instead".into(),
        )));
    }

    let affected = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }
    Ok(StatusCode::NO_CONTENT)
}
