//! Admin CRUD for rubric templates.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use dems_core::models::{EditionPhase, RubricType};

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
    /// Peso porcentual (0..100) de esta rúbrica en el puntaje final combinado
    /// del prototipo.
    pub peso: i32,
    /// `true` si la edición está en fase `preparacion`: la estructura puede
    /// editarse. `false` cuando la edición ya entró en evaluación/cerrada.
    pub editable: bool,
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
    /// Peso porcentual (0..100). Default 100 si se omite.
    #[serde(default)]
    #[validate(range(min = 0, max = 100))]
    pub peso: Option<i32>,
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
}

fn tipo_as_sql(t: RubricType) -> &'static str {
    match t {
        RubricType::Exhibicion => "exhibicion",
        RubricType::Memoria => "memoria",
    }
}

#[utoipa::path(
    post,
    path = "/admin/rubric-templates",
    tag = "admin/rubrics",
    request_body = CreateRubricRequest,
    responses(
        (status = 201, body = RubricTemplateView),
        (status = 422, description = "Validación falló"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn create(
    State(state): State<AppState>,
    _: RequireAdmin,
    Json(req): Json<CreateRubricRequest>,
) -> ApiResult<impl IntoResponse> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;
    validate_sections(&req.sections)?;

    // Gating: solo se crean rúbricas mientras la edición esté en preparación.
    // Si la edición no existe, dejamos caer al INSERT (falla por FK → 422),
    // preservando el contrato de "edición desconocida".
    if let Some(phase) = phase_of_edition(&state, req.edition_id).await? {
        if phase != EditionPhase::Preparacion {
            return Err(ApiError::Core(dems_core::CoreError::Conflict(
                "edition not in preparacion; rubric creation frozen".into(),
            )));
        }
    }

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let template_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_templates
               (id, edition_id, nombre, tipo, descripcion, activo, peso)
           VALUES ($1, $2, $3, $4::rubric_type, $5, true, $6)"#,
    )
    .bind(template_id)
    .bind(req.edition_id)
    .bind(&req.nombre)
    .bind(tipo_as_sql(req.tipo))
    .bind(&req.descripcion)
    .bind(req.peso.unwrap_or(100))
    .execute(&mut *tx)
    .await
    .map_err(|e| classify_integrity(e, "edition_id unknown"))?;

    insert_categorias(&mut tx, template_id, &req.categorias).await?;
    insert_sections(&mut tx, template_id, &req.sections).await?;

    tx.commit()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    let view = load_tree(&state, template_id).await?;
    Ok((StatusCode::CREATED, Json(view)))
}

/// Valida cada sección y criterio del árbol con `validator`.
fn validate_sections(sections: &[CreateSection]) -> ApiResult<()> {
    for s in sections {
        s.validate()
            .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;
        for c in &s.criteria {
            c.validate()
                .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;
        }
    }
    Ok(())
}

/// Fase actual de una edición, o `None` si no existe.
async fn phase_of_edition(state: &AppState, edition_id: Uuid) -> ApiResult<Option<EditionPhase>> {
    sqlx::query_scalar("SELECT phase FROM editions WHERE id = $1")
        .bind(edition_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))
}

/// Inserta los vínculos rúbrica ↔ categoría dentro de la transacción.
async fn insert_categorias(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    template_id: Uuid,
    categorias: &[Uuid],
) -> ApiResult<()> {
    for cat_id in categorias {
        sqlx::query(
            r#"INSERT INTO rubric_template_categorias (template_id, categoria_id)
               VALUES ($1, $2)"#,
        )
        .bind(template_id)
        .bind(cat_id)
        .execute(&mut **tx)
        .await
        .map_err(|e| classify_integrity(e, "categoria_id unknown"))?;
    }
    Ok(())
}

/// Inserta secciones + criterios anidados dentro de la transacción.
async fn insert_sections(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    template_id: Uuid,
    sections: &[CreateSection],
) -> ApiResult<()> {
    for sec in sections {
        let section_id = Uuid::new_v4();
        sqlx::query(
            r#"INSERT INTO rubric_sections (id, template_id, nombre, orden, peso_pct)
               VALUES ($1, $2, $3, $4, $5)"#,
        )
        .bind(section_id)
        .bind(template_id)
        .bind(&sec.nombre)
        .bind(sec.orden)
        .bind(sec.peso_pct)
        .execute(&mut **tx)
        .await
        .map_err(|e| classify_integrity(e, "invalid section"))?;

        for crit in &sec.criteria {
            sqlx::query(
                r#"INSERT INTO rubric_criteria
                       (id, section_id, texto, orden, max_score, kind)
                   VALUES ($1, $2, $3, $4, $5, $6::criterion_kind)"#,
            )
            .bind(Uuid::new_v4())
            .bind(section_id)
            .bind(&crit.texto)
            .bind(crit.orden)
            .bind(crit.max_score)
            .bind(crit.kind.as_sql())
            .execute(&mut **tx)
            .await
            .map_err(|e| classify_integrity(e, "invalid criterion"))?;
        }
    }
    Ok(())
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

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct ListParams {
    pub edition_id: Option<Uuid>,
    pub tipo: Option<RubricType>,
    pub activo: Option<bool>,
}

#[derive(Debug, Serialize, ToSchema, sqlx::FromRow)]
pub struct RubricTemplateSummary {
    pub id: Uuid,
    pub edition_id: Uuid,
    pub nombre: String,
    pub tipo: RubricType,
    pub descripcion: Option<String>,
    pub activo: bool,
    /// Peso porcentual (0..100) de esta rúbrica en el puntaje final combinado.
    pub peso: i32,
    /// `true` si la edición está en fase `preparacion` (estructura editable).
    pub editable: bool,
    pub section_count: i64,
    pub criterion_count: i64,
}

#[utoipa::path(
    get,
    path = "/admin/rubric-templates",
    tag = "admin/rubrics",
    params(
        ("edition_id" = Option<Uuid>, Query, description = "Filtrar por edición"),
        ("tipo" = Option<RubricType>, Query, description = "Filtrar por tipo"),
        ("activo" = Option<bool>, Query, description = "Filtrar por activo"),
    ),
    responses((status = 200, body = [RubricTemplateSummary])),
    security(("bearer_auth" = [])),
)]
pub async fn list(
    State(state): State<AppState>,
    _: RequireAdmin,
    Query(params): Query<ListParams>,
) -> ApiResult<Json<Vec<RubricTemplateSummary>>> {
    let rows = sqlx::query_as::<_, RubricTemplateSummary>(
        r#"
        SELECT
            t.id,
            t.edition_id,
            t.nombre,
            t.tipo,
            t.descripcion,
            t.activo,
            t.peso,
            (e.phase = 'preparacion') AS editable,
            (SELECT COUNT(*) FROM rubric_sections s WHERE s.template_id = t.id) AS section_count,
            (SELECT COUNT(*) FROM rubric_criteria c
               JOIN rubric_sections s ON s.id = c.section_id
               WHERE s.template_id = t.id) AS criterion_count
        FROM rubric_templates t
        JOIN editions e ON e.id = t.edition_id
        WHERE ($1::uuid IS NULL OR t.edition_id = $1)
          AND ($2::rubric_type IS NULL OR t.tipo = $2)
          AND ($3::boolean IS NULL OR t.activo = $3)
        ORDER BY t.created_at DESC
        "#,
    )
    .bind(params.edition_id)
    .bind(params.tipo)
    .bind(params.activo)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "list rubrics query failed");
        ApiError::Internal(e.into())
    })?;

    Ok(Json(rows))
}

// ---------------------------------------------------------------------------
// Get by id (full tree)
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/admin/rubric-templates/{id}",
    tag = "admin/rubrics",
    params(("id" = Uuid, Path, description = "ID")),
    responses(
        (status = 200, body = RubricTemplateView),
        (status = 404),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn get_by_id(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<RubricTemplateView>> {
    load_tree(&state, id).await.map(Json)
}

pub(crate) async fn load_tree(state: &AppState, id: Uuid) -> ApiResult<RubricTemplateView> {
    // 1. Template metadata + fase de la edición (para `editable`).
    let template = sqlx::query_as::<
        _,
        (
            Uuid,
            Uuid,
            String,
            RubricType,
            Option<String>,
            bool,
            i32,
            EditionPhase,
        ),
    >(
        r#"SELECT t.id, t.edition_id, t.nombre, t.tipo, t.descripcion, t.activo, t.peso, e.phase
               FROM rubric_templates t
               JOIN editions e ON e.id = t.edition_id
               WHERE t.id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;

    // 2. Secciones (ordenadas).
    let section_rows = sqlx::query_as::<_, (Uuid, String, i32, Option<f64>)>(
        r#"SELECT id, nombre, orden, peso_pct
           FROM rubric_sections WHERE template_id = $1
           ORDER BY orden ASC"#,
    )
    .bind(id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    // 3. Criterios de todas las secciones en un solo round-trip.
    let section_ids: Vec<Uuid> = section_rows.iter().map(|(sid, ..)| *sid).collect();
    let criterion_rows: Vec<(Uuid, Uuid, String, i32, i32, String)> = if section_ids.is_empty() {
        vec![]
    } else {
        sqlx::query_as(
            r#"SELECT id, section_id, texto, orden, max_score, kind::text
               FROM rubric_criteria WHERE section_id = ANY($1)
               ORDER BY orden ASC"#,
        )
        .bind(&section_ids)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
    };

    // 4. Categorías vinculadas.
    let categorias: Vec<Uuid> = sqlx::query_scalar(
        r#"SELECT categoria_id FROM rubric_template_categorias
           WHERE template_id = $1 ORDER BY categoria_id"#,
    )
    .bind(id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    // Ensamble: secciones en orden, criterios agrupados por section_id.
    let sections: Vec<SectionView> = section_rows
        .into_iter()
        .map(|(sid, nombre, orden, peso_pct)| {
            let criteria: Vec<CriterionView> = criterion_rows
                .iter()
                .filter(|c| c.1 == sid)
                .map(|(cid, _, texto, orden, max_score, kind)| CriterionView {
                    id: *cid,
                    texto: texto.clone(),
                    orden: *orden,
                    max_score: *max_score,
                    kind: kind.clone(),
                })
                .collect();
            SectionView {
                id: sid,
                nombre,
                orden,
                peso_pct,
                criteria,
            }
        })
        .collect();

    let (tid, edition_id, nombre, tipo, descripcion, activo, peso, phase) = template;
    Ok(RubricTemplateView {
        id: tid,
        edition_id,
        nombre,
        tipo,
        descripcion,
        activo,
        peso,
        editable: phase == EditionPhase::Preparacion,
        categorias,
        sections,
    })
}

// ---------------------------------------------------------------------------
// Patch (metadata only; structural changes go through dedicated endpoints)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, Validate, ToSchema)]
pub struct PatchRubricRequest {
    #[validate(length(min = 1, max = 200))]
    pub nombre: Option<String>,
    pub descripcion: Option<String>,
    pub activo: Option<bool>,
    /// Peso porcentual (0..100). Si se omite, no se toca.
    #[serde(default)]
    #[validate(range(min = 0, max = 100))]
    pub peso: Option<i32>,
}

#[utoipa::path(
    patch,
    path = "/admin/rubric-templates/{id}",
    tag = "admin/rubrics",
    params(("id" = Uuid, Path, description = "ID")),
    request_body = PatchRubricRequest,
    responses(
        (status = 200, body = RubricTemplateView),
        (status = 404),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn patch(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
    Json(req): Json<PatchRubricRequest>,
) -> ApiResult<Json<RubricTemplateView>> {
    req.validate()
        .map_err(|e| ApiError::Core(dems_core::CoreError::Validation(e.to_string())))?;

    // COALESCE deja sin tocar cualquier columna cuyo parámetro sea NULL, así
    // podemos recibir un subset de campos. descripcion acepta null como
    // "no tocar" también; el cliente que quiera borrarla usa "" hasta que
    // añadamos sumergido explícito (Option<Option<_>>).
    let affected = sqlx::query(
        r#"UPDATE rubric_templates
           SET nombre = COALESCE($2, nombre),
               descripcion = COALESCE($3, descripcion),
               activo = COALESCE($4, activo),
               peso = COALESCE($5, peso)
           WHERE id = $1"#,
    )
    .bind(id)
    .bind(&req.nombre)
    .bind(&req.descripcion)
    .bind(req.activo)
    .bind(req.peso)
    .execute(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }

    load_tree(&state, id).await.map(Json)
}

// ---------------------------------------------------------------------------
// Replace structure (full-tree replace; gated on edition phase = preparacion)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReplaceStructureRequest {
    #[serde(default)]
    pub categorias: Vec<Uuid>,
    #[serde(default)]
    pub sections: Vec<CreateSection>,
}

/// Fase de la edición a la que pertenece una rúbrica, o `None` si no existe.
async fn phase_of_template(state: &AppState, template_id: Uuid) -> ApiResult<Option<EditionPhase>> {
    sqlx::query_scalar(
        r#"SELECT e.phase FROM rubric_templates t
           JOIN editions e ON e.id = t.edition_id
           WHERE t.id = $1"#,
    )
    .bind(template_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))
}

/// Mapea una violación de FK al borrar criterios (RESTRICT por puntajes) a 409;
/// cualquier otro error de DB es 500. Es el backstop duro de integridad.
fn restrict_to_conflict(e: sqlx::Error) -> ApiError {
    match &e {
        sqlx::Error::Database(db) if db.is_foreign_key_violation() => ApiError::Core(
            dems_core::CoreError::Conflict("rubric has evaluations; structure is frozen".into()),
        ),
        _ => ApiError::Internal(e.into()),
    }
}

#[utoipa::path(
    put,
    path = "/admin/rubric-templates/{id}/structure",
    tag = "admin/rubrics",
    params(("id" = Uuid, Path, description = "ID")),
    request_body = ReplaceStructureRequest,
    responses(
        (status = 200, body = RubricTemplateView),
        (status = 404),
        (status = 409, description = "Edición fuera de preparación — estructura congelada"),
        (status = 422, description = "Validación falló"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn replace_structure(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
    Json(req): Json<ReplaceStructureRequest>,
) -> ApiResult<Json<RubricTemplateView>> {
    validate_sections(&req.sections)?;

    let phase = phase_of_template(&state, id)
        .await?
        .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;
    if phase != EditionPhase::Preparacion {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "edition not in preparacion; rubric structure frozen".into(),
        )));
    }

    let mut tx = state
        .pool
        .begin()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    // Reemplazo total: se borran categorías + secciones (cascada a criterios) y
    // se reinsertan. En preparación ningún puntaje referencia estos criterios;
    // si por alguna razón lo hiciera, el ON DELETE RESTRICT de evaluacion_scores
    // dispara y lo convertimos en 409.
    sqlx::query("DELETE FROM rubric_template_categorias WHERE template_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    sqlx::query("DELETE FROM rubric_sections WHERE template_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(restrict_to_conflict)?;

    insert_categorias(&mut tx, id, &req.categorias).await?;
    insert_sections(&mut tx, id, &req.sections).await?;

    tx.commit()
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    load_tree(&state, id).await.map(Json)
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

#[utoipa::path(
    delete,
    path = "/admin/rubric-templates/{id}",
    tag = "admin/rubrics",
    params(("id" = Uuid, Path, description = "ID")),
    responses(
        (status = 204),
        (status = 404),
        (status = 409, description = "Hay evaluaciones referenciando — desactivar en su lugar"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn delete_rubric(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    // La edición debe estar en preparación: una vez en evaluación, el set de
    // rúbricas queda congelado (existencia incluida). 404 si no existe.
    let phase = phase_of_template(&state, id)
        .await?
        .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;
    if phase != EditionPhase::Preparacion {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "edition not in preparacion; cannot delete rubric".into(),
        )));
    }

    // Si existe alguna evaluación que referencia esta rúbrica, preservamos
    // la auditoría: borrar rompería el historial de puntajes. El admin
    // puede archivar con PATCH { activo: false } en su lugar.
    let used: bool =
        sqlx::query_scalar(r#"SELECT EXISTS (SELECT 1 FROM evaluaciones WHERE template_id = $1)"#)
            .bind(id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;

    if used {
        return Err(ApiError::Core(dems_core::CoreError::Conflict(
            "rubric has evaluations; archive it by setting activo=false".into(),
        )));
    }

    let affected = sqlx::query("DELETE FROM rubric_templates WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;

    if affected.rows_affected() == 0 {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }
    Ok(StatusCode::NO_CONTENT)
}
