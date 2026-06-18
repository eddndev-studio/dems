-- =========================================================================
-- DEMS — revocación de refresh tokens vía token_version
-- =========================================================================
--
-- Cada refresh token lleva el `token_version` del usuario al momento de
-- emitirlo. Al renovar, comparamos el claim contra el valor actual: si el
-- admin reseteó la contraseña o desactivó la cuenta (ambos incrementan
-- token_version), los refresh tokens viejos dejan de servir (→ 401).

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;
