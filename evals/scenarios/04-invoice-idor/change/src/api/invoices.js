import * as db from '../db.js';

/**
 * GET /invoices/:id — return an invoice for the logged-in user.
 * `user` is set by the auth middleware and is always present here.
 */
export async function getInvoice(req) {
  const { user } = req;
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return { status: 400, body: { error: 'bad id' } };
  const invoice = await db.get('invoices', id);
  if (!invoice) return { status: 404, body: { error: 'not found' } };
  return { status: 200, body: { invoice, requestedBy: user.id } };
}

/** GET /invoices — list the logged-in user's invoices. */
export async function listInvoices(req) {
  const invoices = await db.where('invoices', (i) => i.userId === req.user.id);
  return { status: 200, body: { invoices } };
}
