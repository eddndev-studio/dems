//! Admin CRUD for rubric templates.

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use dems_core::models::RubricType;

use crate::error::{ApiError, ApiResult};
use crate::extractors::RequireAdmin;
use crate::state::AppState;

// ---------------------------------------------------------------------------
// Types shared by create / get responses
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct RubricTemplateView {
    pub id: Uuid,
    pub edition_id: Uuid,
    pub nombre: String,
    pub tipo: RubricType,
    pub descripcion: Option<String>,
    pub activo: bool,
    pub categorias: Vec<Uuid>,
    pub sections: Vec<SectionView>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SectionView {
    pub id: Uuid,
    pub nombre: String,
    pub orden: i32,
    pub peso_pct: Option<f64>,
    pub criteria: Vec<CriterionView>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CriterionView {
    pub id: Uuid,
    pub texto: String,
    pub orden: i32,
    pub max_score: i32,
    pub kind: String,
}

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreateRubricRequest {
    pub edition_id: Uuid,
    #[validate(length(min = 1, max = 200))]
    pub nombre: String,
    pub tipo: RubricType,
    pub descripcion: Option<String>,
}

pub async fn create(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<CreateRubricRequest>,
) -> ApiResult<impl IntoResponse> {
    req.validate()
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    let id = Uuid::new_v4();
    let result = sqlx::query(
        r#"INSERT INTO rubric_templates
               (id, edition_id, nombre, tipo, descripcion, activo)
           VALUES ($1, $2, $3, $4::rubric_type, $5, true)"#,
    )
    .bind(id)
    .bind(req.edition_id)
    .bind(&req.nombre)
    .bind(match req.tipo {
        RubricType::Exhibicion => "exhibicion",
        RubricType::Memoria => "memoria",
    })
    .bind(&req.descripcion)
    .execute(&state.pool)
    .await;

    match result {
        Ok(_) => {}
        Err(sqlx::Error::Database(e)) if e.is_foreign_key_violation() => {
            // edition_id inexistente — devolvemos 422 para que el cliente
            // sepa que el payload rompe integridad referencial.
            return Err(ApiError::Core(dems_core::CoreError::Validation(
                "edition_id unknown".into(),
            )));
        }
        Err(e) => return Err(ApiError::Internal(e.into())),
    }

    let view = RubricTemplateView {
        id,
        edition_id: req.edition_id,
        nombre: req.nombre,
        tipo: req.tipo,
        descripcion: req.descripcion,
        activo: true,
        categorias: vec![],
        sections: vec![],
    };
    Ok((StatusCode::CREATED, Json(view)))
}

// ---------------------------------------------------------------------------
// List (stub — fleshed out in a later TDD cycle)
// ---------------------------------------------------------------------------

pub async fn list(_: RequireAdmin) -> Json<Vec<RubricTemplateView>> {
    Json(vec![])
}
