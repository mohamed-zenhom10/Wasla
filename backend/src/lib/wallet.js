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
             WHERE t.customer_id = u.id AND t.status = 'awaiting_verification') AS pending_amount,
            (SELECT w.amount FROM customer_withdrawals w
             WHERE w.customer_id = u.id AND w.status = 'requested') AS pending_withdrawal
     FROM users u WHERE u.id = $1`,
    [customerId],
  );
  return {
    balance: row.balance,
    available: row.available,
    pendingTopups: { count: row.pending_count, amount: row.pending_amount },
    pendingWithdrawal: row.pending_withdrawal,
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

export const SETTLEMENT_SQL = `
  SELECT t.id, t.driver_id, t.amount, t.proof_storage_key, t.transfer_reference, t.status,
         t.verified_at, t.rejection_reason, t.created_at, u.full_name, u.email, u.phone
  FROM driver_settlements t JOIN users u ON u.id = t.driver_id`;

export function toSettlement(row, baseUrl, forAdmin = false) {
  const settlement = {
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
    settlement.driver = { id: row.driver_id, fullName: row.full_name, email: row.email, phone: row.phone };
  }
  return settlement;
}

export function cleanAdjustment(value, field) {
  const text = typeof value === 'number' && Number.isFinite(value) ? String(value) : value;
  if (typeof text !== 'string' || !/^-?[0-9]{1,7}(\.[0-9]{1,2})?$/.test(text.trim())) {
    throw invalid(field, `${field} must be a number like 50.00 or -50.00`);
  }
  if (Number(text) === 0) {
    throw invalid(field, `${field} cannot be zero`);
  }
  return text.trim();
}

const CAIRO_DAY = "date_trunc('day', now() AT TIME ZONE 'Africa/Cairo')";

export async function loadDriverWallet(driverId) {
  const { rows: [row] } = await query(
    `SELECT driver_balance(dp.user_id)::numeric(12,2) AS balance,
            driver_debt_limit(dp.user_id)::numeric(12,2) AS debt_limit,
            dp.debt_limit_override,
            GREATEST(driver_balance(dp.user_id) + driver_debt_limit(dp.user_id), 0)::numeric(12,2) AS debt_left,
            driver_balance(dp.user_id) < -driver_debt_limit(dp.user_id) AS blocked,
            (SELECT count(*)::int FROM driver_settlements s
             WHERE s.driver_id = dp.user_id AND s.status = 'awaiting_verification') AS pending_count,
            (SELECT COALESCE(sum(s.amount), 0)::numeric(12,2) FROM driver_settlements s
             WHERE s.driver_id = dp.user_id AND s.status = 'awaiting_verification') AS pending_amount,
            (SELECT p.amount FROM payout_requests p
             WHERE p.driver_id = dp.user_id AND p.status = 'requested') AS pending_payout,
            e.today_net, e.today_trips, e.week_net, e.week_trips
     FROM driver_profiles dp
     CROSS JOIN (
       SELECT ${CAIRO_DAY} AT TIME ZONE 'Africa/Cairo' AS day_start,
              (${CAIRO_DAY} - make_interval(days => (extract(dow FROM ${CAIRO_DAY})::int + 1) % 7))
                AT TIME ZONE 'Africa/Cairo' AS week_start
     ) b
     CROSS JOIN LATERAL (
       SELECT COALESCE(sum(earned) FILTER (WHERE done_at >= b.day_start), 0)::numeric(12,2) AS today_net,
              count(*) FILTER (WHERE delivered AND done_at >= b.day_start)::int AS today_trips,
              COALESCE(sum(earned), 0)::numeric(12,2) AS week_net,
              count(*) FILTER (WHERE delivered)::int AS week_trips
       FROM (
         SELECT t.status = 'delivered' AS delivered,
                COALESCE(t.delivered_at, t.cancelled_at) AS done_at,
                CASE WHEN t.status = 'delivered' THEN t.driver_earning_amount ELSE t.cancellation_fee END AS earned
         FROM trips t
         WHERE t.driver_id = dp.user_id AND t.status IN ('delivered', 'cancelled')
           AND COALESCE(t.delivered_at, t.cancelled_at) >= b.week_start
       ) done
     ) e
     WHERE dp.user_id = $1`,
    [driverId],
  );
  if (!row) {
    return null;
  }
  return {
    balance: row.balance,
    debtLimit: row.debt_limit,
    debtLimitOverride: row.debt_limit_override,
    debtLeft: row.debt_left,
    blocked: row.blocked,
    pendingSettlements: { count: row.pending_count, amount: row.pending_amount },
    pendingPayout: row.pending_payout,
    today: { net: row.today_net, trips: row.today_trips },
    week: { net: row.week_net, trips: row.week_trips },
  };
}

function toDriverEntry(row) {
  return {
    id: row.id,
    type: row.entry_type,
    amount: row.amount,
    balanceAfter: row.balance_after,
    tripId: row.trip_id,
    shipmentId: row.shipment_id,
    settlementId: row.settlement_id,
    payoutId: row.payout_request_id,
    note: row.entry_type === 'manual_adjustment' ? row.note : null,
    createdAt: row.created_at,
  };
}

export async function listDriverEntries(driverId, page) {
  const { rows } = await query(
    `SELECT * FROM (
       SELECT e.id, e.entry_type, e.amount, e.trip_id, e.settlement_id, e.payout_request_id, e.note, e.created_at,
              tr.shipment_id, sum(e.amount) OVER (ORDER BY e.id) AS balance_after
       FROM wallet_transactions e
       LEFT JOIN trips tr ON tr.id = e.trip_id
       WHERE e.driver_id = $1
     ) entries
     ORDER BY id DESC
     LIMIT ${PAGE_SIZE + 1} OFFSET $2`,
    [driverId, (page - 1) * PAGE_SIZE],
  );
  return {
    transactions: rows.slice(0, PAGE_SIZE).map(toDriverEntry),
    page,
    hasMore: rows.length > PAGE_SIZE,
  };
}
