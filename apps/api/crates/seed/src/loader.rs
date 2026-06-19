use sqlx::PgPool;
use uuid::Uuid;
use argon2::{Argon2, PasswordHasher};
use argon2::password_hash::SaltString;
use argon2::password_hash::rand_core::OsRng;
use crate::data::{JURADOS, PROTOTIPOS};

pub async fn load_data(pool: &PgPool, edition_id: Uuid) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    // Load Jurados
    for &(email, name) in JURADOS {
        let pw = email; // Password matches email as requested
        let salt = SaltString::generate(&mut OsRng);
        let hash = Argon2::default()
            .hash_password(pw.as_bytes(), &salt)
            .map_err(|e| anyhow::anyhow!(e))?
            .to_string();

        sqlx::query(
            r#"INSERT INTO users (id, email, full_name, role, password_hash, is_active)
               VALUES ($1, $2, $3, 'jurado', $4, true)
               ON CONFLICT (email) DO NOTHING"#,
        )
        .bind(Uuid::new_v4())
        .bind(email)
        .bind(name)
        .bind(&hash)
        .execute(&mut *tx)
        .await?;
    }

    // Load Prototipos
    // We need category ID for the slug
    let categories: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT id, slug FROM categorias"
    )
    .fetch_all(&mut *tx)
    .await?;

    for &(folio, nombre, slug) in PROTOTIPOS {
        let cat_id = categories.iter().find(|c| c.1 == slug).map(|c| c.0);
        
        if let Some(cat_id) = cat_id {
            sqlx::query(
                r#"INSERT INTO prototipos (id, edition_id, folio, nombre, category_id, is_active)
                   VALUES ($1, $2, $3, $4, $5, true)
                   ON CONFLICT (folio, edition_id) DO UPDATE SET nombre = EXCLUDED.nombre, category_id = EXCLUDED.category_id"#,
            )
            .bind(Uuid::new_v4())
            .bind(edition_id)
            .bind(folio)
            .bind(nombre)
            .bind(cat_id)
            .execute(&mut *tx)
            .await?;
        } else {
            println!("Warning: Category not found for slug '{}'", slug);
        }
    }

    tx.commit().await?;
    Ok(())
}
