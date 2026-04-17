use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;

use dems_core::CoreError;

pub type ApiResult<T> = Result<T, ApiError>;

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error(transparent)]
    Core(#[from] CoreError),
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("internal: {0}")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, msg) = match &self {
            ApiError::Core(CoreError::NotFound) => (StatusCode::NOT_FOUND, "not found".to_string()),
            ApiError::Core(CoreError::Unauthorized) => {
                (StatusCode::UNAUTHORIZED, "unauthorized".to_string())
            }
            ApiError::Core(CoreError::Forbidden) => {
                (StatusCode::FORBIDDEN, "forbidden".to_string())
            }
            ApiError::Core(CoreError::Conflict(m)) => (StatusCode::CONFLICT, m.clone()),
            ApiError::Core(CoreError::Validation(m)) => {
                (StatusCode::UNPROCESSABLE_ENTITY, m.clone())
            }
            ApiError::Core(CoreError::Database(e)) => {
                tracing::error!(error = %e, "database error");
                (StatusCode::INTERNAL_SERVER_ERROR, "database error".into())
            }
            ApiError::BadRequest(m) => (StatusCode::BAD_REQUEST, m.clone()),
            ApiError::Internal(e) => {
                tracing::error!(error = %e, "internal error");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".into())
            }
        };
        (status, Json(json!({ "error": msg }))).into_response()
    }
}
