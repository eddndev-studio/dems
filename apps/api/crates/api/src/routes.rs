use axum::http::{header, Method};
use axum::{
    routing::{get, post},
    Json, Router,
};
use serde_json::json;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

use crate::openapi::ApiDoc;
use crate::state::AppState;

pub mod admin_assignments;
pub mod admin_categorias;
pub mod admin_editions;
pub mod admin_prototipos;
pub mod admin_results;
pub mod admin_rubrics;
pub mod admin_users;
pub mod auth_routes;
pub mod evaluacion_routes;
pub mod jurado_routes;

pub fn router(state: AppState) -> Router {
    let enable_docs = state.cfg.enable_docs;

    // CORS permisivo. La autenticación es 100% por header `Authorization:
    // Bearer <jwt>` — no usamos cookies ni sesiones del navegador, así que no
    // existe superficie CSRF: una página maliciosa puede emitir la petición
    // pero el navegador NO adjunta automáticamente credenciales, y sin el JWT
    // (que vive en el almacenamiento de la app, inaccesible cross-origin) la
    // petición es anónima. Por eso `AllowOrigin::any` es seguro aquí, y
    // desbloquea el build web (Flutter web sirve desde otro origen) y la LAN.
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PATCH,
            Method::PUT,
            Method::DELETE,
        ])
        .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE]);

    let router = Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/auth/login", post(auth_routes::login))
        .route("/auth/refresh", post(auth_routes::refresh))
        .route("/me", get(auth_routes::me))
        .route("/me/asignaciones", get(jurado_routes::list_asignaciones))
        .route(
            "/me/rubric-templates/:id",
            get(jurado_routes::get_rubric_template),
        )
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
        .route("/admin/categorias", get(admin_categorias::list))
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
        .route("/admin/editions/:id/phase", post(admin_editions::set_phase))
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
            "/admin/rubric-templates/:id/structure",
            axum::routing::put(admin_rubrics::replace_structure),
        )
        .route(
            "/admin/results/categoria/:slug",
            get(admin_results::by_categoria),
        )
        .route(
            "/admin/results/edition/:id/export.xlsx",
            get(admin_results::export_excel),
        )
        .route(
            "/admin/evaluaciones/:id/reopen",
            post(evaluacion_routes::reopen),
        )
        .route(
            "/admin/results/edition/:id/final",
            get(admin_results::final_ranking),
        );

    // Swagger UI + /openapi.json sólo si ENABLE_DOCS != false. En producción se
    // apaga para no exponer el esquema completo de la API públicamente.
    let router = if enable_docs {
        router.merge(SwaggerUi::new("/docs").url("/openapi.json", ApiDoc::openapi()))
    } else {
        router
    };

    router
        .layer(cors)
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
