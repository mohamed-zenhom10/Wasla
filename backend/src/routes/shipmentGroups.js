import express, { Router } from 'express';
import { query, withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { bodyOf, readFields } from '../lib/fields.js';
import {
  cleanId, cleanRef, cleanChoice, cleanInteger, cleanOptionalText,
} from '../lib/validate.js';
import {
  IMAGE_TYPES, MAX_IMAGE_MB, readImage, saveImage,
} from '../lib/storage.js';
import { STATUS_FILTERS } from '../lib/shipments.js';
import { cleanCouponCode, checkCoupon } from '../lib/coupons.js';
import {
  groupFields, stopFields, lockGroup, requireEditable, findStop, createGroup, updateGroup, addStop, updateStop,
  removeStop, reorderStops, readTiming, priceGroup, acceptGroupPrice, withdrawGroupPrice, requestGroup, cancelGroup,
  lockGroupTrips, loadGroup, loadGroupTracking, GROUP_LIST_SQL, toGroupSummary,
} from '../lib/groups.js';

const router = Router();
const PAGE_SIZE = 20;
const MAX_PHOTOS = 10;
const imageBody = express.raw({ type: IMAGE_TYPES, limit: `${MAX_IMAGE_MB}mb` });

router.use(requireAuth, requireRole('customer'));

function actorOf(req, reason) {
  return { id: req.user.id, role: 'customer', reason };
}

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

async function reply(req, res, id, status = 200, recommended = undefined) {
  res.status(status).json({ group: await loadGroup(id, baseUrl(req), recommended) });
}

function change(req, work) {
  const id = cleanId(req.params.id);
  return withTransaction(actorOf(req), async (client) => work(client, await lockGroup(client, id, req.user.id)));
}

async function requireOwn(req, id) {
  const { rows: [own] } = await query(
    'SELECT 1 FROM shipment_groups WHERE id = $1 AND customer_id = $2',
    [id, req.user.id],
  );
  if (!own) {
    throw new AppError(404, 'NOT_FOUND', 'Grouped order not found');
  }
}

router.get('/', async (req, res) => {
  const status = req.query.status === undefined ? null
    : cleanChoice(req.query.status, 'status', Object.keys(STATUS_FILTERS));
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
  const { rows } = await query(
    `${GROUP_LIST_SQL}
     WHERE ($2::text IS NULL OR l.status = ANY(string_to_array($2, ',')))
     ORDER BY l.created_at DESC, l.id DESC
     LIMIT ${PAGE_SIZE + 1} OFFSET $3`,
    [req.user.id, status ? STATUS_FILTERS[status].join(',') : null, (page - 1) * PAGE_SIZE],
  );
  res.json({
    groups: rows.slice(0, PAGE_SIZE).map(toGroupSummary),
    page,
    hasMore: rows.length > PAGE_SIZE,
  });
});

router.post('/', async (req, res) => {
  const state = readFields(bodyOf(req), groupFields, 'create');
  const id = await withTransaction(actorOf(req), (client) => createGroup(client, req.user.id, state));
  await reply(req, res, id, 201);
});

router.get('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  await requireOwn(req, id);
  await reply(req, res, id);
});

router.patch('/:id', async (req, res) => {
  const changes = readFields(bodyOf(req), groupFields, 'update');
  await change(req, async (client, locked) => {
    requireEditable(locked);
    await updateGroup(client, locked, changes);
  });
  await reply(req, res, req.params.id);
});

router.post('/:id/stops', async (req, res) => {
  const state = readFields(bodyOf(req), stopFields, 'create');
  await change(req, async (client, locked) => {
    requireEditable(locked);
    await addStop(client, locked, req.user.id, state);
  });
  await reply(req, res, req.params.id, 201);
});

router.patch('/:id/stops/:stopId', async (req, res) => {
  const stopId = cleanId(req.params.stopId);
  const body = bodyOf(req);
  const changes = readFields(body, stopFields, 'update');
  await change(req, async (client, locked) => {
    requireEditable(locked);
    await updateStop(client, locked, stopId, changes, Object.keys(body));
  });
  await reply(req, res, req.params.id);
});

router.delete('/:id/stops/:stopId', async (req, res) => {
  const stopId = cleanId(req.params.stopId);
  await change(req, async (client, locked) => {
    requireEditable(locked);
    await removeStop(client, locked, stopId);
  });
  await reply(req, res, req.params.id);
});

router.put('/:id/order', async (req, res) => {
  const body = bodyOf(req);
  await change(req, async (client, locked) => {
    if (locked.status !== 'draft') {
      throw new AppError(409, 'WRONG_STATUS', `The grouped order is ${locked.status}`, { status: locked.status });
    }
    await reorderStops(client, locked, body.stopIds);
  });
  await reply(req, res, req.params.id);
});

router.put('/:id/stops/:stopId/photos', imageBody, async (req, res) => {
  const stopId = cleanId(req.params.stopId);
  const image = readImage(req);
  const check = async (client, locked) => {
    requireEditable(locked);
    findStop(locked, stopId);
    const { rows: [count] } = await client.query(
      'SELECT count(*)::int AS n FROM shipment_item_images WHERE shipment_id = $1',
      [stopId],
    );
    if (count.n >= MAX_PHOTOS) {
      throw new AppError(409, 'TOO_MANY_PHOTOS', `A drop-off can have at most ${MAX_PHOTOS} photos`);
    }
  };
  await change(req, check);
  const key = await saveImage(image, `wasla/shipments/${stopId}`);
  await change(req, async (client, locked) => {
    await check(client, locked);
    await client.query('INSERT INTO shipment_item_images (shipment_id, storage_key) VALUES ($1, $2)', [stopId, key]);
  });
  await reply(req, res, req.params.id, 201);
});

router.delete('/:id/stops/:stopId/photos/:photoId', async (req, res) => {
  const stopId = cleanId(req.params.stopId);
  const photoId = cleanId(req.params.photoId);
  await change(req, async (client, locked) => {
    requireEditable(locked);
    findStop(locked, stopId);
    const { rowCount } = await client.query(
      'DELETE FROM shipment_item_images WHERE id = $1 AND shipment_id = $2 RETURNING id',
      [photoId, stopId],
    );
    if (rowCount === 0) {
      throw new AppError(404, 'NOT_FOUND', 'Photo not found');
    }
  });
  await reply(req, res, req.params.id);
});

router.post('/:id/quotes', async (req, res) => {
  const body = bodyOf(req);
  const code = body.couponCode === undefined || body.couponCode === null || body.couponCode === ''
    ? null : cleanCouponCode(body.couponCode, 'couponCode');
  const recommended = await change(req, async (client, locked) => {
    requireEditable(locked);
    const timing = await readTiming(client, body);
    const coupon = code ? await checkCoupon(client, 'lower(code) = lower($1)', code, req.user.id) : null;
    return priceGroup(client, locked, timing, coupon);
  });
  await reply(req, res, req.params.id, 201, recommended);
});

router.post('/:id/quotes/accept', async (req, res) => {
  const body = bodyOf(req);
  const vehicleTypeId = cleanRef(body.vehicleTypeId, 'vehicleTypeId');
  await change(req, async (client, locked) => {
    requireEditable(locked);
    await acceptGroupPrice(client, locked, vehicleTypeId, req.user.id);
  });
  await reply(req, res, req.params.id);
});

router.post('/:id/withdraw-price', async (req, res) => {
  await change(req, (client, locked) => withdrawGroupPrice(client, locked));
  await reply(req, res, req.params.id);
});

router.post('/:id/request', async (req, res) => {
  await change(req, (client, locked) => requestGroup(client, locked, req.user.id));
  await reply(req, res, req.params.id);
});

router.get('/:id/tracking', async (req, res) => {
  const id = cleanId(req.params.id);
  await requireOwn(req, id);
  res.json({ tracking: await loadGroupTracking(id) });
});

router.post('/:id/cancel', async (req, res) => {
  const body = bodyOf(req);
  const reason = body.reason === undefined ? null : cleanOptionalText(body.reason, 'reason', 500);
  const id = cleanId(req.params.id);
  await requireOwn(req, id);
  await withTransaction(actorOf(req, reason), async (client) => {
    const trips = await lockGroupTrips(client, id);
    const locked = await lockGroup(client, id, req.user.id);
    await cancelGroup(client, locked, reason, trips.length ? trips : await lockGroupTrips(client, id),
      body.acceptFee);
  });
  await reply(req, res, id);
});

export default router;
