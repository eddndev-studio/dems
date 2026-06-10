# syntax=docker/dockerfile:1

# ---------- builder ----------
FROM rust:1-bookworm AS builder
WORKDIR /build

# Copy the whole api workspace: Cargo.toml/Cargo.lock, crates/, migrations/.
# migrations/ MUST be present — dems-api embeds them at compile time via
# sqlx::migrate!("../../migrations") and runs them on startup.
COPY . .

# No DATABASE_URL needed at build: the codebase uses runtime sqlx::query
# exclusively (no compile-time query! macros), so the build is hermetic.
RUN cargo build --release --locked --bin dems-api --bin seed

# ---------- runtime ----------
FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/target/release/dems-api /usr/local/bin/dems-api
COPY --from=builder /build/target/release/seed     /usr/local/bin/seed

ENV API_HOST=0.0.0.0 \
    API_PORT=8080 \
    RUST_LOG=dems_api=info,tower_http=info,sqlx=warn

EXPOSE 8080
CMD ["dems-api"]
