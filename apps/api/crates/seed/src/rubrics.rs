//! Seed admin user + edition 2024 + 7 categorías + default rubric templates.
//!
//! Se usa `sqlx::query` (runtime) en lugar de `query!` para que el seed
//! compile sin necesidad de una base de datos disponible.

use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::SaltString;
use argon2::{Argon2, PasswordHasher};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn seed(pool: &PgPool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    // --- Admin user (idempotente) ---
    let admin_email = "admin@dems.local";
    let admin_pw = "admin1234"; // cambiar tras primer login
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(admin_pw.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!(e))?
        .to_string();

    sqlx::query(
        r#"INSERT INTO users (id, email, full_name, role, password_hash, is_active)
           VALUES ($1, $2, 'Administrador', 'admin', $3, true)
           ON CONFLICT (email) DO NOTHING"#,
    )
    .bind(Uuid::new_v4())
    .bind(admin_email)
    .bind(&hash)
    .execute(&mut *tx)
    .await?;

    // --- Categorías (7 oficiales) ---
    let categorias: &[(&str, &str, i32)] = &[
        ("desarrollo-software", "Desarrollo de Software", 1),
        ("productos-ensenanza", "Productos para la Enseñanza", 2),
        ("maquinaria-equipo", "Maquinaria y Equipo Productivo", 3),
        (
            "procesos-quimicos-biologicos",
            "Procesos Químicos y Biológicos",
            4,
        ),
        ("soluciones-domesticas", "Soluciones Domésticas", 5),
        ("productos-salud", "Productos para la Salud", 6),
        ("aplicacion-empresa", "Aplicación para la Empresa", 7),
    ];
    for (slug, nombre, orden) in categorias {
        sqlx::query(
            r#"INSERT INTO categorias (id, slug, nombre, orden)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (slug) DO NOTHING"#,
        )
        .bind(Uuid::new_v4())
        .bind(slug)
        .bind(nombre)
        .bind(orden)
        .execute(&mut *tx)
        .await?;
    }

    // --- Edición 2024 ---
    let edition_id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO editions (id, year, name, active)
           VALUES ($1, 2024, '33° Premio a los Mejores Prototipos NMS 2024', true)
           ON CONFLICT (year) DO UPDATE SET active = EXCLUDED.active
           RETURNING id"#,
    )
    .bind(Uuid::new_v4())
    .fetch_one(&mut *tx)
    .await?;

    seed_exhibicion_2024(&mut tx, edition_id).await?;
    seed_memoria_2021(&mut tx, edition_id).await?;

    tx.commit().await?;
    Ok(())
}

async fn seed_exhibicion_2024(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    edition_id: Uuid,
) -> anyhow::Result<()> {
    let template_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_templates (id, edition_id, nombre, tipo, activo)
           VALUES ($1, $2, 'Rúbrica de Exhibición 2024', 'exhibicion', true)"#,
    )
    .bind(template_id)
    .bind(edition_id)
    .execute(&mut **tx)
    .await?;

    let secciones: &[(&str, i32, &[(&str, i32, &str)])] = &[
        ("Aplicabilidad", 1, &[
            ("El prototipo funciona correctamente sin presentar fallas durante la demostración.", 1, "scale"),
            ("Se identifica en el prototipo la aplicación del conocimiento adquirido por el alumno de acuerdo con la carrera o unidades de aprendizaje.", 2, "scale"),
            ("Los procesos o métodos de construcción utilizados para el desarrollo del prototipo fueron adecuadamente aplicados.", 3, "scale"),
            ("Es aplicable para la población a la cual fue diseñado (cliente, mercado, o servicio).", 4, "scale"),
            ("El prototipo se sometió a pruebas.", 5, "scale"),
            ("La solución es aplicable al problema, necesidad o demanda real presentada.", 6, "scale"),
            ("El prototipo satisface una necesidad acorde a la categoría.", 7, "scale"),
        ]),
        ("Innovación", 2, &[
            ("El prototipo es nuevo o mejora un diseño ya existente.", 1, "scale"),
            ("Introduce un nuevo mercado o servicio.", 2, "scale"),
            ("La solución al problema planteado es resuelta por el prototipo.", 3, "scale"),
            ("Explica claramente el proceso de innovación en el prototipo.", 4, "scale"),
            ("El prototipo desarrollado tiene potencial en el mercado.", 5, "scale"),
            ("Consideras que tu prototipo muestra elementos de creatividad.", 6, "scale"),
        ]),
        ("Factibilidad", 3, &[
            ("Propone una alternativa tecnológica o administrativa viable.", 1, "scale"),
            ("Argumenta el tipo de materiales que consideró para la construcción del prototipo.", 2, "scale"),
            ("Explica cómo consideró el costo unitario del prototipo.", 3, "scale"),
            ("Considera para su producción las necesidades del mercado.", 4, "scale"),
            ("Explica las ventajas desde el punto de vista financiero, económico, social, ambiental en la producción del prototipo, bien o servicio.", 5, "scale"),
            ("¿Existe un potencial en el mercado internacional?", 6, "scale"),
            ("¿Conoce los procesos o métodos de manufactura para llevar a cabo la producción?", 7, "scale"),
        ]),
        ("Exposición Oral", 4, &[
            ("Expone de manera clara y congruente.", 1, "scale"),
            ("La exposición menciona las ideas principales del prototipo.", 2, "scale"),
            ("Los integrantes del equipo conocen el desarrollo del prototipo.", 3, "scale"),
            ("Utiliza el lenguaje técnico o terminología de acuerdo con el prototipo.", 4, "scale"),
            ("Al ser cuestionados las respuestas son precisas.", 5, "scale"),
        ]),
        ("Construcción del Prototipo", 5, &[
            ("Utilizó materiales reciclados o pensados en la sustentabilidad.", 1, "scale"),
            ("Calidad del trabajo realizado (prototipo o programa).", 2, "scale"),
        ]),
    ];

    for (sec_name, sec_orden, criterios) in secciones {
        let sec_id = insert_section(tx, template_id, sec_name, *sec_orden, None).await?;
        for (texto, orden, kind) in *criterios {
            insert_criterion(tx, sec_id, texto, *orden, 3, kind).await?;
        }
    }

    let cartel_sec = insert_section(tx, template_id, "Cartel y Stand", 6, None).await?;
    insert_criterion(
        tx,
        cartel_sec,
        "El cartel es creativo, innovador, presenta cuadro de datos, imágenes, esquemas y apoyos a la exposición.",
        1, 1, "scale",
    ).await?;
    insert_criterion(
        tx,
        cartel_sec,
        "¿Cómo evaluarías el diseño del stand?",
        2,
        3,
        "scale",
    )
    .await?;

    let sec_clave = insert_section(
        tx,
        template_id,
        "Preguntas clave (sin puntaje)",
        7,
        Some(0.0),
    )
    .await?;
    for (i, q) in [
        "¿En dónde surgió la idea del prototipo?",
        "Según el lema del Politécnico \"La técnica al servicio de la patria\", ¿cuál sería tu mejor contribución?",
        "¿Qué hace sustentable tu prototipo?",
    ]
    .iter()
    .enumerate()
    {
        insert_criterion(tx, sec_clave, q, i as i32 + 1, 0, "text_key").await?;
    }
    insert_criterion(
        tx,
        sec_clave,
        "Se observó acompañamiento del asesor",
        4,
        1,
        "boolean",
    )
    .await?;

    Ok(())
}

async fn seed_memoria_2021(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    edition_id: Uuid,
) -> anyhow::Result<()> {
    let template_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_templates (id, edition_id, nombre, tipo, activo)
           VALUES ($1, $2, 'Rúbrica de Memoria Técnica 2021', 'memoria', true)"#,
    )
    .bind(template_id)
    .bind(edition_id)
    .execute(&mut **tx)
    .await?;

    let secciones: &[(&str, i32, &[&str])] = &[
        (
            "Resumen",
            1,
            &[
                "Presenta los datos relevantes del desarrollo del prototipo/modelo de negocios.",
                "Incluye las variables principales del proyecto.",
                "Presenta los resultados obtenidos.",
            ],
        ),
        (
            "Introducción",
            2,
            &[
                "Explica brevemente sobre la estructura del documento.",
                "Planteamiento del problema.",
                "Presenta la metodología de los procedimientos utilizados.",
            ],
        ),
        (
            "Objetivo",
            3,
            &[
                "Presenta un objetivo claro y preciso.",
                "El objetivo es congruente con la categoría.",
                "Los objetivos específicos son congruentes con el objetivo general.",
                "Los objetivos específicos son factibles de evaluar y medibles.",
            ],
        ),
        (
            "Justificación",
            4,
            &[
                "Plantea la forma de solucionar el problema, demanda o necesidad detectada.",
                "Expone la importancia por la cual desarrolló el prototipo/modelo de negocios.",
                "Describe el sector o mercado al que va dirigido.",
                "Menciona los beneficios que se obtendrán al desarrollar el prototipo/B2B.",
            ],
        ),
        (
            "Sustento Teórico",
            5,
            &[
                "Refleja la extracción y recopilación de información teórica y de campo.",
                "Menciona los principios básicos o conceptos en los que se basa.",
                "Se apoya en el sustento teórico para el desarrollo.",
            ],
        ),
        (
            "Metodología — Planeación",
            6,
            &[
                "Describe los procesos detalladamente de cada actividad.",
                "Presenta cronograma de actividades.",
            ],
        ),
        (
            "Factibilidad Técnica",
            7,
            &[
                "Presenta procesos de operación o técnicos utilizados.",
                "Disponibilidad de materiales, recursos humanos, equipo, maquinaria o tecnología.",
                "Presenta propuestas de mantenimiento del prototipo.",
                "Interpretación de resultados (ampliación o reducción de producción).",
                "Utiliza elementos y recursos técnicos congruentes.",
                "Es una alternativa tecnológicamente viable.",
            ],
        ),
        (
            "Factibilidad Económica",
            8,
            &[
                "Determina costos de operación y producción.",
                "Determina análisis costo-beneficio.",
                "Presenta metodología para mantenerse ante el consumidor.",
            ],
        ),
        (
            "Factibilidad Financiera",
            9,
            &[
                "Presenta y determina presupuestos de ingresos y egresos.",
                "Es financieramente factible de producir.",
                "Es una alternativa viable.",
            ],
        ),
        (
            "Impacto Social, Tecnológico y Sustentable",
            10,
            &[
                "Describe los beneficios e impacto social o tecnológico.",
                "Describe el impacto ambiental positivo o negativo posible.",
                "Contribuye a la sustentabilidad para el sector.",
            ],
        ),
        (
            "Grado de Innovación",
            11,
            &[
                "Especifica una novedad, idea nueva, producto, método, servicio o mercado.",
                "Describe la innovación, creatividad, mejoras o nueva solución.",
            ],
        ),
        (
            "Pruebas",
            12,
            &["Describe el tipo de pruebas para comprobar la funcionalidad."],
        ),
        (
            "Análisis de Resultados",
            13,
            &[
                "Presenta resultados mediante tablas, planos, gráficas, fotografías.",
                "Analiza e interpreta resultados comparativos.",
            ],
        ),
        (
            "Conclusión",
            14,
            &[
                "Puntualiza en qué medida se cumplieron los objetivos.",
                "Presenta propuestas para la mejora del prototipo.",
            ],
        ),
        (
            "Bibliografía",
            15,
            &["Utiliza referencias bibliográficas confiables."],
        ),
        (
            "Gramática",
            16,
            &[
                "Presenta una redacción clara y congruente.",
                "Presenta una correcta ortografía.",
            ],
        ),
        (
            "Anexo — Instructivo o Manual",
            17,
            &[
                "Detalles técnicos de ensamble o armado, o uso.",
                "Procedimiento para el funcionamiento o utilización.",
                "Procedimientos de mantenimiento.",
                "Recomendaciones o precauciones de uso.",
            ],
        ),
        (
            "Anexo — Tríptico Publicitario",
            18,
            &[
                "Visualmente creativo (logo, marca, colores, diseño).",
                "Título.",
                "Misión y visión.",
                "Objetivo.",
                "Ventajas competitivas del producto o servicio (propuesta de valor).",
            ],
        ),
        (
            "Anexo — Presentación de Video",
            19,
            &[
                "Presentación.",
                "Nombre del prototipo.",
                "Objetivo.",
                "Características del prototipo en funcionamiento.",
                "Promoción del producto o servicio y mercado.",
                "Elementos de innovación en su presentación.",
                "Conclusiones.",
            ],
        ),
    ];

    for (sec_name, sec_orden, criterios) in secciones {
        let sec_id = insert_section(tx, template_id, sec_name, *sec_orden, None).await?;
        for (i, texto) in criterios.iter().enumerate() {
            insert_criterion(tx, sec_id, texto, i as i32 + 1, 3, "scale").await?;
        }
    }

    let foto_sec = insert_section(tx, template_id, "Anexo — Fotográfico", 20, None).await?;
    insert_criterion(
        tx,
        foto_sec,
        "Presenta 5 fotografías significativas con nota al pie que muestren el proceso del prototipo.",
        1, 1, "boolean",
    ).await?;

    Ok(())
}

async fn insert_section(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    template_id: Uuid,
    nombre: &str,
    orden: i32,
    peso_pct: Option<f64>,
) -> anyhow::Result<Uuid> {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_sections (id, template_id, nombre, orden, peso_pct)
           VALUES ($1, $2, $3, $4, $5)"#,
    )
    .bind(id)
    .bind(template_id)
    .bind(nombre)
    .bind(orden)
    .bind(peso_pct)
    .execute(&mut **tx)
    .await?;
    Ok(id)
}

async fn insert_criterion(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    section_id: Uuid,
    texto: &str,
    orden: i32,
    max_score: i32,
    kind: &str,
) -> anyhow::Result<Uuid> {
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rubric_criteria (id, section_id, texto, orden, max_score, kind)
           VALUES ($1, $2, $3, $4, $5, $6::criterion_kind)"#,
    )
    .bind(id)
    .bind(section_id)
    .bind(texto)
    .bind(orden)
    .bind(max_score)
    .bind(kind)
    .execute(&mut **tx)
    .await?;
    Ok(id)
}
