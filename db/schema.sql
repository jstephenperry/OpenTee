-- ============================================================================
-- OpenTee — open, community-contributed golf course & scorecard database
-- Schema v1 (PostgreSQL 16)
--
-- Design goals, in priority order:
--   1. Faithfully archive course data *as published by courses* (scorecards,
--      rating stickers, course websites), including metric courses, unrated
--      courses, per-gender par/stroke-index rows, and 27-hole facilities.
--   2. Support community submission with moderation: canonical tables only
--      ever contain approved data; every approved fact traces back to a
--      submission and its evidence sources.
--   3. Serve the primary read path — view yardages and print custom
--      scorecards — from simple, index-supported queries.
--
-- Structural overview:
--   users
--   facilities ──< courses ──< holes ──< hole_pars        (par/SI per gender)
--                     │           └──< tee_hole_lengths >── tees
--                     └──< tees ──< tee_ratings           (rating per gender)
--   facilities ──< course_combinations ──< combination_tees ──< combination_ratings
--                     └──< combination_stroke_indexes
--   users ──< submissions ──< submission_sources
--   facilities/courses/combinations ──< external_ids
--
-- Modeling decisions worth knowing before you read on (full rationale in
-- docs/schema-design.md):
--   * A "tee" is the PHYSICAL set of markers; hole lengths are stored once
--     per tee. Ratings (issued per gender under the World Handicap System)
--     live in tee_ratings — 0, 1, or 2 rows per tee. Unrated tee = no row.
--   * Par and stroke index vary by GENDER, not by tee, on real scorecards;
--     they live in hole_pars keyed (course, hole, gender). 'unisex' is for
--     cards that publish a single undifferentiated par/handicap row.
--   * Lengths are stored verbatim in the unit the course publishes
--     (tees.unit): never converted on write.
--   * A "course" is one named loop of physically distinct holes (a nine at
--     a 27-hole club is a course with hole_count = 9). Published 18-hole
--     pairings — North/South combos, a nine played twice — are
--     course_combinations referencing the underlying courses/tees, so
--     shared holes are never entered twice.
--   * Composite foreign keys make cross-course corruption (a tee from
--     course A paired with a hole from course B) impossible by construction.
--   * Community data is never destroyed by accident: facility deletion is
--     RESTRICTed, lifecycle changes are status flips, duplicate facilities
--     are tombstoned with merged_into_id, and history lives in submissions.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm; -- fuzzy name matching for dedupe / "did you mean"

-- ----------------------------------------------------------------------------
-- updated_at maintenance: one trigger function shared by every table.
-- ----------------------------------------------------------------------------
CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- ============================================================================
-- COMMUNITY: users
-- ============================================================================
CREATE TABLE users (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email         text   NOT NULL
                  CONSTRAINT chk_users_email_shape CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    display_name  text   NOT NULL
                  CONSTRAINT chk_users_display_name_length CHECK (char_length(display_name) BETWEEN 1 AND 80),
    role          text   NOT NULL DEFAULT 'contributor'
                  CONSTRAINT chk_users_role CHECK (role IN ('contributor', 'moderator', 'admin')),
    status        text   NOT NULL DEFAULT 'active'
                  CONSTRAINT chk_users_status CHECK (status IN ('active', 'suspended', 'deactivated')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_users_email ON users (lower(email));

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE users IS
    'Contributors and moderators. Authentication itself is handled by the application; this table anchors attribution and moderation.';

-- ============================================================================
-- GEOGRAPHY: facilities
-- ============================================================================
CREATE TABLE facilities (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug            text   NOT NULL
                    CONSTRAINT uq_facilities_slug UNIQUE
                    CONSTRAINT chk_facilities_slug_shape CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120),
    name            text   NOT NULL
                    CONSTRAINT chk_facilities_name_length CHECK (char_length(name) BETWEEN 1 AND 200),
    address         text,
    city            text,
    state_province  text,
    country         text   NOT NULL
                    CONSTRAINT chk_facilities_country_iso CHECK (country ~ '^[A-Z]{2}$'), -- ISO 3166-1 alpha-2
    postal_code     text,
    latitude        numeric(8, 6)
                    CONSTRAINT chk_facilities_latitude CHECK (latitude BETWEEN -90 AND 90),
    longitude       numeric(9, 6)
                    CONSTRAINT chk_facilities_longitude CHECK (longitude BETWEEN -180 AND 180),
    website_url     text
                    CONSTRAINT chk_facilities_website_url CHECK (website_url ~ '^https?://'),
    status          text   NOT NULL DEFAULT 'active'
                    CONSTRAINT chk_facilities_status CHECK (status IN ('active', 'closed', 'duplicate', 'removed')),
    merged_into_id  bigint REFERENCES facilities (id) ON DELETE RESTRICT,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_facilities_latlng_together   CHECK ((latitude IS NULL) = (longitude IS NULL)),
    -- A merge tombstone is exactly a row with status 'duplicate' pointing at
    -- its survivor; lookups by old slug/id 301-redirect via merged_into_id.
    CONSTRAINT chk_facilities_merge_consistency CHECK ((status = 'duplicate') = (merged_into_id IS NOT NULL)),
    CONSTRAINT chk_facilities_no_self_merge     CHECK (merged_into_id <> id)
);

CREATE INDEX idx_facilities_location   ON facilities (country, state_province, city);
CREATE INDEX idx_facilities_name_trgm  ON facilities USING gin (name gin_trgm_ops);
CREATE INDEX idx_facilities_merged_into ON facilities (merged_into_id) WHERE merged_into_id IS NOT NULL;

CREATE TRIGGER trg_facilities_updated_at BEFORE UPDATE ON facilities
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE facilities IS
    'A golf club/resort/property. Owns one or more courses. Never hard-deleted in normal operation: close, mark duplicate (merged_into_id), or mark removed.';
COMMENT ON COLUMN facilities.country IS 'ISO 3166-1 alpha-2 code, e.g. US, AU, GB.';
COMMENT ON COLUMN facilities.merged_into_id IS 'Set when this row was found to duplicate another facility; children are repointed to the survivor and this row becomes a redirect tombstone.';

-- ============================================================================
-- COURSES: one named loop of physically distinct holes
-- ============================================================================
CREATE TABLE courses (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facility_id  bigint NOT NULL REFERENCES facilities (id) ON DELETE RESTRICT,
    slug         text   NOT NULL
                 CONSTRAINT chk_courses_slug_shape CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120),
    name         text   NOT NULL
                 CONSTRAINT chk_courses_name_length CHECK (char_length(name) BETWEEN 1 AND 200),
    hole_count   smallint NOT NULL DEFAULT 18
                 CONSTRAINT chk_courses_hole_count CHECK (hole_count BETWEEN 1 AND 27),
    status       text   NOT NULL DEFAULT 'active'
                 CONSTRAINT chk_courses_status CHECK (status IN ('active', 'closed', 'removed')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_courses_facility_slug UNIQUE (facility_id, slug),
    -- Composite-FK target so children can prove same-facility membership.
    CONSTRAINT uq_courses_id_facility   UNIQUE (id, facility_id)
);

CREATE INDEX idx_courses_facility ON courses (facility_id);

CREATE TRIGGER trg_courses_updated_at BEFORE UPDATE ON courses
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE courses IS
    'One named loop of physically distinct holes. A standard course has hole_count = 18; each nine at a 27-hole club is its own course with hole_count = 9. Published 18-hole pairings of nines live in course_combinations.';

-- ============================================================================
-- HOLES: natural key (course_id, hole_number); carries per-hole facts
-- ============================================================================
CREATE TABLE holes (
    course_id    bigint   NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    hole_number  smallint NOT NULL
                 CONSTRAINT chk_holes_number CHECK (hole_number BETWEEN 1 AND 27),
    name         text
                 CONSTRAINT chk_holes_name_length CHECK (char_length(name) <= 100),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_holes PRIMARY KEY (course_id, hole_number)
);

CREATE TRIGGER trg_holes_updated_at BEFORE UPDATE ON holes
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE holes IS
    'Structural identity of each hole plus per-hole facts that do not vary by tee or gender (e.g. the hole name printed on links cards: "Burn", "Road", "Tea Olive").';

-- ----------------------------------------------------------------------------
-- hole_pars: par and stroke index per (hole, gender) — matching the printed
-- card, which shows one Men's and one Ladies' par/handicap row shared across
-- all tees. 'unisex' is for cards publishing a single undifferentiated row;
-- a course should use EITHER gendered rows OR unisex rows per hole (enforced
-- at the application/submission layer, not in DDL).
-- Stroke index is nullable: many par-3/executive cards omit it. Uniqueness of
-- stroke indexes within a card is deliberately NOT enforced — some published
-- cards genuinely violate the 1–18 permutation, and we archive "as published";
-- the submission UI should flag duplicates for review instead.
-- ----------------------------------------------------------------------------
CREATE TABLE hole_pars (
    course_id     bigint   NOT NULL,
    hole_number   smallint NOT NULL,
    gender        text     NOT NULL
                  CONSTRAINT chk_hole_pars_gender CHECK (gender IN ('men', 'women', 'unisex')),
    par           smallint NOT NULL
                  CONSTRAINT chk_hole_pars_par CHECK (par BETWEEN 3 AND 7),
    stroke_index  smallint
                  CONSTRAINT chk_hole_pars_stroke_index CHECK (stroke_index BETWEEN 1 AND 18),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_hole_pars PRIMARY KEY (course_id, hole_number, gender),
    CONSTRAINT fk_hole_pars_hole FOREIGN KEY (course_id, hole_number)
        REFERENCES holes (course_id, hole_number) ON DELETE CASCADE
);

CREATE TRIGGER trg_hole_pars_updated_at BEFORE UPDATE ON hole_pars
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE hole_pars IS
    'Par and stroke index per hole per gender, as printed on the card. Par 6 and 7 holes exist (e.g. 673-yard Lake Chabot #18), hence the 3–7 range.';
COMMENT ON COLUMN hole_pars.stroke_index IS
    'The per-hole handicap allocation ("Handicap" on US cards, "Stroke Index" in R&A countries). NOT a player''s Handicap Index.';

-- ============================================================================
-- TEES: the physical tee set. Lengths hang off this exactly once; per-gender
-- ratings live in tee_ratings.
-- ============================================================================
CREATE TABLE tees (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id               bigint NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    name                    text   NOT NULL
                            CONSTRAINT chk_tees_name_length CHECK (char_length(name) BETWEEN 1 AND 60),
    color_name              text,        -- marker color when distinct from the name ("Palmer" tees may be black)
    color_hex               char(7)
                            CONSTRAINT chk_tees_color_hex CHECK (color_hex ~ '^#[0-9a-fA-F]{6}$'),
    secondary_color_hex     char(7)      -- two-tone markers, esp. combination tees ("Blue/White")
                            CONSTRAINT chk_tees_secondary_color_hex CHECK (secondary_color_hex ~ '^#[0-9a-fA-F]{6}$'),
    unit                    text   NOT NULL
                            CONSTRAINT chk_tees_unit CHECK (unit IN ('yards', 'meters')),
    display_order           smallint NOT NULL
                            CONSTRAINT chk_tees_display_order CHECK (display_order >= 1),
    is_combination          boolean NOT NULL DEFAULT false,
    published_total_length  integer
                            CONSTRAINT chk_tees_published_total CHECK (published_total_length BETWEEN 100 AND 20000),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_tees_course_name UNIQUE (course_id, name),
    -- DEFERRABLE so a reorder can swap positions inside one transaction.
    CONSTRAINT uq_tees_course_display_order UNIQUE (course_id, display_order) DEFERRABLE INITIALLY DEFERRED,
    -- Composite-FK targets so children can prove same-course membership —
    -- and, for combination_tees, matching units across legs.
    CONSTRAINT uq_tees_id_course UNIQUE (id, course_id),
    CONSTRAINT uq_tees_id_course_unit UNIQUE (id, course_id, unit)
);

CREATE TRIGGER trg_tees_updated_at BEFORE UPDATE ON tees
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE tees IS
    'A physical set of tee markers on one course. Gender-neutral by design: the same White tees rated 69.4/125 for men and 74.6/133 for women are ONE row here with TWO rows in tee_ratings.';
COMMENT ON COLUMN tees.unit IS
    'Unit the course publishes lengths in. Metric-country cards (AU, KR, most of Europe/South America) are stored verbatim in meters; convert only at display time.';
COMMENT ON COLUMN tees.display_order IS
    '1 = first row on the printed card (usually the longest tee). Publisher order is itself "as published" data.';
COMMENT ON COLUMN tees.is_combination IS
    'True for within-course combination tees ("Blue/White") that alternate parent tees hole by hole; per-hole provenance lives in tee_hole_lengths.source_tee_id.';
COMMENT ON COLUMN tees.published_total_length IS
    'The TOTAL printed on the card, verbatim. Compare with the computed sum (v_tee_summaries) — a mismatch is either a data-entry error or a genuine misprint on the published card, and both are worth surfacing.';

-- ----------------------------------------------------------------------------
-- tee_ratings: World Handicap System ratings, issued per tee PER GENDER.
-- 0 rows  = unrated tee (par-3 courses, executive courses, brand-new tees) —
--           absence of a rating is absence of a row, never a fake value.
-- 1–2 rows = rated for one or both genders.
-- For a 9-hole course these are its 9-hole ratings; the 18-hole
-- "played twice" rating belongs to the course_combination that represents
-- the 18-hole configuration.
-- ----------------------------------------------------------------------------
CREATE TABLE tee_ratings (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tee_id             bigint NOT NULL REFERENCES tees (id) ON DELETE CASCADE,
    gender             text   NOT NULL
                       CONSTRAINT chk_tee_ratings_gender CHECK (gender IN ('men', 'women')),
    course_rating      numeric(4, 1) NOT NULL
                       CONSTRAINT chk_tee_ratings_course_rating CHECK (course_rating BETWEEN 15 AND 90),
    slope_rating       smallint NOT NULL
                       CONSTRAINT chk_tee_ratings_slope CHECK (slope_rating BETWEEN 55 AND 155),
    bogey_rating       numeric(4, 1)
                       CONSTRAINT chk_tee_ratings_bogey CHECK (bogey_rating BETWEEN 15 AND 120),
    front_nine_rating  numeric(3, 1)
                       CONSTRAINT chk_tee_ratings_front_rating CHECK (front_nine_rating BETWEEN 10 AND 50),
    front_nine_slope   smallint
                       CONSTRAINT chk_tee_ratings_front_slope CHECK (front_nine_slope BETWEEN 55 AND 155),
    back_nine_rating   numeric(3, 1)
                       CONSTRAINT chk_tee_ratings_back_rating CHECK (back_nine_rating BETWEEN 10 AND 50),
    back_nine_slope    smallint
                       CONSTRAINT chk_tee_ratings_back_slope CHECK (back_nine_slope BETWEEN 55 AND 155),
    effective_date     date,    -- rating stickers and cards print their issue date; ratings expire (≤10 years)
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_tee_ratings_tee_gender UNIQUE (tee_id, gender)
);

CREATE TRIGGER trg_tee_ratings_updated_at BEFORE UPDATE ON tee_ratings
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE tee_ratings IS
    'USGA/WHS Course Rating & Slope per tee per gender. Slope is defined only on 55–155; Course Rating is published to one decimal. Rating bounds are sanity rails for community input, not exact domain law.';

-- ----------------------------------------------------------------------------
-- tee_hole_lengths: the published length of each hole from each tee.
-- Composite FKs guarantee tee and hole belong to the SAME course; a scorecard
-- can never silently mix Pebble Beach tees with Spyglass Hill holes.
-- ----------------------------------------------------------------------------
CREATE TABLE tee_hole_lengths (
    tee_id         bigint   NOT NULL,
    course_id      bigint   NOT NULL,
    hole_number    smallint NOT NULL,
    length         integer  NOT NULL
                   CONSTRAINT chk_tee_hole_lengths_length CHECK (length BETWEEN 20 AND 1500),
    source_tee_id  bigint,  -- for combination tees: which parent tee this hole plays from
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_tee_hole_lengths PRIMARY KEY (tee_id, hole_number),
    CONSTRAINT fk_tee_hole_lengths_tee FOREIGN KEY (tee_id, course_id)
        REFERENCES tees (id, course_id) ON DELETE CASCADE,
    CONSTRAINT fk_tee_hole_lengths_hole FOREIGN KEY (course_id, hole_number)
        REFERENCES holes (course_id, hole_number) ON DELETE CASCADE,
    -- Deferred (not RESTRICT): course deletion must cascade through both the
    -- holes and tees legs regardless of internal RI-trigger creation order,
    -- and RESTRICT checks immediately even when deferrable. A bare delete of
    -- a parent tee that a combo tee sources from is still rejected — at
    -- COMMIT rather than statement time.
    CONSTRAINT fk_tee_hole_lengths_source_tee FOREIGN KEY (source_tee_id, course_id)
        REFERENCES tees (id, course_id) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT chk_tee_hole_lengths_source_not_self CHECK (source_tee_id IS DISTINCT FROM tee_id)
);

CREATE INDEX idx_tee_hole_lengths_hole ON tee_hole_lengths (course_id, hole_number);
CREATE INDEX idx_tee_hole_lengths_source_tee ON tee_hole_lengths (source_tee_id) WHERE source_tee_id IS NOT NULL;

CREATE TRIGGER trg_tee_hole_lengths_updated_at BEFORE UPDATE ON tee_hole_lengths
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE tee_hole_lengths IS
    'Published length of one hole from one tee, verbatim in tees.unit. Stored once per physical tee — never per gender.';
COMMENT ON COLUMN tee_hole_lengths.source_tee_id IS
    'For combination tees ("Blue/White"): the parent tee whose markers this hole uses. Lets views flag drift when a parent tee''s length is corrected but the combo copy is not.';

-- ============================================================================
-- COURSE COMBINATIONS: published 18-hole configurations built from existing
-- courses — the three pairings at a 27-hole club, or a 9-hole course played
-- twice (first_course_id = second_course_id is legal and expected).
-- Hole data is NOT duplicated here; positions 1..N map through the legs:
--   position <= first.hole_count        → first course, hole = position
--   position >  first.hole_count        → second course, hole = position - first.hole_count
-- ============================================================================
CREATE TABLE course_combinations (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facility_id       bigint NOT NULL REFERENCES facilities (id) ON DELETE RESTRICT,
    slug              text   NOT NULL
                      CONSTRAINT chk_combinations_slug_shape CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120),
    name              text   NOT NULL
                      CONSTRAINT chk_combinations_name_length CHECK (char_length(name) BETWEEN 1 AND 200),
    first_course_id   bigint NOT NULL,
    second_course_id  bigint NOT NULL,
    status            text   NOT NULL DEFAULT 'active'
                      CONSTRAINT chk_combinations_status CHECK (status IN ('active', 'closed', 'removed')),
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_combinations_facility_slug UNIQUE (facility_id, slug),
    -- Composite-FK target so combination_tees can prove leg membership.
    CONSTRAINT uq_combinations_id_courses UNIQUE (id, first_course_id, second_course_id),
    -- Legs must belong to the same facility as the combination. DEFERRABLE
    -- so a facility merge can SET CONSTRAINTS ... DEFERRED and repoint
    -- courses and combinations to the survivor with plain UPDATEs; the
    -- delete-RESTRICT action itself always checks immediately.
    CONSTRAINT fk_combinations_first_course FOREIGN KEY (first_course_id, facility_id)
        REFERENCES courses (id, facility_id) ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE,
    CONSTRAINT fk_combinations_second_course FOREIGN KEY (second_course_id, facility_id)
        REFERENCES courses (id, facility_id) ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX idx_combinations_facility     ON course_combinations (facility_id);
CREATE INDEX idx_combinations_first_course  ON course_combinations (first_course_id);
CREATE INDEX idx_combinations_second_course ON course_combinations (second_course_id);

CREATE TRIGGER trg_combinations_updated_at BEFORE UPDATE ON course_combinations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE course_combinations IS
    'A published playing configuration composed of two course legs (usually two nines). Ratings and 18-hole stroke indexes attach here; hole lengths always come from the underlying courses, so shared nines are entered exactly once.';

-- ----------------------------------------------------------------------------
-- combination_tees: the tee pairing a combination is published/rated at —
-- e.g. "Blue" on North/South = North's Blue + South's Blue, or the classic
-- 9-played-twice card "White out, Yellow in" (same course, different tees).
-- The denormalized leg-course columns exist purely to let composite FKs prove
-- each tee belongs to the correct leg.
-- ----------------------------------------------------------------------------
CREATE TABLE combination_tees (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    combination_id          bigint NOT NULL,
    first_course_id         bigint NOT NULL,
    second_course_id        bigint NOT NULL,
    name                    text   NOT NULL
                            CONSTRAINT chk_combination_tees_name_length CHECK (char_length(name) BETWEEN 1 AND 60),
    display_order           smallint NOT NULL
                            CONSTRAINT chk_combination_tees_display_order CHECK (display_order >= 1),
    first_tee_id            bigint NOT NULL,
    second_tee_id           bigint NOT NULL,
    unit                    text   NOT NULL
                            CONSTRAINT chk_combination_tees_unit CHECK (unit IN ('yards', 'meters')),
    published_total_length  integer
                            CONSTRAINT chk_combination_tees_published_total CHECK (published_total_length BETWEEN 100 AND 20000),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_combination_tees_name UNIQUE (combination_id, name),
    CONSTRAINT uq_combination_tees_display_order UNIQUE (combination_id, display_order) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_combination_tees_combination FOREIGN KEY (combination_id, first_course_id, second_course_id)
        REFERENCES course_combinations (id, first_course_id, second_course_id) ON DELETE CASCADE,
    -- Both leg FKs share the unit column, so a combination pairing a yards
    -- tee with a meters tee is unrepresentable and published_total_length
    -- always has an unambiguous unit.
    CONSTRAINT fk_combination_tees_first_tee FOREIGN KEY (first_tee_id, first_course_id, unit)
        REFERENCES tees (id, course_id, unit) ON DELETE RESTRICT,
    CONSTRAINT fk_combination_tees_second_tee FOREIGN KEY (second_tee_id, second_course_id, unit)
        REFERENCES tees (id, course_id, unit) ON DELETE RESTRICT
);

CREATE INDEX idx_combination_tees_first_tee  ON combination_tees (first_tee_id);
CREATE INDEX idx_combination_tees_second_tee ON combination_tees (second_tee_id);

CREATE TRIGGER trg_combination_tees_updated_at BEFORE UPDATE ON combination_tees
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ----------------------------------------------------------------------------
-- combination_ratings: same shape as tee_ratings, attached to a combination
-- tee pairing. This is where an 18-hole rating of a 9-hole course played
-- twice lives, and where each of the three pairings at a 27-hole club gets
-- its own rating. Front/back-nine columns hold the combination's published
-- split (its legs), verbatim.
-- ----------------------------------------------------------------------------
CREATE TABLE combination_ratings (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    combination_tee_id bigint NOT NULL REFERENCES combination_tees (id) ON DELETE CASCADE,
    gender             text   NOT NULL
                       CONSTRAINT chk_combination_ratings_gender CHECK (gender IN ('men', 'women')),
    course_rating      numeric(4, 1) NOT NULL
                       CONSTRAINT chk_combination_ratings_course_rating CHECK (course_rating BETWEEN 15 AND 90),
    slope_rating       smallint NOT NULL
                       CONSTRAINT chk_combination_ratings_slope CHECK (slope_rating BETWEEN 55 AND 155),
    bogey_rating       numeric(4, 1)
                       CONSTRAINT chk_combination_ratings_bogey CHECK (bogey_rating BETWEEN 15 AND 120),
    front_nine_rating  numeric(3, 1)
                       CONSTRAINT chk_combination_ratings_front_rating CHECK (front_nine_rating BETWEEN 10 AND 50),
    front_nine_slope   smallint
                       CONSTRAINT chk_combination_ratings_front_slope CHECK (front_nine_slope BETWEEN 55 AND 155),
    back_nine_rating   numeric(3, 1)
                       CONSTRAINT chk_combination_ratings_back_rating CHECK (back_nine_rating BETWEEN 10 AND 50),
    back_nine_slope    smallint
                       CONSTRAINT chk_combination_ratings_back_slope CHECK (back_nine_slope BETWEEN 55 AND 155),
    effective_date     date,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_combination_ratings_tee_gender UNIQUE (combination_tee_id, gender)
);

CREATE TRIGGER trg_combination_ratings_updated_at BEFORE UPDATE ON combination_ratings
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ----------------------------------------------------------------------------
-- combination_stroke_indexes: the 18-hole stroke-index allocation printed on
-- a combination card. Needed because a 9-hole course played twice publishes
-- SI 1–18 across two loops of the same physical holes (hole 3 may be SI 5 as
-- hole 3 and SI 6 as hole 12), and North/South cards renumber SI across the
-- pairing. Par is NOT stored here — it always comes from the underlying
-- course's hole_pars.
-- ----------------------------------------------------------------------------
CREATE TABLE combination_stroke_indexes (
    combination_id  bigint   NOT NULL REFERENCES course_combinations (id) ON DELETE CASCADE,
    position        smallint NOT NULL
                    CONSTRAINT chk_combination_si_position CHECK (position BETWEEN 1 AND 18),
    gender          text     NOT NULL
                    CONSTRAINT chk_combination_si_gender CHECK (gender IN ('men', 'women', 'unisex')),
    stroke_index    smallint NOT NULL
                    CONSTRAINT chk_combination_si_value CHECK (stroke_index BETWEEN 1 AND 18),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_combination_stroke_indexes PRIMARY KEY (combination_id, position, gender)
);

CREATE TRIGGER trg_combination_si_updated_at BEFORE UPDATE ON combination_stroke_indexes
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- IDENTITY & DEDUPE: external anchors for cross-referencing
-- ============================================================================
CREATE TABLE external_ids (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facility_id     bigint REFERENCES facilities (id) ON DELETE CASCADE,
    course_id       bigint REFERENCES courses (id) ON DELETE CASCADE,
    combination_id  bigint REFERENCES course_combinations (id) ON DELETE CASCADE,
    namespace       text   NOT NULL
                    CONSTRAINT chk_external_ids_namespace CHECK (char_length(namespace) BETWEEN 1 AND 50),
    external_id     text   NOT NULL
                    CONSTRAINT chk_external_ids_value CHECK (char_length(external_id) BETWEEN 1 AND 200),
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_external_ids UNIQUE (namespace, external_id),
    CONSTRAINT chk_external_ids_one_target CHECK (num_nonnulls(facility_id, course_id, combination_id) = 1)
);

CREATE INDEX idx_external_ids_facility    ON external_ids (facility_id)    WHERE facility_id IS NOT NULL;
CREATE INDEX idx_external_ids_course      ON external_ids (course_id)      WHERE course_id IS NOT NULL;
CREATE INDEX idx_external_ids_combination ON external_ids (combination_id) WHERE combination_id IS NOT NULL;

COMMENT ON TABLE external_ids IS
    'Anchors to external systems (namespace examples: usga_crdb, ghin, osm, golflink). Primary tool for duplicate detection and cross-referencing. Combinations are anchorable because official rating databases publish each 18-hole pairing as its own rated entity.';

-- ============================================================================
-- SUBMISSIONS: the community write path. A submission is an ATOMIC envelope —
-- a whole facility record or a whole course scorecard — proposed as JSONB,
-- reviewed by a moderator, and applied to the canonical tables in one
-- transaction on approval. Canonical tables therefore only ever contain
-- approved data; history and revert = the chain of approved submissions.
-- ============================================================================
CREATE TABLE submissions (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind            text   NOT NULL
                    CONSTRAINT chk_submissions_kind CHECK (kind IN ('facility', 'course', 'course_combination')),
    -- Target refs are NULL for brand-new entities until the approval
    -- transaction creates the row and backfills the reference. RESTRICT:
    -- an entity that has ever been targeted by a submission cannot be
    -- hard-deleted in one statement — history ("the chain of approved
    -- submissions") must never be silently severed. Deliberate teardown
    -- requires explicitly deleting the submissions first.
    facility_id     bigint REFERENCES facilities (id) ON DELETE RESTRICT,
    course_id       bigint REFERENCES courses (id) ON DELETE RESTRICT,
    combination_id  bigint REFERENCES course_combinations (id) ON DELETE RESTRICT,
    payload         jsonb  NOT NULL,
    status          text   NOT NULL DEFAULT 'pending'
                    CONSTRAINT chk_submissions_status CHECK (status IN ('pending', 'approved', 'rejected', 'superseded')),
    submitted_by    bigint NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    reviewed_by     bigint REFERENCES users (id) ON DELETE RESTRICT,
    review_note     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    reviewed_at     timestamptz,
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_submissions_review_fields CHECK (
        status NOT IN ('approved', 'rejected')
        OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    ),
    -- Target columns must match the submission kind (facility_id may
    -- accompany course/combination submissions as context). That an
    -- APPROVED submission has its target backfilled is the approval
    -- writer's contract — DDL cannot see it without forbidding legitimate
    -- new-entity payloads.
    CONSTRAINT chk_submissions_kind_targets CHECK (
        (kind = 'facility'           AND course_id IS NULL AND combination_id IS NULL)
        OR (kind = 'course'             AND combination_id IS NULL)
        OR (kind = 'course_combination' AND course_id IS NULL)
    )
);

CREATE INDEX idx_submissions_pending      ON submissions (created_at) WHERE status = 'pending';
CREATE INDEX idx_submissions_facility     ON submissions (facility_id) WHERE facility_id IS NOT NULL;
CREATE INDEX idx_submissions_course       ON submissions (course_id) WHERE course_id IS NOT NULL;
CREATE INDEX idx_submissions_combination  ON submissions (combination_id) WHERE combination_id IS NOT NULL;
CREATE INDEX idx_submissions_submitted_by ON submissions (submitted_by);
CREATE INDEX idx_submissions_reviewed_by  ON submissions (reviewed_by) WHERE reviewed_by IS NOT NULL;

CREATE TRIGGER trg_submissions_updated_at BEFORE UPDATE ON submissions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE submissions IS
    'Atomic proposed change (whole scorecard / whole facility record) as JSONB. Attribution: "who added this course" = its approved submissions. Revert = re-apply an earlier approved payload. Deliberately deferred: field-level diffs, temporal tables, reputation scoring.';
COMMENT ON COLUMN submissions.payload IS
    'Full proposed state, application-versioned JSON (include a schema_version key). Kept verbatim after approval as the audit/history record.';

-- ----------------------------------------------------------------------------
-- submission_sources: the evidence behind a submission. At least one source
-- per submission is an application-level rule ("as published" requires a
-- publication). effective_date is the date printed on the card/sticker or
-- the date the source was observed — rating stickers carry issue dates and
-- ratings expire, so the artifacts users transcribe are dated.
-- ----------------------------------------------------------------------------
CREATE TABLE submission_sources (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    submission_id   bigint NOT NULL REFERENCES submissions (id) ON DELETE CASCADE,
    source_type     text   NOT NULL
                    CONSTRAINT chk_submission_sources_type CHECK (source_type IN
                        ('scorecard_image', 'rating_sticker_image', 'course_website', 'official_rating_db', 'in_person', 'other')),
    url             text
                    CONSTRAINT chk_submission_sources_url CHECK (url ~ '^https?://'),
    file_key        text,   -- object-storage key for an uploaded photo/scan
    note            text,
    effective_date  date,
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_submission_sources_has_evidence CHECK (num_nonnulls(url, file_key, note) >= 1)
);

CREATE INDEX idx_submission_sources_submission ON submission_sources (submission_id);

-- ============================================================================
-- READ-PATH VIEWS
-- ============================================================================

-- One row per (tee, hole): length plus the per-gender par/SI columns pivoted
-- the way a printed card lays them out. The print/app layer pivots tees into
-- side-by-side columns and picks gendered vs unisex par rows (they should not
-- coexist for one course).
CREATE VIEW v_scorecards AS
SELECT
    c.id            AS course_id,
    c.facility_id,
    c.slug          AS course_slug,
    c.name          AS course_name,
    c.hole_count,
    t.id            AS tee_id,
    t.name          AS tee_name,
    t.color_hex,
    t.secondary_color_hex,
    t.unit,
    t.display_order,
    t.is_combination,
    h.hole_number,
    h.name          AS hole_name,
    thl.length,
    pm.par          AS par_men,
    pm.stroke_index AS stroke_index_men,
    pw.par          AS par_women,
    pw.stroke_index AS stroke_index_women,
    pu.par          AS par_unisex,
    pu.stroke_index AS stroke_index_unisex
FROM courses c
JOIN holes h              ON h.course_id = c.id
JOIN tees t               ON t.course_id = c.id
JOIN tee_hole_lengths thl ON thl.tee_id = t.id AND thl.hole_number = h.hole_number
LEFT JOIN hole_pars pm    ON pm.course_id = c.id AND pm.hole_number = h.hole_number AND pm.gender = 'men'
LEFT JOIN hole_pars pw    ON pw.course_id = c.id AND pw.hole_number = h.hole_number AND pw.gender = 'women'
LEFT JOIN hole_pars pu    ON pu.course_id = c.id AND pu.hole_number = h.hole_number AND pu.gender = 'unisex';

COMMENT ON VIEW v_scorecards IS
    'Long-format scorecard: one row per (tee, hole) with per-gender par/SI pivoted into columns. Filter by course and any subset of tee ids to build a custom printable card.';

-- Per-tee computed totals, completeness, and published-vs-computed
-- discrepancy. OUT/IN use the front-nine = holes 1–9 convention and are NULL
-- for courses where that split does not apply (hole_count <> 18).
CREATE VIEW v_tee_summaries AS
SELECT
    t.id           AS tee_id,
    t.course_id,
    t.name         AS tee_name,
    t.unit,
    t.display_order,
    c.hole_count,
    count(thl.hole_number)::int                                        AS holes_entered,
    -- Exact-set completeness: exactly holes 1..hole_count and nothing else.
    -- A tee carrying an out-of-range hole row (a soft-rule breach upstream)
    -- must surface as incomplete, not print as a "complete" card.
    (count(thl.hole_number) FILTER (WHERE thl.hole_number <= c.hole_count) = c.hole_count
     AND count(thl.hole_number) = c.hole_count)                        AS is_complete,
    sum(thl.length)::int                                               AS computed_total_length,
    CASE WHEN c.hole_count = 18
         THEN sum(thl.length) FILTER (WHERE thl.hole_number <= 9)::int
    END                                                                AS out_length,
    CASE WHEN c.hole_count = 18
         THEN sum(thl.length) FILTER (WHERE thl.hole_number > 9)::int
    END                                                                AS in_length,
    t.published_total_length,
    (t.published_total_length IS NOT NULL
     AND count(thl.hole_number) FILTER (WHERE thl.hole_number <= c.hole_count) = c.hole_count
     AND count(thl.hole_number) = c.hole_count
     AND t.published_total_length <> sum(thl.length))                  AS has_total_discrepancy
FROM tees t
JOIN courses c ON c.id = t.course_id
LEFT JOIN tee_hole_lengths thl ON thl.tee_id = t.id
GROUP BY t.id, t.course_id, t.name, t.unit, t.display_order, c.hole_count, t.published_total_length;

COMMENT ON VIEW v_tee_summaries IS
    'Computed OUT/IN/TOTAL per tee plus data-quality signals: is_complete gates public rendering of partial cards; has_total_discrepancy surfaces published-vs-computed mismatches (either a transcription error or a genuine misprint on the card).';

-- The same totals policy for combination cards: computed totals per leg
-- (OUT = first leg, IN = second leg, as printed), exact-set completeness of
-- both legs, and published-vs-computed discrepancy on the combined card.
CREATE VIEW v_combination_tee_summaries AS
SELECT
    ct.id            AS combination_tee_id,
    ct.combination_id,
    cc.facility_id,
    cc.slug          AS combination_slug,
    ct.name          AS tee_name,
    ct.unit,
    ct.display_order,
    (c1.hole_count + c2.hole_count)::smallint          AS hole_count,
    (l1.holes_entered + l2.holes_entered)::int          AS holes_entered,
    (l1.is_leg_complete AND l2.is_leg_complete)         AS is_complete,
    (l1.leg_length + l2.leg_length)::int                AS computed_total_length,
    l1.leg_length::int                                  AS out_length,
    l2.leg_length::int                                  AS in_length,
    ct.published_total_length,
    (ct.published_total_length IS NOT NULL
     AND l1.is_leg_complete AND l2.is_leg_complete
     AND ct.published_total_length <> l1.leg_length + l2.leg_length) AS has_total_discrepancy
FROM combination_tees ct
JOIN course_combinations cc ON cc.id = ct.combination_id
JOIN courses c1 ON c1.id = cc.first_course_id
JOIN courses c2 ON c2.id = cc.second_course_id
CROSS JOIN LATERAL (
    SELECT count(*)::int AS holes_entered,
           sum(thl.length) AS leg_length,
           (count(*) FILTER (WHERE thl.hole_number <= c1.hole_count) = c1.hole_count
            AND count(*) = c1.hole_count) AS is_leg_complete
    FROM tee_hole_lengths thl
    WHERE thl.tee_id = ct.first_tee_id
) l1
CROSS JOIN LATERAL (
    SELECT count(*)::int AS holes_entered,
           sum(thl.length) AS leg_length,
           (count(*) FILTER (WHERE thl.hole_number <= c2.hole_count) = c2.hole_count
            AND count(*) = c2.hole_count) AS is_leg_complete
    FROM tee_hole_lengths thl
    WHERE thl.tee_id = ct.second_tee_id
) l2;

COMMENT ON VIEW v_combination_tee_summaries IS
    'v_tee_summaries counterpart for combination cards: per-leg OUT/IN, combined total, exact-set completeness of both legs, and published-vs-computed misprint detection. Lengths are unambiguous: the leg FKs force both tees to share combination_tees.unit.';

COMMIT;
