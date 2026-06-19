-- =========================================================================
-- DEMS — schema inicial
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Tipos enumerados
CREATE TYPE user_role AS ENUM ('admin', 'jurado');
CREATE TYPE rubric_type AS ENUM ('exhibicion', 'memoria');
CREATE TYPE criterion_kind AS ENUM ('scale', 'boolean', 'text_key');

-- ---------------------------------------------------------------------------
-- Usuarios
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT NOT NULL UNIQUE,
    full_name       TEXT NOT NULL,
    role            user_role NOT NULL,
    password_hash   TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_role ON users(role) WHERE is_active;

-- ---------------------------------------------------------------------------
-- Ediciones (año del concurso)
-- ---------------------------------------------------------------------------
CREATE TABLE editions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    year        INTEGER NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    active      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Garantizamos máximo una edición activa a la vez
CREATE UNIQUE INDEX idx_editions_one_active ON editions(active) WHERE active;

-- ---------------------------------------------------------------------------
-- Categorías (7 oficiales, pero queda extensible)
-- ---------------------------------------------------------------------------
CREATE TABLE categorias (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug    TEXT NOT NULL UNIQUE,
    nombre  TEXT NOT NULL,
    orden   INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- Rúbricas configurables
-- ---------------------------------------------------------------------------
CREATE TABLE rubric_templates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    edition_id  UUID NOT NULL REFERENCES editions(id) ON DELETE CASCADE,
    nombre      TEXT NOT NULL,
    tipo        rubric_type NOT NULL,
    descripcion TEXT,
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_rubric_templates_edition ON rubric_templates(edition_id, tipo) WHERE activo;

-- Vínculo rúbrica ↔ categoría (muchos a muchos; vacía = aplica a todas)
CREATE TABLE rubric_template_categorias (
    template_id     UUID NOT NULL REFERENCES rubric_templates(id) ON DELETE CASCADE,
    categoria_id    UUID NOT NULL REFERENCES categorias(id) ON DELETE CASCADE,
    PRIMARY KEY (template_id, categoria_id)
);

CREATE TABLE rubric_sections (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL REFERENCES rubric_templates(id) ON DELETE CASCADE,
    nombre      TEXT NOT NULL,
    orden       INTEGER NOT NULL,
    peso_pct    DOUBLE PRECISION,
    UNIQUE (template_id, orden)
);

CREATE TABLE rubric_criteria (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id  UUID NOT NULL REFERENCES rubric_sections(id) ON DELETE CASCADE,
    texto       TEXT NOT NULL,
    orden       INTEGER NOT NULL,
    max_score   INTEGER NOT NULL CHECK (max_score >= 0),
    kind        criterion_kind NOT NULL DEFAULT 'scale',
    UNIQUE (section_id, orden)
);

-- ---------------------------------------------------------------------------
-- Prototipos
-- ---------------------------------------------------------------------------
CREATE TABLE prototipos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    edition_id          UUID NOT NULL REFERENCES editions(id) ON DELETE RESTRICT,
    folio               TEXT NOT NULL,
    nombre              TEXT NOT NULL,
    eje_transversal     BOOLEAN NOT NULL DEFAULT FALSE,
    descripcion         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (edition_id, folio)
);

CREATE TABLE prototipo_categorias (
    prototipo_id    UUID NOT NULL REFERENCES prototipos(id) ON DELETE CASCADE,
    categoria_id    UUID NOT NULL REFERENCES categorias(id) ON DELETE RESTRICT,
    PRIMARY KEY (prototipo_id, categoria_id)
);

-- Integrantes del equipo (opcional, para reportes)
CREATE TABLE prototipo_integrantes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prototipo_id    UUID NOT NULL REFERENCES prototipos(id) ON DELETE CASCADE,
    nombre          TEXT NOT NULL,
    rol             TEXT
);

-- ---------------------------------------------------------------------------
-- Asignación jurado ↔ prototipo
-- Un jurado puede evaluar múltiples prototipos y viceversa.
-- ---------------------------------------------------------------------------
CREATE TABLE assignments (
    jurado_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    prototipo_id    UUID NOT NULL REFERENCES prototipos(id) ON DELETE CASCADE,
    template_id     UUID NOT NULL REFERENCES rubric_templates(id) ON DELETE RESTRICT,
    assigned_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (jurado_id, prototipo_id, template_id)
);
CREATE INDEX idx_assignments_prototipo ON assignments(prototipo_id);
CREATE INDEX idx_assignments_jurado ON assignments(jurado_id);

-- ---------------------------------------------------------------------------
-- Evaluaciones y puntajes
-- ---------------------------------------------------------------------------
CREATE TABLE evaluaciones (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prototipo_id            UUID NOT NULL REFERENCES prototipos(id) ON DELETE CASCADE,
    jurado_id               UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    template_id             UUID NOT NULL REFERENCES rubric_templates(id) ON DELETE RESTRICT,
    submitted_at            TIMESTAMPTZ,
    observaciones           TEXT,
    acompanamiento_asesor   BOOLEAN,
    opinion_personal        INTEGER CHECK (opinion_personal BETWEEN 0 AND 100),
    -- ID local generado por la app para dedupe al sincronizar offline
    client_id               TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (prototipo_id, jurado_id, template_id)
);
CREATE UNIQUE INDEX idx_evaluaciones_client_id
    ON evaluaciones(jurado_id, client_id)
    WHERE client_id IS NOT NULL;

CREATE TABLE evaluacion_scores (
    evaluacion_id   UUID NOT NULL REFERENCES evaluaciones(id) ON DELETE CASCADE,
    criterion_id    UUID NOT NULL REFERENCES rubric_criteria(id) ON DELETE RESTRICT,
    score           INTEGER,
    text_answer     TEXT,
    PRIMARY KEY (evaluacion_id, criterion_id),
    CHECK (score IS NOT NULL OR text_answer IS NOT NULL)
);

-- ---------------------------------------------------------------------------
-- Trigger para updated_at
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_rubric_templates_updated_at
    BEFORE UPDATE ON rubric_templates FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_evaluaciones_updated_at
    BEFORE UPDATE ON evaluaciones FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
