import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanInteger, cleanText } from '../../lib/validate.js';
import { bodyOf } from '../../lib/fields.js';
import { sendNotice } from '../../lib/mailer.js';
import { cleanReference } from '../../lib/wallet.js';
import {
  WITHDRAWAL_SQL, PAGE_SIZE, TRANSFER_STATUSES, toTransfer, listTransfers, lockTransferRequest,
} from '../../lib/payouts.js';

const router = Router();

async function withdrawalView(id) {
  const { rows: [row] } = await query(
    `SELECT list.*, customer_balance(list.user_id)::numeric(12,2) AS balance FROM (${WITHDRAWAL_SQL}) list
     WHERE list.id = $1`,
    [id],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Withdrawal not found');
  }
  const item = toTransfer(row, 'customer');
  item.customer.balance = row.balance;
  return item;
}

async function notify(item, kind, params) {
  const { rows: [user] } = await query(
    'SELECT email, preferred_language FROM users WHERE id = $1',
    [item.customer.id],
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
  const { rows, total } = await listTransfers(WITHDRAWAL_SQL, status, search, page);
  res.json({
    withdrawals: rows.map((row) => toTransfer(row, 'customer')),
    page,
    pageSize: PAGE_SIZE,
    total,
  });
});

router.get('/:id', async (req, res) => {
  res.json({ withdrawal: await withdrawalView(cleanId(req.params.id)) });
});

router.post('/:id/pay', async (req, res) => {
  const id = cleanId(req.params.id);
  const reference = cleanReference(bodyOf(req).transferReference, 'transferReference');
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    const request = await lockTransferRequest(client, 'customer_withdrawals', id);
    if (!request.account_usable) {
      throw new AppError(409, 'ACCOUNT_CHANGED', 'The payout account changed, reject this request');
    }
    const { rows: [owner] } = await client.query(
      `SELECT customer_balance(t.customer_id)::numeric(12,2) AS balance,
              customer_balance(t.customer_id) >= t.amount AS enough
       FROM customer_withdrawals t JOIN users o ON o.id = t.customer_id
       WHERE t.id = $1 FOR UPDATE OF o`,
      [id],
    );
    if (!owner.enough) {
      throw new AppError(409, 'BALANCE_TOO_LOW', 'The balance is now less than this request, reject it', {
        balance: owner.balance, amount: request.amount,
      });
    }
    await client.query(
      "UPDATE customer_withdrawals SET status = 'paid', transfer_reference = $2 WHERE id = $1",
      [id, reference],
    );
  });
  const item = await withdrawalView(id);
  await notify(item, 'withdrawal_paid', { reference });
  res.json({ withdrawal: item });
});

router.post('/:id/reject', async (req, res) => {
  const id = cleanId(req.params.id);
  const reason = cleanText(bodyOf(req).reason, 'reason', 500);
  await withTransaction({ id: req.user.id, role: 'admin' }, async (client) => {
    await lockTransferRequest(client, 'customer_withdrawals', id);
    await client.query(
      "UPDATE customer_withdrawals SET status = 'rejected', rejection_reason = $2 WHERE id = $1",
      [id, reason],
    );
  });
  const item = await withdrawalView(id);
  await notify(item, 'withdrawal_rejected', { reason });
  res.json({ withdrawal: item });
});

export default router;
