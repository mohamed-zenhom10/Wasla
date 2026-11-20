import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanInteger } from '../../lib/validate.js';
import {
  bodyOf, readReason, readFields, insertRow, updateRow,
} from '../../lib/fields.js';
import {
  PAGE_SIZE, LOCKED_WHEN_USED, COUPON_SQL, couponFields, toCoupon, loadCoupon,
} from '../../lib/coupons.js';

const router = Router();
const STATES = ['active', 'scheduled', 'expired', 'used_up', 'inactive'];

function adminActor(req, body) {
  return { id: req.user.id, role: 'admin', reason: readReason(body) };
}

async function couponView(id) {
  const coupon = toCoupon(await loadCoupon(id));
  const { rows } = await query(
    `SELECT r.id, r.customer_id, u.full_name, r.shipment_id, r.discount_amount, r.created_at, r.cancelled_at
     FROM coupon_redemptions r JOIN users u ON u.id = r.customer_id
     WHERE r.coupon_id = $1
     ORDER BY r.id DESC LIMIT 20`,
    [id],
  );
  coupon.lastUses = rows.map((row) => ({
    id: row.id,
    customer: { id: row.customer_id, fullName: row.full_name },
    shipmentId: row.shipment_id,
    discountAmount: row.discount_amount,
    usedAt: row.created_at,
    cancelledAt: row.cancelled_at,
  }));
  return coupon;
}

router.get('/', async (req, res) => {
  const state = req.query.state === undefined ? 'all' : cleanChoice(req.query.state, 'state', [...STATES, 'all']);
  const search = typeof req.query.search === 'string' && req.query.search.trim()
    ? `%${req.query.search.trim().replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
  const { rows } = await query(
    `SELECT list.*, count(*) OVER () AS total FROM (${COUPON_SQL}) list
     WHERE ($1 = 'all' OR list.state = $1) AND ($2::text IS NULL OR list.code ILIKE $2)
     ORDER BY list.id DESC
     LIMIT ${PAGE_SIZE} OFFSET $3`,
    [state, search, (page - 1) * PAGE_SIZE],
  );
  res.json({
    coupons: rows.map(toCoupon),
    page,
    pageSize: PAGE_SIZE,
    total: rows.length ? Number(rows[0].total) : 0,
  });
});

router.post('/', async (req, res) => {
  const body = bodyOf(req);
  const values = readFields(body, couponFields, 'create');
  const id = await withTransaction(adminActor(req, body), async (client) => {
    if (!values.starts_at) {
      const { rows: [now] } = await client.query('SELECT now() AS at');
      values.starts_at = now.at;
    }
    values.created_by = req.user.id;
    const row = await insertRow(client, 'coupons', couponFields, values, 'id');
    return row.id;
  });
  res.status(201).json({ coupon: await couponView(id) });
});

router.get('/:id', async (req, res) => {
  res.json({ coupon: await couponView(cleanId(req.params.id)) });
});

router.patch('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const values = readFields(body, couponFields, 'update');
  await withTransaction(adminActor(req, body), async (client) => {
    const { rows: [coupon] } = await client.query('SELECT id FROM coupons WHERE id = $1 FOR UPDATE', [id]);
    if (!coupon) {
      throw new AppError(404, 'NOT_FOUND', 'Coupon not found');
    }
    const locked = Object.keys(values).filter((column) => LOCKED_WHEN_USED.includes(column));
    if (locked.length > 0) {
      const { rows: [used] } = await client.query(
        'SELECT 1 FROM coupon_redemptions WHERE coupon_id = $1 LIMIT 1',
        [id],
      );
      if (used) {
        const field = Object.keys(couponFields).find((key) => couponFields[key].column === locked[0]);
        throw new AppError(409, 'COUPON_IN_USE',
          'This coupon was used, so only its dates, uses and isActive can change', { field });
      }
    }
    await updateRow(client, 'coupons', couponFields, id, values, 'id');
  });
  res.json({ coupon: await couponView(id) });
});

export default router;
