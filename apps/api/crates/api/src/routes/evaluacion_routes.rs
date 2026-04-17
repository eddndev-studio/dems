//! Evaluation endpoints used by the jurado app.

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::extractors::CurrentUser;
use crate::state::AppState;

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateEvaluacionRequest {
    pub prototipo_id: Uuid,
    pub template_id: Uuid,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct EvaluacionView {
    pub id: Uuid,
    pub prototipo_id: Uuid,
    pub template_id: Uuid,
    pub jurado_id: Uuid,
    pub submitted_at: Option<DateTime<Utc>>,
    pub observaciones: Option<String>,
    pub acompanamiento_asesor: Option<bool>,
    pub opinion_personal: Option<i32>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

pub async fn create(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(req): Json<CreateEvaluacionRequest>,
) -> ApiResult<impl IntoResponse> {
    // Authorisation comes from `assignments`, not from role: only the jurado
    // assigned to (prototipo, template) can create the evaluation.
    // Unknown ids also fail this check (no assignment row exists), which
    // conveniently prevents ID enumeration.
    let assigned: bool = sqlx::query_scalar(
        r#"SELECT EXISTS (
               SELECT 1 FROM assignments
               WHERE jurado_id = $1 AND prototipo_id = $2 AND template_id = $3
           )"#,
    )
    .bind(user.id)
    .bind(req.prototipo_id)
    .bind(req.template_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if !assigned {
        return Err(ApiError::Core(dems_core::CoreError::Forbidden));
    }

    let id = Uuid::new_v4();
    let row = sqlx::query_as::<_, (
        Uuid,
        Uuid,
        Uuid,
        Uuid,
        Option<DateTime<Utc>>,
        Option<String>,
        Option<bool>,
        Option<i32>,
        DateTime<Utc>,
        DateTime<Utc>,
    )>(
        r#"INSERT INTO evaluaciones (id, prototipo_id, jurado_id, template_id)
           VALUES ($1, $2, $3, $4)
           RETURNING id, prototipo_id, jurado_id, template_id,
                     submitted_at, observaciones, acompanamiento_asesor,
                     opinion_personal, created_at, updated_at"#,
    )
    .bind(id)
    .bind(req.prototipo_id)
    .bind(user.id)
    .bind(req.template_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(db) = &e {
            if db.is_unique_violation() {
                return ApiError::Core(dems_core::CoreError::Conflict(
                    "evaluation already exists for this prototipo/template".into(),
                ));
            }
        }
        ApiError::Internal(e.into())
    })?;

    let view = EvaluacionView {
        id: row.0,
        prototipo_id: row.1,
        jurado_id: row.2,
        template_id: row.3,
        submitted_at: row.4,
        observaciones: row.5,
        acompanamiento_asesor: row.6,
        opinion_personal: row.7,
        created_at: row.8,
        updated_at: row.9,
    };
    Ok((StatusCode::CREATED, Json(view)))
}
