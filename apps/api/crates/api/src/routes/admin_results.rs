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
use rust_xlsxwriter::{Format, FormatAlign, FormatBorder, Workbook};
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

#[utoipa::path(
    get,
    path = "/admin/results/categoria/{slug}",
    tag = "admin/results",
    params(
        ("slug" = String, Path, description = "Slug de la categoría"),
        ("edition_id" = Uuid, Query, description = "ID de la edición"),
        ("rubric_type" = Option<String>, Query, description = "exhibicion (default) | memoria"),
    ),
    responses(
        (status = 200, description = "Ranking de prototipos", body = CategoriaResultsView),
        (status = 400, description = "rubric_type inválido o edition_id ausente"),
        (status = 403, description = "Sólo admin"),
        (status = 404, description = "Categoría o edición no encontrada"),
    ),
    security(("bearer_auth" = [])),
)]
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
             WHERE edition_id = $1 AND tipo = $2::rubric_type AND activo
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
    prototipos.sort_by(|a, b| match (a.promedio, b.promedio) {
        (Some(ap), Some(bp)) => bp
            .partial_cmp(&ap)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.folio.cmp(&b.folio)),
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
// GET /admin/results/edition/:id/export.xlsx
// ---------------------------------------------------------------------------

#[utoipa::path(
    get,
    path = "/admin/results/edition/{id}/export.xlsx",
    tag = "admin/results",
    params(
        ("id" = Uuid, Path, description = "ID de la edición"),
        ("rubric_type" = Option<String>, Query, description = "exhibicion (default) | memoria"),
    ),
    responses(
        (status = 200, description = "Excel de resultados", content_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        (status = 400, description = "rubric_type inválido"),
        (status = 403, description = "Sólo admin"),
        (status = 404, description = "Edición no encontrada"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn export_excel(
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

    // Ranking General
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
                  WHERE edition_id = $1 AND tipo = $2::rubric_type AND activo
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

    // Desglose por Jurados
    let jurados_rows = sqlx::query_as::<_, (String, String, String, String, i64, DateTime<Utc>)>(
        r#"
        SELECT
            cat.nombre AS categoria,
            p.folio,
            p.nombre AS prototipo,
            u.full_name AS jurado,
            COALESCE(SUM(es.score)::BIGINT, 0) AS total,
            ev.submitted_at
        FROM evaluaciones ev
        JOIN prototipos p ON p.id = ev.prototipo_id
        JOIN prototipo_categorias pc ON pc.prototipo_id = p.id
        JOIN categorias cat ON cat.id = pc.categoria_id
        JOIN users u ON u.id = ev.jurado_id
        LEFT JOIN evaluacion_scores es ON es.evaluacion_id = ev.id
        WHERE ev.submitted_at IS NOT NULL
          AND p.edition_id = $1
          AND ev.template_id IN (
              SELECT id FROM rubric_templates
              WHERE edition_id = $1 AND tipo = $2::rubric_type AND activo
          )
        GROUP BY cat.nombre, p.folio, p.nombre, u.full_name, ev.submitted_at, cat.orden
        ORDER BY cat.orden, p.folio, u.full_name
        "#,
    )
    .bind(edition_id)
    .bind(rubric_type)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    let mut workbook = Workbook::new();

    let header_format = Format::new()
        .set_bold()
        .set_border(FormatBorder::Thin)
        .set_background_color(rust_xlsxwriter::Color::RGB(0xD9E1F2))
        .set_align(FormatAlign::Center);

    let cell_format = Format::new().set_border(FormatBorder::Thin);

    // Hoja 1: Ranking General
    let ws1 = workbook
        .add_worksheet()
        .set_name("Ranking General")
        .map_err(|e| ApiError::Internal(e.into()))?;
    ws1.write_string_with_format(0, 0, "Categoría", &header_format)
        .unwrap();
    ws1.write_string_with_format(0, 1, "Folio", &header_format)
        .unwrap();
    ws1.write_string_with_format(0, 2, "Prototipo", &header_format)
        .unwrap();
    ws1.write_string_with_format(0, 3, "N° Jurados", &header_format)
        .unwrap();
    ws1.write_string_with_format(0, 4, "Promedio", &header_format)
        .unwrap();
    ws1.write_string_with_format(0, 5, "Max Total", &header_format)
        .unwrap();

    ws1.set_column_width(0, 20).unwrap();
    ws1.set_column_width(1, 15).unwrap();
    ws1.set_column_width(2, 40).unwrap();
    ws1.set_column_width(3, 12).unwrap();
    ws1.set_column_width(4, 12).unwrap();
    ws1.set_column_width(5, 12).unwrap();

    for (i, row) in rows.iter().enumerate() {
        let r = (i + 1) as u32;
        ws1.write_string_with_format(r, 0, &row.1, &cell_format)
            .unwrap();
        ws1.write_string_with_format(r, 1, &row.2, &cell_format)
            .unwrap();
        ws1.write_string_with_format(r, 2, &row.3, &cell_format)
            .unwrap();
        ws1.write_number_with_format(r, 3, row.4 as f64, &cell_format)
            .unwrap();
        if let Some(promedio) = row.5 {
            ws1.write_number_with_format(r, 4, promedio, &cell_format)
                .unwrap();
        } else {
            ws1.write_string_with_format(r, 4, "", &cell_format)
                .unwrap();
        }
        ws1.write_number_with_format(r, 5, max_total as f64, &cell_format)
            .unwrap();
    }

    // Hoja 2: Desglose por Jurados
    let ws2 = workbook
        .add_worksheet()
        .set_name("Desglose por Jurados")
        .map_err(|e| ApiError::Internal(e.into()))?;
    ws2.write_string_with_format(0, 0, "Categoría", &header_format)
        .unwrap();
    ws2.write_string_with_format(0, 1, "Folio", &header_format)
        .unwrap();
    ws2.write_string_with_format(0, 2, "Prototipo", &header_format)
        .unwrap();
    ws2.write_string_with_format(0, 3, "Jurado", &header_format)
        .unwrap();
    ws2.write_string_with_format(0, 4, "Total", &header_format)
        .unwrap();
    ws2.write_string_with_format(0, 5, "Fecha Evaluación", &header_format)
        .unwrap();

    ws2.set_column_width(0, 20).unwrap();
    ws2.set_column_width(1, 15).unwrap();
    ws2.set_column_width(2, 40).unwrap();
    ws2.set_column_width(3, 30).unwrap();
    ws2.set_column_width(4, 10).unwrap();
    ws2.set_column_width(5, 20).unwrap();

    for (i, row) in jurados_rows.iter().enumerate() {
        let r = (i + 1) as u32;
        ws2.write_string_with_format(r, 0, &row.0, &cell_format)
            .unwrap();
        ws2.write_string_with_format(r, 1, &row.1, &cell_format)
            .unwrap();
        ws2.write_string_with_format(r, 2, &row.2, &cell_format)
            .unwrap();
        ws2.write_string_with_format(r, 3, &row.3, &cell_format)
            .unwrap();
        ws2.write_number_with_format(r, 4, row.4 as f64, &cell_format)
            .unwrap();
        ws2.write_string_with_format(
            r,
            5,
            &row.5.format("%Y-%m-%d %H:%M:%S").to_string(),
            &cell_format,
        )
        .unwrap();
    }

    let buf = workbook
        .save_to_buffer()
        .map_err(|e| ApiError::Internal(e.into()))?;

    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ),
    );
    let filename = format!("resultados-edicion-{year}-{rubric_type}.xlsx");
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
            .unwrap_or_else(|_| HeaderValue::from_static("attachment")),
    );
    Ok((headers, buf))
}

#[derive(Debug, Deserialize)]
pub struct ExportQuery {
    #[serde(default)]
    pub rubric_type: Option<String>,
}

// ---------------------------------------------------------------------------
// GET /admin/results/edition/:id/final — puntaje combinado ponderado
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct FinalRankingView {
    pub edition_id: Uuid,
    /// Prototipos ordenados por `puntaje_final` descendente.
    pub prototipos: Vec<FinalPrototipoView>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct FinalPrototipoView {
    pub prototipo_id: Uuid,
    pub folio: String,
    pub nombre: String,
    /// Σ_tipo (promedio_tipo / max_total_tipo) * (peso_tipo / 100), en 0..1.
    pub puntaje_final: f64,
    /// Desglose por tipo de rúbrica (exhibicion, memoria).
    pub desglose: Vec<FinalBreakdownView>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct FinalBreakdownView {
    pub rubric_type: String,
    pub peso: i32,
    pub max_total: i64,
    /// Promedio de los `total` de jurados (null si no hay evaluaciones).
    pub promedio: Option<f64>,
    /// Aporte ponderado de este tipo al `puntaje_final`:
    /// (promedio / max_total) * (peso / 100). 0 si max_total es 0.
    pub aporte: f64,
}

/// Parámetros (max_total, peso) de la rúbrica activa de un tipo dado.
struct TipoParams {
    max_total: i64,
    peso: i32,
}

/// Resuelve (max_total, peso) de la rúbrica ACTIVA más reciente para
/// (edition, tipo). Si no hay rúbrica activa, max_total=0 y peso=0.
async fn tipo_params(pool: &sqlx::PgPool, edition_id: Uuid, tipo: &str) -> ApiResult<TipoParams> {
    let row: Option<(i32, i64)> = sqlx::query_as(
        r#"
        SELECT t.peso,
               COALESCE((
                   SELECT SUM(c.max_score)::BIGINT
                   FROM rubric_criteria c
                   JOIN rubric_sections s ON s.id = c.section_id
                   WHERE s.template_id = t.id
                     AND c.kind IN ('scale', 'boolean')
               ), 0) AS max_total
        FROM rubric_templates t
        WHERE t.edition_id = $1 AND t.tipo = $2::rubric_type AND t.activo
        ORDER BY t.created_at DESC
        LIMIT 1
        "#,
    )
    .bind(edition_id)
    .bind(tipo)
    .fetch_optional(pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    Ok(match row {
        Some((peso, max_total)) => TipoParams { max_total, peso },
        None => TipoParams {
            max_total: 0,
            peso: 0,
        },
    })
}

/// Puntaje final combinado por prototipo de una edición.
///
/// Para cada prototipo: `puntaje_final = Σ_tipo (promedio_tipo / max_total_tipo)
/// * (peso_tipo / 100)`, considerando SÓLO la rúbrica ACTIVA de cada tipo. El
/// promedio_tipo es la media de los `total` (suma de scores) de las
/// evaluaciones ya `submitted_at` contra esa rúbrica. Si un tipo no tiene
/// rúbrica activa o `max_total = 0`, su aporte es 0 (no NaN). El ranking se
/// ordena por `puntaje_final` descendente.
#[utoipa::path(
    get,
    path = "/admin/results/edition/{id}/final",
    tag = "admin/results",
    params(("id" = Uuid, Path, description = "ID de la edición")),
    responses(
        (status = 200, description = "Ranking combinado ponderado", body = FinalRankingView),
        (status = 403, description = "Sólo admin"),
        (status = 404, description = "Edición no encontrada"),
    ),
    security(("bearer_auth" = [])),
)]
pub async fn final_ranking(
    State(state): State<AppState>,
    _: RequireAdmin,
    Path(edition_id): Path<Uuid>,
) -> ApiResult<Json<FinalRankingView>> {
    let edition_exists: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM editions WHERE id = $1)")
            .bind(edition_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| ApiError::Internal(e.into()))?;
    if !edition_exists {
        return Err(ApiError::Core(dems_core::CoreError::NotFound));
    }

    const TIPOS: [&str; 2] = ["exhibicion", "memoria"];

    // Parámetros (max_total, peso) por tipo, una sola vez.
    let mut params: HashMap<&str, TipoParams> = HashMap::new();
    for tipo in TIPOS {
        params.insert(tipo, tipo_params(&state.pool, edition_id, tipo).await?);
    }

    // Prototipos de la edición + promedio por tipo (sólo rúbrica activa,
    // evaluaciones submitted). Una fila por (prototipo, tipo) con promedio.
    let rows = sqlx::query_as::<_, (Uuid, String, String, String, Option<f64>)>(
        r#"
        WITH ev_totals AS (
            SELECT ev.prototipo_id,
                   rt.tipo::text AS tipo,
                   ev.id AS ev_id,
                   COALESCE(SUM(es.score)::BIGINT, 0) AS total
            FROM evaluaciones ev
            JOIN rubric_templates rt ON rt.id = ev.template_id
            LEFT JOIN evaluacion_scores es ON es.evaluacion_id = ev.id
            WHERE ev.submitted_at IS NOT NULL
              AND rt.edition_id = $1
              AND rt.activo
            GROUP BY ev.prototipo_id, rt.tipo, ev.id
        )
        SELECT p.id, p.folio, p.nombre,
               t.tipo,
               AVG(t.total)::DOUBLE PRECISION AS promedio
        FROM prototipos p
        LEFT JOIN ev_totals t ON t.prototipo_id = p.id
        WHERE p.edition_id = $1
        GROUP BY p.id, p.folio, p.nombre, t.tipo
        ORDER BY p.folio
        "#,
    )
    .bind(edition_id)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;

    // Agrupar por prototipo, conservando orden estable de aparición.
    let mut order: Vec<Uuid> = Vec::new();
    let mut promedios: HashMap<Uuid, (String, String, HashMap<String, f64>)> = HashMap::new();
    for (pid, folio, nombre, tipo, promedio) in rows {
        let entry = promedios.entry(pid).or_insert_with(|| {
            order.push(pid);
            (folio, nombre, HashMap::new())
        });
        // tipo es NULL sólo cuando el prototipo no tiene evaluaciones (LEFT JOIN);
        // en ese caso `promedio` también es NULL. Sólo registramos pares válidos.
        if let Some(avg) = promedio {
            entry.2.insert(tipo, avg);
        }
    }

    let mut prototipos: Vec<FinalPrototipoView> = order
        .into_iter()
        .map(|pid| {
            let (folio, nombre, type_avgs) = promedios.remove(&pid).unwrap();
            let mut puntaje_final = 0.0_f64;
            let mut desglose: Vec<FinalBreakdownView> = Vec::with_capacity(TIPOS.len());
            for tipo in TIPOS {
                let tp = params.get(tipo).expect("params seeded for every tipo");
                let promedio = type_avgs.get(tipo).copied();
                let aporte = match promedio {
                    Some(avg) if tp.max_total > 0 => {
                        (avg / tp.max_total as f64) * (tp.peso as f64 / 100.0)
                    }
                    _ => 0.0,
                };
                puntaje_final += aporte;
                desglose.push(FinalBreakdownView {
                    rubric_type: tipo.to_string(),
                    peso: tp.peso,
                    max_total: tp.max_total,
                    promedio,
                    aporte,
                });
            }
            FinalPrototipoView {
                prototipo_id: pid,
                folio,
                nombre,
                puntaje_final,
                desglose,
            }
        })
        .collect();

    // Ranking: puntaje_final desc; empate → folio asc para estabilidad.
    prototipos.sort_by(|a, b| {
        b.puntaje_final
            .partial_cmp(&a.puntaje_final)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.folio.cmp(&b.folio))
    });

    Ok(Json(FinalRankingView {
        edition_id,
        prototipos,
    }))
}
