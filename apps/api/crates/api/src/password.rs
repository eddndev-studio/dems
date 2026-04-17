//! Password hashing and verification (argon2id with a per-hash salt).

use anyhow::Result;
use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;

pub fn hash(password: &str) -> Result<String> {
    let salt = SaltString::generate(&mut OsRng);
    let phc = Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!("argon2 hash: {e}"))?
        .to_string();
    Ok(phc)
}

pub fn verify(password: &str, phc: &str) -> Result<bool> {
    let parsed = PasswordHash::new(phc).map_err(|e| anyhow::anyhow!("argon2 parse: {e}"))?;
    Ok(Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_and_verify_roundtrip() {
        let h = hash("correct-horse-battery-staple").unwrap();
        assert!(verify("correct-horse-battery-staple", &h).unwrap());
    }

    #[test]
    fn verify_rejects_wrong_password() {
        let h = hash("secret123").unwrap();
        assert!(!verify("secret1234", &h).unwrap());
        assert!(!verify("", &h).unwrap());
    }

    #[test]
    fn hash_is_not_plaintext() {
        let h = hash("plaintext").unwrap();
        assert!(!h.contains("plaintext"));
        assert!(h.starts_with("$argon2"));
    }

    #[test]
    fn hashes_are_salted_and_differ_across_calls() {
        let a = hash("same-password").unwrap();
        let b = hash("same-password").unwrap();
        assert_ne!(a, b, "each hash must use a fresh salt");
    }
}
