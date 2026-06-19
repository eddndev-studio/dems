//! Endpoints scoped to the authenticated caller — primarily for jurados
//! reading their own assignments and evaluations.

use axum::extract::{Path, State};
use axum::Json;
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use dems_core::models::RubricType;

use crate::error::{ApiError, ApiResult};
use crate::extractors::CurrentUser;
use crate::routes::admin_rubrics::{self, RubricTemplateView};
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
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RubricSummary {
    pub id: Uuid,
    pub nombre: String,
    pub tipo: RubricType,
}

#[utoipa::path(
    get,
    path = "/me/asignaciones",
    tag = "jurado",
    responses(
        (status = 200, description = "Asignaciones del jurado autenticado", body = [AsignacionItem]),
        (status = 401, description = "Sin token o inválido"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn list_asignaciones(
    State(state): State<AppState>,
    user: CurrentUser,
) -> ApiResult<Json<Vec<AsignacionItem>>> {
    // Queremos una fila por (prototipo, template) para el usuario autenticado,
    // con el id de evaluación existente (si lo hay) y si ya está enviada.
    let rows = sqlx::query_as::<
        _,
        (
            Uuid,
            String,
            String, // prototipo
            Uuid,
            String,
            RubricType, // rubric
            Option<Uuid>,
            Option<chrono::DateTime<chrono::Utc>>, // evaluacion
        ),
    >(
        r#"
        SELECT
            p.id, p.folio, p.nombre,
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
        ORDER BY (e.submitted_at IS NOT NULL), p.folio, r.nombre
        "#,
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let items: Vec<AsignacionItem> = rows
        .into_iter()
        .map(
            |(p_id, p_folio, p_nombre, r_id, r_nombre, r_tipo, eval_id, submitted_at)| {
                AsignacionItem {
                    prototipo: PrototipoSummary {
                        id: p_id,
                        folio: p_folio,
                        nombre: p_nombre,
                    },
                    rubric: RubricSummary {
                        id: r_id,
                        nombre: r_nombre,
                        tipo: r_tipo,
                    },
                    evaluacion_id: eval_id,
                    submitted: submitted_at.is_some(),
                }
            },
        )
        .collect();

    Ok(Json(items))
}

// ---------------------------------------------------------------------------
// GET /me/rubric-templates/:id
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/me/rubric-templates/{id}",
    tag = "jurado",
    params(("id" = Uuid, Path, description = "ID del rubric template")),
    responses(
        (status = 200, description = "Estructura de la rúbrica", body = RubricTemplateView),
        (status = 403, description = "Jurado no asignado a ese template"),
        (status = 404, description = "Template no existe"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn get_rubric_template(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<RubricTemplateView>> {
    let assigned: bool = sqlx::query_scalar(
        r#"SELECT EXISTS (
               SELECT 1 FROM assignments
               WHERE jurado_id = $1 AND template_id = $2
           )"#,
    )
    .bind(user.id)
    .bind(id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if !assigned {
        return Err(ApiError::Core(dems_core::CoreError::Forbidden));
    }

    admin_rubrics::load_tree(&state, id).await.map(Json)
}
