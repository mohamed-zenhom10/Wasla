import { query } from '../db.js';
import { AppError } from '../errors.js';

export const PAGE_SIZE = 20;
export const TRANSFER_STATUSES = ['requested', 'paid', 'rejected'];

const CAIRO_DAY = "date_trunc('day', now() AT TIME ZONE 'Africa/Cairo')";
const WEEK_START = `(${CAIRO_DAY} - make_interval(
  days => (extract(dow FROM ${CAIRO_DAY})::int - ps.driver_payout_weekday + 7) % 7)) AT TIME ZONE 'Africa/Cairo'`;

const transferSql = (table, owner) => `
  SELECT t.id, t.${owner} AS user_id, t.amount, t.status, t.transfer_reference, t.rejection_reason,
         t.created_at, t.processed_at, u.full_name, u.email, u.phone,
         a.method, a.holder_name, a.bank_name, a.account_number,
         a.review_status = 'approved' AND a.superseded_at IS NULL AS account_usable
  FROM ${table} t
  JOIN users u ON u.id = t.${owner}
  JOIN payout_accounts a ON a.id = t.payout_account_id`;

export const PAYOUT_SQL = transferSql('payout_requests', 'driver_id');
export const WITHDRAWAL_SQL = transferSql('customer_withdrawals', 'customer_id');

export function toTransfer(row, ownerKey = null) {
  const transfer = {
    id: row.id,
    amount: row.amount,
    status: row.status,
    reference: row.transfer_reference,
    rejectionReason: row.rejection_reason,
    account: {
      method: row.method,
      holderName: row.holder_name,
      bankName: row.bank_name,
      accountLast4: row.account_number.slice(-4),
    },
    createdAt: row.created_at,
    processedAt: row.processed_at,
  };
  if (ownerKey) {
    transfer.account.accountNumber = row.account_number;
    transfer.account.usable = row.account_usable;
    transfer[ownerKey] = { id: row.user_id, fullName: row.full_name, email: row.email, phone: row.phone };
  }
  return transfer;
}

export async function listOwnTransfers(sql, userId, page) {
  const { rows } = await query(
    `SELECT * FROM (${sql}) list WHERE list.user_id = $1
     ORDER BY list.id DESC
     LIMIT ${PAGE_SIZE + 1} OFFSET $2`,
    [userId, (page - 1) * PAGE_SIZE],
  );
  return { rows: rows.slice(0, PAGE_SIZE), page, hasMore: rows.length > PAGE_SIZE };
}

export async function listTransfers(sql, status, search, page) {
  const like = search ? `%${search.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const { rows } = await query(
    `SELECT list.*, count(*) OVER () AS total FROM (${sql}) list
     WHERE ($1 = 'all' OR list.status = $1)
       AND ($2::text IS NULL OR list.id::text = $3 OR list.full_name ILIKE $2 OR list.email ILIKE $2
            OR list.phone LIKE $2 OR list.transfer_reference ILIKE $2)
     ORDER BY CASE WHEN $1 = 'requested' THEN list.id END, list.id DESC
     LIMIT ${PAGE_SIZE} OFFSET $4`,
    [status, like, search, (page - 1) * PAGE_SIZE],
  );
  return { rows, total: rows.length ? Number(rows[0].total) : 0 };
}

export async function lockTransferRequest(client, table, id) {
  const { rows: [row] } = await client.query(
    `SELECT t.status, t.amount, a.review_status = 'approved' AND a.superseded_at IS NULL AS account_usable
     FROM ${table} t JOIN payout_accounts a ON a.id = t.payout_account_id
     WHERE t.id = $1 FOR UPDATE OF t`,
    [id],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Request not found');
  }
  if (row.status !== 'requested') {
    throw new AppError(409, 'ALREADY_REVIEWED', `This request is already ${row.status}`, { status: row.status });
  }
  return row;
}

export async function createPayouts(client, driverId = null, everyDay = false) {
  const { rowCount } = await client.query(
    `INSERT INTO payout_requests (driver_id, payout_account_id, amount)
     SELECT dp.user_id, a.id, driver_balance(dp.user_id)
     FROM driver_profiles dp
     JOIN users u ON u.id = dp.user_id AND u.account_status = 'active'
     JOIN payout_accounts a ON a.user_id = dp.user_id AND a.superseded_at IS NULL AND a.review_status = 'approved'
     CROSS JOIN platform_settings ps
     WHERE ($1::bigint IS NULL OR dp.user_id = $1)
       AND driver_balance(dp.user_id) > 0
       AND NOT EXISTS (
         SELECT 1 FROM payout_requests p
         WHERE p.driver_id = dp.user_id AND (p.status = 'requested' OR (NOT $2 AND p.created_at >= ${WEEK_START})))
     ON CONFLICT DO NOTHING`,
    [driverId, everyDay],
  );
  return rowCount;
}
