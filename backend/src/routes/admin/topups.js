import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanInteger, cleanText } from '../../lib/validate.js';
import { bodyOf } from '../../lib/fields.js';
import { sendNotice } from '../../lib/mailer.js';
import {
  TOPUP_SQL, TOPUP_STATUSES, cleanReference, lockTransfer, toTopup,
} from '../../lib/wallet.js';

const router = Router();
const PAGE_SIZE = 20;

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

async function lockTopup(client, id) {
  const { rows: [topup] } = await client.query('SELECT status FROM customer_topups WHERE id = $1 FOR UPDATE', [id]);
  if (!topup) {
    throw new AppError(404, 'NOT_FOUND', 'Top-up not found');
  }
  if (topup.status !== 'awaiting_verification') {
    throw new AppError(409, 'ALREADY_REVIEWED', `This top-up is already ${topup.status}`, { status: topup.status });
  }
}

async function topupView(req, id) {
  const { rows: [row] } = await query(
    `SELECT list.*, customer_balance(list.customer_id)::numeric(12,2) AS balance FROM (${TOPUP_SQL}) list
     WHERE list.id = $1`,
    [id],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Top-up not found');
  }
  const topup = toTopup(row, baseUrl(req), true);
  topup.customer.balance = row.balance;
  return topup;
}

router.get('/', async (req, res) => {
  const status = req.query.status === undefined ? 'awaiting_verification'
    : cleanChoice(req.query.status, 'status', [...TOPUP_STATUSES, 'all']);
  const search = typeof req.query.search === 'string' && req.query.search.trim()
    ? req.query.search.trim() : null;
  const like = search ? `%${search.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);

  const { rows } = await query(
    `SELECT list.*, count(*) OVER () AS total FROM (${TOPUP_SQL}) list
     WHERE ($1 = 'all' OR list.status = $1)
       AND ($2::text IS NULL OR list.id::text = $3 OR list.full_name ILIKE $2 OR list.email ILIKE $2
            OR list.phone LIKE $2 OR list.transfer_reference ILIKE $2)
     ORDER BY CASE WHEN $1 = 'awaiting_verification' THEN list.id END, list.id DESC
     LIMIT ${PAGE_SIZE} OFFSET $4`,
    [status, like, search, (page - 1) * PAGE_SIZE],
  );
  res.json({
    topups: rows.map((row) => toTopup(row, baseUrl(req), true)),
    page,
    pageSize: PAGE_SIZE,
    total: rows.length ? Number(rows[0].total) : 0,
  });
});

router.get('/:id', async (req, res) => {
  res.json({ topup: await topupView(req, cleanId(req.params.id)) });
});

router.post('/:id/verify', async (req, res) => {
  const id = cleanId(req.params.id);
  const reference = cleanReference(bodyOf(req).transferReference, 'transferReference');
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    await lockTopup(client, id);
    await lockTransfer(client, reference);
    await client.query(
      "UPDATE customer_topups SET status = 'verified', transfer_reference = $2 WHERE id = $1",
      [id, reference],
    );
  });
  res.json({ topup: await topupView(req, id) });
});

router.post('/:id/reject', async (req, res) => {
  const id = cleanId(req.params.id);
  const reason = cleanText(bodyOf(req).reason, 'reason', 500);
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    await lockTopup(client, id);
    await client.query(
      "UPDATE customer_topups SET status = 'rejected', rejection_reason = $2 WHERE id = $1",
      [id, reason],
    );
  });

  const topup = await topupView(req, id);
  const { rows: [user] } = await query(
    'SELECT email, preferred_language FROM users WHERE id = $1',
    [topup.customer.id],
  );
  if (user && user.email) {
    await sendNotice(user.email, user.preferred_language, 'topup_rejected', { amount: topup.amount, reason });
  }
  res.json({ topup });
});

export default router;
