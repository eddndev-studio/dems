//! Carga jurados y prototipos oficiales 2026 desde [`crate::data`] (generado
//! con `scripts/gen_seed_data.py` a partir de los Excel oficiales).
//!
//! - Jurados: usuarios rol `jurado`, password = su email. Sin Unidad Académica.
//! - Prototipos: vinculados a su categoría vía `prototipo_categorias`.
//! - Asignaciones: cada jurado evalúa TODOS los prototipos de su categoría con
//!   la rúbrica de exhibición activa (asignación por categoría / área).
//!
//! Idempotente: se puede correr varias veces.

use crate::data::{JURADOS, PROTOTIPOS};
use anyhow::{anyhow, Context};
use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::SaltString;
use argon2::{Argon2, PasswordHasher};
use sqlx::PgPool;
use std::collections::HashMap;
use uuid::Uuid;

pub async fn load_data(pool: &PgPool, edition_id: Uuid) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    // Catálogo de categorías: slug -> id.
    let categorias: HashMap<String, Uuid> = sqlx::query_as("SELECT slug, id FROM categorias")
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .collect();

    // Rúbrica de exhibición activa de la edición (para las asignaciones).
    let tpl_exhib: Uuid = sqlx::query_scalar(
        r#"SELECT id FROM rubric_templates
           WHERE edition_id = $1 AND tipo = 'exhibicion' AND activo
           ORDER BY created_at DESC LIMIT 1"#,
    )
    .bind(edition_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| anyhow!("falta rubric_template tipo=exhibicion — corre el seed de rúbricas"))?;

    // Jurados -> id + categoría.
    let mut jurado_por_slug: HashMap<&str, Vec<Uuid>> = HashMap::new();
    for &(email, name, slug) in JURADOS {
        if !categorias.contains_key(slug) {
            return Err(anyhow!("jurado {email}: slug de categoría desconocido '{slug}'"));
        }
        let salt = SaltString::generate(&mut OsRng);
        let hash = Argon2::default()
            .hash_password(email.as_bytes(), &salt) // password = email
            .map_err(|e| anyhow!(e))?
            .to_string();

        let jurado_id: Uuid = sqlx::query_scalar(
            r#"INSERT INTO users (id, email, full_name, role, password_hash, is_active)
               VALUES ($1, $2, $3, 'jurado', $4, true)
               ON CONFLICT (email) DO UPDATE SET full_name = EXCLUDED.full_name, is_active = true
               RETURNING id"#,
        )
        .bind(Uuid::new_v4())
        .bind(email)
        .bind(name)
        .bind(&hash)
        .fetch_one(&mut *tx)
        .await
        .with_context(|| format!("upsert jurado {email}"))?;

        jurado_por_slug.entry(slug).or_default().push(jurado_id);
    }

    // Prototipos -> id + vínculo de categoría. slug -> [prototipo_id].
    let mut prototipo_por_slug: HashMap<&str, Vec<Uuid>> = HashMap::new();
    for &(folio, nombre, slug) in PROTOTIPOS {
        let cat_id = *categorias
            .get(slug)
            .ok_or_else(|| anyhow!("prototipo {folio}: slug de categoría desconocido '{slug}'"))?;

        let prot_id: Uuid = sqlx::query_scalar(
            r#"INSERT INTO prototipos (id, edition_id, folio, nombre)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (edition_id, folio) DO UPDATE SET nombre = EXCLUDED.nombre
               RETURNING id"#,
        )
        .bind(Uuid::new_v4())
        .bind(edition_id)
        .bind(folio)
        .bind(nombre)
        .fetch_one(&mut *tx)
        .await
        .with_context(|| format!("upsert prototipo {folio}"))?;

        sqlx::query(
            r#"INSERT INTO prototipo_categorias (prototipo_id, categoria_id)
               VALUES ($1, $2) ON CONFLICT DO NOTHING"#,
        )
        .bind(prot_id)
        .bind(cat_id)
        .execute(&mut *tx)
        .await?;

        prototipo_por_slug.entry(slug).or_default().push(prot_id);
    }

    // Asignación por categoría: cada jurado evalúa todos los prototipos de su
    // categoría con la rúbrica de exhibición.
    let mut asignaciones = 0usize;
    for (slug, jurados) in &jurado_por_slug {
        let prototipos = match prototipo_por_slug.get(slug) {
            Some(p) => p,
            None => continue, // categoría sin prototipos en esta edición
        };
        for &jurado_id in jurados {
            for &prot_id in prototipos {
                sqlx::query(
                    r#"INSERT INTO assignments (jurado_id, prototipo_id, template_id)
                       VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
                )
                .bind(jurado_id)
                .bind(prot_id)
                .bind(tpl_exhib)
                .execute(&mut *tx)
                .await?;
                asignaciones += 1;
            }
        }
    }

    tx.commit().await?;
    tracing::info!(
        jurados = JURADOS.len(),
        prototipos = PROTOTIPOS.len(),
        asignaciones,
        "datos oficiales 2026 cargados"
    );
    Ok(())
}
