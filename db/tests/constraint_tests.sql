-- ============================================================================
-- OpenTee constraint tests
--
-- Verifies that the schema's integrity rails reject bad community input and
-- that the deliberately flexible paths stay open. Run against a database
-- loaded with db/schema.sql + db/seed/example_seed.sql:
--
--   psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/tests/constraint_tests.sql
--
-- The whole file runs in one transaction and rolls back: it never mutates
-- the database it runs against. Output: one "ok: ..." NOTICE per test;
-- any failure aborts the script with TEST FAILED.
-- ============================================================================

BEGIN;

CREATE FUNCTION pg_temp.assert_fails(test_name text, stmt text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE stmt;
        RAISE EXCEPTION 'TEST FAILED: % — statement unexpectedly succeeded', test_name;
    EXCEPTION
        WHEN raise_exception THEN
            RAISE;                       -- re-throw our own TEST FAILED
        WHEN others THEN
            RAISE NOTICE 'ok: % (rejected: %)', test_name, SQLERRM;
    END;
END;
$$;

CREATE FUNCTION pg_temp.assert_ok(test_name text, stmt text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'ok: %', test_name;
END;
$$;

-- ---------------------------------------------------------------- value rails
SELECT pg_temp.assert_fails('gender must be canonical lowercase',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par) VALUES (2, 1, 'Male', 3) $q$);

SELECT pg_temp.assert_fails('par above 7 rejected',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par) VALUES (2, 1, 'men', 8) $q$);

SELECT pg_temp.assert_fails('par below 3 rejected',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par) VALUES (2, 1, 'men', 2) $q$);

SELECT pg_temp.assert_fails('stroke index above 18 rejected',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index) VALUES (2, 1, 'men', 3, 19) $q$);

SELECT pg_temp.assert_fails('slope outside 55-155 rejected',
    $q$ INSERT INTO tee_ratings (tee_id, gender, course_rating, slope_rating) VALUES (6, 'men', 62.0, 156) $q$);

SELECT pg_temp.assert_fails('course rating outside sanity bounds rejected',
    $q$ INSERT INTO tee_ratings (tee_id, gender, course_rating, slope_rating) VALUES (6, 'men', 999.9, 120) $q$);

SELECT pg_temp.assert_fails('hole length outside 20-1500 rejected',
    $q$ INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length) VALUES (6, 2, 1, 5000) $q$);

SELECT pg_temp.assert_fails('hole_number 0 rejected',
    $q$ INSERT INTO holes (course_id, hole_number) VALUES (2, 0) $q$);

SELECT pg_temp.assert_fails('tee unit must be yards or meters',
    $q$ INSERT INTO tees (course_id, name, unit, display_order) VALUES (2, 'Gold', 'feet', 9) $q$);

SELECT pg_temp.assert_fails('country must be ISO 3166-1 alpha-2',
    $q$ INSERT INTO facilities (slug, name, country) VALUES ('bad-country', 'Bad Country GC', 'USA') $q$);

SELECT pg_temp.assert_fails('malformed slug rejected',
    $q$ INSERT INTO facilities (slug, name, country) VALUES ('Bad Slug!', 'Bad Slug GC', 'US') $q$);

SELECT pg_temp.assert_fails('malformed color hex rejected',
    $q$ INSERT INTO tees (course_id, name, unit, display_order, color_hex) VALUES (2, 'Gold', 'yards', 9, 'blue') $q$);

-- ------------------------------------------------------------ identity rails
SELECT pg_temp.assert_fails('explicit id without OVERRIDING SYSTEM VALUE rejected',
    $q$ INSERT INTO users (id, email, display_name) VALUES (99, 'x@example.com', 'x') $q$);

SELECT pg_temp.assert_fails('duplicate tee name per course rejected',
    $q$ INSERT INTO tees (course_id, name, unit, display_order) VALUES (1, 'Blue', 'yards', 9) $q$);

SELECT pg_temp.assert_fails('duplicate email (case-insensitive) rejected',
    $q$ INSERT INTO users (email, display_name) VALUES ('ALICE@example.com', 'alice2') $q$);

SELECT pg_temp.assert_fails('duplicate external id per namespace rejected',
    $q$ INSERT INTO external_ids (facility_id, namespace, external_id) VALUES (2, 'osm', 'way/123456789') $q$);

-- ------------------------------------------------- cross-entity corruption
-- Tee 6 (The Short Nine, course 2) cannot be paired with a hole on course 1:
-- the composite FK (tee_id, course_id) → tees (id, course_id) fails. The
-- (tee_id, hole_number) pair is chosen not to collide with existing rows so
-- the rejection provably comes from the FK, not the primary key.
SELECT pg_temp.assert_fails('tee from course A cannot join holes of course B',
    $q$ INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length) VALUES (6, 1, 15, 300) $q$);

-- Combination tee legs must belong to the combination's leg courses:
-- combination 1 is North(3)/South(4); tee 13 belongs to Wattle Flat (6).
SELECT pg_temp.assert_fails('combination tee must belong to the leg course',
    $q$ INSERT INTO combination_tees
            (combination_id, first_course_id, second_course_id, name, display_order, first_tee_id, second_tee_id)
        VALUES (1, 3, 4, 'Gold', 9, 13, 9) $q$);

-- Combination legs must belong to the combination's facility: facility 3
-- (Wattle Flat) cannot pair Trillium Creek's nines.
SELECT pg_temp.assert_fails('combination legs must belong to the same facility',
    $q$ INSERT INTO course_combinations (facility_id, slug, name, first_course_id, second_course_id)
        VALUES (3, 'stolen-nines', 'Stolen Nines', 3, 4) $q$);

-- --------------------------------------------------------- lifecycle rails
SELECT pg_temp.assert_fails('facility with courses cannot be hard-deleted',
    $q$ DELETE FROM facilities WHERE id = 1 $q$);

SELECT pg_temp.assert_fails('merged_into requires duplicate status',
    $q$ UPDATE facilities SET merged_into_id = 2 WHERE id = 1 $q$);

SELECT pg_temp.assert_fails('duplicate status requires merged_into',
    $q$ UPDATE facilities SET status = 'duplicate' WHERE id = 1 $q$);

SELECT pg_temp.assert_fails('approved submission requires reviewer fields',
    $q$ UPDATE submissions SET status = 'approved' WHERE id = 3 $q$);

SELECT pg_temp.assert_fails('deleting a tee used by a combination is blocked',
    $q$ DELETE FROM tees WHERE id = 13 $q$);

SELECT pg_temp.assert_fails('submission source needs at least one piece of evidence',
    $q$ INSERT INTO submission_sources (submission_id, source_type) VALUES (3, 'other') $q$);

-- -------------------------------------------------- flexibility must remain
SELECT pg_temp.assert_ok('unrated tee (no rating rows) is legal',
    $q$ INSERT INTO tees (course_id, name, unit, display_order) VALUES (2, 'Forward', 'yards', 2) $q$);

-- Note: hole 10 on a 9-hole course is deliberately DDL-legal — hole_number
-- vs hole_count consistency is an application/submission-layer rule.
SELECT pg_temp.assert_ok('hole beyond hole_count is a soft (app-layer) rule',
    $q$ INSERT INTO holes (course_id, hole_number) VALUES (2, 10) $q$);

SELECT pg_temp.assert_ok('par row without stroke index is legal',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index) VALUES (2, 10, 'men', 3, NULL) $q$);

SELECT pg_temp.assert_ok('same course as both combination legs is legal (nine played twice)',
    $q$ INSERT INTO course_combinations (facility_id, slug, name, first_course_id, second_course_id)
        VALUES (1, 'short-nine-18', 'The Short Nine (18 holes)', 2, 2) $q$);

-- Deferred display_order lets a reorder swap positions inside one transaction.
SELECT pg_temp.assert_ok('tee display_order swap inside one transaction',
    $q$ UPDATE tees SET display_order = CASE id WHEN 1 THEN 2 WHEN 2 THEN 1 END WHERE id IN (1, 2) $q$);
SET CONSTRAINTS ALL IMMEDIATE;   -- force the deferred uniqueness check now
DO $$ BEGIN RAISE NOTICE 'ok: deferred display_order uniqueness validated'; END $$;

ROLLBACK;
