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
// Read-side views (shared by create echo, list, get)
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
    #[serde(default)]
    pub categorias: Vec<Uuid>,
    #[serde(default)]
    pub sections: Vec<CreateSection>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreateSection {
    #[validate(length(min = 1, max = 200))]
    pub nombre: String,
    pub orden: i32,
    #[serde(default)]
    pub peso_pct: Option<f64>,
    #[serde(default)]
    pub criteria: Vec<CreateCriterion>,
}

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct CreateCriterion {
    #[validate(length(min = 1, max = 2000))]
    pub texto: String,
    pub orden: i32,
    #[validate(range(min = 0, max = 100))]
    pub max_score: i32,
    pub kind: CriterionKindInput,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CriterionKindInput {
    Scale,
    Boolean,
    TextKey,
}

impl CriterionKindInput {
    fn as_sql(self) -> &'static str {
        match self {
            Self::Scale => "scale",
            Self::Boolean => "boolean",
            Self::TextKey => "text_key",
        }
    }

    fn as_api(self) -> &'static str {
        self.as_sql()
    }
}

fn tipo_as_sql(t: RubricType) -> &'static str {
    match t {
        RubricType::Exhibicion => "exhibicion",
        RubricType::Memoria => "memoria",
    }
}

pub async fn create(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<CreateRubricRequest>,
) -> ApiResult<impl IntoResponse> {
    req.validate()
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    for s in &req.sections {
        s.validate()
            .map_err(|e| ApiError::BadRequest(e.to_string()))?;
        for c in &s.criteria {
            c.validate()
                .map_err(|e| ApiError::BadRequest(e.to_string()))?;
        }
    }

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let template_id = Uuid::new_v4();
    let insert_template = sqlx::query(
        r#"INSERT INTO rubric_templates
               (id, edition_id, nombre, tipo, descripcion, activo)
           VALUES ($1, $2, $3, $4::rubric_type, $5, true)"#,
    )
    .bind(template_id)
    .bind(req.edition_id)
    .bind(&req.nombre)
    .bind(tipo_as_sql(req.tipo))
    .bind(&req.descripcion)
    .execute(&mut *tx)
    .await;
    if let Err(e) = insert_template {
        return Err(classify_integrity(e, "edition_id unknown"));
    }

    // Categorías.
    for cat_id in &req.categorias {
        if let Err(e) = sqlx::query(
            r#"INSERT INTO rubric_template_categorias (template_id, categoria_id)
               VALUES ($1, $2)"#,
        )
        .bind(template_id)
        .bind(cat_id)
        .execute(&mut *tx)
        .await
        {
            return Err(classify_integrity(e, "categoria_id unknown"));
        }
    }

    // Secciones + criterios. Mantenemos los IDs generados para eco de
    // respuesta sin volver a consultar.
    let mut sections_out: Vec<SectionView> = Vec::with_capacity(req.sections.len());
    for sec in req.sections {
        let section_id = Uuid::new_v4();
        if let Err(e) = sqlx::query(
            r#"INSERT INTO rubric_sections (id, template_id, nombre, orden, peso_pct)
               VALUES ($1, $2, $3, $4, $5)"#,
        )
        .bind(section_id)
        .bind(template_id)
        .bind(&sec.nombre)
        .bind(sec.orden)
        .bind(sec.peso_pct)
        .execute(&mut *tx)
        .await
        {
            return Err(classify_integrity(e, "invalid section"));
        }

        let mut criteria_out: Vec<CriterionView> = Vec::with_capacity(sec.criteria.len());
        for crit in sec.criteria {
            let crit_id = Uuid::new_v4();
            if let Err(e) = sqlx::query(
                r#"INSERT INTO rubric_criteria
                       (id, section_id, texto, orden, max_score, kind)
                   VALUES ($1, $2, $3, $4, $5, $6::criterion_kind)"#,
            )
            .bind(crit_id)
            .bind(section_id)
            .bind(&crit.texto)
            .bind(crit.orden)
            .bind(crit.max_score)
            .bind(crit.kind.as_sql())
            .execute(&mut *tx)
            .await
            {
                return Err(classify_integrity(e, "invalid criterion"));
            }
            criteria_out.push(CriterionView {
                id: crit_id,
                texto: crit.texto,
                orden: crit.orden,
                max_score: crit.max_score,
                kind: crit.kind.as_api().to_string(),
            });
        }

        sections_out.push(SectionView {
            id: section_id,
            nombre: sec.nombre,
            orden: sec.orden,
            peso_pct: sec.peso_pct,
            criteria: criteria_out,
        });
    }

    tx.commit().await.map_err(|e| ApiError::Internal(e.into()))?;

    let view = RubricTemplateView {
        id: template_id,
        edition_id: req.edition_id,
        nombre: req.nombre,
        tipo: req.tipo,
        descripcion: req.descripcion,
        activo: true,
        categorias: req.categorias,
        sections: sections_out,
    };
    Ok((StatusCode::CREATED, Json(view)))
}

/// Map sqlx integrity errors (FK, UNIQUE, CHECK) into 422 validations with
/// a context-specific message; everything else bubbles as 500.
fn classify_integrity(e: sqlx::Error, unknown_fk_msg: &str) -> ApiError {
    match &e {
        sqlx::Error::Database(db) if db.is_foreign_key_violation() => {
            ApiError::Core(dems_core::CoreError::Validation(unknown_fk_msg.into()))
        }
        sqlx::Error::Database(db) if db.is_unique_violation() => ApiError::Core(
            dems_core::CoreError::Validation("duplicate orden within parent".into()),
        ),
        sqlx::Error::Database(db) if db.is_check_violation() => {
            ApiError::Core(dems_core::CoreError::Validation("check failed".into()))
        }
        _ => ApiError::Internal(e.into()),
    }
}

// ---------------------------------------------------------------------------
// List (stub — fleshed out in a later TDD cycle)
// ---------------------------------------------------------------------------

pub async fn list(_: RequireAdmin) -> Json<Vec<RubricTemplateView>> {
    Json(vec![])
}
