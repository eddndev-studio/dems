-- =========================================================================
-- DEMS — CHECK de no-negatividad en evaluacion_scores.score
-- =========================================================================
--
-- Defensa en profundidad: la validación de rango (0..max_score) vive en la
-- aplicación (validate_scores_against_template), pero el límite inferior se
-- ancla también en la base. El límite SUPERIOR (score <= max_score del
-- criterio) sigue siendo responsabilidad de la app: depende de la rúbrica y
-- no es expresable con un CHECK estático por fila.

ALTER TABLE evaluacion_scores
    ADD CONSTRAINT evaluacion_scores_score_nonneg
    CHECK (score IS NULL OR score >= 0);
