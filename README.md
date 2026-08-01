# OpenTee

An open, community-contributed database of golf course scorecard data — yardages, pars,
stroke indexes, and ratings per tee, **as published by courses**.

Course websites bury scorecard data in PDFs and third-party booking widgets, and it
disappears when sites are redesigned. OpenTee aims to be the central single source of
truth: look up any course's tee-by-tee data, and print a clean custom scorecard for
exactly the tees you play.

## What can it represent?

The schema is built around how golf data actually works, including the awkward cases:

- **One physical tee, per-gender ratings.** The same White tees rated 69.4/125 for men
  and 74.6/133 for women are one set of yardages with two rating rows — never entered
  twice.
- **Per-gender par and stroke index**, the way real cards print them (men's par 4 can be
  women's par 5 on the same hole) — plus `unisex` for cards with a single row.
- **Yards and meters**, stored verbatim in whichever unit the course publishes.
- **Unrated courses.** Par-3 and executive courses without ratings are first-class
  citizens; a missing rating is a missing row, never a fake number.
- **27-hole clubs and nines played twice.** North/South-style pairings and "White out,
  Yellow in" 18-hole cards are combinations over the underlying nines — shared holes are
  stored exactly once, so a correction propagates everywhere.
- **Combo tees** ("Blue/White") with per-hole provenance, hole names, tee colors and
  printed order, front/back-nine ratings, published-vs-computed total reconciliation.
- **Community submissions.** Scorecards enter through an atomic submission + moderation
  pipeline with photo/URL evidence and effective dates; canonical tables only ever hold
  approved data, and every fact is attributable and revertible.

## Repository layout

| Path | Contents |
| --- | --- |
| `db/schema.sql` | Canonical PostgreSQL 16 schema (documented inline) |
| `db/seed/example_seed.sql` | Fictional demo data exercising every schema feature |
| `db/data/arlington_tx.sql` | Real course data: Arlington, TX public courses, transcribed from cited public sources (awaiting verification against official cards) |
| `db/data/dfw_tx.sql` | Real course data: 97 public facilities / 120 courses across the Dallas-Fort Worth Metroplex |
| `db/data/collected/` | Raw harvested scorecard JSON, kept exactly as collected |
| `db/data/corrections.json` | Documented corrections applied to the raw data, each with its evidence |
| `db/data/generate.py`, `normalize.py` | Validating pipeline: harvested JSON → schema-conformant SQL |
| `db/tests/constraint_tests.sql` | Self-rolling-back test suite for the integrity rails |
| `app/OpenTee.Scorecard/` | Avalonia desktop app: search courses, pick tees, print custom scorecards |
| `web/` | The website (GitHub Pages): static search, tee picker and printable card |
| `docs/schema-design.md` | Full design rationale, ERD, decisions, example queries |

## Quick start

Requires PostgreSQL 16+ (uses the bundled `pg_trgm` extension).

```bash
createdb opentee_dev
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/schema.sql
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/seed/example_seed.sql   # fictional demo data
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/data/arlington_tx.sql   # real courses
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/data/dfw_tx.sql         # real courses
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/tests/constraint_tests.sql
```

## Course data

The `db/data/` files hold real, cited course data for the Dallas-Fort Worth Metroplex —
**101 public facilities, 124 courses, 7,000+ per-hole yardages**. They load in any
combination alongside the fictional example seed.

How the data is produced, and why it is trustworthy:

1. **Discovery** enumerated every public course in the metro area, recording the ones it
   *rejected* and why (`db/data/dfw_courses.json`), so stale directory listings for closed
   or private courses cannot creep back in.
2. **Collection** transcribed published scorecards, under a standing rule never to invent a
   number. A tee whose per-hole card is not published is stored with its total only and
   reads as incomplete — that is the honest answer, and the schema is built to express it.
3. **Normalization and generation** (`normalize.py` → `generate.py`) validate every course
   against the schema's own constraints plus golf-domain sanity, and refuse to emit anything
   inconsistent.
4. **Verification** adversarially re-checked a sample against the published cards, trying to
   refute rather than confirm. Its corrections live in `corrections.json` with the evidence
   for each, applied on top of the untouched raw harvest in `collected/`.

So every value in the database traces to either a cited source or a documented correction.
Nothing here has been checked against an official printed card in hand, so it is community
data awaiting verification — which is exactly what the submission model in the schema is for.

To regenerate after editing the raw data or corrections:

```bash
python3 db/data/normalize.py db/data/collected/*.json > db/data/dfw_tx.json
python3 db/data/generate.py db/data/dfw_tx.json > db/data/dfw_tx.sql
```

Then print your first scorecard:

```sql
SELECT hole_number, hole_name, tee_name, length, par_men, stroke_index_men
FROM v_scorecards
WHERE course_slug = 'dunes'
ORDER BY hole_number, display_order;
```

See [docs/schema-design.md](docs/schema-design.md) for the entity model and more
involved queries (custom tee subsets, 27-hole combination cards, fuzzy dedupe search).

## Scorecard app

`app/OpenTee.Scorecard` is a cross-platform Avalonia desktop app (.NET 8) that
searches the database, lets you pick a course and any subset of its tees, previews
the card, and produces a print-ready PDF (landscape Letter) with per-hole yardages,
par and stroke-index rows per published gender, OUT/IN/TOT columns, blank player
rows, and the ratings/unit footer. Avalonia has no cross-platform print API, so
"print" hands the PDF to your viewer's print dialog. Incomplete tees (per-hole data
not yet in the database) are shown but not printable.

```bash
cd app/OpenTee.Scorecard
export OPENTEE_DB="Host=localhost;Database=opentee_dev;Username=postgres"  # default
dotnet run                                        # the GUI
dotnet run -- --pdf texas-rangers                 # headless: PDF for a course slug
dotnet run -- --pdf dunes --tees Blue,White,Red   # headless: custom tee subset
```

## Website

**<https://jstephenperry.github.io/OpenTee/>** — search every course, tick the tees you
play, print the card. It is a static site with no framework and no build step: the pages
are plain HTML/CSS/ES modules, and the data they read is exported straight out of the
schema's own views by `web/export.py`.

Nothing derived is committed. `.github/workflows/pages.yml` loads `db/schema.sql` and the
data files into a real PostgreSQL on every push, exports the JSON, and deploys `web/` to
GitHub Pages — so the site cannot drift from `db/`. Publishing needs Pages switched on
once under Settings → Pages → Source: GitHub Actions; a workflow token is not permitted to
do that itself. To run it locally:

```bash
python3 web/export.py --database opentee_dev
python3 -m http.server 8000 --directory web       # http://localhost:8000
```

Card layout, completeness rules and the ratings footer follow the desktop app's
`CardBuilder` exactly, so the two never disagree about what the data says. See
[web/README.md](web/README.md).

## Status

Early days: the database schema is designed, validated, and tested; a desktop app and a
published website cover the primary read path; the community submission API is not built
yet. Contributions and design feedback are welcome.

## License

[AGPL-3.0](LICENSE).
