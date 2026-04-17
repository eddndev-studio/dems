use axum::{
    routing::{get, post},
    Json, Router,
};
use serde_json::json;
use tower_http::trace::TraceLayer;

use crate::state::AppState;

mod admin_rubrics;
mod auth_routes;
mod evaluacion_routes;
mod jurado_routes;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/auth/login", post(auth_routes::login))
        .route("/auth/refresh", post(auth_routes::refresh))
        .route("/me", get(auth_routes::me))
        .route(
            "/me/asignaciones",
            get(jurado_routes::list_asignaciones),
        )
        .route("/evaluaciones", post(evaluacion_routes::create))
        .route(
            "/evaluaciones/:id",
            get(evaluacion_routes::get_by_id).patch(evaluacion_routes::patch_evaluacion),
        )
        .route(
            "/admin/rubric-templates",
            get(admin_rubrics::list).post(admin_rubrics::create),
        )
        .route(
            "/admin/rubric-templates/:id",
            get(admin_rubrics::get_by_id)
                .patch(admin_rubrics::patch)
                .delete(admin_rubrics::delete_rubric),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

async fn healthz() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok" }))
}

async fn readyz(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> Json<serde_json::Value> {
    let db_ok = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.pool)
        .await
        .is_ok();
    Json(json!({ "db": db_ok }))
}
