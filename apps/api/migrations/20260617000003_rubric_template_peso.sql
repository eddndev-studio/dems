-- =========================================================================
-- DEMS — peso por rúbrica (ponderación del puntaje final combinado)
-- =========================================================================
--
-- `peso` es el porcentaje (0..100) con que esta rúbrica contribuye al
-- puntaje final combinado del prototipo. Regla actual del concurso:
-- exhibición = 60, memoria = 50 (la suma no tiene por qué dar 100; cada
-- rúbrica aporta su fracción independiente sobre el máximo de su tipo).

ALTER TABLE rubric_templates
    ADD COLUMN IF NOT EXISTS peso INTEGER NOT NULL DEFAULT 100
    CHECK (peso >= 0 AND peso <= 100);

-- Backfill por tipo según la regla del concurso.
UPDATE rubric_templates SET peso = 60 WHERE tipo = 'exhibicion';
UPDATE rubric_templates SET peso = 50 WHERE tipo = 'memoria';
