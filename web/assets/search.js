// Home page: instant search over the whole course index (it is small enough to
// filter in the browser, so there is no server to be down).

import { loadIndex, place, courseTitle, formatNumber, courseUrl } from './data.js';

const els = {
  stats: document.getElementById('stats'),
  q: document.getElementById('q'),
  holes: document.getElementById('holes'),
  sort: document.getElementById('sort'),
  ratedOnly: document.getElementById('ratedOnly'),
  completeOnly: document.getElementById('completeOnly'),
  count: document.getElementById('count'),
  results: document.getElementById('results'),
};

const STAT_LABELS = [
  ['facilities', 'facilities'],
  ['courses', 'courses'],
  ['tees', 'tee sets'],
  ['holeLengths', 'published hole yardages'],
];

let courses = [];

init();

async function init() {
  let index;
  try {
    index = await loadIndex();
  } catch (error) {
    els.count.textContent = `Could not load the course index (${error.message}).`;
    return;
  }

  courses = index.courses.map((course) => ({
    ...course,
    haystack: [course.name, course.facility, course.city, course.state].filter(Boolean).join(' ').toLowerCase(),
  }));

  els.stats.replaceChildren(...STAT_LABELS.flatMap(([key, label]) => {
    const dt = document.createElement('dt');
    dt.textContent = formatNumber(index.stats[key]);
    const dd = document.createElement('dd');
    dd.textContent = label;
    return [dt, dd];
  }));

  // A query in the URL makes a search shareable, and survives the back button.
  const initial = new URLSearchParams(location.search).get('q');
  if (initial) els.q.value = initial;

  for (const el of [els.q, els.holes, els.sort, els.ratedOnly, els.completeOnly]) {
    el.addEventListener('input', render);
  }
  render();
}

function render() {
  const terms = els.q.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const holes = els.holes.value ? Number(els.holes.value) : null;

  let matches = courses.filter((course) => {
    if (holes !== null && course.holeCount !== holes) return false;
    if (els.ratedOnly.checked && !course.rated) return false;
    if (els.completeOnly.checked && course.completeTees === 0) return false;
    return terms.every((term) => course.haystack.includes(term));
  });

  matches = sortMatches(matches, els.sort.value);

  els.count.textContent = matches.length === courses.length
    ? `${formatNumber(courses.length)} courses`
    : `${formatNumber(matches.length)} of ${formatNumber(courses.length)} courses`;

  els.results.replaceChildren(...matches.map(resultItem));

  if (matches.length === 0) {
    const li = document.createElement('li');
    li.className = 'no-results';
    li.textContent = 'No course matches that. Try a club name, a course name or a city.';
    els.results.replaceChildren(li);
  }

  const url = new URL(location.href);
  if (terms.length) url.searchParams.set('q', els.q.value.trim());
  else url.searchParams.delete('q');
  history.replaceState(null, '', url);
}

function sortMatches(matches, mode) {
  const byName = (a, b) =>
    a.facility.localeCompare(b.facility) || a.name.localeCompare(b.name);
  // Courses with no complete tee have no length to sort by; park them last
  // rather than treating a missing number as zero.
  const byLength = (dir) => (a, b) => {
    const av = a.maxLength ?? null;
    const bv = b.maxLength ?? null;
    if (av === null && bv === null) return byName(a, b);
    if (av === null) return 1;
    if (bv === null) return -1;
    return dir * (bv - av) || byName(a, b);
  };
  switch (mode) {
    case 'city':
      return [...matches].sort((a, b) => (a.city ?? '').localeCompare(b.city ?? '') || byName(a, b));
    case 'long':
      return [...matches].sort(byLength(1));
    case 'short':
      return [...matches].sort(byLength(-1));
    default:
      return [...matches].sort(byName);
  }
}

function resultItem(course) {
  const li = document.createElement('li');
  li.className = 'result';

  const link = document.createElement('a');
  link.href = courseUrl(course.key);
  link.className = 'result-link';

  const title = document.createElement('span');
  title.className = 'result-title';
  title.textContent = courseTitle(course.facility, course.name);

  const where = document.createElement('span');
  where.className = 'result-where';
  where.textContent = place(course);

  const facts = document.createElement('span');
  facts.className = 'result-facts';
  facts.append(
    fact(`${course.holeCount} holes`),
    fact(course.par ? `par ${course.par}` : 'par not published', !course.par),
    fact(lengthRange(course), course.completeTees === 0),
    fact(`${course.teeCount} ${course.teeCount === 1 ? 'tee' : 'tees'}${course.rated ? '' : ' · unrated'}`),
  );

  link.append(title, where, facts);
  li.append(link);
  return li;
}

function lengthRange(course) {
  if (course.completeTees === 0) return 'totals only';
  if (course.minLength === course.maxLength) return `${formatNumber(course.maxLength)} ${course.unit}`;
  return `${formatNumber(course.minLength)}–${formatNumber(course.maxLength)} ${course.unit}`;
}

function fact(text, muted = false) {
  const span = document.createElement('span');
  span.className = muted ? 'fact muted' : 'fact';
  span.textContent = text;
  return span;
}
