import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanInteger, cleanText, cleanRef } from '../../lib/validate.js';
import { bodyOf } from '../../lib/fields.js';
import { sendNotice } from '../../lib/mailer.js';
import { cleanReference } from '../../lib/wallet.js';
import {
  PAYOUT_SQL, PAGE_SIZE, TRANSFER_STATUSES, toTransfer, listTransfers, lockTransferRequest, createPayouts,
} from '../../lib/payouts.js';

const router = Router();

async function payoutView(id) {
  const { rows: [row] } = await query(
    `SELECT list.*, driver_balance(list.user_id)::numeric(12,2) AS balance FROM (${PAYOUT_SQL}) list
     WHERE list.id = $1`,
    [id],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Payout not found');
  }
  const item = toTransfer(row, 'driver');
  item.driver.balance = row.balance;
  return item;
}

async function notify(item, kind, params) {
  const { rows: [user] } = await query(
    'SELECT email, preferred_language FROM users WHERE id = $1',
    [item.driver.id],
  );
  if (user && user.email) {
    await sendNotice(user.email, user.preferred_language, kind, { amount: item.amount, ...params });
  }
}

router.get('/', async (req, res) => {
  const status = req.query.status === undefined ? 'requested'
    : cleanChoice(req.query.status, 'status', [...TRANSFER_STATUSES, 'all']);
  const search = typeof req.query.search === 'string' && req.query.search.trim()
    ? req.query.search.trim() : null;
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
  const { rows, total } = await listTransfers(PAYOUT_SQL, status, search, page);
  res.json({
    payouts: rows.map((row) => toTransfer(row, 'driver')),
    page,
    pageSize: PAGE_SIZE,
    total,
  });
});

router.post('/run', async (req, res) => {
  const body = bodyOf(req);
  const driverId = body.driverId === undefined || body.driverId === null ? null : cleanRef(body.driverId, 'driverId');
  const created = await withTransaction(null, (client) => createPayouts(client, driverId, true));
  res.json({ created });
});

router.get('/:id', async (req, res) => {
  res.json({ payout: await payoutView(cleanId(req.params.id)) });
});

router.post('/:id/pay', async (req, res) => {
  const id = cleanId(req.params.id);
  const reference = cleanReference(bodyOf(req).transferReference, 'transferReference');
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    const request = await lockTransferRequest(client, 'payout_requests', id);
    if (!request.account_usable) {
      throw new AppError(409, 'ACCOUNT_CHANGED', 'The payout account changed, reject this request');
    }
    const { rows: [owner] } = await client.query(
      `SELECT driver_balance(t.driver_id)::numeric(12,2) AS balance,
              driver_balance(t.driver_id) >= t.amount AS enough
       FROM payout_requests t JOIN driver_profiles o ON o.user_id = t.driver_id
       WHERE t.id = $1 FOR UPDATE OF o`,
      [id],
    );
    if (!owner.enough) {
      throw new AppError(409, 'BALANCE_TOO_LOW', 'The balance is now less than this request, reject it', {
        balance: owner.balance, amount: request.amount,
      });
    }
    await client.query(
      "UPDATE payout_requests SET status = 'paid', transfer_reference = $2 WHERE id = $1",
      [id, reference],
    );
  });
  const item = await payoutView(id);
  await notify(item, 'payout_paid', { reference });
  res.json({ payout: item });
});

router.post('/:id/reject', async (req, res) => {
  const id = cleanId(req.params.id);
  const reason = cleanText(bodyOf(req).reason, 'reason', 500);
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    await lockTransferRequest(client, 'payout_requests', id);
    await client.query(
      "UPDATE payout_requests SET status = 'rejected', rejection_reason = $2 WHERE id = $1",
      [id, reason],
    );
  });
  const item = await payoutView(id);
  await notify(item, 'payout_rejected', { reason });
  res.json({ payout: item });
});

export default router;
