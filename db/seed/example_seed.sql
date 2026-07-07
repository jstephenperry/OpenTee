-- ============================================================================
-- OpenTee example seed data (v1)
--
-- ALL FACILITIES, COURSES, AND VALUES ARE FICTIONAL. This file exists to
-- demonstrate and exercise every schema feature with internally consistent
-- data (generated; totals are computed from the per-hole values):
--
--   facility 1  Sandpiper Dunes Golf Resort (US)
--     course 1  Dunes            18 holes, hole names, 4 physical tees +
--                                 a "Blue/White" combination tee, men-only
--                                 rating on Black, dual-gender ratings with
--                                 front/back splits, women's par 5 on men's
--                                 par-4 hole 8, per-gender stroke indexes,
--                                 one deliberate published-total misprint
--                                 (Red tee) to exercise the discrepancy flag
--     course 2  The Short Nine   9-hole par-3: UNRATED, no stroke indexes,
--                                 unisex par rows
--   facility 2  Trillium Creek Country Club (US)
--     courses 3/4/5  North/South/West nines + the three 18-hole pairings as
--                    course_combinations with their own tees, ratings, and
--                    men's + women's 18-hole stroke-index allocations — no
--                    hole entered twice
--   facility 3  Wattle Flat Golf Club (AU)
--     course 6  Wattle Flat      9 holes in METERS, unisex par; played twice
--                                 as 18 ("White out, Yellow in") via a
--                                 combination whose legs are the same course
--
-- Plus: users, an approved/pending submission trail with evidence sources,
-- and external_ids anchors.
--
-- Ids are explicit (OVERRIDING SYSTEM VALUE) so cross-references stay
-- readable; sequences are resynced at the end.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- users
INSERT INTO users (id, email, display_name, role) OVERRIDING SYSTEM VALUE VALUES
    (1, 'alice@example.com', 'alice',  'admin'),
    (2, 'bob@example.com',   'bob',    'contributor'),
    (3, 'carol@example.com', 'carol',  'moderator');

-- ------------------------------------------------------------ facilities
INSERT INTO facilities (id, slug, name, address, city, state_province, country,
                        postal_code, latitude, longitude, website_url)
OVERRIDING SYSTEM VALUE VALUES
    (1, 'sandpiper-dunes-golf-resort', 'Sandpiper Dunes Golf Resort',
        '1 Shorebird Way', 'Lakeport', 'Michigan', 'US', '49001',
        43.512345, -86.234567, 'https://example.com/sandpiper-dunes'),
    (2, 'trillium-creek-country-club', 'Trillium Creek Country Club',
        '400 Trillium Creek Rd', 'Maplewood', 'Ohio', 'US', '44101',
        41.223344, -81.556677, 'https://example.com/trillium-creek'),
    (3, 'wattle-flat-golf-club', 'Wattle Flat Golf Club',
        '12 Fairway Track', 'Wattle Flat', 'New South Wales', 'AU', '2795',
        -33.401122, 149.687788, 'https://example.com/wattle-flat');

-- --------------------------------------------------------------- courses
INSERT INTO courses (id, facility_id, slug, name, hole_count) OVERRIDING SYSTEM VALUE VALUES
    (1, 1, 'dunes',       'Dunes',          18),
    (2, 1, 'short-nine',  'The Short Nine',  9),
    (3, 2, 'north',       'North',           9),
    (4, 2, 'south',       'South',           9),
    (5, 2, 'west',        'West',            9),
    (6, 3, 'wattle-flat', 'Wattle Flat',     9);

-- ----------------------------------------------------------------- holes
INSERT INTO holes (course_id, hole_number, name) VALUES
    (1,  1, 'Sandpiper'),
    (1,  2, 'Long Marsh'),
    (1,  3, 'Cattail'),
    (1,  4, 'Driftwood'),
    (1,  5, 'Bluff'),
    (1,  6, 'Fox Run'),
    (1,  7, 'The Well'),
    (1,  8, 'Osprey'),
    (1,  9, 'Breakers'),
    (1, 10, 'Turnstone'),
    (1, 11, 'Short Grass'),
    (1, 12, 'Twin Oaks'),
    (1, 13, 'High Dune'),
    (1, 14, 'Blowout'),
    (1, 15, 'Plover'),
    (1, 16, 'Little Sands'),
    (1, 17, 'Gale'),
    (1, 18, 'Home'),
    (2,  1, NULL),
    (2,  2, NULL),
    (2,  3, NULL),
    (2,  4, NULL),
    (2,  5, NULL),
    (2,  6, NULL),
    (2,  7, NULL),
    (2,  8, NULL),
    (2,  9, NULL),
    (3,  1, NULL),
    (3,  2, NULL),
    (3,  3, NULL),
    (3,  4, NULL),
    (3,  5, NULL),
    (3,  6, NULL),
    (3,  7, NULL),
    (3,  8, NULL),
    (3,  9, NULL),
    (4,  1, NULL),
    (4,  2, NULL),
    (4,  3, NULL),
    (4,  4, NULL),
    (4,  5, NULL),
    (4,  6, NULL),
    (4,  7, NULL),
    (4,  8, NULL),
    (4,  9, NULL),
    (5,  1, NULL),
    (5,  2, NULL),
    (5,  3, NULL),
    (5,  4, NULL),
    (5,  5, NULL),
    (5,  6, NULL),
    (5,  7, NULL),
    (5,  8, NULL),
    (5,  9, NULL),
    (6,  1, NULL),
    (6,  2, NULL),
    (6,  3, NULL),
    (6,  4, NULL),
    (6,  5, NULL),
    (6,  6, NULL),
    (6,  7, NULL),
    (6,  8, NULL),
    (6,  9, NULL);

-- ------------------------------------------------------------- hole_pars
-- Dunes: gendered rows; women's par 5 on hole 8 where men play par 4.
INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index) VALUES
    (1,  1, 'men',   4,  9),
    (1,  2, 'men',   4,  3),
    (1,  3, 'men',   3, 17),
    (1,  4, 'men',   5,  7),
    (1,  5, 'men',   4,  1),
    (1,  6, 'men',   4, 11),
    (1,  7, 'men',   3, 15),
    (1,  8, 'men',   4,  5),
    (1,  9, 'men',   5, 13),
    (1, 10, 'men',   4,  8),
    (1, 11, 'men',   3, 16),
    (1, 12, 'men',   4,  4),
    (1, 13, 'men',   5, 10),
    (1, 14, 'men',   4,  2),
    (1, 15, 'men',   4,  6),
    (1, 16, 'men',   3, 18),
    (1, 17, 'men',   4, 12),
    (1, 18, 'men',   5, 14),
    (1,  1, 'women', 4,  7),
    (1,  2, 'women', 4,  3),
    (1,  3, 'women', 3, 15),
    (1,  4, 'women', 5,  9),
    (1,  5, 'women', 4,  1),
    (1,  6, 'women', 4, 13),
    (1,  7, 'women', 3, 17),
    (1,  8, 'women', 5,  5),
    (1,  9, 'women', 5, 11),
    (1, 10, 'women', 4, 10),
    (1, 11, 'women', 3, 16),
    (1, 12, 'women', 4,  2),
    (1, 13, 'women', 5,  8),
    (1, 14, 'women', 4,  4),
    (1, 15, 'women', 4,  6),
    (1, 16, 'women', 3, 18),
    (1, 17, 'women', 4, 12),
    (1, 18, 'women', 5, 14);

-- The Short Nine: single unisex par row, card publishes no stroke indexes.
INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index) VALUES
    (2, 1, 'unisex', 3, NULL),
    (2, 2, 'unisex', 3, NULL),
    (2, 3, 'unisex', 3, NULL),
    (2, 4, 'unisex', 3, NULL),
    (2, 5, 'unisex', 3, NULL),
    (2, 6, 'unisex', 3, NULL),
    (2, 7, 'unisex', 3, NULL),
    (2, 8, 'unisex', 3, NULL),
    (2, 9, 'unisex', 3, NULL);

-- Trillium Creek nines: gendered rows, SI 1-9 on each nine's own card.
INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index) VALUES
    (3, 1, 'men',   4, 3),
    (3, 2, 'men',   5, 1),
    (3, 3, 'men',   3, 9),
    (3, 4, 'men',   4, 5),
    (3, 5, 'men',   4, 7),
    (3, 6, 'men',   3, 8),
    (3, 7, 'men',   5, 2),
    (3, 8, 'men',   4, 4),
    (3, 9, 'men',   4, 6),
    (3, 1, 'women', 4, 5),
    (3, 2, 'women', 5, 1),
    (3, 3, 'women', 3, 9),
    (3, 4, 'women', 4, 3),
    (3, 5, 'women', 4, 7),
    (3, 6, 'women', 3, 8),
    (3, 7, 'women', 5, 2),
    (3, 8, 'women', 4, 6),
    (3, 9, 'women', 4, 4),
    (4, 1, 'men',   5, 2),
    (4, 2, 'men',   4, 6),
    (4, 3, 'men',   3, 8),
    (4, 4, 'men',   4, 4),
    (4, 5, 'men',   5, 1),
    (4, 6, 'men',   4, 5),
    (4, 7, 'men',   3, 9),
    (4, 8, 'men',   4, 7),
    (4, 9, 'men',   4, 3),
    (4, 1, 'women', 5, 1),
    (4, 2, 'women', 4, 5),
    (4, 3, 'women', 3, 9),
    (4, 4, 'women', 4, 4),
    (4, 5, 'women', 5, 2),
    (4, 6, 'women', 4, 6),
    (4, 7, 'women', 3, 8),
    (4, 8, 'women', 4, 7),
    (4, 9, 'women', 4, 3),
    (5, 1, 'men',   4, 4),
    (5, 2, 'men',   4, 7),
    (5, 3, 'men',   5, 1),
    (5, 4, 'men',   3, 9),
    (5, 5, 'men',   4, 3),
    (5, 6, 'men',   4, 6),
    (5, 7, 'men',   3, 8),
    (5, 8, 'men',   5, 2),
    (5, 9, 'men',   4, 5),
    (5, 1, 'women', 4, 6),
    (5, 2, 'women', 4, 7),
    (5, 3, 'women', 5, 1),
    (5, 4, 'women', 3, 9),
    (5, 5, 'women', 4, 3),
    (5, 6, 'women', 4, 4),
    (5, 7, 'women', 3, 8),
    (5, 8, 'women', 5, 2),
    (5, 9, 'women', 4, 5);

-- Wattle Flat: single unisex par/SI row, as on the published card.
INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index) VALUES
    (6, 1, 'unisex', 4, 3),
    (6, 2, 'unisex', 3, 7),
    (6, 3, 'unisex', 4, 5),
    (6, 4, 'unisex', 5, 1),
    (6, 5, 'unisex', 4, 4),
    (6, 6, 'unisex', 3, 9),
    (6, 7, 'unisex', 4, 6),
    (6, 8, 'unisex', 5, 2),
    (6, 9, 'unisex', 4, 8);

-- ------------------------------------------------------------------ tees
-- Red tee published total is DELIBERATELY 12 off the computed sum
-- (5435 vs 5423) to demonstrate
-- v_tee_summaries.has_total_discrepancy (a "misprint on the physical card").
INSERT INTO tees (id, course_id, name, color_name, color_hex, secondary_color_hex,
                  unit, display_order, is_combination, published_total_length)
OVERRIDING SYSTEM VALUE VALUES
    ( 1, 1, 'Black',      'Black', '#1a1a1a', NULL,      'yards', 1, false, 7278),
    ( 2, 1, 'Blue',       'Blue',  '#1e56a0', NULL,      'yards', 2, false, 6935),
    ( 3, 1, 'White',      'White', '#f5f5f5', NULL,      'yards', 3, false, 6603),
    ( 4, 1, 'Blue/White', NULL,    '#1e56a0', '#f5f5f5', 'yards', 4, true,  6766),
    ( 5, 1, 'Red',        'Red',   '#c0392b', NULL,      'yards', 5, false, 5435),
    ( 6, 2, 'White',      'White', '#f5f5f5', NULL,      'yards', 1, false, 1132),
    ( 7, 3, 'Blue',       'Blue',  '#1e56a0', NULL,      'yards', 1, false, 3374),
    ( 8, 3, 'White',      'White', '#f5f5f5', NULL,      'yards', 2, false, 3164),
    ( 9, 4, 'Blue',       'Blue',  '#1e56a0', NULL,      'yards', 1, false, 3368),
    (10, 4, 'White',      'White', '#f5f5f5', NULL,      'yards', 2, false, 3145),
    (11, 5, 'Blue',       'Blue',  '#1e56a0', NULL,      'yards', 1, false, 3361),
    (12, 5, 'White',      'White', '#f5f5f5', NULL,      'yards', 2, false, 3139),
    (13, 6, 'White',      'White', '#f5f5f5', NULL,      'meters', 1, false, 2922),
    (14, 6, 'Yellow',     'Yellow','#f1c40f', NULL,      'meters', 2, false, 2776),
    (15, 6, 'Red',        'Red',   '#c0392b', NULL,      'meters', 3, false, 2490);

-- ----------------------------------------------------------- tee_ratings
-- Black is rated for men only; White/Red for both genders (same physical
-- tee, one length set, two rating rows). The Short Nine has NO rating rows.
-- Nine-hole courses carry their 9-hole ratings here; 18-hole "played twice"
-- ratings live on the combination.
INSERT INTO tee_ratings (tee_id, gender, course_rating, slope_rating, bogey_rating,
                         front_nine_rating, front_nine_slope, back_nine_rating,
                         back_nine_slope, effective_date) VALUES
    ( 1, 'men',   74.8, 145, 100.2, 37.6, 147, 37.2, 143, '2024-05-01'),
    ( 2, 'men',   72.6, 138,  96.9, 36.5, 139, 36.1, 137, '2024-05-01'),
    ( 3, 'men',   70.4, 131,  93.7, 35.4, 132, 35.0, 130, '2024-05-01'),
    ( 3, 'women', 76.1, 137, 106.8, 38.3, 138, 37.8, 136, '2024-05-01'),
    ( 4, 'men',   71.5, 134,  95.2, 36.0, 136, 35.5, 132, '2024-05-01'),
    ( 5, 'men',   66.8, 118,  87.4, 33.6, 119, 33.2, 117, '2024-05-01'),
    ( 5, 'women', 71.9, 126,  99.6, 36.2, 127, 35.7, 125, '2024-05-01'),
    ( 7, 'men',   35.9, 136, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    ( 8, 'men',   34.7, 129, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    ( 8, 'women', 37.4, 134, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    ( 9, 'men',   36.1, 138, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    (10, 'men',   34.9, 131, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    (10, 'women', 37.7, 136, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    (11, 'men',   35.6, 134, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    (12, 'men',   34.4, 127, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    (12, 'women', 37.2, 132, NULL, NULL, NULL, NULL, NULL, '2023-08-15'),
    (13, 'men',   34.9, 125, NULL, NULL, NULL, NULL, NULL, '2022-11-30'),
    (14, 'men',   34.1, 121, NULL, NULL, NULL, NULL, NULL, '2022-11-30'),
    (14, 'women', 36.8, 128, NULL, NULL, NULL, NULL, NULL, '2022-11-30'),
    (15, 'women', 35.6, 122, NULL, NULL, NULL, NULL, NULL, '2022-11-30');

-- ----------------------------------------------------- tee_hole_lengths
-- Dunes physical tees.
INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length) VALUES
    (1, 1,  1, 430),
    (1, 1,  2, 440),
    (1, 1,  3, 190),
    (1, 1,  4, 562),
    (1, 1,  5, 436),
    (1, 1,  6, 406),
    (1, 1,  7, 180),
    (1, 1,  8, 449),
    (1, 1,  9, 553),
    (1, 1, 10, 421),
    (1, 1, 11, 192),
    (1, 1, 12, 437),
    (1, 1, 13, 562),
    (1, 1, 14, 402),
    (1, 1, 15, 444),
    (1, 1, 16, 166),
    (1, 1, 17, 428),
    (1, 1, 18, 580),
    (2, 1,  1, 407),
    (2, 1,  2, 420),
    (2, 1,  3, 178),
    (2, 1,  4, 544),
    (2, 1,  5, 416),
    (2, 1,  6, 387),
    (2, 1,  7, 167),
    (2, 1,  8, 426),
    (2, 1,  9, 531),
    (2, 1, 10, 399),
    (2, 1, 11, 181),
    (2, 1, 12, 416),
    (2, 1, 13, 540),
    (2, 1, 14, 383),
    (2, 1, 15, 421),
    (2, 1, 16, 156),
    (2, 1, 17, 407),
    (2, 1, 18, 556),
    (3, 1,  1, 385),
    (3, 1,  2, 402),
    (3, 1,  3, 168),
    (3, 1,  4, 520),
    (3, 1,  5, 396),
    (3, 1,  6, 371),
    (3, 1,  7, 155),
    (3, 1,  8, 405),
    (3, 1,  9, 505),
    (3, 1, 10, 380),
    (3, 1, 11, 172),
    (3, 1, 12, 398),
    (3, 1, 13, 515),
    (3, 1, 14, 366),
    (3, 1, 15, 401),
    (3, 1, 16, 148),
    (3, 1, 17, 388),
    (3, 1, 18, 528),
    (5, 1,  1, 323),
    (5, 1,  2, 332),
    (5, 1,  3, 130),
    (5, 1,  4, 425),
    (5, 1,  5, 328),
    (5, 1,  6, 316),
    (5, 1,  7, 120),
    (5, 1,  8, 334),
    (5, 1,  9, 407),
    (5, 1, 10, 316),
    (5, 1, 11, 132),
    (5, 1, 12, 332),
    (5, 1, 13, 419),
    (5, 1, 14, 308),
    (5, 1, 15, 332),
    (5, 1, 16, 118),
    (5, 1, 17, 325),
    (5, 1, 18, 426);

-- Dunes 'Blue/White' combination tee: odd holes from Blue (tee 2), even
-- from White (tee 3); source_tee_id records per-hole provenance.
INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length, source_tee_id) VALUES
    (4, 1,  1, 407, 2),
    (4, 1,  2, 402, 3),
    (4, 1,  3, 178, 2),
    (4, 1,  4, 520, 3),
    (4, 1,  5, 416, 2),
    (4, 1,  6, 371, 3),
    (4, 1,  7, 167, 2),
    (4, 1,  8, 405, 3),
    (4, 1,  9, 531, 2),
    (4, 1, 10, 380, 3),
    (4, 1, 11, 181, 2),
    (4, 1, 12, 398, 3),
    (4, 1, 13, 540, 2),
    (4, 1, 14, 366, 3),
    (4, 1, 15, 421, 2),
    (4, 1, 16, 148, 3),
    (4, 1, 17, 407, 2),
    (4, 1, 18, 528, 3);

-- The Short Nine.
INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length) VALUES
    (6, 2, 1, 128),
    (6, 2, 2, 95),
    (6, 2, 3, 142),
    (6, 2, 4, 110),
    (6, 2, 5, 165),
    (6, 2, 6, 133),
    (6, 2, 7, 88),
    (6, 2, 8, 151),
    (6, 2, 9, 120);

-- Trillium Creek nines.
INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length) VALUES
    (7, 3, 1, 398),
    (7, 3, 2, 522),
    (7, 3, 3, 176),
    (7, 3, 4, 410),
    (7, 3, 5, 385),
    (7, 3, 6, 162),
    (7, 3, 7, 545),
    (7, 3, 8, 372),
    (7, 3, 9, 404),
    (8, 3, 1, 371),
    (8, 3, 2, 498),
    (8, 3, 3, 155),
    (8, 3, 4, 384),
    (8, 3, 5, 362),
    (8, 3, 6, 148),
    (8, 3, 7, 516),
    (8, 3, 8, 349),
    (8, 3, 9, 381),
    (9, 4, 1, 538),
    (9, 4, 2, 388),
    (9, 4, 3, 168),
    (9, 4, 4, 415),
    (9, 4, 5, 510),
    (9, 4, 6, 392),
    (9, 4, 7, 180),
    (9, 4, 8, 376),
    (9, 4, 9, 401),
    (10, 4, 1, 509),
    (10, 4, 2, 361),
    (10, 4, 3, 150),
    (10, 4, 4, 388),
    (10, 4, 5, 482),
    (10, 4, 6, 368),
    (10, 4, 7, 158),
    (10, 4, 8, 352),
    (10, 4, 9, 377),
    (11, 5, 1, 402),
    (11, 5, 2, 377),
    (11, 5, 3, 528),
    (11, 5, 4, 172),
    (11, 5, 5, 408),
    (11, 5, 6, 381),
    (11, 5, 7, 158),
    (11, 5, 8, 540),
    (11, 5, 9, 395),
    (12, 5, 1, 378),
    (12, 5, 2, 351),
    (12, 5, 3, 501),
    (12, 5, 4, 152),
    (12, 5, 5, 380),
    (12, 5, 6, 357),
    (12, 5, 7, 140),
    (12, 5, 8, 512),
    (12, 5, 9, 368);

-- Wattle Flat (meters, stored verbatim).
INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length) VALUES
    (13, 6, 1, 356),
    (13, 6, 2, 148),
    (13, 6, 3, 340),
    (13, 6, 4, 472),
    (13, 6, 5, 331),
    (13, 6, 6, 131),
    (13, 6, 7, 348),
    (13, 6, 8, 459),
    (13, 6, 9, 337),
    (14, 6, 1, 338),
    (14, 6, 2, 139),
    (14, 6, 3, 322),
    (14, 6, 4, 451),
    (14, 6, 5, 315),
    (14, 6, 6, 122),
    (14, 6, 7, 331),
    (14, 6, 8, 438),
    (14, 6, 9, 320),
    (15, 6, 1, 301),
    (15, 6, 2, 118),
    (15, 6, 3, 290),
    (15, 6, 4, 410),
    (15, 6, 5, 282),
    (15, 6, 6, 105),
    (15, 6, 7, 297),
    (15, 6, 8, 399),
    (15, 6, 9, 288);

-- ----------------------------------------------------- course_combinations
-- Trillium Creek's three published 18-hole pairings, and Wattle Flat played
-- twice (both legs are course 6 — first_course_id = second_course_id).
INSERT INTO course_combinations (id, facility_id, slug, name, first_course_id, second_course_id)
OVERRIDING SYSTEM VALUE VALUES
    (1, 2, 'north-south', 'North / South', 3, 4),
    (2, 2, 'south-west',  'South / West',  4, 5),
    (3, 2, 'north-west',  'North / West',  3, 5),
    (4, 3, 'wattle-flat-18', 'Wattle Flat (18 holes)', 6, 6);

-- ------------------------------------------------------- combination_tees
-- Wattle Flat's 18-hole card is the classic "White out, Yellow in". The
-- unit column is FK-tied to both leg tees' units, so it always matches.
INSERT INTO combination_tees (id, combination_id, first_course_id, second_course_id,
                              name, display_order, first_tee_id, second_tee_id,
                              unit, published_total_length)
OVERRIDING SYSTEM VALUE VALUES
    (1, 1, 3, 4, 'Blue',           1,  7,  9, 'yards',  6742),
    (2, 1, 3, 4, 'White',          2,  8, 10, 'yards',  6309),
    (3, 2, 4, 5, 'Blue',           1,  9, 11, 'yards',  6729),
    (4, 2, 4, 5, 'White',          2, 10, 12, 'yards',  6284),
    (5, 3, 3, 5, 'Blue',           1,  7, 11, 'yards',  6735),
    (6, 3, 3, 5, 'White',          2,  8, 12, 'yards',  6303),
    (7, 4, 6, 6, 'White / Yellow', 1, 13, 14, 'meters', 5698);

-- ---------------------------------------------------- combination_ratings
INSERT INTO combination_ratings (combination_tee_id, gender, course_rating, slope_rating,
                                 bogey_rating, front_nine_rating, front_nine_slope,
                                 back_nine_rating, back_nine_slope, effective_date) VALUES
    (1, 'men',   72.0, 137, 96.4, 35.9, 136, 36.1, 138, '2023-08-15'),
    (2, 'men',   69.6, 130, 92.5, 34.7, 129, 34.9, 131, '2023-08-15'),
    (2, 'women', 75.1, 135, 105.3, 37.4, 134, 37.7, 136, '2023-08-15'),
    (3, 'men',   71.7, 136, 95.8, 36.1, 138, 35.6, 134, '2023-08-15'),
    (4, 'men',   69.3, 129, 92.0, 34.9, 131, 34.4, 127, '2023-08-15'),
    (4, 'women', 74.9, 134, 104.8, 37.7, 136, 37.2, 132, '2023-08-15'),
    (5, 'men',   71.5, 135, 95.5, 35.9, 136, 35.6, 134, '2023-08-15'),
    (6, 'men',   69.1, 128, 91.7, 34.7, 129, 34.4, 127, '2023-08-15'),
    (6, 'women', 74.6, 133, 104.4, 37.4, 134, 37.2, 132, '2023-08-15'),
    (7, 'men',   69.0, 123, 91.2, 34.9, 125, 34.1, 121, '2022-11-30');

-- ---------------------------------------------- combination_stroke_indexes
-- Trillium Creek's combined 18-hole cards reallocate SI 1-18 across each
-- pairing (odd SIs on the first nine, even on the second — a common club
-- convention), published for men and women on all three pairings.
INSERT INTO combination_stroke_indexes (combination_id, position, gender, stroke_index) VALUES

    (1,  1, 'men',  5),
    (1,  2, 'men',  1),
    (1,  3, 'men', 17),
    (1,  4, 'men',  9),
    (1,  5, 'men', 13),
    (1,  6, 'men', 15),
    (1,  7, 'men',  3),
    (1,  8, 'men',  7),
    (1,  9, 'men', 11),
    (1, 10, 'men',  4),
    (1, 11, 'men', 12),
    (1, 12, 'men', 16),
    (1, 13, 'men',  8),
    (1, 14, 'men',  2),
    (1, 15, 'men', 10),
    (1, 16, 'men', 18),
    (1, 17, 'men', 14),
    (1, 18, 'men',  6),
    (1,  1, 'women',  9),
    (1,  2, 'women',  1),
    (1,  3, 'women', 17),
    (1,  4, 'women',  5),
    (1,  5, 'women', 13),
    (1,  6, 'women', 15),
    (1,  7, 'women',  3),
    (1,  8, 'women', 11),
    (1,  9, 'women',  7),
    (1, 10, 'women',  2),
    (1, 11, 'women', 10),
    (1, 12, 'women', 18),
    (1, 13, 'women',  8),
    (1, 14, 'women',  4),
    (1, 15, 'women', 12),
    (1, 16, 'women', 16),
    (1, 17, 'women', 14),
    (1, 18, 'women',  6),
    (2,  1, 'men',  3),
    (2,  2, 'men', 11),
    (2,  3, 'men', 15),
    (2,  4, 'men',  7),
    (2,  5, 'men',  1),
    (2,  6, 'men',  9),
    (2,  7, 'men', 17),
    (2,  8, 'men', 13),
    (2,  9, 'men',  5),
    (2, 10, 'men',  8),
    (2, 11, 'men', 14),
    (2, 12, 'men',  2),
    (2, 13, 'men', 18),
    (2, 14, 'men',  6),
    (2, 15, 'men', 12),
    (2, 16, 'men', 16),
    (2, 17, 'men',  4),
    (2, 18, 'men', 10),
    (2,  1, 'women',  1),
    (2,  2, 'women',  9),
    (2,  3, 'women', 17),
    (2,  4, 'women',  7),
    (2,  5, 'women',  3),
    (2,  6, 'women', 11),
    (2,  7, 'women', 15),
    (2,  8, 'women', 13),
    (2,  9, 'women',  5),
    (2, 10, 'women', 12),
    (2, 11, 'women', 14),
    (2, 12, 'women',  2),
    (2, 13, 'women', 18),
    (2, 14, 'women',  6),
    (2, 15, 'women',  8),
    (2, 16, 'women', 16),
    (2, 17, 'women',  4),
    (2, 18, 'women', 10),
    (3,  1, 'men',  5),
    (3,  2, 'men',  1),
    (3,  3, 'men', 17),
    (3,  4, 'men',  9),
    (3,  5, 'men', 13),
    (3,  6, 'men', 15),
    (3,  7, 'men',  3),
    (3,  8, 'men',  7),
    (3,  9, 'men', 11),
    (3, 10, 'men',  8),
    (3, 11, 'men', 14),
    (3, 12, 'men',  2),
    (3, 13, 'men', 18),
    (3, 14, 'men',  6),
    (3, 15, 'men', 12),
    (3, 16, 'men', 16),
    (3, 17, 'men',  4),
    (3, 18, 'men', 10),
    (3,  1, 'women',  9),
    (3,  2, 'women',  1),
    (3,  3, 'women', 17),
    (3,  4, 'women',  5),
    (3,  5, 'women', 13),
    (3,  6, 'women', 15),
    (3,  7, 'women',  3),
    (3,  8, 'women', 11),
    (3,  9, 'women',  7),
    (3, 10, 'women', 12),
    (3, 11, 'women', 14),
    (3, 12, 'women',  2),
    (3, 13, 'women', 18),
    (3, 14, 'women',  6),
    (3, 15, 'women',  8),
    (3, 16, 'women', 16),
    (3, 17, 'women',  4),
    (3, 18, 'women', 10);

-- Wattle Flat 18-hole card: SI 1-18 over two loops of the same nine
-- (hole 4 is SI 1 on the way out and SI 2 as hole 13 coming in).
INSERT INTO combination_stroke_indexes (combination_id, position, gender, stroke_index) VALUES
    (4,  1, 'unisex',  5),
    (4,  2, 'unisex', 13),
    (4,  3, 'unisex',  9),
    (4,  4, 'unisex',  1),
    (4,  5, 'unisex',  7),
    (4,  6, 'unisex', 17),
    (4,  7, 'unisex', 11),
    (4,  8, 'unisex',  3),
    (4,  9, 'unisex', 15),
    (4, 10, 'unisex',  6),
    (4, 11, 'unisex', 14),
    (4, 12, 'unisex', 10),
    (4, 13, 'unisex',  2),
    (4, 14, 'unisex',  8),
    (4, 15, 'unisex', 18),
    (4, 16, 'unisex', 12),
    (4, 17, 'unisex',  4),
    (4, 18, 'unisex', 16);

-- ------------------------------------------------------------ external_ids
-- Official rating databases publish each 18-hole pairing as its own rated
-- entity, so combinations are anchorable alongside facilities and courses.
INSERT INTO external_ids (facility_id, course_id, combination_id, namespace, external_id) VALUES
    (1,    NULL, NULL, 'osm',            'way/123456789'),
    (NULL, 1,    NULL, 'usga_crdb',      'demo-30412'),
    (NULL, 6,    NULL, 'golf_australia', 'demo-nsw-0042'),
    (NULL, NULL, 1,    'usga_crdb',      'demo-30498-ns');

-- ------------------------------------------------------------ submissions
-- The write path: bob submitted the Dunes scorecard with photo + website
-- evidence; carol approved it. A pending correction shows the moderation
-- queue. Payloads are abbreviated illustrations — the application defines
-- the full payload contract (include a schema_version key).
INSERT INTO submissions (id, kind, facility_id, course_id, payload, status,
                         submitted_by, reviewed_by, review_note, created_at, reviewed_at)
OVERRIDING SYSTEM VALUE VALUES
    (1, 'facility', 1, NULL,
     '{"schema_version": 1, "name": "Sandpiper Dunes Golf Resort", "country": "US", "city": "Lakeport"}',
     'approved', 2, 3, 'Matches website and state golf association listing.',
     '2025-03-10 14:02:00+00', '2025-03-11 09:30:00+00'),
    (2, 'course', 1, 1,
     '{"schema_version": 1, "course": {"name": "Dunes", "hole_count": 18}, "note": "full scorecard payload elided in seed"}',
     'approved', 2, 3, 'Cross-checked against scorecard photo.',
     '2025-03-12 10:15:00+00', '2025-03-14 16:45:00+00'),
    (3, 'course', 1, 1,
     '{"schema_version": 1, "correction": {"tee": "White", "hole": 7, "length": 158}, "note": "card reprinted for 2026"}',
     'pending', 2, NULL, NULL,
     '2026-06-28 08:00:00+00', NULL);

INSERT INTO submission_sources (submission_id, source_type, url, file_key, note, effective_date) VALUES
    (1, 'course_website',       'https://example.com/sandpiper-dunes', NULL, NULL, '2025-03-10'),
    (2, 'scorecard_image',      NULL, 'evidence/2025/03/dunes-scorecard-front.jpg', 'Front of printed card', '2025-04-01'),
    (2, 'scorecard_image',      NULL, 'evidence/2025/03/dunes-scorecard-back.jpg',  'Back of printed card',  '2025-04-01'),
    (2, 'rating_sticker_image', NULL, 'evidence/2025/03/dunes-rating-sticker.jpg',  'Sticker in pro shop',   '2024-05-01'),
    (3, 'scorecard_image',      NULL, 'evidence/2026/06/dunes-scorecard-2026.jpg',  '2026 reprint',          '2026-06-01');

-- Resync identity sequences after explicit-id inserts.
SELECT setval(pg_get_serial_sequence('users', 'id'),               (SELECT max(id) FROM users));
SELECT setval(pg_get_serial_sequence('facilities', 'id'),          (SELECT max(id) FROM facilities));
SELECT setval(pg_get_serial_sequence('courses', 'id'),             (SELECT max(id) FROM courses));
SELECT setval(pg_get_serial_sequence('tees', 'id'),                (SELECT max(id) FROM tees));
SELECT setval(pg_get_serial_sequence('course_combinations', 'id'), (SELECT max(id) FROM course_combinations));
SELECT setval(pg_get_serial_sequence('combination_tees', 'id'),    (SELECT max(id) FROM combination_tees));
SELECT setval(pg_get_serial_sequence('submissions', 'id'),         (SELECT max(id) FROM submissions));

COMMIT;

