#!/usr/bin/env python3
"""Export the OpenTee database to the static JSON the web frontend reads.

The website is a static site (GitHub Pages), so it cannot query PostgreSQL.
This script is the one bridge between the two: it reads the canonical schema
through its own read-path views (``v_scorecards`` totals policy lives in
``v_tee_summaries``, so completeness and OUT/IN here mean exactly what they
mean in the database) and writes:

    web/data/index.json              -- one small record per course, for search
    web/data/courses/<key>.json      -- everything needed to print one card

Usage:

    createdb opentee_dev
    psql -d opentee_dev -f db/schema.sql
    psql -d opentee_dev -f db/data/arlington_tx.sql
    psql -d opentee_dev -f db/data/dfw_tx.sql
    python3 web/export.py --database opentee_dev

Only ``psql`` is required -- no Python database driver -- so this runs
anywhere the rest of the pipeline already runs.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_OUT = HERE / "data"

# One JSON document per active course. Everything the card needs is assembled
# server-side so the browser never has to join anything.
COURSE_QUERY = r"""
SELECT json_build_object(
    'key', CASE WHEN cnt.n = 1 THEN f.slug ELSE f.slug || '--' || c.slug END,
    'course', json_build_object(
        'slug', c.slug,
        'name', c.name,
        'holeCount', c.hole_count
    ),
    'facility', json_build_object(
        'slug', f.slug,
        'name', f.name,
        'address', f.address,
        'city', f.city,
        'state', f.state_province,
        'postalCode', f.postal_code,
        'country', f.country,
        'website', f.website_url
    ),
    'holes', (
        SELECT json_agg(json_build_object(
            'number', h.hole_number,
            'name', h.name,
            'parMen', pm.par, 'siMen', pm.stroke_index,
            'parWomen', pw.par, 'siWomen', pw.stroke_index,
            'parUnisex', pu.par, 'siUnisex', pu.stroke_index
        ) ORDER BY h.hole_number)
        FROM holes h
        LEFT JOIN hole_pars pm ON pm.course_id = c.id AND pm.hole_number = h.hole_number AND pm.gender = 'men'
        LEFT JOIN hole_pars pw ON pw.course_id = c.id AND pw.hole_number = h.hole_number AND pw.gender = 'women'
        LEFT JOIN hole_pars pu ON pu.course_id = c.id AND pu.hole_number = h.hole_number AND pu.gender = 'unisex'
        WHERE h.course_id = c.id
    ),
    'tees', (
        SELECT json_agg(json_build_object(
            'name', t.name,
            'color', t.color_hex,
            'secondaryColor', t.secondary_color_hex,
            'unit', t.unit,
            'isCombination', t.is_combination,
            'isComplete', ts.is_complete,
            'total', ts.computed_total_length,
            'out', ts.out_length,
            'in', ts.in_length,
            'publishedTotal', ts.published_total_length,
            'hasTotalDiscrepancy', ts.has_total_discrepancy,
            'ratings', COALESCE((
                SELECT json_agg(json_build_object(
                    'gender', tr.gender,
                    'rating', tr.course_rating,
                    'slope', tr.slope_rating,
                    'frontRating', tr.front_nine_rating, 'frontSlope', tr.front_nine_slope,
                    'backRating', tr.back_nine_rating, 'backSlope', tr.back_nine_slope
                ) ORDER BY tr.gender)
                FROM tee_ratings tr WHERE tr.tee_id = t.id
            ), '[]'::json),
            -- Lengths in hole order, NULL where the course has not published
            -- a per-hole number. Positional, so the client indexes straight
            -- into it with the hole's ordinal.
            'lengths', (
                SELECT json_agg(thl.length ORDER BY h2.hole_number)
                FROM holes h2
                LEFT JOIN tee_hole_lengths thl ON thl.tee_id = t.id AND thl.hole_number = h2.hole_number
                WHERE h2.course_id = c.id
            )
        ) ORDER BY t.display_order, t.name)
        FROM tees t
        JOIN v_tee_summaries ts ON ts.tee_id = t.id
        WHERE t.course_id = c.id
    ),
    -- Evidence behind the approved data, so every card can show its receipts.
    'sources', COALESCE((
        SELECT json_agg(json_build_object(
            'type', d.source_type,
            'url', d.url,
            'note', d.note,
            'effectiveDate', d.effective_date
        ) ORDER BY d.source_type, d.url)
        FROM (
            SELECT DISTINCT ss.source_type, ss.url, ss.note, ss.effective_date
            FROM submissions s
            JOIN submission_sources ss ON ss.submission_id = s.id
            WHERE s.status = 'approved'
              AND (s.course_id = c.id OR (s.course_id IS NULL AND s.facility_id = f.id))
        ) d
    ), '[]'::json)
)::text
FROM courses c
JOIN facilities f ON f.id = c.facility_id
CROSS JOIN LATERAL (
    SELECT count(*)::int AS n FROM courses c2
    WHERE c2.facility_id = f.id AND c2.status = 'active'
) cnt
WHERE c.status = 'active' AND f.status = 'active'
ORDER BY f.name, c.name;
"""


def run_psql(database: str, sql: str) -> list[str]:
    """Run a query with psql and return its rows (unaligned, tuples only)."""
    psql = shutil.which("psql")
    if psql is None:
        sys.exit("psql not found on PATH; PostgreSQL client tools are required")
    cmd = [psql, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-d", database, "-c", sql]
    proc = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ})
    if proc.returncode != 0:
        sys.exit(f"psql failed:\n{proc.stderr.strip()}")
    return [line for line in proc.stdout.splitlines() if line.strip()]


def summarise(course: dict) -> dict:
    """The small record the search page loads for every course at once."""
    tees = course["tees"] or []
    complete = [t for t in tees if t["isComplete"]]
    lengths = [t["total"] for t in complete if t["total"] is not None]
    ratings = [r for t in tees for r in t["ratings"]]
    facility = course["facility"]
    return {
        "key": course["key"],
        "name": course["course"]["name"],
        "facility": facility["name"],
        "city": facility["city"],
        "state": facility["state"],
        "country": facility["country"],
        "holeCount": course["course"]["holeCount"],
        "teeCount": len(tees),
        "completeTees": len(complete),
        "unit": complete[0]["unit"] if complete else (tees[0]["unit"] if tees else None),
        "maxLength": max(lengths) if lengths else None,
        "minLength": min(lengths) if lengths else None,
        "par": course_par(course),
        "rated": bool(ratings),
    }


def course_par(course: dict) -> int | None:
    """Total par as printed: the men's/unisex row if there is one, else women's."""
    for field in ("parMen", "parUnisex", "parWomen"):
        values = [h[field] for h in course["holes"] or []]
        if values and all(v is not None for v in values):
            return sum(values)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default=os.environ.get("PGDATABASE", "opentee_dev"),
                        help="database name or connection string (default: $PGDATABASE or opentee_dev)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"output directory (default: {DEFAULT_OUT})")
    args = parser.parse_args()

    courses = [json.loads(line) for line in run_psql(args.database, COURSE_QUERY)]
    if not courses:
        sys.exit("no active courses found — is the database loaded?")

    keys = [c["key"] for c in courses]
    duplicates = {k for k in keys if keys.count(k) > 1}
    if duplicates:
        sys.exit(f"course keys are not unique, refusing to write: {sorted(duplicates)}")

    courses_dir = args.out / "courses"
    if courses_dir.exists():
        shutil.rmtree(courses_dir)
    courses_dir.mkdir(parents=True)

    for course in courses:
        path = courses_dir / f"{course['key']}.json"
        path.write_text(json.dumps(course, separators=(",", ":"), sort_keys=False) + "\n")

    summaries = [summarise(c) for c in courses]
    index = {
        "stats": {
            "facilities": len({c["facility"]["slug"] for c in courses}),
            "courses": len(courses),
            "tees": sum(len(c["tees"] or []) for c in courses),
            "cities": len({(c["facility"]["city"], c["facility"]["state"]) for c in courses
                           if c["facility"]["city"]}),
            "holeLengths": sum(1 for c in courses for t in (c["tees"] or [])
                               for length in (t["lengths"] or []) if length is not None),
        },
        "courses": sorted(summaries, key=lambda s: (s["facility"].lower(), s["name"].lower())),
    }
    (args.out / "index.json").write_text(
        json.dumps(index, separators=(",", ":")) + "\n")

    stats = index["stats"]
    print(f"wrote {stats['courses']} courses / {stats['facilities']} facilities "
          f"/ {stats['tees']} tees to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
