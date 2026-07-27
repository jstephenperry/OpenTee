#!/usr/bin/env python3
"""Generate an OpenTee data SQL file from a JSON course dataset.

    python3 db/data/generate.py db/data/dfw_tx.json > db/data/dfw_tx.sql

The JSON is a list of facility objects (see dfw_tx.json for real examples):

    {
      "facility": {"name", "address", "city", "state_province", "country",
                   "postal_code", "website_url"},
      "courses": [{
        "name", "hole_count",
        "hole_names": [..] | null,
        "pars": {"men"|"women"|"unisex": {"par": [..], "stroke_index": [..] | null}},
        "tees": [{"name", "unit", "published_total", "lengths": [..] | null,
                  "ratings": [{"gender", "rating", "slope"}]}]
      }],
      "sources": [{"type", "url", "note"}]
    }

Every course is validated against the schema's own constraints before any SQL is
emitted; a course that fails validation is SKIPPED and reported on stderr rather
than silently producing data the database would reject or, worse, accept as true.
Tees whose per-hole lengths are unknown are emitted with their published total and
ratings only — v_tee_summaries then reports them incomplete, which is the honest
representation of "we have the tee sheet but not the card".
"""

import json
import re
import sys
from collections import Counter

# ---------------------------------------------------------------------------
# UUID allocation. Sequence numbers continue past the example seed (facilities
# 1-3, courses 1-6, tees 1-15, combos 1-4, combo tees 1-7, users 1-3,
# submissions 1-3) and arlington_tx.sql (facilities 4-7, courses 7-10,
# tees 16-27, users 4, submissions 4-7), so every data file can be loaded
# together or on its own.
# ---------------------------------------------------------------------------
TAGS = {"user": 1, "facility": 2, "course": 3, "tee": 4,
        "combo": 5, "combo_tee": 6, "submission": 7}
START = {"user": 5, "facility": 8, "course": 11, "tee": 28,
         "combo": 5, "combo_tee": 8, "submission": 8}

# Slugs already claimed by the example seed and arlington_tx.sql.
RESERVED_FACILITY_SLUGS = {
    "sandpiper-dunes-golf-resort", "trillium-creek-country-club", "wattle-flat-golf-club",
    "tierra-verde-golf-club", "texas-rangers-golf-club", "lake-arlington-golf-course",
    "meadowbrook-park-golf-course",
}

TEE_COLORS = {
    "black": "#1a1a1a", "blue": "#1e56a0", "white": "#f5f5f5", "red": "#c0392b",
    "gold": "#c9a227", "silver": "#c0c0c0", "green": "#2e7d32", "yellow": "#f1c40f",
    "bronze": "#cd7f32", "burgundy": "#7b1f2b", "orange": "#e67e22", "purple": "#6c3483",
    "copper": "#b87333", "maroon": "#800000", "navy": "#1a2a5e", "teal": "#128277",
    "pink": "#e88ca0", "grey": "#808080", "gray": "#808080", "brown": "#795548",
}

GENDERS = ("men", "women", "unisex")


class Counters:
    def __init__(self):
        self.next = dict(START)

    def take(self, tag):
        n = self.next[tag]
        self.next[tag] += 1
        return n


def uuid_literal(tag, n):
    return f"'00000000-0000-4000-8000-{TAGS[tag]:04d}{n:08d}'"


def slugify(name, used):
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    slug = re.sub(r"-+", "-", slug)[:120].strip("-")
    if not slug:
        slug = "course"
    base, i = slug, 2
    while slug in used:
        slug = f"{base}-{i}"
        i += 1
    used.add(slug)
    return slug


def q(value):
    """SQL literal for a nullable string."""
    if value is None or value == "":
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


# ---------------------------------------------------------------------------
# Validation — mirrors the schema's CHECK constraints plus golf-domain sanity.
# ---------------------------------------------------------------------------
def validate_course(facility_name, course, problems, warnings):
    """Returns True if the course is safe to emit."""
    where = f"{facility_name} / {course.get('name', '?')}"
    ok = True

    holes = course.get("hole_count")
    if not isinstance(holes, int) or not 1 <= holes <= 27:
        problems.append(f"{where}: hole_count {holes!r} outside 1-27")
        return False

    names = course.get("hole_names")
    if names is not None and len(names) != holes:
        warnings.append(f"{where}: {len(names)} hole names for {holes} holes — dropping names")
        course["hole_names"] = None

    pars = course.get("pars") or {}
    if not pars:
        problems.append(f"{where}: no par data")
        return False
    for gender, block in list(pars.items()):
        if gender not in GENDERS:
            problems.append(f"{where}: unknown par gender {gender!r}")
            ok = False
            continue
        par_list = block.get("par") or []
        if len(par_list) != holes:
            problems.append(f"{where}: {gender} par has {len(par_list)} values for {holes} holes")
            ok = False
            continue
        if any(not isinstance(p, int) or not 3 <= p <= 7 for p in par_list):
            problems.append(f"{where}: {gender} par values outside 3-7: {par_list}")
            ok = False
        total_par = sum(par_list)
        expected = (27, 80) if holes > 9 else (25, 40)
        if not expected[0] <= total_par <= expected[1]:
            warnings.append(f"{where}: {gender} par total {total_par} is unusual for {holes} holes")

        si = block.get("stroke_index")
        if si is not None:
            if len(si) != holes:
                warnings.append(f"{where}: {gender} stroke index has {len(si)} values for {holes} holes — dropping")
                block["stroke_index"] = None
            elif any(not isinstance(s, int) or not 1 <= s <= 18 for s in si):
                warnings.append(f"{where}: {gender} stroke index outside 1-18 — dropping")
                block["stroke_index"] = None
            else:
                dupes = [v for v, c in Counter(si).items() if c > 1]
                if dupes:
                    warnings.append(f"{where}: {gender} stroke index repeats {dupes} (kept: archived as published)")

    tees = course.get("tees") or []
    if not tees:
        problems.append(f"{where}: no tees")
        return False
    seen_names = set()
    for tee in tees:
        name = tee.get("name")
        if not name:
            problems.append(f"{where}: tee with no name")
            ok = False
            continue
        if name.lower() in seen_names:
            problems.append(f"{where}: duplicate tee name {name!r}")
            ok = False
        seen_names.add(name.lower())

        if tee.get("unit") not in ("yards", "meters"):
            tee["unit"] = "yards"

        lengths = tee.get("lengths")
        if lengths is not None:
            if len(lengths) != holes:
                warnings.append(f"{where} [{name}]: {len(lengths)} lengths for {holes} holes — storing tee without per-hole data")
                tee["lengths"] = None
            elif any(not isinstance(v, int) or not 20 <= v <= 1500 for v in lengths):
                warnings.append(f"{where} [{name}]: length outside 20-1500 — storing tee without per-hole data")
                tee["lengths"] = None

        total = tee.get("published_total")
        if total is not None and not 100 <= total <= 20000:
            warnings.append(f"{where} [{name}]: published total {total} implausible — dropping")
            tee["published_total"] = None
        if tee.get("lengths") and tee.get("published_total"):
            computed = sum(tee["lengths"])
            if computed != tee["published_total"]:
                warnings.append(
                    f"{where} [{name}]: per-hole sum {computed} != published total "
                    f"{tee['published_total']} (kept: surfaces via has_total_discrepancy)")

        for r in tee.get("ratings") or []:
            if r.get("gender") not in ("men", "women"):
                problems.append(f"{where} [{name}]: rating gender {r.get('gender')!r}")
                ok = False
            if not 15 <= float(r.get("rating", 0)) <= 90:
                problems.append(f"{where} [{name}]: course rating {r.get('rating')} outside 15-90")
                ok = False
            if not 55 <= int(r.get("slope", 0)) <= 155:
                problems.append(f"{where} [{name}]: slope {r.get('slope')} outside 55-155")
                ok = False

    if not any(t.get("lengths") for t in tees):
        warnings.append(f"{where}: no tee has per-hole lengths — course is discovery-only")
    return ok


# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------
def generate(dataset, title, description, date):
    counters = Counters()
    facility_slugs = set(RESERVED_FACILITY_SLUGS)
    problems, warnings = [], []

    facilities, courses, holes, pars = [], [], [], []
    tees, ratings, lengths, submissions, sources = [], [], [], [], []
    stats = Counter()

    for entry in dataset:
        f = entry["facility"]
        valid_courses = []
        for course in entry.get("courses", []):
            if validate_course(f["name"], course, problems, warnings):
                valid_courses.append(course)
            else:
                stats["courses_skipped"] += 1
        if not valid_courses:
            continue

        fn = counters.take("facility")
        fslug = slugify(f["name"], facility_slugs)
        facilities.append((fn, fslug, f))
        stats["facilities"] += 1

        course_slugs = set()
        for course in valid_courses:
            cn = counters.take("course")
            cslug = slugify(course["name"], course_slugs)
            hole_count = course["hole_count"]
            courses.append((cn, fn, cslug, course["name"], hole_count))
            stats["courses"] += 1

            hole_names = course.get("hole_names")
            for i in range(1, hole_count + 1):
                holes.append((cn, i, hole_names[i - 1] if hole_names else None))

            for gender, block in course["pars"].items():
                si = block.get("stroke_index")
                for i, par in enumerate(block["par"], 1):
                    pars.append((cn, i, gender, par, si[i - 1] if si else None))

            for order, tee in enumerate(course["tees"], 1):
                tn = counters.take("tee")
                colour = TEE_COLORS.get(tee["name"].strip().lower())
                tees.append((tn, cn, tee["name"], colour, tee["unit"], order, tee.get("published_total")))
                stats["tees"] += 1
                for r in tee.get("ratings") or []:
                    ratings.append((tn, r["gender"], r["rating"], r["slope"]))
                    stats["ratings"] += 1
                if tee.get("lengths"):
                    stats["tees_with_holes"] += 1
                    for i, L in enumerate(tee["lengths"], 1):
                        lengths.append((tn, cn, i, L))
                        stats["hole_lengths"] += 1

        sn = counters.take("submission")
        first_course = next(c for c in courses if c[1] == fn)
        payload = {
            "schema_version": 1,
            "import": "web",
            "facility": f["name"],
            "courses": [c["name"] for c in valid_courses],
        }
        submissions.append((sn, fn, first_course[0], json.dumps(payload)))
        for s in entry.get("sources", []):
            sources.append((sn, s.get("type", "other"), s.get("url"), s.get("note")))

    out = []
    w = out.append

    w(f"""-- ============================================================================
-- OpenTee data: {title}
--
-- {description}
--
-- GENERATED FILE — do not hand-edit. Regenerate with:
--     python3 db/data/generate.py db/data/{title.split(':')[0].strip().lower().replace(' ', '_')}.json
--
-- PROVENANCE: transcribed {date} from public web sources; every facility carries
-- an approved submission with its source URLs. Per-hole values were validated
-- against the schema's constraints and, where the source published a total,
-- reconciled against it (mismatches are kept and surface through
-- v_tee_summaries.has_total_discrepancy). None of this has been verified
-- against an official printed card in hand — treat as community data awaiting
-- verification. Tees with published totals but no published per-hole card are
-- stored without hole lengths and read as incomplete by design.
--
-- Loads standalone or alongside db/seed/example_seed.sql and the other
-- db/data/*.sql files (UUID ranges and slugs are disjoint).
-- ============================================================================

BEGIN;

-- Import identity for attribution of these submissions.
INSERT INTO users (id, email, display_name, role) VALUES
    ({uuid_literal('user', 5)}, 'dfw-import@opentee.example', 'dfw-import', 'moderator');
""")

    w("-- ------------------------------------------------------------ facilities")
    w("""INSERT INTO facilities (id, slug, name, address, city, state_province, country,
                        postal_code, website_url) VALUES""")
    rows = []
    for (fn, fslug, f) in facilities:
        rows.append(
            f"    ({uuid_literal('facility', fn)}, {q(fslug)}, {q(f['name'])}, {q(f.get('address'))}, "
            f"{q(f.get('city'))}, {q(f.get('state_province', 'Texas'))}, {q(f.get('country', 'US'))}, "
            f"{q(f.get('postal_code'))}, {q(f.get('website_url'))})")
    w(",\n".join(rows) + ";\n")

    w("-- --------------------------------------------------------------- courses")
    w("INSERT INTO courses (id, facility_id, slug, name, hole_count) VALUES")
    rows = [f"    ({uuid_literal('course', cn)}, {uuid_literal('facility', fn)}, {q(slug)}, {q(name)}, {hc})"
            for (cn, fn, slug, name, hc) in courses]
    w(",\n".join(rows) + ";\n")

    w("-- ----------------------------------------------------------------- holes")
    w("INSERT INTO holes (course_id, hole_number, name) VALUES")
    rows = [f"    ({uuid_literal('course', cn)}, {i:>2}, {q(name)})" for (cn, i, name) in holes]
    w(",\n".join(rows) + ";\n")

    w("""-- ------------------------------------------------------------- hole_pars
-- Cards that publish separate men's and women's par/handicap rows get both;
-- cards with a single undifferentiated row are stored as 'unisex'.""")
    w("INSERT INTO hole_pars (course_id, hole_number, gender, par, stroke_index) VALUES")
    rows = [f"    ({uuid_literal('course', cn)}, {i:>2}, {q(g)}, {par}, "
            f"{si if si is not None else 'NULL'})" for (cn, i, g, par, si) in pars]
    w(",\n".join(rows) + ";\n")

    w("""-- ------------------------------------------------------------------ tees
-- Tee colour hexes are display defaults derived from the tee name, not
-- published data. published_total_length is the figure the source printed.""")
    w("""INSERT INTO tees (id, course_id, name, color_name, color_hex,
                  unit, display_order, published_total_length) VALUES""")
    rows = []
    for (tn, cn, name, colour, unit, order, total) in tees:
        colour_name = q(name) if colour else "NULL"
        rows.append(f"    ({uuid_literal('tee', tn)}, {uuid_literal('course', cn)}, {q(name)}, "
                    f"{colour_name}, {q(colour)}, {q(unit)}, {order}, "
                    f"{total if total is not None else 'NULL'})")
    w(",\n".join(rows) + ";\n")

    if ratings:
        w("""-- ----------------------------------------------------------- tee_ratings
-- USGA/WHS Course Rating and Slope per tee per gender, as published. Tees with
-- no published rating (par-3 courses, unrated forward tees) simply have no row.
-- Front/back-nine splits and bogey ratings are not published by these sources.""")
        w("INSERT INTO tee_ratings (tee_id, gender, course_rating, slope_rating) VALUES")
        rows = [f"    ({uuid_literal('tee', tn)}, {q(g)}, {rating}, {slope})"
                for (tn, g, rating, slope) in ratings]
        w(",\n".join(rows) + ";\n")

    w("-- ----------------------------------------------------- tee_hole_lengths")
    w("INSERT INTO tee_hole_lengths (tee_id, course_id, hole_number, length) VALUES")
    rows = [f"    ({uuid_literal('tee', tn)}, {uuid_literal('course', cn)}, {i:>2}, {L})"
            for (tn, cn, i, L) in lengths]
    w(",\n".join(rows) + ";\n")

    w(f"""-- ------------------------------------------------------------ submissions
-- One approved submission per facility records what was imported and from
-- where. Corrections (transcribing an official card, adding a missing tee)
-- should arrive as new submissions superseding these.
INSERT INTO submissions (id, kind, facility_id, course_id, payload, status,
                         submitted_by, reviewed_by, review_note, created_at, reviewed_at) VALUES""")
    rows = []
    for (sn, fn, cn, payload) in submissions:
        rows.append(
            f"""    ({uuid_literal('submission', sn)}, 'course', {uuid_literal('facility', fn)}, {uuid_literal('course', cn)},
     {q(payload)},
     'approved', {uuid_literal('user', 5)}, {uuid_literal('user', 5)},
     'Imported from public web sources on {date}; awaiting verification against the official printed scorecard.',
     '{date} 00:00:00+00', '{date} 00:00:00+00')""")
    w(",\n".join(rows) + ";\n")

    if sources:
        w("INSERT INTO submission_sources (submission_id, source_type, url, note, effective_date) VALUES")
        rows = []
        for (sn, stype, url, note) in sources:
            if stype not in ("scorecard_image", "rating_sticker_image", "course_website",
                             "official_rating_db", "in_person", "other"):
                stype = "other"
            if not url and not note:
                continue
            rows.append(f"    ({uuid_literal('submission', sn)}, {q(stype)}, {q(url)},\n"
                        f"     {q(note)}, '{date}')")
        w(",\n".join(rows) + ";\n")

    w("COMMIT;")

    return "\n".join(out), stats, problems, warnings


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: generate.py <dataset.json>")
    with open(sys.argv[1]) as fh:
        doc = json.load(fh)

    dataset = doc["facilities"] if isinstance(doc, dict) else doc
    meta = doc if isinstance(doc, dict) else {}
    sql, stats, problems, warnings = generate(
        dataset,
        meta.get("title", "course data"),
        meta.get("description", ""),
        meta.get("date", "2026-07-27"),
    )
    print(sql)

    for p in problems:
        print(f"SKIPPED  {p}", file=sys.stderr)
    for wn in warnings:
        print(f"warning  {wn}", file=sys.stderr)
    print(f"\n{dict(stats)}", file=sys.stderr)


if __name__ == "__main__":
    main()
