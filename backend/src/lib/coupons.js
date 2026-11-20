import { query } from '../db.js';
import { AppError } from '../errors.js';
import {
  invalid, cleanDecimal, cleanMoney, cleanInteger, cleanBoolean, cleanChoice,
} from './validate.js';

export const PAGE_SIZE = 20;
const CODE_PATTERN = /^[A-Z0-9][A-Z0-9_-]{2,29}$/;
export const LOCKED_WHEN_USED = ['code', 'discount_type', 'discount_value', 'max_discount', 'min_order_amount'];

export function cleanCouponCode(value, field) {
  const code = typeof value === 'string' ? value.trim().toUpperCase() : '';
  if (!CODE_PATTERN.test(code)) {
    throw invalid(field, `${field} must be 3 to 30 letters, numbers, - or _`);
  }
  return code;
}

function cleanTime(value, field) {
  const time = typeof value === 'string' ? new Date(value) : null;
  if (!time || Number.isNaN(time.getTime()) || !/^\d{4}-\d{2}-\d{2}T/.test(value)) {
    throw invalid(field, `${field} must be a date and time like 2026-12-01T00:00:00+02:00`);
  }
  return time.toISOString();
}

const optionalMoney = (v, f) => (v === null ? null : cleanMoney(v, f, true));
const optionalUses = (v, f) => (v === null ? null : cleanInteger(v, f, 1, 1000000));

export const couponFields = {
  code: { column: 'code', clean: cleanCouponCode, required: true },
  discountType: { column: 'discount_type', clean: (v, f) => cleanChoice(v, f, ['percent', 'fixed']), required: true },
  discountValue: {
    column: 'discount_value',
    clean: (v, f) => cleanDecimal(v, f, { max: 1000000, places: 2, above: true }),
    required: true,
  },
  maxDiscount: { column: 'max_discount', clean: optionalMoney },
  minOrderAmount: { column: 'min_order_amount', clean: (v, f) => cleanMoney(v, f) },
  startsAt: { column: 'starts_at', clean: cleanTime },
  endsAt: { column: 'ends_at', clean: cleanTime, required: true },
  maxTotalUses: { column: 'max_total_uses', clean: optionalUses },
  maxUsesPerCustomer: { column: 'max_uses_per_customer', clean: (v, f) => cleanInteger(v, f, 1, 1000) },
  isActive: { column: 'is_active', clean: cleanBoolean },
};

export const COUPON_SQL = `
  SELECT c.*,
         (SELECT count(*)::int FROM coupon_redemptions r
          WHERE r.coupon_id = c.id AND r.cancelled_at IS NULL) AS used_count,
         (SELECT COALESCE(sum(r.discount_amount), 0)::numeric(12,2) FROM coupon_redemptions r
          WHERE r.coupon_id = c.id AND r.cancelled_at IS NULL) AS total_discount,
         CASE WHEN NOT c.is_active THEN 'inactive'
              WHEN now() < c.starts_at THEN 'scheduled'
              WHEN now() > c.ends_at THEN 'expired'
              WHEN c.max_total_uses IS NOT NULL AND (SELECT count(*) FROM coupon_redemptions r
                   WHERE r.coupon_id = c.id AND r.cancelled_at IS NULL) >= c.max_total_uses THEN 'used_up'
              ELSE 'active' END AS state
  FROM coupons c`;

export function toCoupon(row) {
  return {
    id: row.id,
    code: row.code,
    discountType: row.discount_type,
    discountValue: row.discount_value,
    maxDiscount: row.max_discount,
    minOrderAmount: row.min_order_amount,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    maxTotalUses: row.max_total_uses,
    maxUsesPerCustomer: row.max_uses_per_customer,
    isActive: row.is_active,
    state: row.state,
    usedCount: row.used_count,
    totalDiscount: row.total_discount,
    createdAt: row.created_at,
  };
}

export async function loadCoupon(id) {
  const { rows: [row] } = await query(`SELECT * FROM (${COUPON_SQL}) list WHERE list.id = $1`, [id]);
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Coupon not found');
  }
  return row;
}

function couponError(status, code, message, extra = {}) {
  return new AppError(status, code, message, { field: 'couponCode', ...extra });
}

export async function checkCoupon(client, where, value, customerId) {
  const { rows: [locked] } = await client.query(`SELECT id FROM coupons WHERE ${where} FOR UPDATE`, [value]);
  if (!locked) {
    throw couponError(409, 'COUPON_INVALID', 'This coupon code is not valid');
  }
  const { rows: [row] } = await client.query(
    `SELECT c.id, c.code, c.is_active, c.starts_at, c.ends_at, c.min_order_amount,
            now() < c.starts_at AS not_started, now() > c.ends_at AS ended,
            c.max_total_uses IS NOT NULL AND (SELECT count(*) FROM coupon_redemptions r
              WHERE r.coupon_id = c.id AND r.cancelled_at IS NULL) >= c.max_total_uses AS used_up,
            (SELECT count(*) FROM coupon_redemptions r
              WHERE r.coupon_id = c.id AND r.customer_id = $2 AND r.cancelled_at IS NULL) >= c.max_uses_per_customer
              AS used_by_me
     FROM coupons c WHERE c.id = $1`,
    [locked.id, customerId],
  );
  if (!row.is_active) {
    throw couponError(409, 'COUPON_INVALID', 'This coupon code is not valid');
  }
  if (row.not_started) {
    throw couponError(409, 'COUPON_NOT_STARTED', 'This coupon cannot be used yet', { startsAt: row.starts_at });
  }
  if (row.ended) {
    throw couponError(409, 'COUPON_EXPIRED', 'This coupon has expired', { endsAt: row.ends_at });
  }
  if (row.used_up) {
    throw couponError(409, 'COUPON_USED_UP', 'This coupon has no uses left');
  }
  if (row.used_by_me) {
    throw couponError(409, 'COUPON_ALREADY_USED', 'You already used this coupon');
  }
  return row;
}

export function minOrderError(coupon) {
  return couponError(409, 'COUPON_MIN_ORDER', `This coupon needs an order of at least ${coupon.min_order_amount}`, {
    minOrderAmount: coupon.min_order_amount,
  });
}
