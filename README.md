# DEMS — Plataforma de Evaluación de Prototipos

Plataforma para evaluar el concurso **"Premio a los Mejores Prototipos de Nivel Medio Superior"** del IPN-DEMS.

## Estructura

```
dems/
├── apps/
│   ├── api/              # Rust + Axum + SQLx + PostgreSQL
│   └── mobile/           # Flutter (Android/iOS/Web) offline-first
├── packages/
│   └── shared/           # OpenAPI spec + tipos generados
├── docs/                 # Documentación y referencias de rúbricas
├── scripts/              # Scripts de desarrollo
├── docker-compose.yml    # Postgres local
├── justfile              # Comandos comunes
└── .env.example
```

## Roles

- **admin** — configura ediciones, categorías, rúbricas, usuarios y prototipos.
- **jurado** — evalúa los prototipos asignados (offline-first).

## Dominio

- **Edición**: año del concurso (2024, 2025, ...). Rúbricas viven por edición.
- **Categoría**: una de las 7 oficiales (Software, Enseñanza, Maquinaria, Químicos/Biológicos, Domésticas, Salud, Empresa).
- **Rúbrica** (configurable): plantilla con secciones y criterios. Dos tipos: `exhibicion` (en piso) y `memoria` (documento).
- **Prototipo**: pertenece a una edición y una o más categorías.
- **Evaluación**: un jurado evalúa un prototipo con una rúbrica → puntajes por criterio.

## Desarrollo rápido

```bash
# Levantar Postgres
just db-up

# Correr migraciones + seed
just db-migrate
just db-seed

# Correr API
just api

# Correr app Flutter
just mobile
```

Requisitos: `cargo`, `flutter`, `docker`, `just`, `sqlx-cli`.
