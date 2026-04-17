//! DEMS API library — exposes modules to integration tests and the binary.

pub mod auth;
pub mod config;
pub mod error;
pub mod password;
pub mod routes;
pub mod state;

pub use error::{ApiError, ApiResult};
pub use state::AppState;
