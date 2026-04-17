use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use dems_core::models::UserRole;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,
    pub role: UserRole,
    pub exp: i64,
    pub iat: i64,
    pub kind: TokenKind,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TokenKind {
    Access,
    Refresh,
}

#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error("token expired")]
    Expired,
    #[error("token invalid")]
    Invalid,
    #[error("wrong token kind: expected {expected:?}, got {got:?}")]
    WrongKind { expected: TokenKind, got: TokenKind },
}

pub fn issue(
    secret: &str,
    user_id: Uuid,
    role: UserRole,
    ttl_secs: i64,
    kind: TokenKind,
) -> Result<String, AuthError> {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id,
        role,
        iat: now.timestamp(),
        exp: (now + Duration::seconds(ttl_secs)).timestamp(),
        kind,
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|_| AuthError::Invalid)
}

pub fn verify(secret: &str, token: &str) -> Result<Claims, AuthError> {
    let mut validation = Validation::default();
    // No queremos que tokens recién expirados pasen por la ventana de gracia
    // por defecto (60s); una evaluación tomada con un token vencido no debe
    // aceptarse.
    validation.leeway = 0;

    let data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &validation,
    )
    .map_err(|e| match e.kind() {
        jsonwebtoken::errors::ErrorKind::ExpiredSignature => AuthError::Expired,
        _ => AuthError::Invalid,
    })?;
    Ok(data.claims)
}

/// Verify and assert the token is of the expected [`TokenKind`].
///
/// Used so the refresh endpoint cannot be fed an access token and vice versa.
pub fn verify_kind(secret: &str, token: &str, expected: TokenKind) -> Result<Claims, AuthError> {
    let claims = verify(secret, token)?;
    if claims.kind != expected {
        return Err(AuthError::WrongKind {
            expected,
            got: claims.kind,
        });
    }
    Ok(claims)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SECRET: &str = "test-secret";

    #[test]
    fn issue_and_verify_preserves_claims() {
        let user = Uuid::new_v4();
        let tok = issue(SECRET, user, UserRole::Admin, 60, TokenKind::Access).unwrap();

        let claims = verify(SECRET, &tok).unwrap();
        assert_eq!(claims.sub, user);
        assert_eq!(claims.role, UserRole::Admin);
        assert_eq!(claims.kind, TokenKind::Access);
        assert!(claims.exp > claims.iat);
    }

    #[test]
    fn verify_rejects_wrong_secret() {
        let tok = issue(
            SECRET,
            Uuid::new_v4(),
            UserRole::Jurado,
            60,
            TokenKind::Access,
        )
        .unwrap();

        let err = verify("other-secret", &tok).unwrap_err();
        assert!(matches!(err, AuthError::Invalid));
    }

    #[test]
    fn verify_rejects_expired_token() {
        // TTL negativo ⇒ ya expirado.
        let tok = issue(
            SECRET,
            Uuid::new_v4(),
            UserRole::Jurado,
            -10,
            TokenKind::Access,
        )
        .unwrap();

        let err = verify(SECRET, &tok).unwrap_err();
        assert!(matches!(err, AuthError::Expired));
    }

    #[test]
    fn verify_kind_rejects_refresh_where_access_expected() {
        let tok = issue(
            SECRET,
            Uuid::new_v4(),
            UserRole::Jurado,
            60,
            TokenKind::Refresh,
        )
        .unwrap();

        let err = verify_kind(SECRET, &tok, TokenKind::Access).unwrap_err();
        assert!(matches!(err, AuthError::WrongKind { .. }));
    }

    #[test]
    fn verify_kind_accepts_matching_kind() {
        let tok = issue(
            SECRET,
            Uuid::new_v4(),
            UserRole::Jurado,
            60,
            TokenKind::Refresh,
        )
        .unwrap();

        let claims = verify_kind(SECRET, &tok, TokenKind::Refresh).unwrap();
        assert_eq!(claims.kind, TokenKind::Refresh);
    }
}
