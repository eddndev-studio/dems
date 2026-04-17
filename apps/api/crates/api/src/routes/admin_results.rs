//! Admin endpoint: ranking de prototipos por categoría/edición/tipo de rúbrica.
//!
//! Promedio = media aritmética de los `total` (suma de scores) de las
//! evaluaciones ya **submitted** (`submitted_at IS NOT NULL`). Los borradores
//! no cuentan: el promedio del concurso se calcula sólo sobre lo entregado.

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue};
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt::Write as _;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::extractors::RequireAdmin;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ResultsQuery {
    pub edition_id: Uuid,
    #[serde(default)]
    pub rubric_type: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CategoriaResultsView {
    pub categoria: CategoriaRef,
    pub edition_id: Uuid,
    pub rubric_type: String,
    /// Suma máxima alcanzable según la rúbrica activa (0 si no hay rúbrica).
    pub max_total: i64,
    pub prototipos: Vec<PrototipoResultView>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CategoriaRef {
    pub id: Uuid,
    pub slug: String,
    pub nombre: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PrototipoResultView {
    pub prototipo_id: Uuid,
    pub folio: String,
    pub nombre: String,
    pub n_jurados: i64,
    /// Promedio de los `total` por jurado (null si no hay evaluaciones).
    pub promedio: Option<f64>,
    pub evaluaciones: Vec<EvaluacionResultView>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct EvaluacionResultView {
    pub evaluacion_id: Uuid,
    pub jurado_id: Uuid,
    pub jurado_nombre: String,
    pub total: i64,
    pub submitted_at: DateTime<Utc>,
}

pub async fn by_categoria(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(slug): Path<String>,
    Query(q): Query<ResultsQuery>,
) -> ApiResult<Json<CategoriaResultsView>> {
    let rubric_type = q.rubric_type.as_deref().unwrap_or("exhibicion");
    if !matches!(rubric_type, "exhibicion" | "memoria") {
        return Err(ApiError::BadRequest(
            "rubric_type must be 'exhibicion' or 'memoria'".into(),
        ));
    }

    let categoria = sqlx::query_as::<_, (Uuid, String, String)>(
        r#"SELECT id, slug, nombre FROM categorias WHERE slug = $1"#,
    )
    .bind(&slug)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?
    .ok_or(ApiError::Core(dems_core::CoreError::NotFound))?;

    let edition_exists: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM editions WHERE id = $1)")
            .bind(q.edition_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
    if !edition_exists {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }

    // max_total = suma de max_score de la(s) rúbrica(s) activas para la
    // (edición, tipo). Si hay varias activas (caso raro) tomamos la más
    // reciente; la realidad es que en una edición habrá una sola activa
    // por tipo.
    let max_total: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE((
            SELECT SUM(c.max_score)::BIGINT
            FROM rubric_criteria c
            JOIN rubric_sections s ON s.id = c.section_id
            WHERE s.template_id = (
                SELECT id FROM rubric_templates
                WHERE edition_id = $1 AND tipo = $2::rubric_type AND activo
                ORDER BY created_at DESC
                LIMIT 1
            )
            AND c.kind IN ('scale', 'boolean')
        ), 0)
        "#,
    )
    .bind(q.edition_id)
    .bind(rubric_type)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    // Una sola query: prototipos de esta categoría/edición + sus evaluaciones
    // submitted del tipo solicitado, con total agregado por evaluación.
    let rows = sqlx::query_as::<
        _,
        (
            Uuid,
            String,
            String,
            Option<Uuid>,
            Option<Uuid>,
            Option<String>,
            Option<i64>,
            Option<DateTime<Utc>>,
        ),
    >(
        r#"
        SELECT
            p.id, p.folio, p.nombre,
            ev.id, ev.jurado_id, u.full_name,
            (SELECT COALESCE(SUM(es.score)::BIGINT, 0)
               FROM evaluacion_scores es WHERE es.evaluacion_id = ev.id) AS total,
            ev.submitted_at
        FROM prototipos p
        JOIN prototipo_categorias pc ON pc.prototipo_id = p.id
        LEFT JOIN evaluaciones ev
          ON ev.prototipo_id = p.id
         AND ev.submitted_at IS NOT NULL
         AND ev.template_id IN (
             SELECT id FROM rubric_templates
             WHERE edition_id = $1 AND tipo = $2::rubric_type
         )
        LEFT JOIN users u ON u.id = ev.jurado_id
        WHERE p.edition_id = $1
          AND pc.categoria_id = $3
        ORDER BY p.folio
        "#,
    )
    .bind(q.edition_id)
    .bind(rubric_type)
    .bind(categoria.0)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    // Agrupar por prototipo, conservando orden estable.
    let mut order: Vec<Uuid> = Vec::new();
    let mut by_proto: HashMap<Uuid, PrototipoResultView> = HashMap::new();
    for (pid, folio, nombre, ev_id, jurado_id, jurado_nombre, total, submitted_at) in rows {
        let entry = by_proto.entry(pid).or_insert_with(|| {
            order.push(pid);
            PrototipoResultView {
                prototipo_id: pid,
                folio,
                nombre,
                n_jurados: 0,
                promedio: None,
                evaluaciones: Vec::new(),
            }
        });
        if let (Some(ev_id), Some(jid), Some(name), Some(t), Some(at)) =
            (ev_id, jurado_id, jurado_nombre, total, submitted_at)
        {
            entry.evaluaciones.push(EvaluacionResultView {
                evaluacion_id: ev_id,
                jurado_id: jid,
                jurado_nombre: name,
                total: t,
                submitted_at: at,
            });
        }
    }

    let mut prototipos: Vec<PrototipoResultView> = order
        .into_iter()
        .map(|id| {
            let mut v = by_proto.remove(&id).unwrap();
            v.n_jurados = v.evaluaciones.len() as i64;
            v.promedio = if v.evaluaciones.is_empty() {
                None
            } else {
                let sum: i64 = v.evaluaciones.iter().map(|e| e.total).sum();
                Some(sum as f64 / v.evaluaciones.len() as f64)
            };
            v
        })
        .collect();

    // Ranking: promedio desc, los sin evaluaciones al final.
    prototipos.sort_by(|a, b| match (b.promedio, a.promedio) {
        (Some(bp), Some(ap)) => bp.partial_cmp(&ap).unwrap_or(std::cmp::Ordering::Equal),
        (Some(_), None) => std::cmp::Ordering::Less,
        (None, Some(_)) => std::cmp::Ordering::Greater,
        (None, None) => a.folio.cmp(&b.folio),
    });

    Ok(Json(CategoriaResultsView {
        categoria: CategoriaRef {
            id: categoria.0,
            slug: categoria.1,
            nombre: categoria.2,
        },
        edition_id: q.edition_id,
        rubric_type: rubric_type.to_string(),
        max_total,
        prototipos,
    }))
}

// ---------------------------------------------------------------------------
// GET /admin/results/edition/:id/export.csv
// ---------------------------------------------------------------------------

/// CSV con todos los prototipos de la edición. Una fila por (categoría,
/// prototipo). Promedio sobre evaluaciones submitted del rubric_type
/// solicitado.
pub async fn export_csv(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(edition_id): Path<Uuid>,
    Query(q): Query<ExportQuery>,
) -> ApiResult<impl IntoResponse> {
    let rubric_type = q.rubric_type.as_deref().unwrap_or("exhibicion");
    if !matches!(rubric_type, "exhibicion" | "memoria") {
        return Err(ApiError::BadRequest(
            "rubric_type must be 'exhibicion' or 'memoria'".into(),
        ));
    }

    let edition: Option<i32> = sqlx::query_scalar("SELECT year FROM editions WHERE id = $1")
        .bind(edition_id)
        .fetch_optional(&state.pool)
        .await
        .map_err(|e| ApiError::Internal(e.into()))?;
    let Some(year) = edition else {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    };

    let max_total: i64 = sqlx::query_scalar(
        r#"
        SELECT COALESCE((
            SELECT SUM(c.max_score)::BIGINT
            FROM rubric_criteria c
            JOIN rubric_sections s ON s.id = c.section_id
            WHERE s.template_id = (
                SELECT id FROM rubric_templates
                WHERE edition_id = $1 AND tipo = $2::rubric_type AND activo
                ORDER BY created_at DESC
                LIMIT 1
            )
            AND c.kind IN ('scale', 'boolean')
        ), 0)
        "#,
    )
    .bind(edition_id)
    .bind(rubric_type)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    // Una fila por (categoria, prototipo). Promedio sobre evals submitted del
    // tipo solicitado. LEFT JOIN para incluir prototipos sin evaluaciones.
    let rows = sqlx::query_as::<_, (String, String, String, String, i64, Option<f64>)>(
        r#"
        WITH ev_totals AS (
            SELECT ev.prototipo_id, ev.id AS ev_id,
                   COALESCE(SUM(es.score)::BIGINT, 0) AS total
            FROM evaluaciones ev
            LEFT JOIN evaluacion_scores es ON es.evaluacion_id = ev.id
            WHERE ev.submitted_at IS NOT NULL
              AND ev.template_id IN (
                  SELECT id FROM rubric_templates
                  WHERE edition_id = $1 AND tipo = $2::rubric_type
              )
            GROUP BY ev.prototipo_id, ev.id
        )
        SELECT
            cat.slug, cat.nombre, p.folio, p.nombre,
            COALESCE(COUNT(t.ev_id), 0)::BIGINT AS n_jurados,
            AVG(t.total)::DOUBLE PRECISION AS promedio
        FROM prototipos p
        JOIN prototipo_categorias pc ON pc.prototipo_id = p.id
        JOIN categorias cat ON cat.id = pc.categoria_id
        LEFT JOIN ev_totals t ON t.prototipo_id = p.id
        WHERE p.edition_id = $1
        GROUP BY cat.slug, cat.nombre, cat.orden, p.folio, p.nombre
        ORDER BY cat.orden, cat.slug, p.folio
        "#,
    )
    .bind(edition_id)
    .bind(rubric_type)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let mut body = String::new();
    body.push_str("categoria_slug,categoria,folio,prototipo,n_jurados,promedio,max_total\n");
    for (slug, nombre_cat, folio, nombre_p, n, promedio) in rows {
        let _ = write!(
            body,
            "{},{},{},{},{},{},{}\n",
            csv_escape(&slug),
            csv_escape(&nombre_cat),
            csv_escape(&folio),
            csv_escape(&nombre_p),
            n,
            promedio
                .map(|v| {
                    // Imprimir enteros sin .0 cuando el promedio es exacto.
                    if (v.fract()).abs() < f64::EPSILON {
                        format!("{}", v as i64)
                    } else {
                        format!("{v}")
                    }
                })
                .unwrap_or_default(),
            max_total,
        );
    }

    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    let filename = format!("resultados-edicion-{year}-{rubric_type}.csv");
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
            .unwrap_or_else(|_| HeaderValue::from_static("attachment")),
    );
    Ok((headers, body))
}

#[derive(Debug, Deserialize)]
pub struct ExportQuery {
    #[serde(default)]
    pub rubric_type: Option<String>,
}

fn csv_escape(s: &str) -> String {
    if s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r') {
        let escaped = s.replace('"', "\"\"");
        format!("\"{escaped}\"")
    } else {
        s.to_string()
    }
}
