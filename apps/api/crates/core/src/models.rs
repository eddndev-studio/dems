use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Type;
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Type, ToSchema)]
#[sqlx(type_name = "user_role", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum UserRole {
    Admin,
    Jurado,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Type, ToSchema)]
#[sqlx(type_name = "rubric_type", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum RubricType {
    Exhibicion,
    Memoria,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Type, ToSchema)]
#[sqlx(type_name = "criterion_kind", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum CriterionKind {
    /// Escala 0..max_score (típicamente 0-3 Insuficiente/Regular/Bueno/Excelente).
    Scale,
    /// Cumple / No cumple (bool), almacenado como 0 o max_score.
    Boolean,
    /// Pregunta clave — texto libre, no puntúa.
    TextKey,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub full_name: String,
    pub role: UserRole,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct Edition {
    pub id: Uuid,
    pub year: i32,
    pub name: String,
    pub active: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct Categoria {
    pub id: Uuid,
    pub slug: String,
    pub nombre: String,
    pub orden: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct RubricTemplate {
    pub id: Uuid,
    pub edition_id: Uuid,
    pub nombre: String,
    pub tipo: RubricType,
    pub descripcion: Option<String>,
    pub activo: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct RubricSection {
    pub id: Uuid,
    pub template_id: Uuid,
    pub nombre: String,
    pub orden: i32,
    pub peso_pct: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct RubricCriterion {
    pub id: Uuid,
    pub section_id: Uuid,
    pub texto: String,
    pub orden: i32,
    pub max_score: i32,
    pub kind: CriterionKind,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct Prototipo {
    pub id: Uuid,
    pub edition_id: Uuid,
    pub folio: String,
    pub nombre: String,
    pub plantel: Option<String>,
    pub eje_transversal: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct Evaluacion {
    pub id: Uuid,
    pub prototipo_id: Uuid,
    pub jurado_id: Uuid,
    pub template_id: Uuid,
    pub submitted_at: Option<DateTime<Utc>>,
    pub observaciones: Option<String>,
    pub acompanamiento_asesor: Option<bool>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
pub struct EvaluacionScore {
    pub evaluacion_id: Uuid,
    pub criterion_id: Uuid,
    pub score: Option<i32>,
    pub text_answer: Option<String>,
}
