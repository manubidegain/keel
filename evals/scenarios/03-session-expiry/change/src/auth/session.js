import { randomBytes, createHmac, timingSafeEqual } from 'node:crypto';

const SECRET = process.env.SESSION_SECRET;
const TTL_MS = 1000 * 60 * 60 * 24 * 7; // 7 days

function sign(payload) {
  return createHmac('sha256', SECRET).update(payload).digest('base64url');
}

export function createSession(userId, now = Date.now()) {
  const payload = Buffer.from(JSON.stringify({ uid: userId, exp: now + TTL_MS, n: randomBytes(8).toString('hex') })).toString('base64url');
  return `${payload}.${sign(payload)}`;
}

/** Returns the user id for a valid session token, or null. */
export function verifySession(token) {
  const [payload, sig] = String(token).split('.');
  if (!payload || !sig) return null;
  const expected = sign(payload);
  if (sig.length !== expected.length || !timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  const { uid } = JSON.parse(Buffer.from(payload, 'base64url').toString());
  return uid;
}
