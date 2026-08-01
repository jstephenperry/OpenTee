// Turns a course document into the row/column layout of a printed card:
// holes as columns (with OUT/IN/TOT on 18-hole courses), one row per selected
// tee, then par and stroke-index rows for each gender the course publishes.
//
// This is the web twin of app/OpenTee.Scorecard/CardBuilder.cs, and follows the
// same rules on purpose: the printed card, the desktop card and this one should
// never disagree about what a course's data says.

/** Column headings: hole numbers with OUT/IN/TOT inserted where they belong. */
export function columnLabels(course) {
  const split = course.course.holeCount === 18;
  const labels = [];
  for (const hole of course.holes) {
    if (split && hole.number === 10) labels.push('OUT');
    labels.push(String(hole.number));
  }
  if (split) labels.push('IN');
  labels.push('TOT');
  return labels;
}

const GENDER_ROWS = [
  { par: 'parUnisex', si: 'siUnisex', parLabel: 'PAR', siLabel: 'HCP' },
  { par: 'parMen', si: 'siMen', parLabel: 'PAR', siLabel: 'HCP' },
  { par: 'parWomen', si: 'siWomen', parLabel: 'PAR (W)', siLabel: 'HCP (W)' },
];

/**
 * Build the card's rows.
 * @param course  the course document as exported by web/export.py
 * @param tees    the selected tees, in display order
 * @param opts    { scoreRows: number, showNames: boolean }
 */
export function buildRows(course, tees, opts = {}) {
  const { scoreRows = 0, showNames = true } = opts;
  const holes = course.holes;
  const split = course.course.holeCount === 18;
  const rows = [{ kind: 'header', label: 'HOLE', cells: columnLabels(course) }];

  // Hole names go in whole: no column is wide enough for one, so the cell
  // clips with an ellipsis and keeps the full name in its tooltip.
  if (showNames && holes.some((h) => h.name)) {
    rows.push(row('names', 'NAME', null, (h) => h.name ?? '', null));
  }

  for (const tee of tees) {
    // Lengths are positional against this course's holes, so key them by hole
    // number rather than assuming holes run 1..n with no gaps.
    const byHole = new Map(holes.map((h, i) => [h.number, tee.lengths?.[i] ?? null]));
    const at = (h) => byHole.get(h.number) ?? null;
    rows.push(row('tee', tee.name.toUpperCase(), tee.color, at, sum(at)));
  }

  for (const g of GENDER_ROWS) {
    const par = (h) => h[g.par];
    const si = (h) => h[g.si];
    if (holes.some((h) => par(h) !== null && par(h) !== undefined)) {
      rows.push(row('par', g.parLabel, null, par, sum(par)));
    }
    if (holes.some((h) => si(h) !== null && si(h) !== undefined)) {
      rows.push(row('si', g.siLabel, null, si, null));
    }
  }

  for (let i = 1; i <= scoreRows; i++) {
    rows.push(row('score', `PLAYER ${i}`, null, () => '', () => ''));
  }

  return rows;

  /** One row: a label plus a cell per column, totals filled in where asked. */
  function row(kind, label, color, cell, total) {
    const cells = [];
    const front = holes.filter((h) => h.number <= 9);
    const back = holes.filter((h) => h.number > 9);
    for (const hole of holes) {
      if (split && hole.number === 10) cells.push(total ? total(front) : '');
      cells.push(text(cell(hole)));
    }
    if (split) cells.push(total ? total(back) : '');
    cells.push(total ? total(holes) : '');
    return { kind, label, color, cells };
  }

  /** Totals ignore holes with no published number, the way a card would. */
  function sum(pick) {
    return (subset) => {
      const values = subset.map(pick).filter((v) => typeof v === 'number');
      return values.length ? String(values.reduce((a, b) => a + b, 0)) : '';
    };
  }
}

function text(value) {
  if (value === null || value === undefined) return '';
  return String(value);
}

/** "All lengths in yards." — or per-tee when a course mixes units. */
export function unitNote(tees) {
  const units = [...new Set(tees.map((t) => t.unit))];
  if (units.length === 0) return '';
  if (units.length === 1) return `All lengths in ${units[0]}.`;
  return `${tees.map((t) => `${t.name}: ${t.unit}`).join('; ')}.`;
}

/**
 * The footer's rating line, one entry per selected tee that has published
 * ratings — kept as parts so the page can space them apart properly.
 */
export function ratingsParts(tees) {
  const rated = tees.filter((t) => t.ratings.length > 0);
  if (rated.length === 0) return ['No published course rating.'];
  return rated.map((t) =>
    `${t.name}: ${t.ratings.map((r) => `${genderLabel(r.gender)} ${r.rating}/${r.slope}`).join(' · ')}`);
}

export function genderLabel(gender) {
  return { men: 'Men', women: 'Women', unisex: 'Rating' }[gender] ?? gender;
}

export function shortGenderLabel(gender) {
  return { men: 'M', women: 'W', unisex: 'U' }[gender] ?? gender;
}

/** A tee's one-line summary: total, unit and ratings, or why it can't print. */
export function teeSummary(tee) {
  if (!tee.isComplete) return 'incomplete — per-hole data not yet in the database';
  const ratings = tee.ratings.length
    ? tee.ratings.map((r) => `${shortGenderLabel(r.gender)} ${r.rating}/${r.slope}`).join(' · ')
    : 'unrated';
  return `${tee.total.toLocaleString()} ${tee.unit} · ${ratings}`;
}
