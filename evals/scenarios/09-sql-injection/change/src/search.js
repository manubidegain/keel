import * as db from './db.js';

/** GET /courts/search?q= — find courts by name. */
export async function searchCourts(q) {
  const term = String(q ?? '').trim();
  if (term.length < 2) return [];
  const { rows } = await db.query(`SELECT id, name FROM courts WHERE name ILIKE '%${term}%' ORDER BY name LIMIT 20`);
  return rows;
}
