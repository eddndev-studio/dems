//! Read-only catalog endpoint for the 7 (extensible) categorías.

use axum::extract::State;
use axum::Json;
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::extractors::RequireAdmin;
use crate::state::AppState;

#[derive(Debug, Serialize, ToSchema, sqlx::FromRow)]
pub struct CategoriaView {
    pub id: Uuid,
    pub slug: String,
    pub nombre: String,
    pub orden: i32,
}

#[utoipa::path(
    get,
    path = "/admin/categorias",
    tag = "admin/categorias",
    responses((status = 200, body = [CategoriaView])),
    security(("bearer_auth" = [])),
)]
pub async fn list(
    State(state): State<AppState>,
    _: RequireAdmin,
) -> ApiResult<Json<Vec<CategoriaView>>> {
    let rows = sqlx::query_as::<_, CategoriaView>(
        r#"SELECT id, slug, nombre, orden FROM categorias ORDER BY orden, slug"#,
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| ApiError::Internal(e.into()))?;
    Ok(Json(rows))
}
