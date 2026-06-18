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
    /// 409 Conflict con un `code` máquina además del mensaje humano. El cliente
    /// (app de jurado) ramifica por `code` —p.ej. `already_submitted`,
    /// `edition_closed`— sin parsear el texto humano, que puede cambiar.
    #[error("conflict[{0}]: {1}")]
    ConflictCoded(&'static str, String),
    #[error("internal: {0}")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        // `code`: sólo presente en respuestas que llevan un código máquina
        // (por ahora los 409 de evaluación). El resto va sin `code`.
        let (status, msg, code): (StatusCode, String, Option<&'static str>) = match &self {
            ApiError::Core(CoreError::NotFound) => {
                (StatusCode::NOT_FOUND, "not found".to_string(), None)
            }
            ApiError::Core(CoreError::Unauthorized) => {
                (StatusCode::UNAUTHORIZED, "unauthorized".to_string(), None)
            }
            ApiError::Core(CoreError::Forbidden) => {
                (StatusCode::FORBIDDEN, "forbidden".to_string(), None)
            }
            ApiError::Core(CoreError::Conflict(m)) => (StatusCode::CONFLICT, m.clone(), None),
            ApiError::Core(CoreError::Validation(m)) => {
                (StatusCode::UNPROCESSABLE_ENTITY, m.clone(), None)
            }
            ApiError::Core(CoreError::Database(e)) => {
                tracing::error!(error = %e, "database error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "database error".into(),
                    None,
                )
            }
            ApiError::BadRequest(m) => (StatusCode::BAD_REQUEST, m.clone(), None),
            ApiError::ConflictCoded(code, m) => (StatusCode::CONFLICT, m.clone(), Some(code)),
            ApiError::Internal(e) => {
                tracing::error!(error = %e, "internal error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal error".into(),
                    None,
                )
            }
        };
        let body = match code {
            Some(code) => json!({ "error": msg, "code": code }),
            None => json!({ "error": msg }),
        };
        (status, Json(body)).into_response()
    }
}
