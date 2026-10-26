import { AppError } from '../errors.js';

export function rateLimit({ minutes, max, key }) {
  const windowMs = minutes * 60 * 1000;
  const hits = new Map();

  setInterval(() => {
    const now = Date.now();
    for (const [id, entry] of hits) {
      if (entry.resetAt <= now) {
        hits.delete(id);
      }
    }
  }, windowMs).unref();

  return (req, res, next) => {
    const now = Date.now();
    const id = key(req);
    const entry = hits.get(id);

    if (!entry || entry.resetAt <= now) {
      hits.set(id, { count: 1, resetAt: now + windowMs });
      return next();
    }

    entry.count += 1;
    if (entry.count > max) {
      throw new AppError(429, 'TOO_MANY_REQUESTS', 'Too many tries, wait and try again', {
        retryAfter: Math.ceil((entry.resetAt - now) / 1000),
      });
    }
    next();
  };
}

export function emailOf(req) {
  const email = req.body && typeof req.body.email === 'string' ? req.body.email : '';
  return email.trim().toLowerCase();
}
