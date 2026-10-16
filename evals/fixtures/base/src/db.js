// In-memory stand-in for a SQL database. Async to mirror a real driver.
const tables = { users: new Map(), courts: new Map(), bookings: new Map(), invoices: new Map() };
let seq = 1;

export async function insert(table, row) {
  const id = row.id ?? seq++;
  tables[table].set(id, { ...row, id });
  return { ...row, id };
}
export async function get(table, id) {
  const row = tables[table].get(id);
  return row ? { ...row } : null;
}
export async function update(table, id, patch) {
  const row = tables[table].get(id);
  if (!row) throw new Error(`${table} ${id} not found`);
  tables[table].set(id, { ...row, ...patch });
  return { ...row, ...patch };
}
export async function where(table, pred) {
  return [...tables[table].values()].filter(pred).map((r) => ({ ...r }));
}
// Parameterized raw query (tiny subset, for search). Params are never interpolated.
export async function query(sql, params = []) {
  return { sql, params, rows: [] };
}
export function reset() {
  for (const t of Object.values(tables)) t.clear();
  seq = 1;
}
