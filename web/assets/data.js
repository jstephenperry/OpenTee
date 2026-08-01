// Loading and formatting helpers shared by the two pages.

const INDEX_URL = new URL('../data/index.json', import.meta.url);

let indexPromise = null;

/** The search index: small records for every course, plus database totals. */
export function loadIndex() {
  indexPromise ??= fetchJson(INDEX_URL);
  return indexPromise;
}

/** One course's full document: holes, tees, per-hole lengths, sources. */
export function loadCourse(key) {
  return fetchJson(new URL(`../data/courses/${encodeURIComponent(key)}.json`, import.meta.url));
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return response.json();
}

/** "Fort Worth, Texas" — dropping whichever half the source omitted. */
export function place(record) {
  return [record.city, record.state].filter(Boolean).join(', ');
}

/** Facilities usually share their name with their only course; don't repeat it. */
export function courseTitle(facilityName, courseName) {
  return facilityName === courseName ? facilityName : `${facilityName} — ${courseName}`;
}

export function formatNumber(value) {
  return typeof value === 'number' ? value.toLocaleString() : '';
}

export function courseUrl(key) {
  return `course.html?c=${encodeURIComponent(key)}`;
}
