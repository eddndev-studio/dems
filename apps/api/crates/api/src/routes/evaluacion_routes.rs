//! Evaluation endpoints used by the jurado app.

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use dems_core::models::{EditionPhase, UserRole};

use crate::error::{ApiError, ApiResult};
use crate::extractors::{CurrentUser, RequireAdmin};
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

#[utoipa::path(
    post,
    path = "/evaluaciones",
    tag = "evaluaciones",
    request_body = CreateEvaluacionRequest,
    responses(
        (status = 201, description = "Evaluación creada", body = EvaluacionView),
        (status = 200, description = "Replay idempotente — devuelve la existente", body = EvaluacionView),
        (status = 403, description = "Jurado no asignado a (prototipo, template)"),
        (status = 422, description = "Score fuera de rango o criterio inválido"),
        (status = 409, description = "Conflicto. Body lleva `code`: `client_id_reused` (client_id de otra terna) o `edition_closed` (edición fuera de fase 'evaluacion'). El choque de unicidad de terna va sin `code`."),
    ),
    security(("bearer_auth" = [])),
)]
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
        let existing: Option<(Uuid, Uuid, Uuid)> = sqlx::query_as(
            r#"SELECT id, prototipo_id, template_id FROM evaluaciones
               WHERE jurado_id = $1 AND client_id = $2"#,
        )
        .bind(user.id)
        .bind(cid)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

        if let Some((id, existing_prototipo, existing_template)) = existing {
            // El client_id ya se usó. Sólo es un replay legítimo si la terna
            // coincide; si difiere, el cliente reutilizó el id para otra
            // (prototipo, template) — error de cliente, 409.
            if existing_prototipo != req.prototipo_id || existing_template != req.template_id {
                return Err(ApiError::ConflictCoded(
                    "client_id_reused",
                    "client_id reused for a different prototipo/template".into(),
                ));
            }
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

    // --- Phase gate: la edición del prototipo debe estar en `evaluacion`. ---
    require_edition_in_evaluacion(&state.pool, req.prototipo_id).await?;

    // --- Validate every score against its criterion up front. ---
    validate_scores_against_template(&state.pool, req.template_id, &req.scores).await?;

    // --- Write evaluation + scores in one transaction. ---
    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let id = Uuid::new_v4();
    let row = sqlx::query_as::<
        _,
        (
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
        ),
    >(
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
                // PK (evaluacion_id, criterion_id) duplicada ⇒ body inválido,
                // no error de servidor.
                if db.is_unique_violation() {
                    return ApiError::Core(dems_core::CoreError::Validation(
                        "duplicate criterion_id in scores".into(),
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

    tx.commit()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

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

// ---------------------------------------------------------------------------
// GET /evaluaciones/:id
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/evaluaciones/{id}",
    tag = "evaluaciones",
    params(("id" = Uuid, Path, description = "ID de la evaluación")),
    responses(
        (status = 200, description = "Evaluación", body = EvaluacionView),
        (status = 403, description = "No es el dueño ni admin"),
        (status = 404, description = "No encontrada"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn get_by_id(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<EvaluacionView>> {
    let view = load_evaluacion(&state, id).await?;
    // Owner or admin only. Other jurados get 403, not 404, because
    // at this point the resource is known to exist.
    if !matches!(user.role, UserRole::Admin) && view.jurado_id != user.id {
        return Err(ApiError::Core(dems_core::CoreError::Forbidden));
    }
    Ok(Json(view))
}

// ---------------------------------------------------------------------------
// PATCH /evaluaciones/:id
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct PatchEvaluacionRequest {
    #[serde(default)]
    pub observaciones: Option<String>,
    #[serde(default)]
    pub acompanamiento_asesor: Option<bool>,
    #[serde(default)]
    #[validate(range(min = 0, max = 100))]
    pub opinion_personal: Option<i32>,
    /// Opcional. Si se envía, REEMPLAZA el set completo de scores: el cliente
    /// manda siempre todas las filas que deben quedar. Las filas existentes
    /// cuyo criterion_id no aparezca en el payload se ELIMINAN del servidor
    /// (así un score que el jurado limpió desaparece), y las presentes se
    /// hacen upsert. Si es `None`, los scores no se tocan.
    #[serde(default)]
    pub scores: Option<Vec<ScoreInput>>,
}

#[utoipa::path(
    patch,
    path = "/evaluaciones/{id}",
    tag = "evaluaciones",
    params(("id" = Uuid, Path, description = "ID de la evaluación")),
    request_body = PatchEvaluacionRequest,
    responses(
        (status = 200, description = "Evaluación actualizada", body = EvaluacionView),
        (status = 403, description = "No es el dueño"),
        (status = 404, description = "No encontrada"),
        (status = 409, description = "Conflicto. Body lleva `code`: `already_submitted` (ya enviada — chequeado antes que la fase) o `edition_closed` (edición fuera de fase 'evaluacion')."),
        (status = 422, description = "Body inválido"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn patch_evaluacion(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(req): Json<PatchEvaluacionRequest>,
) -> ApiResult<Json<EvaluacionView>> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    let (jurado_id, prototipo_id, template_id, submitted_at) =
        sqlx::query_as::<_, (Uuid, Uuid, Uuid, Option<DateTime<Utc>>)>(
            r#"SELECT jurado_id, prototipo_id, template_id, submitted_at
           FROM evaluaciones WHERE id = $1"#,
        )
        .bind(id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;

    if jurado_id != user.id {
        return Err(ApiError::Core(dems_core::CoreError::Forbidden));
    }

    // El check de "ya enviada" corre ANTES del gate de fase: un replay de algo
    // YA enviado debe devolver `already_submitted` aunque la edición esté
    // cerrada (de lo contrario el cliente vería `edition_closed` y nunca sabría
    // que su envío sí llegó).
    if submitted_at.is_some() {
        return Err(ApiError::ConflictCoded(
            "already_submitted",
            "evaluation already submitted; cannot edit".into(),
        ));
    }

    // Phase gate: la edición del prototipo debe estar en `evaluacion`.
    require_edition_in_evaluacion(&state.pool, prototipo_id).await?;

    // Validamos ANTES de abrir la transacción: un score inválido no debe borrar
    // las filas existentes (el delete vive dentro de la tx).
    if let Some(scores) = &req.scores {
        validate_scores_against_template(&state.pool, template_id, scores).await?;
    }

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query(
        r#"UPDATE evaluaciones
           SET observaciones = COALESCE($2, observaciones),
               acompanamiento_asesor = COALESCE($3, acompanamiento_asesor),
               opinion_personal = COALESCE($4, opinion_personal)
           WHERE id = $1"#,
    )
    .bind(id)
    .bind(&req.observaciones)
    .bind(req.acompanamiento_asesor)
    .bind(req.opinion_personal)
    .execute(&mut *tx)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if let Some(scores) = req.scores {
        // El cliente envía SIEMPRE el set completo de scores. Borramos las
        // filas que ya no aparecen en el payload (un score que el jurado limpió
        // debe desaparecer del servidor) y hacemos upsert de las presentes,
        // todo dentro de la misma transacción.
        let keep_ids: Vec<Uuid> = scores.iter().map(|s| s.criterion_id).collect();
        sqlx::query(
            r#"DELETE FROM evaluacion_scores
               WHERE evaluacion_id = $1 AND NOT (criterion_id = ANY($2))"#,
        )
        .bind(id)
        .bind(&keep_ids)
        .execute(&mut *tx)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

        for s in scores {
            sqlx::query(
                r#"INSERT INTO evaluacion_scores
                       (evaluacion_id, criterion_id, score, text_answer)
                   VALUES ($1, $2, $3, $4)
                   ON CONFLICT (evaluacion_id, criterion_id)
                   DO UPDATE SET score = EXCLUDED.score,
                                 text_answer = EXCLUDED.text_answer"#,
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
        }
    }

    tx.commit()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    load_evaluacion(&state, id).await.map(Json)
}

// ---------------------------------------------------------------------------
// POST /evaluaciones/:id/submit
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/evaluaciones/{id}/submit",
    tag = "evaluaciones",
    params(("id" = Uuid, Path, description = "ID de la evaluación")),
    responses(
        (status = 200, description = "Evaluación enviada", body = EvaluacionView),
        (status = 403, description = "No es el dueño"),
        (status = 404, description = "No encontrada"),
        (status = 409, description = "Conflicto. Body lleva `code`: `already_submitted` (ya enviada — chequeado antes que la fase), `edition_closed` (edición fuera de fase 'evaluacion') o `incomplete` (algún criterio sin puntuar)."),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn submit(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<EvaluacionView>> {
    let row = sqlx::query_as::<_, (Uuid, Uuid, Uuid, Option<DateTime<Utc>>)>(
        r#"SELECT jurado_id, prototipo_id, template_id, submitted_at
           FROM evaluaciones WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;

    let (jurado_id, prototipo_id, template_id, submitted_at) = row;
    if jurado_id != user.id {
        return Err(ApiError::Core(dems_core::CoreError::Forbidden));
    }

    // El check de "ya enviada" corre ANTES del gate de fase: un replay de un
    // submit de algo YA enviado debe devolver `already_submitted` aunque la
    // edición esté cerrada, no `edition_closed`.
    if submitted_at.is_some() {
        return Err(ApiError::ConflictCoded(
            "already_submitted",
            "evaluation already submitted".into(),
        ));
    }

    // Phase gate: la edición del prototipo debe estar en `evaluacion`.
    require_edition_in_evaluacion(&state.pool, prototipo_id).await?;

    // Completeness check: every scoring criterion (scale/boolean) in the
    // rubric must have a score row. text_key criteria are unscored and
    // therefore don't block submit — they're just aide-memoires for the
    // final opinion.
    let unscored: Option<String> = sqlx::query_scalar(
        r#"
        SELECT c.texto
        FROM rubric_criteria c
        JOIN rubric_sections s ON s.id = c.section_id
        LEFT JOIN evaluacion_scores es
          ON es.criterion_id = c.id AND es.evaluacion_id = $1
        WHERE s.template_id = $2
          AND c.kind IN ('scale', 'boolean')
          AND es.criterion_id IS NULL
        LIMIT 1
        "#,
    )
    .bind(id)
    .bind(template_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if let Some(criterion_text) = unscored {
        return Err(ApiError::ConflictCoded(
            "incomplete",
            format!("cannot submit: criterion \"{criterion_text}\" is unscored"),
        ));
    }

    sqlx::query("UPDATE evaluaciones SET submitted_at = NOW() WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    load_evaluacion(&state, id).await.map(Json)
}

// ---------------------------------------------------------------------------
// POST /admin/evaluaciones/:id/reopen
// ---------------------------------------------------------------------------

/// Admin pone `submitted_at = NULL` para que el jurado dueño pueda corregir
/// la evaluación. Los scores no se tocan; reabrir un draft es 409 (no hay
/// nada que reabrir).
#[utoipa::path(
    post,
    path = "/admin/evaluaciones/{id}/reopen",
    tag = "admin/results",
    params(("id" = Uuid, Path, description = "ID de la evaluación")),
    responses(
        (status = 200, description = "Evaluación reabierta", body = EvaluacionView),
        (status = 403, description = "Sólo admin"),
        (status = 404, description = "No encontrada"),
        (status = 409, description = "No está submitted — nada que reabrir"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn reopen(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<EvaluacionView>> {
    let submitted_at: Option<DateTime<Utc>> =
        sqlx::query_scalar("SELECT submitted_at FROM evaluaciones WHERE id = $1")
            .bind(id)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?
            .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;

    if submitted_at.is_none() {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "evaluation is not submitted; nothing to reopen".into(),
        )));
    }

    sqlx::query("UPDATE evaluaciones SET submitted_at = NULL WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    load_evaluacion(&state, id).await.map(Json)
}

// ---------------------------------------------------------------------------
// Shared: gate edition phase via prototipo → edition
// ---------------------------------------------------------------------------

/// Bloquea la operación si la edición a la que pertenece `prototipo_id` no está
/// en fase `evaluacion`. Resuelve prototipo → edition_id → editions.phase.
/// Devuelve 409 si la fase no es `evaluacion`. Si el prototipo no existe no
/// hace nada (deja que el flujo normal — assignment/FK — produzca su error),
/// para no filtrar la existencia del prototipo.
async fn require_edition_in_evaluacion(pool: &sqlx::PgPool, prototipo_id: Uuid) -> ApiResult<()> {
    let phase: Option<EditionPhase> = sqlx::query_scalar(
        r#"SELECT e.phase
           FROM prototipos p
           JOIN editions e ON e.id = p.edition_id
           WHERE p.id = $1"#,
    )
    .bind(prototipo_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if let Some(phase) = phase {
        if phase != EditionPhase::Evaluacion {
            return Err(ApiError::ConflictCoded(
                "edition_closed",
                "edition not in evaluation phase".into(),
            ));
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Shared: validate a batch of scores against a rubric template
// ---------------------------------------------------------------------------

async fn validate_scores_against_template(
    pool: &sqlx::PgPool,
    template_id: Uuid,
    scores: &[ScoreInput],
) -> ApiResult<()> {
    if scores.is_empty() {
        return Ok(());
    }

    // Rechazamos criterion_id duplicados en el payload con 422 antes de tocar
    // la DB: de lo contrario el INSERT chocaría con la PK (evaluacion_id,
    // criterion_id) y reportaría un 500 espurio para lo que es un body inválido.
    let mut seen = std::collections::HashSet::with_capacity(scores.len());
    for s in scores {
        if !seen.insert(s.criterion_id) {
            return Err(ApiError::Core(dems_core::CoreError::Validation(format!(
                "duplicate criterion_id {} in scores",
                s.criterion_id
            ))));
        }
    }

    let crit_rows: Vec<(Uuid, i32, String)> = sqlx::query_as(
        r#"SELECT c.id, c.max_score, c.kind::text
           FROM rubric_criteria c
           JOIN rubric_sections s ON s.id = c.section_id
           WHERE s.template_id = $1"#,
    )
    .bind(template_id)
    .fetch_all(pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let catalog: HashMap<Uuid, (i32, String)> = crit_rows
        .into_iter()
        .map(|(id, max, kind)| (id, (max, kind)))
        .collect();

    for s in scores {
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
                    return Err(ApiError::Core(dems_core::CoreError::Validation(format!(
                        "score out of range for criterion {}",
                        s.criterion_id
                    ))))
                }
                None => {
                    return Err(ApiError::Core(dems_core::CoreError::Validation(format!(
                        "numeric criterion {} requires score",
                        s.criterion_id
                    ))))
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
    Ok(())
}

async fn load_evaluacion(state: &AppState, id: Uuid) -> ApiResult<EvaluacionView> {
    let row = sqlx::query_as::<
        _,
        (
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
        ),
    >(
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
