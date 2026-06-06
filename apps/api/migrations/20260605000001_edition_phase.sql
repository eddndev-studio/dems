-- =========================================================================
-- DEMS — fase de edición (workflow del concurso)
-- =========================================================================
--
-- Una edición avanza manualmente por fases:
--   preparacion  → se configuran rúbricas, prototipos y asignaciones.
--   evaluacion   → los jurados califican; la estructura de rúbricas se congela.
--   cerrada      → resultados finalizados.
--
-- La estructura de rúbricas (secciones/criterios) solo puede crearse, editarse
-- o borrarse mientras la edición esté en `preparacion`. El backstop duro sigue
-- siendo el ON DELETE RESTRICT de evaluacion_scores → rubric_criteria.

CREATE TYPE edition_phase AS ENUM ('preparacion', 'evaluacion', 'cerrada');

ALTER TABLE editions
    ADD COLUMN phase edition_phase NOT NULL DEFAULT 'preparacion';
