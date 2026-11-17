import { query } from '../db.js';
import { AppError } from '../errors.js';
import { imageUrl } from './storage.js';
import { invalid, cleanMoney } from './validate.js';

const PAGE_SIZE = 20;
const REFERENCE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9 ._/-]{3,39}$/;

export const TOPUP_STATUSES = ['awaiting_verification', 'verified', 'rejected'];

export const TOPUP_SQL = `
  SELECT t.id, t.customer_id, t.amount, t.proof_storage_key, t.transfer_reference, t.status,
         t.verified_at, t.rejection_reason, t.created_at, u.full_name, u.email, u.phone
  FROM customer_topups t JOIN users u ON u.id = t.customer_id`;

export function cleanAmount(value, field) {
  if (typeof value !== 'string') {
    throw invalid(field, `${field} is required`);
  }
  return cleanMoney(value, field, true);
}

export function cleanReference(value, field) {
  const reference = typeof value === 'string' ? value.trim() : '';
  if (!REFERENCE_PATTERN.test(reference)) {
    throw invalid(field, `${field} must be 4 to 40 letters or numbers`);
  }
  return reference;
}

export function transferUsed() {
  return new AppError(409, 'TRANSFER_USED', 'This transfer was already used for another payment');
}

export async function lockTransfer(client, reference) {
  const key = reference.toLowerCase();
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [key]);
  const { rows: [claim] } = await client.query(
    'SELECT 1 FROM incoming_transfer_claims WHERE transfer_reference = $1',
    [key],
  );
  if (claim) {
    throw transferUsed();
  }
}

export function toTopup(row, baseUrl, forAdmin = false) {
  const topup = {
    id: row.id,
    amount: row.amount,
    status: row.status,
    reference: row.transfer_reference,
    rejectionReason: row.rejection_reason,
    proofUrl: imageUrl(row.proof_storage_key, baseUrl),
    createdAt: row.created_at,
    reviewedAt: row.verified_at,
  };
  if (forAdmin) {
    topup.customer = { id: row.customer_id, fullName: row.full_name, email: row.email, phone: row.phone };
  }
  return topup;
}

export async function loadWallet(customerId) {
  const { rows: [row] } = await query(
    `SELECT customer_balance(u.id)::numeric(12,2) AS balance,
            customer_available_balance(u.id)::numeric(12,2) AS available,
            u.default_payment_method,
            (SELECT count(*)::int FROM customer_topups t
             WHERE t.customer_id = u.id AND t.status = 'awaiting_verification') AS pending_count,
            (SELECT COALESCE(sum(t.amount), 0)::numeric(12,2) FROM customer_topups t
             WHERE t.customer_id = u.id AND t.status = 'awaiting_verification') AS pending_amount
     FROM users u WHERE u.id = $1`,
    [customerId],
  );
  return {
    balance: row.balance,
    available: row.available,
    pendingTopups: { count: row.pending_count, amount: row.pending_amount },
    defaultPaymentMethod: row.default_payment_method,
  };
}

function toEntry(row) {
  return {
    id: row.id,
    type: row.entry_type,
    amount: row.amount,
    balanceAfter: row.balance_after,
    shipmentId: row.shipment_id,
    topupId: row.topup_id,
    withdrawalId: row.withdrawal_id,
    note: row.entry_type === 'manual_adjustment' ? row.note : null,
    createdAt: row.created_at,
  };
}

export async function listEntries(customerId, page) {
  const { rows } = await query(
    `SELECT * FROM (
       SELECT e.id, e.entry_type, e.amount, e.topup_id, e.withdrawal_id, e.note, e.created_at,
              COALESCE(p.shipment_id, r.shipment_id, tr.shipment_id) AS shipment_id,
              sum(e.amount) OVER (ORDER BY e.id) AS balance_after
       FROM customer_wallet_transactions e
       LEFT JOIN payments p ON p.id = e.payment_id
       LEFT JOIN refunds r ON r.id = e.refund_id
       LEFT JOIN trips tr ON tr.id = e.trip_id
       WHERE e.customer_id = $1
     ) entries
     ORDER BY id DESC
     LIMIT ${PAGE_SIZE + 1} OFFSET $2`,
    [customerId, (page - 1) * PAGE_SIZE],
  );
  return {
    transactions: rows.slice(0, PAGE_SIZE).map(toEntry),
    page,
    hasMore: rows.length > PAGE_SIZE,
  };
}
