//! Vuelca el OpenAPI doc al sistema de archivos para que el cliente Flutter
//! (y cualquier otro consumidor) regenere sus tipos sin levantar el servidor.
//!
//!     cargo run --bin openapi-export -- ../../packages/shared/openapi.json
//!
//! Sin argumento, escribe en `packages/shared/openapi.json` relativo al
//! workspace root (asume `cargo run` desde `apps/api`).

use std::path::PathBuf;

use dems_api::openapi::ApiDoc;
use utoipa::OpenApi;

fn main() -> anyhow::Result<()> {
    let target = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("../../packages/shared/openapi.json"));

    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let doc = ApiDoc::openapi();
    let json = doc.to_pretty_json()?;
    std::fs::write(&target, format!("{json}\n"))?;
    println!("wrote {} ({} bytes)", target.display(), json.len() + 1);
    Ok(())
}
