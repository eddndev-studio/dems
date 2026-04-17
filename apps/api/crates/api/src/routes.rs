use axum::{
    routing::{get, post},
    Json, Router,
};
use serde_json::json;
use tower_http::trace::TraceLayer;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

use crate::openapi::ApiDoc;
use crate::state::AppState;

pub mod admin_assignments;
pub mod admin_editions;
pub mod admin_prototipos;
pub mod admin_results;
pub mod admin_rubrics;
pub mod admin_users;
pub mod auth_routes;
pub mod evaluacion_routes;
pub mod jurado_routes;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/auth/login", post(auth_routes::login))
        .route("/auth/refresh", post(auth_routes::refresh))
        .route("/me", get(auth_routes::me))
        .route("/me/asignaciones", get(jurado_routes::list_asignaciones))
        .route("/evaluaciones", post(evaluacion_routes::create))
        .route(
            "/evaluaciones/:id",
            get(evaluacion_routes::get_by_id).patch(evaluacion_routes::patch_evaluacion),
        )
        .route("/evaluaciones/:id/submit", post(evaluacion_routes::submit))
        .route(
            "/admin/users",
            get(admin_users::list).post(admin_users::create),
        )
        .route(
            "/admin/users/:id",
            get(admin_users::get_by_id)
                .patch(admin_users::patch)
                .delete(admin_users::delete),
        )
        .route(
            "/admin/users/:id/password",
            axum::routing::put(admin_users::reset_password),
        )
        .route(
            "/admin/editions",
            get(admin_editions::list).post(admin_editions::create),
        )
        .route(
            "/admin/editions/:id",
            get(admin_editions::get_by_id)
                .patch(admin_editions::patch)
                .delete(admin_editions::delete),
        )
        .route(
            "/admin/prototipos",
            get(admin_prototipos::list).post(admin_prototipos::create),
        )
        .route(
            "/admin/prototipos/:id",
            get(admin_prototipos::get_by_id)
                .patch(admin_prototipos::patch)
                .delete(admin_prototipos::delete),
        )
        .route(
            "/admin/prototipos/:id/assignments",
            get(admin_assignments::list_for_prototipo),
        )
        .route(
            "/admin/assignments",
            post(admin_assignments::create).delete(admin_assignments::delete),
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
        .route(
            "/admin/results/categoria/:slug",
            get(admin_results::by_categoria),
        )
        .route(
            "/admin/results/edition/:id/export.csv",
            get(admin_results::export_csv),
        )
        .route(
            "/admin/evaluaciones/:id/reopen",
            post(evaluacion_routes::reopen),
        )
        .merge(SwaggerUi::new("/docs").url("/openapi.json", ApiDoc::openapi()))
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
