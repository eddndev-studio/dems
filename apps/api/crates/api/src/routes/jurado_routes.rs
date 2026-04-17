//! Endpoints scoped to the authenticated caller — primarily for jurados
//! reading their own assignments and evaluations.

use axum::extract::State;
use axum::Json;
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use dems_core::models::RubricType;

use crate::error::{ApiError, ApiResult};
use crate::extractors::CurrentUser;
use crate::state::AppState;

#[derive(Debug, Serialize, ToSchema)]
pub struct AsignacionItem {
    pub prototipo: PrototipoSummary,
    pub rubric: RubricSummary,
    pub evaluacion_id: Option<Uuid>,
    pub submitted: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PrototipoSummary {
    pub id: Uuid,
    pub folio: String,
    pub nombre: String,
    pub plantel: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RubricSummary {
    pub id: Uuid,
    pub nombre: String,
    pub tipo: RubricType,
}

pub async fn list_asignaciones(
    State(state): State<AppState>,
    user: CurrentUser,
) -> ApiResult<Json<Vec<AsignacionItem>>> {
    // Queremos una fila por (prototipo, template) para el usuario autenticado,
    // con el id de evaluación existente (si lo hay) y si ya está enviada.
    let rows = sqlx::query_as::<_, (
        Uuid, String, String, Option<String>, // prototipo
        Uuid, String, RubricType,             // rubric
        Option<Uuid>, Option<chrono::DateTime<chrono::Utc>>, // evaluacion
    )>(
        r#"
        SELECT
            p.id, p.folio, p.nombre, p.plantel,
            r.id, r.nombre, r.tipo,
            e.id, e.submitted_at
        FROM assignments a
        JOIN prototipos p ON p.id = a.prototipo_id
        JOIN rubric_templates r ON r.id = a.template_id
        LEFT JOIN evaluaciones e
          ON e.prototipo_id = a.prototipo_id
         AND e.template_id  = a.template_id
         AND e.jurado_id    = a.jurado_id
        WHERE a.jurado_id = $1
        ORDER BY p.folio, r.nombre
        "#,
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let items: Vec<AsignacionItem> = rows
        .into_iter()
        .map(|(p_id, p_folio, p_nombre, p_plantel, r_id, r_nombre, r_tipo, eval_id, submitted_at)| {
            AsignacionItem {
                prototipo: PrototipoSummary {
                    id: p_id,
                    folio: p_folio,
                    nombre: p_nombre,
                    plantel: p_plantel,
                },
                rubric: RubricSummary {
                    id: r_id,
                    nombre: r_nombre,
                    tipo: r_tipo,
                },
                evaluacion_id: eval_id,
                submitted: submitted_at.is_some(),
            }
        })
        .collect();

    Ok(Json(items))
}
