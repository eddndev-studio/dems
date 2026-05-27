//! seed-dev debe ser idempotente: correrlo N veces produce los mismos
//! conteos que correrlo una sola vez. Cubre la deuda técnica que
//! reportaba duplicación de asignaciones en la segunda corrida.

use sqlx::PgPool;
use uuid::Uuid;

async fn seed_prereqs(pool: &PgPool) {
    let edition_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO editions (id, year, name, active)
           VALUES ($1, 2024, '33° Premio NMS 2024', true)"#,
    )
    .bind(edition_id)
    .execute(pool)
    .await
    .expect("insert edition");

    for (slug, nombre, orden) in [
        ("desarrollo-software", "Desarrollo de Software", 1),
        ("productos-salud", "Productos para la Salud", 2),
    ] {
        sqlx::query(r#"INSERT INTO categorias (id, slug, nombre, orden) VALUES ($1, $2, $3, $4)"#)
            .bind(Uuid::new_v4())
            .bind(slug)
            .bind(nombre)
            .bind(orden)
            .execute(pool)
            .await
            .expect("insert categoria");
    }

    for (nombre, tipo) in [
        ("Rúbrica de Exhibición 2024", "exhibicion"),
        ("Rúbrica de Memoria Técnica 2021", "memoria"),
    ] {
        sqlx::query(
            r#"INSERT INTO rubric_templates (id, edition_id, nombre, tipo, activo)
               VALUES ($1, $2, $3, $4::rubric_type, true)"#,
        )
        .bind(Uuid::new_v4())
        .bind(edition_id)
        .bind(nombre)
        .bind(tipo)
        .execute(pool)
        .await
        .expect("insert rubric_template");
    }
}

async fn count(pool: &PgPool, sql: &str) -> i64 {
    sqlx::query_scalar(sql).fetch_one(pool).await.unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn seed_dev_is_idempotent(pool: PgPool) {
    seed_prereqs(&pool).await;

    dems_seed::dev::run(&pool).await.expect("first run");
    let p1 = count(&pool, "SELECT COUNT(*) FROM prototipos").await;
    let pc1 = count(&pool, "SELECT COUNT(*) FROM prototipo_categorias").await;
    let a1 = count(&pool, "SELECT COUNT(*) FROM assignments").await;
    let u1 = count(&pool, "SELECT COUNT(*) FROM users WHERE role = 'jurado'").await;

    assert_eq!(p1, 4, "prototipos tras primera corrida");
    assert_eq!(pc1, 4, "prototipo_categorias tras primera corrida");
    assert_eq!(
        a1, 6,
        "assignments tras primera corrida (4 exhibición + 2 memoria)"
    );
    assert_eq!(u1, 1, "jurado de prueba creado");

    dems_seed::dev::run(&pool).await.expect("second run");
    let p2 = count(&pool, "SELECT COUNT(*) FROM prototipos").await;
    let pc2 = count(&pool, "SELECT COUNT(*) FROM prototipo_categorias").await;
    let a2 = count(&pool, "SELECT COUNT(*) FROM assignments").await;
    let u2 = count(&pool, "SELECT COUNT(*) FROM users WHERE role = 'jurado'").await;

    assert_eq!(p2, p1, "segunda corrida no duplica prototipos");
    assert_eq!(pc2, pc1, "segunda corrida no duplica prototipo_categorias");
    assert_eq!(a2, a1, "segunda corrida no duplica assignments");
    assert_eq!(u2, u1, "segunda corrida no duplica jurado");

    dems_seed::dev::run(&pool).await.expect("third run");
    let a3 = count(&pool, "SELECT COUNT(*) FROM assignments").await;
    assert_eq!(a3, a1, "tercera corrida sigue estable");
}
