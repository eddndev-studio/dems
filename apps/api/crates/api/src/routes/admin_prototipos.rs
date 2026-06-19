//! Admin CRUD for prototipos.

use axum::extract::{Path, Query, State};
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

#[derive(Debug, Serialize, ToSchema)]
pub struct PrototipoView {
    pub id: Uuid,
    pub edition_id: Uuid,
    pub folio: String,
    pub nombre: String,
    pub eje_transversal: bool,
    pub descripcion: Option<String>,
    pub categorias: Vec<Uuid>,
    pub integrantes: Vec<IntegranteView>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct IntegranteView {
    pub id: Uuid,
    pub nombre: String,
    pub rol: Option<String>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreatePrototipoRequest {
    pub edition_id: Uuid,
    #[validate(length(min = 1, max = 80))]
    pub folio: String,
    #[validate(length(min = 1, max = 200))]
    pub nombre: String,
    #[serde(default)]
    pub eje_transversal: bool,
    #[serde(default)]
    pub descripcion: Option<String>,
    #[serde(default)]
    pub categorias: Vec<Uuid>,
    #[serde(default)]
    pub integrantes: Vec<IntegranteInput>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct IntegranteInput {
    #[validate(length(min = 1, max = 200))]
    pub nombre: String,
    #[serde(default)]
    pub rol: Option<String>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct PatchPrototipoRequest {
    #[serde(default)]
    #[validate(length(min = 1, max = 200))]
    pub nombre: Option<String>,
    #[serde(default)]
    pub eje_transversal: Option<bool>,
    #[serde(default)]
    pub descripcion: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ListParams {
    pub edition_id: Option<Uuid>,
}

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

#[utoipa::path(
    post,
    path = "/admin/prototipos",
    tag = "admin/prototipos",
    request_body = CreatePrototipoRequest,
    responses(
        (status = 201, body = PrototipoView),
        (status = 409, description = "folio duplicado en la edición"),
        (status = 422, description = "Validación falló"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn create(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<CreatePrototipoRequest>,
) -> ApiResult<impl IntoResponse> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;
    for i in &req.integrantes {
        i.validate()
            .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;
    }

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let id = Uuid::new_v4();
    let created_at: DateTime<Utc> = sqlx::query_scalar(
        r#"INSERT INTO prototipos
               (id, edition_id, folio, nombre, eje_transversal, descripcion)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING created_at"#,
    )
    .bind(id)
    .bind(req.edition_id)
    .bind(&req.folio)
    .bind(&req.nombre)
    .bind(req.eje_transversal)
    .bind(&req.descripcion)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.is_unique_violation() => ApiError::Core(
            dems_core::CoreError::Conflict("folio already used for this edition".into()),
        ),
        sqlx::Error::Database(db) if db.is_foreign_key_violation() => ApiError::Core(
            dems_core::CoreError::Validation("edition_id unknown".into()),
        ),
        _ => ApiError::Internal(e.into()),
    })?;

    for cat_id in &req.categorias {
        sqlx::query(
            r#"INSERT INTO prototipo_categorias (prototipo_id, categoria_id)
               VALUES ($1, $2)"#,
        )
        .bind(id)
        .bind(cat_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| match &e {
            sqlx::Error::Database(db) if db.is_foreign_key_violation() => ApiError::Core(
                dems_core::CoreError::Validation("categoria_id unknown".into()),
            ),
            _ => ApiError::Internal(e.into()),
        })?;
    }

    let mut integrantes_out: Vec<IntegranteView> = Vec::with_capacity(req.integrantes.len());
    for i in req.integrantes {
        let int_id = Uuid::new_v4();
        sqlx::query(
            r#"INSERT INTO prototipo_integrantes (id, prototipo_id, nombre, rol)
               VALUES ($1, $2, $3, $4)"#,
        )
        .bind(int_id)
        .bind(id)
        .bind(&i.nombre)
        .bind(&i.rol)
        .execute(&mut *tx)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
        integrantes_out.push(IntegranteView {
            id: int_id,
            nombre: i.nombre,
            rol: i.rol,
        });
    }

    tx.commit()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    Ok((
        StatusCode::CREATED,
        Json(PrototipoView {
            id,
            edition_id: req.edition_id,
            folio: req.folio,
            nombre: req.nombre,
            eje_transversal: req.eje_transversal,
            descripcion: req.descripcion,
            categorias: req.categorias,
            integrantes: integrantes_out,
            created_at,
        }),
    ))
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema, sqlx::FromRow)]
pub struct PrototipoSummary {
    pub id: Uuid,
    pub edition_id: Uuid,
    pub folio: String,
    pub nombre: String,
    pub eje_transversal: bool,
    pub created_at: DateTime<Utc>,
}

#[utoipa::path(
    get,
    path = "/admin/prototipos",
    tag = "admin/prototipos",
    params(("edition_id" = Option<Uuid>, Query, description = "Filtrar por edición")),
    responses((status = 200, body = [PrototipoSummary])),
    security(("bearer_auth" = [])),
)]
pub async fn list(
    State(state): State<AppState>,
    _: RequireAdmin,
    Query(params): Query<ListParams>,
) -> ApiResult<Json<Vec<PrototipoSummary>>> {
    let rows = sqlx::query_as::<_, PrototipoSummary>(
        r#"SELECT id, edition_id, folio, nombre, eje_transversal, created_at
           FROM prototipos
           WHERE ($1::uuid IS NULL OR edition_id = $1)
           ORDER BY folio"#,
    )
    .bind(params.edition_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    Ok(Json(rows))
}

// ---------------------------------------------------------------------------
// Get by id
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/admin/prototipos/{id}",
    tag = "admin/prototipos",
    params(("id" = Uuid, Path, description = "ID")),
    responses(
        (status = 200, body = PrototipoView),
        (status = 404),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn get_by_id(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<PrototipoView>> {
    load_prototipo(&state, id).await.map(Json)
}

async fn load_prototipo(state: &AppState, id: Uuid) -> ApiResult<PrototipoView> {
    let main = sqlx::query_as::<
        _,
        (
            Uuid,
            Uuid,
            String,
            String,
            bool,
            Option<String>,
            DateTime<Utc>,
        ),
    >(
        r#"SELECT id, edition_id, folio, nombre, eje_transversal,
                  descripcion, created_at
           FROM prototipos WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;

    let categorias: Vec<Uuid> = sqlx::query_scalar(
        r#"SELECT categoria_id FROM prototipo_categorias
           WHERE prototipo_id = $1 ORDER BY categoria_id"#,
    )
    .bind(id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let integrantes: Vec<IntegranteView> = sqlx::query_as::<_, (Uuid, String, Option<String>)>(
        r#"SELECT id, nombre, rol FROM prototipo_integrantes
           WHERE prototipo_id = $1 ORDER BY nombre"#,
    )
    .bind(id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .into_iter()
    .map(|(id, nombre, rol)| IntegranteView { id, nombre, rol })
    .collect();

    Ok(PrototipoView {
        id: main.0,
        edition_id: main.1,
        folio: main.2,
        nombre: main.3,
        eje_transversal: main.4,
        descripcion: main.5,
        created_at: main.6,
        categorias,
        integrantes,
    })
}

// ---------------------------------------------------------------------------
// Patch
// ---------------------------------------------------------------------------

#[utoipa::path(
    patch,
    path = "/admin/prototipos/{id}",
    tag = "admin/prototipos",
    params(("id" = Uuid, Path, description = "ID")),
    request_body = PatchPrototipoRequest,
    responses(
        (status = 200, body = PrototipoView),
        (status = 404),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn patch(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
    Json(req): Json<PatchPrototipoRequest>,
) -> ApiResult<Json<PrototipoView>> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    let affected = sqlx::query(
        r#"UPDATE prototipos
           SET nombre = COALESCE($2, nombre),
               eje_transversal = COALESCE($3, eje_transversal),
               descripcion = COALESCE($4, descripcion)
           WHERE id = $1"#,
    )
    .bind(id)
    .bind(&req.nombre)
    .bind(req.eje_transversal)
    .bind(&req.descripcion)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }
    load_prototipo(&state, id).await.map(Json)
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

#[utoipa::path(
    delete,
    path = "/admin/prototipos/{id}",
    tag = "admin/prototipos",
    params(("id" = Uuid, Path, description = "ID")),
    responses(
        (status = 204),
        (status = 404),
        (status = 409, description = "Tiene evaluaciones"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn delete(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    let has_evals: bool =
        sqlx::query_scalar(r#"SELECT EXISTS (SELECT 1 FROM evaluaciones WHERE prototipo_id = $1)"#)
            .bind(id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;

    if has_evals {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "prototipo has evaluations; cannot delete".into(),
        )));
    }

    let affected = sqlx::query("DELETE FROM prototipos WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }
    Ok(StatusCode::NO_CONTENT)
}
