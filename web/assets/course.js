// Course page: pick tees, see the card that will print, print it.

import { loadCourse, place, courseTitle, formatNumber } from './data.js';
import { buildRows, unitNote, ratingsParts, teeSummary } from './card.js';

const els = {
  loading: document.getElementById('loading'),
  error: document.getElementById('error'),
  course: document.getElementById('course'),
  title: document.getElementById('title'),
  meta: document.getElementById('meta'),
  links: document.getElementById('links'),
  tees: document.getElementById('tees'),
  scoreRows: document.getElementById('scoreRows'),
  showNames: document.getElementById('showNames'),
  print: document.getElementById('print'),
  share: document.getElementById('share'),
  sheet: document.getElementById('sheet'),
  sheetTitle: document.getElementById('sheetTitle'),
  sheetSub: document.getElementById('sheetSub'),
  table: document.getElementById('table'),
  ratingsNote: document.getElementById('ratingsNote'),
  unitNote: document.getElementById('unitNote'),
  discrepancyNote: document.getElementById('discrepancyNote'),
  provenanceNote: document.getElementById('provenanceNote'),
  empty: document.getElementById('empty'),
  sourcesBlock: document.getElementById('sourcesBlock'),
  sources: document.getElementById('sources'),
};

const SOURCE_LABELS = {
  scorecard_image: 'Scorecard image',
  rating_sticker_image: 'Rating plate',
  course_website: 'Course website',
  official_rating_db: 'Rating database',
  in_person: 'Recorded in person',
  other: 'Other source',
};

let course = null;
const selected = new Set();

init();

async function init() {
  const key = new URLSearchParams(location.search).get('c');
  if (!key) return fail('No course was requested. Start from the search page.');

  try {
    course = await loadCourse(key);
  } catch (error) {
    return fail(`Could not load that course (${error.message}). It may have been renamed — try searching again.`);
  }

  els.loading.hidden = true;
  els.course.hidden = false;
  document.title = `${courseTitle(course.facility.name, course.course.name)} — OpenTee`;

  renderHeader();
  renderTeeList();
  restoreState();

  els.scoreRows.addEventListener('input', render);
  els.showNames.addEventListener('input', render);
  els.print.addEventListener('click', () => window.print());
  els.share.addEventListener('click', copyLink);

  renderSources();
  render();
}

function fail(message) {
  els.loading.hidden = true;
  els.error.hidden = false;
  els.error.textContent = message;
}

function renderHeader() {
  els.title.textContent = courseTitle(course.facility.name, course.course.name);

  const bits = [place(course.facility), `${course.course.holeCount} holes`];
  const par = totalPar();
  if (par) bits.push(`par ${par}`);
  els.meta.textContent = bits.filter(Boolean).join(' · ');

  els.links.replaceChildren();
  if (course.facility.address) {
    const address = document.createElement('span');
    address.className = 'muted';
    address.textContent = [course.facility.address, place(course.facility), course.facility.postalCode]
      .filter(Boolean).join(', ');
    els.links.append(address);
  }
  if (course.facility.website) {
    const link = document.createElement('a');
    link.href = course.facility.website;
    link.rel = 'noopener nofollow';
    link.textContent = 'Course website';
    els.links.append(link);
  }
}

function totalPar() {
  for (const field of ['parMen', 'parUnisex', 'parWomen']) {
    const values = course.holes.map((h) => h[field]);
    if (values.every((v) => typeof v === 'number')) {
      return values.reduce((a, b) => a + b, 0);
    }
  }
  return null;
}

function renderTeeList() {
  els.tees.replaceChildren(...course.tees.map((tee, i) => {
    const li = document.createElement('li');
    li.className = tee.isComplete ? 'tee' : 'tee unavailable';

    const label = document.createElement('label');
    const box = document.createElement('input');
    box.type = 'checkbox';
    box.disabled = !tee.isComplete;
    box.dataset.index = String(i);
    box.addEventListener('input', () => {
      if (box.checked) selected.add(i); else selected.delete(i);
      render();
    });

    const swatch = document.createElement('span');
    swatch.className = 'swatch';
    if (tee.color) swatch.style.background = tee.color;
    else swatch.classList.add('swatch-empty');

    const text = document.createElement('span');
    text.className = 'tee-text';
    const name = document.createElement('span');
    name.className = 'tee-name';
    name.textContent = tee.name;
    const sub = document.createElement('span');
    sub.className = 'tee-sub';
    sub.textContent = teeSummary(tee);
    text.append(name, sub);

    label.append(box, swatch, text);
    li.append(label);

    if (tee.hasTotalDiscrepancy) {
      const warn = document.createElement('p');
      warn.className = 'tee-warn';
      warn.textContent = `Course prints ${formatNumber(tee.publishedTotal)}; the holes add to ${formatNumber(tee.total)}.`;
      li.append(warn);
    }
    return li;
  }));
}

/** Selection and card options come from the URL, so a card is shareable. */
function restoreState() {
  const params = new URLSearchParams(location.search);
  const wanted = params.get('tees');
  const names = wanted ? new Set(wanted.split('~')) : null;

  course.tees.forEach((tee, i) => {
    const include = names ? names.has(tee.name) : tee.isComplete;
    if (include && tee.isComplete) selected.add(i);
  });

  const rows = params.get('rows');
  if (rows !== null && [...els.scoreRows.options].some((o) => o.value === rows)) {
    els.scoreRows.value = rows;
  }
  if (params.get('names') === '0') els.showNames.checked = false;

  syncCheckboxes();
}

function syncCheckboxes() {
  for (const box of els.tees.querySelectorAll('input[type=checkbox]')) {
    box.checked = selected.has(Number(box.dataset.index));
  }
}

function selectedTees() {
  return course.tees.filter((_, i) => selected.has(i));
}

function render() {
  const tees = selectedTees();
  const hasCard = tees.length > 0;
  els.sheet.hidden = !hasCard;
  els.empty.hidden = hasCard;
  els.print.disabled = !hasCard;
  syncUrl();
  if (!hasCard) {
    renderEmptyState();
    return;
  }

  els.sheetTitle.textContent = courseTitle(course.facility.name, course.course.name);
  els.sheetSub.textContent = [place(course.facility), `${course.course.holeCount} holes`]
    .filter(Boolean).join(' · ');

  const rows = buildRows(course, tees, {
    scoreRows: Number(els.scoreRows.value),
    showNames: els.showNames.checked,
  });
  renderTable(rows);

  els.ratingsNote.replaceChildren(...ratingsParts(tees).map((part) => {
    const span = document.createElement('span');
    span.className = 'rating-part';
    span.textContent = part;
    return span;
  }));
  els.unitNote.textContent = unitNote(tees);

  // If the course's own printed total disagrees with the sum of its holes, the
  // card says so rather than quietly picking a winner.
  const mismatched = tees.filter((t) => t.hasTotalDiscrepancy);
  els.discrepancyNote.textContent = mismatched.length === 0 ? '' : `${mismatched
    .map((t) => `${t.name}: course prints ${formatNumber(t.publishedTotal)}, holes add to ${formatNumber(t.total)}`)
    .join('; ')}.`;
  els.provenanceNote.textContent =
    `OpenTee · course data as published · printed ${new Date().toISOString().slice(0, 10)}`;
}

/**
 * Nothing to print. Either the reader unticked every tee, or — the honest case
 * the schema is built for — this course has published totals but no per-hole
 * card, so say that plainly and show what the database does hold.
 */
function renderEmptyState() {
  if (course.tees.some((t) => t.isComplete)) {
    els.empty.textContent = 'Select at least one tee to build a card.';
    return;
  }

  const intro = document.createElement('p');
  intro.textContent = course.tees.length
    ? 'No per-hole card has been published for this course yet, so there is nothing to print. The database holds these totals:'
    : 'No tee data has been collected for this course yet.';

  const list = document.createElement('ul');
  list.className = 'totals-only';
  for (const tee of course.tees) {
    const li = document.createElement('li');
    const total = tee.publishedTotal ?? tee.total;
    li.textContent = [
      tee.name,
      total ? `${formatNumber(total)} ${tee.unit}` : 'no published total',
      tee.ratings.map((r) => `${r.gender} ${r.rating}/${r.slope}`).join(' · '),
    ].filter(Boolean).join(' — ');
    list.append(li);
  }

  const help = document.createElement('p');
  help.className = 'muted';
  help.append(document.createTextNode('Have the printed card? '));
  const link = document.createElement('a');
  link.href = 'https://github.com/jstephenperry/OpenTee/issues';
  link.rel = 'noopener';
  link.textContent = 'Contribute it';
  help.append(link, document.createTextNode(' and this page will print it.'));

  els.empty.replaceChildren(intro, list, help);
}

function renderTable(rows) {
  const head = document.createElement('thead');
  const body = document.createElement('tbody');
  const totalColumns = new Set(
    rows[0].cells.flatMap((cell, i) => (['OUT', 'IN', 'TOT'].includes(cell) ? [i] : [])),
  );

  rows.forEach((row, index) => {
    const tr = document.createElement('tr');
    tr.className = `row-${row.kind}`;

    const label = document.createElement('th');
    label.scope = 'row';
    label.className = 'row-label';
    if (row.color) {
      const swatch = document.createElement('span');
      swatch.className = 'swatch';
      swatch.style.background = row.color;
      label.append(swatch);
    }
    label.append(document.createTextNode(row.label));
    tr.append(label);

    row.cells.forEach((cell, i) => {
      const td = document.createElement(row.kind === 'header' ? 'th' : 'td');
      if (row.kind === 'header') td.scope = 'col';
      if (totalColumns.has(i)) td.classList.add('total');
      td.textContent = cell;
      if (row.kind === 'names' && cell) td.title = cell;
      tr.append(td);
    });

    (index === 0 ? head : body).append(tr);
  });

  els.table.replaceChildren(head, body);
}

function syncUrl() {
  const url = new URL(location.href);
  const names = selectedTees().map((t) => t.name);
  const defaults = course.tees.filter((t) => t.isComplete).map((t) => t.name);
  const isDefault = names.length === defaults.length && names.every((n, i) => n === defaults[i]);

  if (isDefault) url.searchParams.delete('tees');
  else url.searchParams.set('tees', names.join('~'));

  if (els.scoreRows.value === '4') url.searchParams.delete('rows');
  else url.searchParams.set('rows', els.scoreRows.value);

  if (els.showNames.checked) url.searchParams.delete('names');
  else url.searchParams.set('names', '0');

  history.replaceState(null, '', url);
}

async function copyLink() {
  try {
    await navigator.clipboard.writeText(location.href);
    flash(els.share, 'Link copied');
  } catch {
    flash(els.share, 'Press ⌘/Ctrl-C');
  }
}

function flash(button, message) {
  const original = button.textContent;
  button.textContent = message;
  button.disabled = true;
  setTimeout(() => {
    button.textContent = original;
    button.disabled = false;
  }, 1600);
}

function renderSources() {
  if (!course.sources.length) {
    els.sourcesBlock.hidden = true;
    return;
  }
  els.sources.replaceChildren(...course.sources.map((source) => {
    const li = document.createElement('li');

    const kind = document.createElement('span');
    kind.className = 'source-kind';
    kind.textContent = SOURCE_LABELS[source.type] ?? source.type;
    li.append(kind);

    if (source.url) {
      const link = document.createElement('a');
      link.href = source.url;
      link.rel = 'noopener nofollow';
      link.textContent = shortenUrl(source.url);
      li.append(link);
    }
    if (source.effectiveDate) {
      const date = document.createElement('span');
      date.className = 'muted';
      date.textContent = `read ${source.effectiveDate}`;
      li.append(date);
    }
    if (source.note) {
      const note = document.createElement('p');
      note.className = 'source-note';
      note.textContent = source.note;
      li.append(note);
    }
    return li;
  }));
}

function shortenUrl(url) {
  try {
    const parsed = new URL(url);
    const path = parsed.pathname.replace(/\/$/, '');
    return `${parsed.hostname.replace(/^www\./, '')}${path.length > 28 ? `${path.slice(0, 27)}…` : path}`;
  } catch {
    return url;
  }
}
