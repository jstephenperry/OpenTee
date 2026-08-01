# OpenTee website

A static site — no framework, no build step, no runtime dependencies — that lets anyone
search the database, pick the tees they play, and print a clean scorecard.

| Path | Contents |
| --- | --- |
| `index.html` | Search and browse every course |
| `course.html` | Tee picker, live card preview, print |
| `about.html` | How the data is made and what its limits are |
| `assets/card.js` | Card layout rules — the web twin of `app/OpenTee.Scorecard/CardBuilder.cs` |
| `assets/styles.css` | Everything visual, including the print stylesheet |
| `export.py` | Database → `data/*.json` |
| `data/` | Generated; not committed |

## Build and preview locally

The site reads JSON exported from a loaded database, so build that first:

```bash
createdb opentee_dev
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/schema.sql
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/data/arlington_tx.sql
psql -v ON_ERROR_STOP=1 -d opentee_dev -f db/data/dfw_tx.sql

python3 web/export.py --database opentee_dev
python3 -m http.server 8000 --directory web    # then open http://localhost:8000
```

`export.py` shells out to `psql`; there is no Python database driver to install. Loading
`db/seed/example_seed.sql` as well is fine locally — its fictional courses will simply show
up in the site alongside the real ones.

## How it is published

`.github/workflows/pages.yml` does exactly the above on GitHub Actions — spins up
PostgreSQL 16, loads `db/schema.sql` and the data files, runs `export.py`, and deploys
`web/` to GitHub Pages. Nothing derived is committed, so the published site can never
disagree with `db/`.

## Design notes

- **The database decides what is printable.** Completeness, OUT/IN totals and
  published-vs-computed discrepancies all come from `v_tee_summaries`, not from arithmetic
  invented here. A tee without a full per-hole card cannot be selected, and says why.
- **Missing stays missing.** No inferred pars, no averaged ratings, no tee colour guessed
  from a tee's name — a tee with no `color_hex` gets a hatched swatch, not a plausible one.
- **Printing is the point.** `@media print` drops the site chrome and lays the card out on
  landscape Letter; the blank player rows are sized to write in.
- **URLs carry state.** `course.html?c=<key>&tees=Blue~White&rows=2` reproduces a card
  exactly, so a foursome can share one link.
