import express, { Router } from 'express';
import { query, withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { bodyOf } from '../lib/fields.js';
import { cleanChoice, cleanInteger, invalid } from '../lib/validate.js';
import {
  IMAGE_TYPES, MAX_IMAGE_MB, readImage, saveImage,
} from '../lib/storage.js';
import {
  TOPUP_SQL, cleanAmount, cleanReference, transferUsed, toTopup, loadWallet, listEntries,
} from '../lib/wallet.js';

const router = Router();
const PAGE_SIZE = 20;
const MAX_PENDING_TOPUPS = 3;
const imageBody = express.raw({ type: IMAGE_TYPES, limit: `${MAX_IMAGE_MB}mb` });

router.use(requireAuth, requireRole('customer'));

function actorOf(req) {
  return { id: req.user.id, role: 'customer' };
}

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

function readPage(req) {
  return req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
}

router.get('/', async (req, res) => {
  res.json({ wallet: await loadWallet(req.user.id) });
});

router.put('/payment-method', async (req, res) => {
  const body = bodyOf(req);
  if (body.method === undefined) {
    throw invalid('method', 'method is required');
  }
  const method = body.method === null ? null : cleanChoice(body.method, 'method', ['cash', 'wallet']);
  await withTransaction(actorOf(req), (client) => client.query(
    'UPDATE users SET default_payment_method = $2 WHERE id = $1',
    [req.user.id, method],
  ));
  res.json({ wallet: await loadWallet(req.user.id) });
});

router.get('/transactions', async (req, res) => {
  res.json(await listEntries(req.user.id, readPage(req)));
});

router.get('/topups', async (req, res) => {
  const page = readPage(req);
  const { rows } = await query(
    `${TOPUP_SQL} WHERE t.customer_id = $1
     ORDER BY t.id DESC
     LIMIT ${PAGE_SIZE + 1} OFFSET $2`,
    [req.user.id, (page - 1) * PAGE_SIZE],
  );
  res.json({
    topups: rows.slice(0, PAGE_SIZE).map((row) => toTopup(row, baseUrl(req))),
    page,
    hasMore: rows.length > PAGE_SIZE,
  });
});

router.post('/topups', imageBody, async (req, res) => {
  const amount = cleanAmount(req.query.amount, 'amount');
  const reference = req.query.reference === undefined ? null : cleanReference(req.query.reference, 'reference');
  const image = readImage(req);

  const check = async (client) => {
    await client.query('SELECT 1 FROM users WHERE id = $1 FOR UPDATE', [req.user.id]);
    const { rows: [limits] } = await client.query(
      `SELECT min_topup_amount AS min, max_topup_amount AS max,
              $1::numeric BETWEEN min_topup_amount AND max_topup_amount AS allowed,
              (SELECT count(*)::int FROM customer_topups
               WHERE customer_id = $2 AND status = 'awaiting_verification') AS pending
       FROM platform_settings`,
      [amount, req.user.id],
    );
    if (!limits.allowed) {
      throw new AppError(400, 'INVALID_INPUT', `amount must be from ${limits.min} to ${limits.max}`, {
        field: 'amount', min: limits.min, max: limits.max,
      });
    }
    if (limits.pending >= MAX_PENDING_TOPUPS) {
      throw new AppError(409, 'TOO_MANY_PENDING', 'Wait until your earlier top-ups are checked');
    }
    if (reference) {
      const { rows: [claim] } = await client.query(
        'SELECT 1 FROM incoming_transfer_claims WHERE transfer_reference = $1',
        [reference.toLowerCase()],
      );
      if (claim) {
        throw transferUsed();
      }
    }
  };

  await withTransaction(null, check);
  const key = await saveImage(image, `wasla/topups/${req.user.id}`);
  const id = await withTransaction(actorOf(req), async (client) => {
    await check(client);
    const { rows: [row] } = await client.query(
      `INSERT INTO customer_topups (customer_id, amount, proof_storage_key, transfer_reference)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [req.user.id, amount, key, reference],
    );
    return row.id;
  });

  const { rows: [row] } = await query(`${TOPUP_SQL} WHERE t.id = $1`, [id]);
  res.status(201).json({ topup: toTopup(row, baseUrl(req)) });
});

export default router;
