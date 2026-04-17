//! Admin CRUD for jurado↔prototipo↔template assignments.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::extractors::RequireAdmin;
use crate::state::AppState;

#[derive(Debug, Serialize, ToSchema)]
pub struct AssignmentView {
    pub jurado_id: Uuid,
    pub prototipo_id: Uuid,
    pub template_id: Uuid,
    pub assigned_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct AssignmentWithJuradoView {
    pub jurado: JuradoSummary,
    pub template_id: Uuid,
    pub assigned_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct JuradoSummary {
    pub id: Uuid,
    pub full_name: String,
    pub email: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateAssignmentRequest {
    pub jurado_id: Uuid,
    pub prototipo_id: Uuid,
    pub template_id: Uuid,
}

#[derive(Debug, Deserialize)]
pub struct DeleteParams {
    pub jurado_id: Uuid,
    pub prototipo_id: Uuid,
    pub template_id: Uuid,
}

// ---------------------------------------------------------------------------
// Create (idempotent)
// ---------------------------------------------------------------------------

pub async fn create(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<CreateAssignmentRequest>,
) -> ApiResult<impl IntoResponse> {
    // Validación semántica que el FK-check no cubre:
    // 1) user debe existir y tener role='jurado'
    // 2) prototipo.edition_id == rubric_template.edition_id
    let role: Option<String> = sqlx::query_scalar("SELECT role::text FROM users WHERE id = $1")
        .bind(req.jurado_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    match role.as_deref() {
        Some("jurado") => {}
        Some(_) => {
            return Err(ApiError::Core(dems_core::CoreError::Validation(
                "user is not a jurado".into(),
            )))
        }
        None => {
            return Err(ApiError::Core(dems_core::CoreError::Validation(
                "jurado_id unknown".into(),
            )))
        }
    }

    let eds: Option<(Uuid, Uuid)> = sqlx::query_as(
        r#"SELECT p.edition_id, r.edition_id
           FROM prototipos p, rubric_templates r
           WHERE p.id = $1 AND r.id = $2"#,
    )
    .bind(req.prototipo_id)
    .bind(req.template_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    match eds {
        Some((pe, re)) if pe == re => {}
        Some(_) => {
            return Err(ApiError::Core(dems_core::CoreError::Validation(
                "prototipo and template belong to different editions".into(),
            )))
        }
        None => {
            return Err(ApiError::Core(dems_core::CoreError::Validation(
                "prototipo_id or template_id unknown".into(),
            )))
        }
    }

    // INSERT ... ON CONFLICT DO NOTHING para idempotencia.
    let result = sqlx::query_as::<_, (DateTime<Utc>,)>(
        r#"INSERT INTO assignments (jurado_id, prototipo_id, template_id)
           VALUES ($1, $2, $3)
           ON CONFLICT (jurado_id, prototipo_id, template_id) DO NOTHING
           RETURNING assigned_at"#,
    )
    .bind(req.jurado_id)
    .bind(req.prototipo_id)
    .bind(req.template_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let (assigned_at, status) = match result {
        Some((at,)) => (at, StatusCode::CREATED),
        None => {
            // Ya existía — regresamos la existente con 200.
            let at: DateTime<Utc> = sqlx::query_scalar(
                r#"SELECT assigned_at FROM assignments
                   WHERE jurado_id = $1 AND prototipo_id = $2 AND template_id = $3"#,
            )
            .bind(req.jurado_id)
            .bind(req.prototipo_id)
            .bind(req.template_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
            (at, StatusCode::OK)
        }
    };

    Ok((
        status,
        Json(AssignmentView {
            jurado_id: req.jurado_id,
            prototipo_id: req.prototipo_id,
            template_id: req.template_id,
            assigned_at,
        }),
    ))
}

// ---------------------------------------------------------------------------
// List for a prototipo
// ---------------------------------------------------------------------------

pub async fn list_for_prototipo(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(prototipo_id): Path<Uuid>,
) -> ApiResult<Json<Vec<AssignmentWithJuradoView>>> {
    let rows = sqlx::query_as::<_, (Uuid, String, String, Uuid, DateTime<Utc>)>(
        r#"SELECT u.id, u.full_name, u.email, a.template_id, a.assigned_at
           FROM assignments a
           JOIN users u ON u.id = a.jurado_id
           WHERE a.prototipo_id = $1
           ORDER BY u.full_name"#,
    )
    .bind(prototipo_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(Json(
        rows.into_iter()
            .map(
                |(id, full_name, email, template_id, assigned_at)| AssignmentWithJuradoView {
                    jurado: JuradoSummary {
                        id,
                        full_name,
                        email,
                    },
                    template_id,
                    assigned_at,
                },
            )
            .collect(),
    ))
}

// ---------------------------------------------------------------------------
// Delete (compound key via query string)
// ---------------------------------------------------------------------------

pub async fn delete(
    State(state): State<AppState>,
    _: RequireAdmin,
    Query(q): Query<DeleteParams>,
) -> ApiResult<StatusCode> {
    // Si ya existe una evaluación para este (prototipo, jurado, template),
    // romper la asignación rompería la cadena de custodia del puntaje.
    let has_eval: bool = sqlx::query_scalar(
        r#"SELECT EXISTS (
               SELECT 1 FROM evaluaciones
               WHERE prototipo_id = $1 AND jurado_id = $2 AND template_id = $3
           )"#,
    )
    .bind(q.prototipo_id)
    .bind(q.jurado_id)
    .bind(q.template_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if has_eval {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "an evaluation already exists for this triple; cannot unassign".into(),
        )));
    }

    let affected = sqlx::query(
        r#"DELETE FROM assignments
           WHERE jurado_id = $1 AND prototipo_id = $2 AND template_id = $3"#,
    )
    .bind(q.jurado_id)
    .bind(q.prototipo_id)
    .bind(q.template_id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }
    Ok(StatusCode::NO_CONTENT)
}
