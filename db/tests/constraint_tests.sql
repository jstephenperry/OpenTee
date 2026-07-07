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
--
-- Seed UUIDs follow 00000000-0000-4000-8000-TTTTNNNNNNNN, where TTTT tags
-- the entity type (0001 users, 0002 facilities, 0003 courses, 0004 tees,
-- 0005 combinations, 0006 combination tees, 0007 submissions) and N is the
-- entity's sequence number, so '...-000300000002' below is course 2
-- (The Short Nine) and '...-000400000013' is tee 13 (Wattle Flat White).
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

-- ----------------------------------------------------- seed data-quality views
-- The seed plants exactly one misprint (Sandpiper Red tee) and everything
-- else must reconcile — on plain tees and combination cards alike.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM v_tee_summaries WHERE has_total_discrepancy;
    IF n <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: expected exactly 1 planted tee misprint, found %', n;
    END IF;
    SELECT count(*) INTO n FROM v_tee_summaries WHERE NOT is_complete;
    IF n <> 0 THEN
        RAISE EXCEPTION 'TEST FAILED: % seeded tees are incomplete', n;
    END IF;
    SELECT count(*) INTO n FROM v_combination_tee_summaries
    WHERE NOT is_complete OR has_total_discrepancy;
    IF n <> 0 THEN
        RAISE EXCEPTION 'TEST FAILED: % combination tees incomplete or discrepant', n;
    END IF;
    RAISE NOTICE 'ok: seed reconciles in v_tee_summaries and v_combination_tee_summaries (1 planted misprint)';
END;
$$;

-- ---------------------------------------------------------------- value rails
SELECT pg_temp.assert_fails('gender must be canonical lowercase',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par)
        VALUES ('00000000-0000-4000-8000-000300000002', 1, 'Male', 3) $q$);

SELECT pg_temp.assert_fails('par above 7 rejected',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par)
        VALUES ('00000000-0000-4000-8000-000300000002', 1, 'men', 8) $q$);

SELECT pg_temp.assert_fails('par below 3 rejected',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par)
        VALUES ('00000000-0000-4000-8000-000300000002', 1, 'men', 2) $q$);

SELECT pg_temp.assert_fails('stroke index above 18 rejected',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index)
        VALUES ('00000000-0000-4000-8000-000300000002', 1, 'men', 3, 19) $q$);

SELECT pg_temp.assert_fails('slope outside 55-155 rejected',
    $q$ INSERT INTO tee_ratings (tee_id, gender, course_rating, slope_rating)
        VALUES ('00000000-0000-4000-8000-000400000006', 'men', 62.0, 156) $q$);

SELECT pg_temp.assert_fails('course rating outside sanity bounds rejected',
    $q$ INSERT INTO tee_ratings (tee_id, gender, course_rating, slope_rating)
        VALUES ('00000000-0000-4000-8000-000400000006', 'men', 999.9, 120) $q$);

SELECT pg_temp.assert_fails('hole length outside 20-1500 rejected',
    $q$ INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length)
        VALUES ('00000000-0000-4000-8000-000400000006', '00000000-0000-4000-8000-000300000002', 1, 5000) $q$);

SELECT pg_temp.assert_fails('hole_number 0 rejected',
    $q$ INSERT INTO holes (course_id, hole_number)
        VALUES ('00000000-0000-4000-8000-000300000002', 0) $q$);

SELECT pg_temp.assert_fails('tee unit must be yards or meters',
    $q$ INSERT INTO tees (course_id, name, unit, display_order)
        VALUES ('00000000-0000-4000-8000-000300000002', 'Gold', 'feet', 9) $q$);

SELECT pg_temp.assert_fails('country must be ISO 3166-1 alpha-2',
    $q$ INSERT INTO facilities (slug, name, country) VALUES ('bad-country', 'Bad Country GC', 'USA') $q$);

SELECT pg_temp.assert_fails('malformed slug rejected',
    $q$ INSERT INTO facilities (slug, name, country) VALUES ('Bad Slug!', 'Bad Slug GC', 'US') $q$);

SELECT pg_temp.assert_fails('malformed color hex rejected',
    $q$ INSERT INTO tees (course_id, name, unit, display_order, color_hex)
        VALUES ('00000000-0000-4000-8000-000300000002', 'Gold', 'yards', 9, 'blue') $q$);

-- ------------------------------------------------------------ identity rails
SELECT pg_temp.assert_fails('duplicate explicit uuid rejected',
    $q$ INSERT INTO users (id, email, display_name)
        VALUES ('00000000-0000-4000-8000-000100000001', 'x@example.com', 'x') $q$);

SELECT pg_temp.assert_ok('auto-generated uuid on plain insert',
    $q$ INSERT INTO users (email, display_name) VALUES ('dave@example.com', 'dave') $q$);

SELECT pg_temp.assert_fails('duplicate tee name per course rejected',
    $q$ INSERT INTO tees (course_id, name, unit, display_order)
        VALUES ('00000000-0000-4000-8000-000300000001', 'Blue', 'yards', 9) $q$);

SELECT pg_temp.assert_fails('duplicate email (case-insensitive) rejected',
    $q$ INSERT INTO users (email, display_name) VALUES ('ALICE@example.com', 'alice2') $q$);

SELECT pg_temp.assert_fails('duplicate external id per namespace rejected',
    $q$ INSERT INTO external_ids (facility_id, namespace, external_id)
        VALUES ('00000000-0000-4000-8000-000200000002', 'osm', 'way/123456789') $q$);

-- ------------------------------------------------- cross-entity corruption
-- Tee 6 (The Short Nine, course 2) cannot be paired with a hole on course 1
-- (Dunes): the composite FK (tee_id, course_id) → tees (id, course_id)
-- fails. The (tee_id, hole_number) pair is chosen not to collide with
-- existing rows so the rejection provably comes from the FK, not the PK.
SELECT pg_temp.assert_fails('tee from course A cannot join holes of course B',
    $q$ INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length)
        VALUES ('00000000-0000-4000-8000-000400000006', '00000000-0000-4000-8000-000300000001', 15, 300) $q$);

-- Combination tee legs must belong to the combination's leg courses:
-- combination 1 is North(3)/South(4); tee 13 belongs to Wattle Flat (6).
SELECT pg_temp.assert_fails('combination tee must belong to the leg course',
    $q$ INSERT INTO combination_tees
            (combination_id, first_course_id, second_course_id, name, display_order, first_tee_id, second_tee_id, unit)
        VALUES ('00000000-0000-4000-8000-000500000001',
                '00000000-0000-4000-8000-000300000003',
                '00000000-0000-4000-8000-000300000004',
                'Gold', 9,
                '00000000-0000-4000-8000-000400000013',
                '00000000-0000-4000-8000-000400000009',
                'yards') $q$);

-- Both leg tees are yards tees, so a 'meters' combination tee cannot
-- reference them: units agree by construction.
SELECT pg_temp.assert_fails('combination tee unit must match its leg tees',
    $q$ INSERT INTO combination_tees
            (combination_id, first_course_id, second_course_id, name, display_order, first_tee_id, second_tee_id, unit)
        VALUES ('00000000-0000-4000-8000-000500000001',
                '00000000-0000-4000-8000-000300000003',
                '00000000-0000-4000-8000-000300000004',
                'Gold', 9,
                '00000000-0000-4000-8000-000400000007',
                '00000000-0000-4000-8000-000400000010',
                'meters') $q$);

-- Combination legs must belong to the combination's facility: facility 3
-- (Wattle Flat) cannot pair Trillium Creek's nines.
SELECT pg_temp.assert_fails('combination legs must belong to the same facility',
    $q$ INSERT INTO course_combinations (facility_id, slug, name, first_course_id, second_course_id)
        VALUES ('00000000-0000-4000-8000-000200000003', 'stolen-nines', 'Stolen Nines',
                '00000000-0000-4000-8000-000300000003',
                '00000000-0000-4000-8000-000300000004') $q$);

-- --------------------------------------------------------- lifecycle rails
SELECT pg_temp.assert_fails('facility with courses cannot be hard-deleted',
    $q$ DELETE FROM facilities WHERE id = '00000000-0000-4000-8000-000200000001' $q$);

SELECT pg_temp.assert_fails('merged_into requires duplicate status',
    $q$ UPDATE facilities SET merged_into_id = '00000000-0000-4000-8000-000200000002'
        WHERE id = '00000000-0000-4000-8000-000200000001' $q$);

SELECT pg_temp.assert_fails('duplicate status requires merged_into',
    $q$ UPDATE facilities SET status = 'duplicate'
        WHERE id = '00000000-0000-4000-8000-000200000001' $q$);

SELECT pg_temp.assert_fails('approved submission requires reviewer fields',
    $q$ UPDATE submissions SET status = 'approved'
        WHERE id = '00000000-0000-4000-8000-000700000003' $q$);

SELECT pg_temp.assert_fails('deleting a tee used by a combination is blocked',
    $q$ DELETE FROM tees WHERE id = '00000000-0000-4000-8000-000400000013' $q$);

SELECT pg_temp.assert_fails('submission source needs at least one piece of evidence',
    $q$ INSERT INTO submission_sources (submission_id, source_type)
        VALUES ('00000000-0000-4000-8000-000700000003', 'other') $q$);

SELECT pg_temp.assert_fails('submission targets must match its kind',
    $q$ INSERT INTO submissions (kind, course_id, payload, submitted_by)
        VALUES ('facility', '00000000-0000-4000-8000-000300000001', '{"schema_version": 1}',
                '00000000-0000-4000-8000-000100000002') $q$);

-- Course 1 is targeted by submissions 2 and 3: its history chain protects
-- it from single-statement destruction.
SELECT pg_temp.assert_fails('course targeted by submissions cannot be hard-deleted',
    $q$ DELETE FROM courses WHERE id = '00000000-0000-4000-8000-000300000001' $q$);

-- -------------------------------------------------- flexibility must remain
SELECT pg_temp.assert_ok('unrated tee (no rating rows) is legal',
    $q$ INSERT INTO tees (course_id, name, unit, display_order)
        VALUES ('00000000-0000-4000-8000-000300000002', 'Forward', 'yards', 2) $q$);

-- Note: hole 10 on a 9-hole course is deliberately DDL-legal — hole_number
-- vs hole_count consistency is an application/submission-layer rule.
SELECT pg_temp.assert_ok('hole beyond hole_count is a soft (app-layer) rule',
    $q$ INSERT INTO holes (course_id, hole_number)
        VALUES ('00000000-0000-4000-8000-000300000002', 10) $q$);

SELECT pg_temp.assert_ok('par row without stroke index is legal',
    $q$ INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index)
        VALUES ('00000000-0000-4000-8000-000300000002', 10, 'men', 3, NULL) $q$);

SELECT pg_temp.assert_ok('same course as both combination legs is legal (nine played twice)',
    $q$ INSERT INTO course_combinations (facility_id, slug, name, first_course_id, second_course_id)
        VALUES ('00000000-0000-4000-8000-000200000001', 'short-nine-18', 'The Short Nine (18 holes)',
                '00000000-0000-4000-8000-000300000002',
                '00000000-0000-4000-8000-000300000002') $q$);

-- Deferred display_order lets a reorder swap positions inside one transaction.
SELECT pg_temp.assert_ok('tee display_order swap inside one transaction',
    $q$ UPDATE tees SET display_order = CASE id
            WHEN '00000000-0000-4000-8000-000400000001' THEN 2
            WHEN '00000000-0000-4000-8000-000400000002' THEN 1
        END
        WHERE id IN ('00000000-0000-4000-8000-000400000001',
                     '00000000-0000-4000-8000-000400000002') $q$);
SET CONSTRAINTS ALL IMMEDIATE;   -- force the deferred uniqueness check now
DO $$ BEGIN RAISE NOTICE 'ok: deferred display_order uniqueness validated'; END $$;

-- Deleting a course (one with no submission history) must cascade cleanly
-- through holes, tees, and combo-tee provenance regardless of RI-trigger
-- creation order — this is why fk_tee_hole_lengths_source_tee is deferred.
DO $$
DECLARE cid uuid; t1 uuid; t2 uuid; tc uuid;
BEGIN
    INSERT INTO courses (facility_id, slug, name, hole_count)
    VALUES ('00000000-0000-4000-8000-000200000001', 'scratch-cascade', 'Scratch Cascade', 2)
    RETURNING id INTO cid;
    INSERT INTO holes (course_id, hole_number) VALUES (cid, 1), (cid, 2);
    INSERT INTO tees (course_id, name, unit, display_order) VALUES (cid, 'A', 'yards', 1) RETURNING id INTO t1;
    INSERT INTO tees (course_id, name, unit, display_order) VALUES (cid, 'B', 'yards', 2) RETURNING id INTO t2;
    INSERT INTO tees (course_id, name, unit, display_order, is_combination)
    VALUES (cid, 'A/B', 'yards', 3, true) RETURNING id INTO tc;
    INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length)
    VALUES (t1, cid, 1, 310), (t1, cid, 2, 415), (t2, cid, 1, 290), (t2, cid, 2, 390);
    INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length, source_tee_id)
    VALUES (tc, cid, 1, 310, t1), (tc, cid, 2, 390, t2);
    DELETE FROM courses WHERE id = cid;
    RAISE NOTICE 'ok: course delete cascades cleanly through combo-tee provenance';
END;
$$;

-- The documented facility-merge recipe must be executable with plain SQL:
-- defer the combination-leg FKs, repoint children, tombstone the loser.
-- Facility 2 (Trillium Creek) owns three combinations — the hard case.
SAVEPOINT merge_test;
SET CONSTRAINTS fk_combinations_first_course, fk_combinations_second_course DEFERRED;
UPDATE courses             SET facility_id = '00000000-0000-4000-8000-000200000001'
                           WHERE facility_id = '00000000-0000-4000-8000-000200000002';
UPDATE course_combinations SET facility_id = '00000000-0000-4000-8000-000200000001'
                           WHERE facility_id = '00000000-0000-4000-8000-000200000002';
UPDATE facilities SET status = 'duplicate', merged_into_id = '00000000-0000-4000-8000-000200000001'
                  WHERE id = '00000000-0000-4000-8000-000200000002';
SET CONSTRAINTS ALL IMMEDIATE;   -- validate the deferred FK checks now
DO $$ BEGIN RAISE NOTICE 'ok: facility merge repoint recipe works on a combination-owning facility'; END $$;
ROLLBACK TO SAVEPOINT merge_test;

ROLLBACK;
