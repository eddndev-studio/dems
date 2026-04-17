//! Admin CRUD for rubric templates.

use axum::Json;
use serde_json::{json, Value};

use crate::extractors::RequireAdmin;

/// Placeholder for the rubric list handler — the next TDD cycle fleshes
/// it out. For now it exists so the RequireAdmin gate has somewhere to
/// sit and the auth tests can exercise it.
pub async fn list(_: RequireAdmin) -> Json<Value> {
    Json(json!([]))
}
