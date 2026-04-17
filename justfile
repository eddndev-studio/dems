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
