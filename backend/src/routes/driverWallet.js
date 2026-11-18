import express, { Router } from 'express';
import { query, withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { cleanInteger } from '../lib/validate.js';
import {
  IMAGE_TYPES, MAX_IMAGE_MB, readImage, saveImage,
} from '../lib/storage.js';
import {
  SETTLEMENT_SQL, cleanAmount, cleanReference, transferUsed, toSettlement, loadDriverWallet, listDriverEntries,
} from '../lib/wallet.js';

const router = Router();
const PAGE_SIZE = 20;
const MAX_PENDING = 3;
const imageBody = express.raw({ type: IMAGE_TYPES, limit: `${MAX_IMAGE_MB}mb` });

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

function readPage(req) {
  return req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
}

function profileRequired() {
  return new AppError(409, 'PROFILE_REQUIRED', 'Save the personal information first');
}

router.get('/', async (req, res) => {
  const wallet = await loadDriverWallet(req.user.id);
  if (!wallet) {
    throw profileRequired();
  }
  res.json({ wallet });
});

router.get('/transactions', async (req, res) => {
  res.json(await listDriverEntries(req.user.id, readPage(req)));
});

router.get('/settlements', async (req, res) => {
  const page = readPage(req);
  const { rows } = await query(
    `${SETTLEMENT_SQL} WHERE t.driver_id = $1
     ORDER BY t.id DESC
     LIMIT ${PAGE_SIZE + 1} OFFSET $2`,
    [req.user.id, (page - 1) * PAGE_SIZE],
  );
  res.json({
    settlements: rows.slice(0, PAGE_SIZE).map((row) => toSettlement(row, baseUrl(req))),
    page,
    hasMore: rows.length > PAGE_SIZE,
  });
});

router.post('/settlements', imageBody, async (req, res) => {
  const amount = cleanAmount(req.query.amount, 'amount');
  const reference = req.query.reference === undefined ? null : cleanReference(req.query.reference, 'reference');
  const image = readImage(req);

  const check = async (client) => {
    const { rows: [profile] } = await client.query(
      'SELECT user_id FROM driver_profiles WHERE user_id = $1 FOR UPDATE',
      [req.user.id],
    );
    if (!profile) {
      throw profileRequired();
    }
    const { rows: [debt] } = await client.query(
      `SELECT x.balance, x.pending, x.max, $2::numeric <= x.max AS allowed
       FROM (
         SELECT driver_balance($1)::numeric(12,2) AS balance,
                (SELECT count(*)::int FROM driver_settlements
                 WHERE driver_id = $1 AND status = 'awaiting_verification') AS pending,
                GREATEST(-driver_balance($1) - (
                  SELECT COALESCE(sum(amount), 0) FROM driver_settlements
                  WHERE driver_id = $1 AND status = 'awaiting_verification'), 0)::numeric(12,2) AS max
       ) x`,
      [req.user.id, amount],
    );
    if (debt.pending >= MAX_PENDING) {
      throw new AppError(409, 'TOO_MANY_PENDING', 'Wait until your earlier payments are checked');
    }
    if (Number(debt.max) === 0) {
      throw new AppError(409, 'NOTHING_TO_SETTLE', 'You have no debt left to pay', { balance: debt.balance });
    }
    if (!debt.allowed) {
      throw new AppError(400, 'INVALID_INPUT', `amount must be at most ${debt.max}`, {
        field: 'amount', max: debt.max,
      });
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
  const key = await saveImage(image, `wasla/settlements/${req.user.id}`);
  const id = await withTransaction({ id: req.user.id, role: 'driver' }, async (client) => {
    await check(client);
    const { rows: [row] } = await client.query(
      `INSERT INTO driver_settlements (driver_id, amount, proof_storage_key, transfer_reference)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [req.user.id, amount, key, reference],
    );
    return row.id;
  });

  const { rows: [row] } = await query(`${SETTLEMENT_SQL} WHERE t.id = $1`, [id]);
  res.status(201).json({ settlement: toSettlement(row, baseUrl(req)) });
});

export default router;
