//! Seed dev-only fixtures: un jurado de prueba, prototipos en dos categorías,
//! y asignaciones (una memoria + dos exhibición) para ver la UI móvil con datos.
//!
//! Idempotente: corre `just seed-dev` las veces que quieras. Asume que
//! `just db-seed` ya corrió antes (edición activa + categorías + templates).

use anyhow::{anyhow, Context};
use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::SaltString;
use argon2::{Argon2, PasswordHasher};
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use uuid::Uuid;

const JURADO_EMAIL: &str = "jurado@dems.local";
const JURADO_PASSWORD: &str = "jurado1234";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt().with_env_filter("info").init();

    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL missing")?;
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&database_url)
        .await?;

    run(&pool).await?;

    tracing::info!(
        "seed-dev listo. Login como jurado: {} / {}",
        JURADO_EMAIL,
        JURADO_PASSWORD
    );
    Ok(())
}

async fn run(pool: &PgPool) -> anyhow::Result<()> {
    let edition_id: Uuid = sqlx::query_scalar(
        "SELECT id FROM editions WHERE active = true ORDER BY year DESC LIMIT 1",
    )
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| anyhow!("no hay edición activa — corre `just db-seed` primero"))?;

    let tpl_exhib: Uuid = sqlx::query_scalar(
        r#"SELECT id FROM rubric_templates
           WHERE edition_id = $1 AND tipo = 'exhibicion' AND activo
           ORDER BY created_at DESC LIMIT 1"#,
    )
    .bind(edition_id)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| anyhow!("falta rubric_template tipo=exhibicion"))?;

    let tpl_memoria: Uuid = sqlx::query_scalar(
        r#"SELECT id FROM rubric_templates
           WHERE edition_id = $1 AND tipo = 'memoria' AND activo
           ORDER BY created_at DESC LIMIT 1"#,
    )
    .bind(edition_id)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| anyhow!("falta rubric_template tipo=memoria"))?;

    let cat_software: Uuid = fetch_categoria(pool, "desarrollo-software").await?;
    let cat_salud: Uuid = fetch_categoria(pool, "productos-salud").await?;

    let jurado_id = upsert_jurado(pool).await?;
    tracing::info!(jurado_id = %jurado_id, "jurado listo");

    // Prototipos: (folio, nombre, plantel, categoria_id)
    let prototipos: &[(&str, &str, &str, Uuid)] = &[
        (
            "PR-2024-0101",
            "AulaSync — gestor de asistencia por QR",
            "CECyT 9 · Juan de Dios Bátiz",
            cat_software,
        ),
        (
            "PR-2024-0102",
            "NeuroLens — diagnóstico oftálmico asistido por IA",
            "CECyT 7 · Cuauhtémoc",
            cat_software,
        ),
        (
            "PR-2024-0201",
            "OxiBoost — concentrador de oxígeno portátil de bajo costo",
            "CECyT 6 · Miguel Othón de Mendizábal",
            cat_salud,
        ),
        (
            "PR-2024-0202",
            "DermaPatch — parche con biosensores para heridas crónicas",
            "CECyT 11 · Wilfrido Massieu",
            cat_salud,
        ),
    ];

    // Estrategia de asignación:
    // - Los 4 prototipos reciben exhibición.
    // - Sólo los 2 de software además reciben memoria (más variedad para la UI).
    for (folio, nombre, plantel, categoria_id) in prototipos {
        let prot_id = upsert_prototipo(pool, edition_id, folio, nombre, plantel).await?;
        link_categoria(pool, prot_id, *categoria_id).await?;
        upsert_assignment(pool, jurado_id, prot_id, tpl_exhib).await?;
    }
    // Memoria sólo para los dos de software
    for (folio, ..) in &prototipos[..2] {
        let prot_id: Uuid =
            sqlx::query_scalar("SELECT id FROM prototipos WHERE edition_id = $1 AND folio = $2")
                .bind(edition_id)
                .bind(*folio)
                .fetch_one(pool)
                .await?;
        upsert_assignment(pool, jurado_id, prot_id, tpl_memoria).await?;
    }

    Ok(())
}

async fn fetch_categoria(pool: &PgPool, slug: &str) -> anyhow::Result<Uuid> {
    sqlx::query_scalar("SELECT id FROM categorias WHERE slug = $1")
        .bind(slug)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| anyhow!("categoría {slug} no encontrada — corre `just db-seed`"))
}

async fn upsert_jurado(pool: &PgPool) -> anyhow::Result<Uuid> {
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(JURADO_PASSWORD.as_bytes(), &salt)
        .map_err(|e| anyhow!(e))?
        .to_string();

    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO users (id, email, full_name, role, password_hash, is_active)
           VALUES ($1, $2, 'Jurado de Prueba', 'jurado', $3, true)
           ON CONFLICT (email) DO UPDATE SET is_active = true
           RETURNING id"#,
    )
    .bind(Uuid::new_v4())
    .bind(JURADO_EMAIL)
    .bind(&hash)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

async fn upsert_prototipo(
    pool: &PgPool,
    edition_id: Uuid,
    folio: &str,
    nombre: &str,
    plantel: &str,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO prototipos (id, edition_id, folio, nombre, plantel)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (edition_id, folio)
           DO UPDATE SET nombre = EXCLUDED.nombre, plantel = EXCLUDED.plantel
           RETURNING id"#,
    )
    .bind(Uuid::new_v4())
    .bind(edition_id)
    .bind(folio)
    .bind(nombre)
    .bind(plantel)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

async fn link_categoria(
    pool: &PgPool,
    prototipo_id: Uuid,
    categoria_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO prototipo_categorias (prototipo_id, categoria_id)
           VALUES ($1, $2) ON CONFLICT DO NOTHING"#,
    )
    .bind(prototipo_id)
    .bind(categoria_id)
    .execute(pool)
    .await?;
    Ok(())
}

async fn upsert_assignment(
    pool: &PgPool,
    jurado_id: Uuid,
    prototipo_id: Uuid,
    template_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO assignments (jurado_id, prototipo_id, template_id)
           VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
    )
    .bind(jurado_id)
    .bind(prototipo_id)
    .bind(template_id)
    .execute(pool)
    .await?;
    Ok(())
}
