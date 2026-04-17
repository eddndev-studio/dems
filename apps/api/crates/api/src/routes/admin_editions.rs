//! Admin CRUD for editions.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use crate::error::{ApiError, ApiResult};
use crate::extractors::RequireAdmin;
use crate::state::AppState;

#[derive(Debug, Serialize, ToSchema, sqlx::FromRow)]
pub struct EditionView {
    pub id: Uuid,
    pub year: i32,
    pub name: String,
    pub active: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreateEditionRequest {
    #[validate(range(min = 2000, max = 2100))]
    pub year: i32,
    #[validate(length(min = 1, max = 200))]
    pub name: String,
    #[serde(default)]
    pub active: bool,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct PatchEditionRequest {
    #[serde(default)]
    #[validate(length(min = 1, max = 200))]
    pub name: Option<String>,
    #[serde(default)]
    pub active: Option<bool>,
}

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

pub async fn create(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<CreateEditionRequest>,
) -> ApiResult<impl IntoResponse> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    // Si se crea como activa, desactivamos la otra primero (solo una activa).
    if req.active {
        sqlx::query("UPDATE editions SET active = false WHERE active = true")
            .execute(&mut *tx)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
    }

    let id = Uuid::new_v4();
    let view = sqlx::query_as::<_, EditionView>(
        r#"INSERT INTO editions (id, year, name, active)
           VALUES ($1, $2, $3, $4)
           RETURNING id, year, name, active, created_at"#,
    )
    .bind(id)
    .bind(req.year)
    .bind(&req.name)
    .bind(req.active)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(db) = &e {
            if db.is_unique_violation() {
                return ApiError::Core(dems_core::CoreError::Conflict(
                    "edition year already exists".into(),
                ));
            }
        }
        ApiError::Internal(e.into())
    })?;

    tx.commit()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    Ok((StatusCode::CREATED, Json(view)))
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

pub async fn list(
    State(state): State<AppState>,
    _: RequireAdmin,
) -> ApiResult<Json<Vec<EditionView>>> {
    let rows = sqlx::query_as::<_, EditionView>(
        r#"SELECT id, year, name, active, created_at
           FROM editions ORDER BY year DESC"#,
    )
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
) -> ApiResult<Json<EditionView>> {
    let row = sqlx::query_as::<_, EditionView>(
        r#"SELECT id, year, name, active, created_at
           FROM editions WHERE id = $1"#,
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
    Json(req): Json<PatchEditionRequest>,
) -> ApiResult<Json<EditionView>> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    // Verificar que existe antes de tocar nada.
    let exists: Option<bool> = sqlx::query_scalar("SELECT active FROM editions WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    if exists.is_none() {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }

    // Si se va a activar, desactivamos la(s) otra(s) primero para no violar
    // el partial unique index idx_editions_one_active.
    if req.active == Some(true) {
        sqlx::query("UPDATE editions SET active = false WHERE active = true AND id != $1")
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
    }

    let view = sqlx::query_as::<_, EditionView>(
        r#"UPDATE editions
           SET name = COALESCE($2, name),
               active = COALESCE($3, active)
           WHERE id = $1
           RETURNING id, year, name, active, created_at"#,
    )
    .bind(id)
    .bind(&req.name)
    .bind(req.active)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    tx.commit()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    Ok(Json(view))
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

pub async fn delete(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    // Si hay rúbricas o prototipos con esta edición, no borramos —
    // preservamos la historia del concurso. El admin puede desactivarla.
    let has_refs: bool = sqlx::query_scalar(
        r#"SELECT EXISTS (
               SELECT 1 FROM rubric_templates WHERE edition_id = $1
               UNION ALL
               SELECT 1 FROM prototipos WHERE edition_id = $1
           )"#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if has_refs {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "edition has rubric_templates or prototipos; deactivate instead".into(),
        )));
    }

    let affected = sqlx::query("DELETE FROM editions WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }
    Ok(StatusCode::NO_CONTENT)
}
