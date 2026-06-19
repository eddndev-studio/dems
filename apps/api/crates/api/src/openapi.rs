//! OpenAPI document for the DEMS API.
//!
//! El doc se construye declarativamente con `utoipa::OpenApi`. Cada handler
//! que aparece en `paths(...)` debe estar anotado con `#[utoipa::path(...)]`.

use utoipa::openapi::security::{Http, HttpAuthScheme, SecurityScheme};
use utoipa::{Modify, OpenApi};

use crate::routes::{
    admin_assignments, admin_categorias, admin_editions, admin_prototipos, admin_results,
    admin_rubrics, admin_users, auth_routes, evaluacion_routes, jurado_routes,
};

/// Bearer JWT como esquema global. Los handlers que requieren autenticación
/// declaran `security(("bearer_auth" = []))` en su `#[utoipa::path]`.
pub struct SecurityAddon;

impl Modify for SecurityAddon {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        let components = openapi.components.get_or_insert_with(Default::default);
        components.add_security_scheme(
            "bearer_auth",
            SecurityScheme::Http(Http::new(HttpAuthScheme::Bearer)),
        );
    }
}

#[derive(OpenApi)]
#[openapi(
    info(
        title = "DEMS API",
        version = "0.1.0",
        description = "Plataforma de evaluación de prototipos IPN-DEMS.",
    ),
    servers(
        (url = "http://localhost:8080", description = "Local dev"),
    ),
    paths(
        // --- Auth ---
        auth_routes::login,
        auth_routes::refresh,
        auth_routes::me,
        // --- Jurado ---
        jurado_routes::list_asignaciones,
        jurado_routes::get_rubric_template,
        evaluacion_routes::create,
        evaluacion_routes::get_by_id,
        evaluacion_routes::patch_evaluacion,
        evaluacion_routes::submit,
        // --- Admin: users ---
        admin_users::list,
        admin_users::create,
        admin_users::get_by_id,
        admin_users::patch,
        admin_users::delete,
        admin_users::reset_password,
        // --- Admin: categorias ---
        admin_categorias::list,
        // --- Admin: editions ---
        admin_editions::list,
        admin_editions::create,
        admin_editions::get_by_id,
        admin_editions::patch,
        admin_editions::delete,
        admin_editions::set_phase,
        // --- Admin: prototipos ---
        admin_prototipos::list,
        admin_prototipos::create,
        admin_prototipos::get_by_id,
        admin_prototipos::patch,
        admin_prototipos::delete,
        // --- Admin: assignments ---
        admin_assignments::list_for_prototipo,
        admin_assignments::create,
        admin_assignments::delete,
        // --- Admin: rubric templates ---
        admin_rubrics::list,
        admin_rubrics::create,
        admin_rubrics::get_by_id,
        admin_rubrics::patch,
        admin_rubrics::replace_structure,
        admin_rubrics::delete_rubric,
        // --- Admin: results & ops ---
        admin_results::by_categoria,
        admin_results::export_excel,
        admin_results::final_ranking,
        evaluacion_routes::reopen,
    ),
    modifiers(&SecurityAddon),
)]
pub struct ApiDoc;
