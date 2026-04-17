//! Evaluation endpoints used by the jurado app.

use std::collections::HashMap;

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use crate::error::{ApiError, ApiResult};
use crate::extractors::CurrentUser;
use crate::state::AppState;

// ---------------------------------------------------------------------------
// Request / response
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreateEvaluacionRequest {
    pub prototipo_id: Uuid,
    pub template_id: Uuid,
    /// Caller-supplied id generated on the device. If present, the request is
    /// idempotent: a replay with the same client_id returns the existing
    /// evaluation (200) instead of creating a duplicate (201).
    #[serde(default)]
    #[validate(length(min = 1, max = 128))]
    pub client_id: Option<String>,
    #[serde(default)]
    pub observaciones: Option<String>,
    #[serde(default)]
    pub acompanamiento_asesor: Option<bool>,
    #[serde(default)]
    #[validate(range(min = 0, max = 100))]
    pub opinion_personal: Option<i32>,
    #[serde(default)]
    pub scores: Vec<ScoreInput>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ScoreInput {
    pub criterion_id: Uuid,
    #[serde(default)]
    pub score: Option<i32>,
    #[serde(default)]
    pub text_answer: Option<String>,
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
    pub scores: Vec<ScoreView>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ScoreView {
    pub criterion_id: Uuid,
    pub score: Option<i32>,
    pub text_answer: Option<String>,
}

// ---------------------------------------------------------------------------
// POST /evaluaciones
// ---------------------------------------------------------------------------

pub async fn create(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(req): Json<CreateEvaluacionRequest>,
) -> ApiResult<impl IntoResponse> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    // --- Idempotency: replay with the same (jurado, client_id) returns the
    //     existing evaluation so the offline sync worker can safely retry.
    if let Some(cid) = &req.client_id {
        let existing: Option<Uuid> = sqlx::query_scalar(
            r#"SELECT id FROM evaluaciones
               WHERE jurado_id = $1 AND client_id = $2"#,
        )
        .bind(user.id)
        .bind(cid)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

        if let Some(id) = existing {
            let view = load_evaluacion(&state, id).await?;
            return Ok((StatusCode::OK, Json(view)));
        }
    }

    // --- Authorisation: must be assigned to (prototipo, template). ---
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

    // --- Validate every score against its criterion up front. ---
    // Fetching the rubric's criteria once avoids N+1 and lets us reject the
    // whole payload before touching any row.
    if !req.scores.is_empty() {
        let crit_rows: Vec<(Uuid, i32, String)> = sqlx::query_as(
            r#"SELECT c.id, c.max_score, c.kind::text
               FROM rubric_criteria c
               JOIN rubric_sections s ON s.id = c.section_id
               WHERE s.template_id = $1"#,
        )
        .bind(req.template_id)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

        let catalog: HashMap<Uuid, (i32, String)> = crit_rows
            .into_iter()
            .map(|(id, max, kind)| (id, (max, kind)))
            .collect();

        for s in &req.scores {
            let Some((max, kind)) = catalog.get(&s.criterion_id) else {
                return Err(ApiError::Core(dems_core::CoreError::Validation(format!(
                    "criterion {} does not belong to template",
                    s.criterion_id
                ))));
            };
            match kind.as_str() {
                "scale" | "boolean" => match s.score {
                    Some(v) if v >= 0 && v <= *max => {}
                    Some(_) => {
                        return Err(ApiError::Core(dems_core::CoreError::Validation(
                            format!("score out of range for criterion {}", s.criterion_id),
                        )))
                    }
                    None => {
                        return Err(ApiError::Core(dems_core::CoreError::Validation(
                            format!("numeric criterion {} requires score", s.criterion_id),
                        )))
                    }
                },
                "text_key" => {
                    if s.text_answer.is_none() {
                        return Err(ApiError::Core(dems_core::CoreError::Validation(format!(
                            "text criterion {} requires text_answer",
                            s.criterion_id
                        ))));
                    }
                }
                other => {
                    return Err(ApiError::Internal(anyhow::anyhow!(
                        "unknown criterion kind: {other}"
                    )))
                }
            }
        }
    }

    // --- Write evaluation + scores in one transaction. ---
    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

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
        r#"INSERT INTO evaluaciones
               (id, prototipo_id, jurado_id, template_id, client_id,
                observaciones, acompanamiento_asesor, opinion_personal)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           RETURNING id, prototipo_id, jurado_id, template_id,
                     submitted_at, observaciones, acompanamiento_asesor,
                     opinion_personal, created_at, updated_at"#,
    )
    .bind(id)
    .bind(req.prototipo_id)
    .bind(user.id)
    .bind(req.template_id)
    .bind(&req.client_id)
    .bind(&req.observaciones)
    .bind(req.acompanamiento_asesor)
    .bind(req.opinion_personal)
    .fetch_one(&mut *tx)
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

    let mut score_views: Vec<ScoreView> = Vec::with_capacity(req.scores.len());
    for s in req.scores {
        sqlx::query(
            r#"INSERT INTO evaluacion_scores
                   (evaluacion_id, criterion_id, score, text_answer)
               VALUES ($1, $2, $3, $4)"#,
        )
        .bind(id)
        .bind(s.criterion_id)
        .bind(s.score)
        .bind(&s.text_answer)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(db) = &e {
                if db.is_check_violation() {
                    return ApiError::Core(dems_core::CoreError::Validation(
                        "score or text_answer must be set".into(),
                    ));
                }
            }
            ApiError::Internal(e.into())
        })?;
        score_views.push(ScoreView {
            criterion_id: s.criterion_id,
            score: s.score,
            text_answer: s.text_answer,
        });
    }

    tx.commit().await.map_err(|e| ApiError::Internal(e.into()))?;

    let view = EvaluacionView {
        id: row.0,
        prototipo_id: row.1,
        jurado_id: row.2,
        template_id: row.3,
        submitted_at: row.4,
        observaciones: row.5,
        acompanamiento_asesor: row.6,
        opinion_personal: row.7,
        scores: score_views,
        created_at: row.8,
        updated_at: row.9,
    };
    Ok((StatusCode::CREATED, Json(view)))
}

// ---------------------------------------------------------------------------
// Read helper (used by idempotent replay + read endpoints in later cycles)
// ---------------------------------------------------------------------------

async fn load_evaluacion(state: &AppState, id: Uuid) -> ApiResult<EvaluacionView> {
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
        r#"SELECT id, prototipo_id, jurado_id, template_id,
                  submitted_at, observaciones, acompanamiento_asesor,
                  opinion_personal, created_at, updated_at
           FROM evaluaciones WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;

    let score_rows = sqlx::query_as::<_, (Uuid, Option<i32>, Option<String>)>(
        r#"SELECT criterion_id, score, text_answer
           FROM evaluacion_scores WHERE evaluacion_id = $1
           ORDER BY criterion_id"#,
    )
    .bind(id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(EvaluacionView {
        id: row.0,
        prototipo_id: row.1,
        jurado_id: row.2,
        template_id: row.3,
        submitted_at: row.4,
        observaciones: row.5,
        acompanamiento_asesor: row.6,
        opinion_personal: row.7,
        scores: score_rows
            .into_iter()
            .map(|(cid, score, text_answer)| ScoreView {
                criterion_id: cid,
                score,
                text_answer,
            })
            .collect(),
        created_at: row.8,
        updated_at: row.9,
    })
}
