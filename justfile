set dotenv-load := true

# Runtime de contenedores (podman en Fedora). Override: `COMPOSE=docker just db-up`.
COMPOSE := env_var_or_default("COMPOSE", "podman compose")

default:
    @just --list

# --- DB ---
db-up:
    {{COMPOSE}} up -d postgres

db-down:
    {{COMPOSE}} down

db-logs:
    {{COMPOSE}} logs -f postgres

db-shell:
    {{COMPOSE}} exec postgres psql -U dems -d dems

db-reset:
    {{COMPOSE}} down -v
    {{COMPOSE}} up -d postgres
    sleep 3
    just db-migrate
    just db-seed

db-migrate:
    cd apps/api && sqlx migrate run

db-seed:
    cd apps/api && cargo run --bin seed

# Fixtures de desarrollo: jurado de prueba + prototipos + asignaciones.
# Idempotente. Corre después de `just db-seed`.
seed-dev:
    cd apps/api && cargo run --bin seed-dev

# --- API ---
api:
    cd apps/api && cargo run --bin dems-api

api-check:
    cd apps/api && cargo check --workspace

api-test:
    cd apps/api && cargo test --workspace

api-fmt:
    cd apps/api && cargo fmt --all

api-lint:
    cd apps/api && cargo clippy --workspace --all-targets -- -D warnings

# Regenera packages/shared/openapi.json a partir de las anotaciones utoipa.
openapi-export:
    cd apps/api && cargo run --quiet --bin openapi-export -- ../../packages/shared/openapi.json

# Verifica que packages/shared/openapi.json está sincronizado con el código.
# Útil en CI — falla si alguien cambió un handler sin regenerar.
openapi-check:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    cd apps/api && cargo run --quiet --bin openapi-export -- "$tmp"
    if ! diff -q "$tmp" ../../packages/shared/openapi.json > /dev/null; then
        echo "openapi.json out of sync — run 'just openapi-export' and commit." >&2
        diff -u ../../packages/shared/openapi.json "$tmp" | head -40 >&2
        exit 1
    fi
    echo "openapi.json in sync"

# --- Mobile ---
mobile:
    cd apps/mobile && flutter run

mobile-gen:
    cd apps/mobile && dart run build_runner build --delete-conflicting-outputs

mobile-test:
    cd apps/mobile && flutter test

# --- All ---
check: api-check
    cd apps/mobile && flutter analyze
