import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanInteger, cleanText } from '../../lib/validate.js';
import { bodyOf } from '../../lib/fields.js';
import { sendNotice } from '../../lib/mailer.js';
import {
  SETTLEMENT_SQL, TOPUP_STATUSES, cleanReference, lockTransfer, toSettlement,
} from '../../lib/wallet.js';

const router = Router();
const PAGE_SIZE = 20;

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

async function lockSettlement(client, id) {
  const { rows: [row] } = await client.query('SELECT status FROM driver_settlements WHERE id = $1 FOR UPDATE', [id]);
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Payment not found');
  }
  if (row.status !== 'awaiting_verification') {
    throw new AppError(409, 'ALREADY_REVIEWED', `This payment is already ${row.status}`, { status: row.status });
  }
}

async function settlementView(req, id) {
  const { rows: [row] } = await query(
    `SELECT list.*, driver_balance(list.driver_id)::numeric(12,2) AS balance,
            driver_debt_limit(list.driver_id)::numeric(12,2) AS debt_limit
     FROM (${SETTLEMENT_SQL}) list
     WHERE list.id = $1`,
    [id],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Payment not found');
  }
  const settlement = toSettlement(row, baseUrl(req), true);
  settlement.driver.balance = row.balance;
  settlement.driver.debtLimit = row.debt_limit;
  return settlement;
}

router.get('/', async (req, res) => {
  const status = req.query.status === undefined ? 'awaiting_verification'
    : cleanChoice(req.query.status, 'status', [...TOPUP_STATUSES, 'all']);
  const search = typeof req.query.search === 'string' && req.query.search.trim()
    ? req.query.search.trim() : null;
  const like = search ? `%${search.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);

  const { rows } = await query(
    `SELECT list.*, count(*) OVER () AS total FROM (${SETTLEMENT_SQL}) list
     WHERE ($1 = 'all' OR list.status = $1)
       AND ($2::text IS NULL OR list.id::text = $3 OR list.full_name ILIKE $2 OR list.email ILIKE $2
            OR list.phone LIKE $2 OR list.transfer_reference ILIKE $2)
     ORDER BY CASE WHEN $1 = 'awaiting_verification' THEN list.id END, list.id DESC
     LIMIT ${PAGE_SIZE} OFFSET $4`,
    [status, like, search, (page - 1) * PAGE_SIZE],
  );
  res.json({
    settlements: rows.map((row) => toSettlement(row, baseUrl(req), true)),
    page,
    pageSize: PAGE_SIZE,
    total: rows.length ? Number(rows[0].total) : 0,
  });
});

router.get('/:id', async (req, res) => {
  res.json({ settlement: await settlementView(req, cleanId(req.params.id)) });
});

router.post('/:id/verify', async (req, res) => {
  const id = cleanId(req.params.id);
  const reference = cleanReference(bodyOf(req).transferReference, 'transferReference');
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    await lockSettlement(client, id);
    await lockTransfer(client, reference);
    await client.query(
      "UPDATE driver_settlements SET status = 'verified', transfer_reference = $2 WHERE id = $1",
      [id, reference],
    );
  });
  res.json({ settlement: await settlementView(req, id) });
});

router.post('/:id/reject', async (req, res) => {
  const id = cleanId(req.params.id);
  const reason = cleanText(bodyOf(req).reason, 'reason', 500);
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    await lockSettlement(client, id);
    await client.query(
      "UPDATE driver_settlements SET status = 'rejected', rejection_reason = $2 WHERE id = $1",
      [id, reason],
    );
  });

  const settlement = await settlementView(req, id);
  const { rows: [user] } = await query(
    'SELECT email, preferred_language FROM users WHERE id = $1',
    [settlement.driver.id],
  );
  if (user && user.email) {
    await sendNotice(user.email, user.preferred_language, 'settlement_rejected', { amount: settlement.amount, reason });
  }
  res.json({ settlement });
});

export default router;
