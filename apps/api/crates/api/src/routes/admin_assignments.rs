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

#[utoipa::path(
    post,
    path = "/admin/assignments",
    tag = "admin/assignments",
    request_body = CreateAssignmentRequest,
    responses(
        (status = 201, body = AssignmentView),
        (status = 200, description = "Idempotente — ya existía", body = AssignmentView),
        (status = 422, description = "user no jurado, edición distinta o IDs desconocidos"),
    ),
    security(("bearer_auth" = [])),
)]
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
// Bulk assign: jurados → todos los prototipos de una categoría (= área)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct BulkAssignRequest {
    pub categoria_id: Uuid,
    pub template_id: Uuid,
    /// Jurados a asignar a cada prototipo de la categoría.
    pub jurado_ids: Vec<Uuid>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct BulkAssignResult {
    /// Asignaciones realmente creadas (las que ya existían no se recrean).
    pub created: i64,
    /// Combinaciones (jurado × prototipo) que ya existían y se omitieron.
    pub skipped: i64,
    /// Prototipos de la categoría en la edición del template.
    pub prototipos: i64,
    /// Jurados únicos en la petición.
    pub jurados: i64,
}

/// Asigna un conjunto de jurados a TODOS los prototipos de una categoría dentro
/// de la edición del template. Es la forma práctica de cubrir el "área" de la
/// exhibición: muchos jurados evalúan cada prototipo de su categoría sin
/// asignar uno por uno. Idempotente (las asignaciones existentes se respetan).
#[utoipa::path(
    post,
    path = "/admin/assignments/bulk",
    tag = "admin/assignments",
    request_body = BulkAssignRequest,
    responses(
        (status = 200, description = "Resumen de la asignación masiva", body = BulkAssignResult),
        (status = 422, description = "jurado_ids vacío, algún id no es jurado, o categoría/template desconocidos"),
        (status = 403, description = "Sólo admin"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn bulk(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<BulkAssignRequest>,
) -> ApiResult<impl IntoResponse> {
    if req.jurado_ids.is_empty() {
        return Err(ApiError::Core(dems_core::CoreError::Validation(
            "jurado_ids must not be empty".into(),
        )));
    }

    // Dedup de jurado_ids para que los contadores sean exactos.
    let jurado_ids: Vec<Uuid> = {
        let mut seen = std::collections::HashSet::new();
        req.jurado_ids
            .iter()
            .copied()
            .filter(|id| seen.insert(*id))
            .collect()
    };

    // El template define la edición; debe existir.
    let edition_id: Option<Uuid> =
        sqlx::query_scalar("SELECT edition_id FROM rubric_templates WHERE id = $1")
            .bind(req.template_id)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
    let Some(edition_id) = edition_id else {
        return Err(ApiError::Core(dems_core::CoreError::Validation(
            "template_id unknown".into(),
        )));
    };

    // La categoría debe existir.
    let categoria_exists: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM categorias WHERE id = $1)")
            .bind(req.categoria_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
    if !categoria_exists {
        return Err(ApiError::Core(dems_core::CoreError::Validation(
            "categoria_id unknown".into(),
        )));
    }

    // Todos los ids deben ser usuarios con rol jurado (los desconocidos también
    // caen aquí, igual que el create individual rechaza no-jurados).
    let non_jurado: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM unnest($1::uuid[]) AS t(id)
           WHERE NOT EXISTS (
               SELECT 1 FROM users u WHERE u.id = t.id AND u.role = 'jurado'::user_role
           )"#,
    )
    .bind(&jurado_ids)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    if non_jurado > 0 {
        return Err(ApiError::Core(dems_core::CoreError::Validation(
            "every jurado_id must be an existing user with role 'jurado'".into(),
        )));
    }

    // Prototipos de la categoría en la edición del template.
    let prototipos: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM prototipos p
           JOIN prototipo_categorias pc ON pc.prototipo_id = p.id
           WHERE p.edition_id = $1 AND pc.categoria_id = $2"#,
    )
    .bind(edition_id)
    .bind(req.categoria_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    // Inserción masiva del producto (jurado × prototipo), idempotente.
    let created = sqlx::query(
        r#"INSERT INTO assignments (jurado_id, prototipo_id, template_id)
           SELECT j.id, proto.id, $3
           FROM unnest($1::uuid[]) AS j(id)
           CROSS JOIN (
               SELECT p.id FROM prototipos p
               JOIN prototipo_categorias pc ON pc.prototipo_id = p.id
               WHERE p.edition_id = $4 AND pc.categoria_id = $2
           ) AS proto
           ON CONFLICT (jurado_id, prototipo_id, template_id) DO NOTHING"#,
    )
    .bind(&jurado_ids)
    .bind(req.categoria_id)
    .bind(req.template_id)
    .bind(edition_id)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .rows_affected() as i64;

    let jurados = jurado_ids.len() as i64;
    let attempted = jurados * prototipos;
    Ok((
        StatusCode::OK,
        Json(BulkAssignResult {
            created,
            skipped: attempted - created,
            prototipos,
            jurados,
        }),
    ))
}

// ---------------------------------------------------------------------------
// List for a prototipo
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/admin/prototipos/{id}/assignments",
    tag = "admin/assignments",
    params(("id" = Uuid, Path, description = "ID del prototipo")),
    responses((status = 200, body = [AssignmentWithJuradoView])),
    security(("bearer_auth" = [])),
)]
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

#[utoipa::path(
    delete,
    path = "/admin/assignments",
    tag = "admin/assignments",
    params(
        ("jurado_id" = Uuid, Query, description = "ID del jurado"),
        ("prototipo_id" = Uuid, Query, description = "ID del prototipo"),
        ("template_id" = Uuid, Query, description = "ID del template"),
    ),
    responses(
        (status = 204),
        (status = 404),
        (status = 409, description = "Existe evaluación para esta tripleta"),
    ),
    security(("bearer_auth" = [])),
)]
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
