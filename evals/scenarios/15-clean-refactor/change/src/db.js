// In-memory stand-in for a SQL database. Async to mirror a real driver.
// Every function returns copies so callers can't mutate stored rows by accident.

/** @typedef {'users'|'courts'|'bookings'|'invoices'} Table */

const tables = { users: new Map(), courts: new Map(), bookings: new Map(), invoices: new Map() };
let nextId = 1;

const copy = (row) => (row ? { ...row } : null);

function tableOf(name) {
  const t = tables[name];
  if (!t) throw new Error(`unknown table ${name}`);
  return t;
}

/** Insert a row, assigning an id when it has none. @param {Table} table */
export async function insert(table, row) {
  const id = row.id ?? nextId++;
  const stored = { ...row, id };
  tableOf(table).set(id, stored);
  return copy(stored);
}

/** Get a row by id, or null. @param {Table} table */
export async function get(table, id) {
  return copy(tableOf(table).get(id));
}

/** Merge `patch` into a row. Throws if it doesn't exist. @param {Table} table */
export async function update(table, id, patch) {
  const t = tableOf(table);
  const current = t.get(id);
  if (!current) throw new Error(`${table} ${id} not found`);
  const next = { ...current, ...patch };
  t.set(id, next);
  return copy(next);
}

/** Rows matching a predicate. @param {Table} table */
export async function where(table, predicate) {
  return [...tableOf(table).values()].filter(predicate).map(copy);
}

/** Parameterized raw query (tiny subset, for search). Params are never interpolated. */
export async function query(sql, params = []) {
  return { sql, params, rows: [] };
}

/** Clear every table (tests only). */
export function reset() {
  for (const t of Object.values(tables)) t.clear();
  nextId = 1;
}
