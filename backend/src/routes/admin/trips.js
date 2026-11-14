import crypto from 'node:crypto';
import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { bodyOf } from '../../lib/fields.js';
import {
  cleanId, cleanChoice, cleanInteger, cleanText,
} from '../../lib/validate.js';
import {
  EXECUTING, FINISHED, BEFORE_LOADING, TRIP_SQL, toTrip, withPhotos, loadTracking,
} from '../../lib/trips.js';

const router = Router();
const PAGE_SIZE = 20;

function adminActor(req, reason) {
  return { id: req.user.id, role: 'admin', reason };
}

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

router.get('/trips', async (req, res) => {
  const status = req.query.status === undefined ? 'active'
    : cleanChoice(req.query.status, 'status', ['active', 'finished', 'all']);
  const search = typeof req.query.search === 'string' && req.query.search.trim()
    ? req.query.search.trim() : null;
  const like = search ? `%${search.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);

  const { rows } = await query(
    `SELECT t.id, t.status, t.shipment_id, t.fare_amount, t.planned_start_at, t.started_at, t.delivered_at,
            t.cancelled_at, t.cancellation_party, t.created_at,
            d.id AS driver_id, d.full_name AS driver_name, c.id AS customer_id, c.full_name AS customer_name,
            count(*) OVER () AS total
     FROM trips t
     JOIN users d ON d.id = t.driver_id
     JOIN shipments s ON s.id = t.shipment_id
     JOIN users c ON c.id = s.customer_id
     WHERE ($1 = 'all' OR (t.status = ANY($2::text[])) = ($1 = 'finished'))
       AND ($3::text IS NULL OR t.id::text = $4 OR s.id::text = $4
            OR d.full_name ILIKE $3 OR d.phone LIKE $3 OR c.full_name ILIKE $3 OR c.phone LIKE $3)
     ORDER BY t.created_at DESC, t.id DESC
     LIMIT ${PAGE_SIZE} OFFSET $5`,
    [status, FINISHED, like, search, (page - 1) * PAGE_SIZE],
  );
  res.json({
    trips: rows.map((row) => ({
      id: row.id,
      status: row.status,
      shipmentId: row.shipment_id,
      fareAmount: row.fare_amount,
      driver: { id: row.driver_id, name: row.driver_name },
      customer: { id: row.customer_id, name: row.customer_name },
      plannedStartAt: row.planned_start_at,
      startedAt: row.started_at,
      deliveredAt: row.delivered_at,
      cancelledAt: row.cancelled_at,
      cancellationParty: row.cancellation_party,
      createdAt: row.created_at,
    })),
    page,
    pageSize: PAGE_SIZE,
    total: rows.length ? Number(rows[0].total) : 0,
  });
});

router.get('/map', async (req, res) => {
  const { rows } = await query(
    `SELECT dp.user_id, u.full_name, u.phone, dp.is_online, dp.location_updated_at,
            ST_X(dp.current_location::geometry) AS lng, ST_Y(dp.current_location::geometry) AS lat,
            dp.location_updated_at < now() - make_interval(secs => ps.location_stale_seconds) AS is_stale,
            v.vehicle_type_id, v.plate_number, t.id AS trip_id, t.status AS trip_status, t.shipment_id
     FROM driver_profiles dp
     JOIN users u ON u.id = dp.user_id
     CROSS JOIN platform_settings ps
     LEFT JOIN vehicles v ON v.id = dp.active_vehicle_id
     LEFT JOIN LATERAL (
       SELECT id, status, shipment_id FROM trips
       WHERE driver_id = dp.user_id AND status = ANY($1::text[])
       ORDER BY id DESC
       LIMIT 1
     ) t ON true
     WHERE dp.current_location IS NOT NULL AND (dp.is_online OR t.id IS NOT NULL)
     ORDER BY dp.user_id`,
    [EXECUTING],
  );
  res.json({
    drivers: rows.map((row) => ({
      id: row.user_id,
      name: row.full_name,
      phone: row.phone,
      online: row.is_online,
      signal: row.is_stale ? 'lost' : 'live',
      location: { lat: Number(row.lat), lng: Number(row.lng), updatedAt: row.location_updated_at },
      vehicle: row.plate_number ? { vehicleTypeId: row.vehicle_type_id, plateNumber: row.plate_number } : null,
      trip: row.trip_id ? { id: row.trip_id, status: row.trip_status, shipmentId: row.shipment_id } : null,
    })),
  });
});

async function loadAdminTrip(id, url) {
  const { rows: [row] } = await query(`${TRIP_SQL} WHERE t.id = $1`, [id]);
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Trip not found');
  }
  const [{ rows: [extra] }, { rows: history }, { rows: path }] = await Promise.all([
    query(
      `SELECT t.driver_id, d.full_name, d.phone, t.vehicle_id, v.vehicle_type_id, v.plate_number, v.make, v.model,
              v.color, t.is_late_cancellation, t.cancellation_fee, t.commission_amount, t.driver_earning_amount
       FROM trips t JOIN users d ON d.id = t.driver_id JOIN vehicles v ON v.id = t.vehicle_id
       WHERE t.id = $1`,
      [id],
    ),
    query(
      `SELECT from_status, to_status, change_source, reason, created_at
       FROM trip_status_history WHERE trip_id = $1 ORDER BY id`,
      [id],
    ),
    query(
      `SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng, accuracy_m, recorded_at
       FROM trip_location_points WHERE trip_id = $1 ORDER BY recorded_at, id`,
      [id],
    ),
  ]);
  const trip = await withPhotos(toTrip(row), url);
  return {
    ...trip,
    customer: { name: row.customer_name, phone: row.customer_phone },
    recipient: row.recipient_name ? { name: row.recipient_name, phone: row.recipient_phone } : null,
    driver: { id: extra.driver_id, name: extra.full_name, phone: extra.phone },
    vehicle: {
      id: extra.vehicle_id,
      vehicleTypeId: extra.vehicle_type_id,
      plateNumber: extra.plate_number,
      make: extra.make,
      model: extra.model,
      color: extra.color,
    },
    isLateCancellation: extra.is_late_cancellation,
    cancellationFee: extra.cancellation_fee,
    finalCommission: extra.commission_amount,
    finalDriverEarning: extra.driver_earning_amount,
    timeline: history.map((h) => ({
      from: h.from_status, to: h.to_status, by: h.change_source, reason: h.reason, at: h.created_at,
    })),
    path: path.map((p) => ({
      lat: Number(p.lat),
      lng: Number(p.lng),
      accuracyM: p.accuracy_m === null ? null : Number(p.accuracy_m),
      at: p.recorded_at,
    })),
    tracking: await loadTracking(row.shipment_id),
  };
}

async function replyTrip(req, res, id) {
  res.json({ trip: await loadAdminTrip(id, baseUrl(req)) });
}

router.get('/trips/:id', async (req, res) => {
  await replyTrip(req, res, cleanId(req.params.id));
});

async function lockTrip(client, id) {
  const { rows: [trip] } = await client.query(
    `SELECT t.id, t.status, t.shipment_id, t.delivery_code_attempts, t.delivery_code_verified_at,
            ps.max_delivery_code_attempts, s.delivery_code
     FROM trips t
     JOIN shipments s ON s.id = t.shipment_id
     CROSS JOIN platform_settings ps
     WHERE t.id = $1
     FOR UPDATE OF t`,
    [id],
  );
  if (!trip) {
    throw new AppError(404, 'NOT_FOUND', 'Trip not found');
  }
  return trip;
}

router.post('/trips/:id/cancel', async (req, res) => {
  const id = cleanId(req.params.id);
  const reason = cleanText(bodyOf(req).reason, 'reason', 500);
  await withTransaction(adminActor(req, reason), async (client) => {
    const trip = await lockTrip(client, id);
    if (FINISHED.includes(trip.status)) {
      throw new AppError(409, 'TRIP_FINISHED', `The trip is ${trip.status}`, { status: trip.status });
    }
    if (!BEFORE_LOADING.includes(trip.status)) {
      throw new AppError(409, 'CARGO_LOADED', 'The cargo is loaded, cancelling needs a support ticket');
    }
    await client.query(
      `UPDATE trips SET status = 'cancelled', cancellation_party = 'platform', cancellation_reason = $2
       WHERE id = $1`,
      [id, reason],
    );
  });
  await replyTrip(req, res, id);
});

router.post('/trips/:id/new-code', async (req, res) => {
  const id = cleanId(req.params.id);
  await withTransaction(adminActor(req, 'new delivery code'), async (client) => {
    const trip = await lockTrip(client, id);
    if (trip.status !== 'arrived_at_dropoff' || trip.delivery_code_verified_at
        || trip.delivery_code_attempts < trip.max_delivery_code_attempts) {
      throw new AppError(409, 'CODE_NOT_LOCKED', 'A new code is only for a trip whose code tries ran out');
    }
    await client.query('SELECT id FROM shipments WHERE id = $1 FOR UPDATE', [trip.shipment_id]);
    let code = trip.delivery_code;
    while (code === trip.delivery_code) {
      code = String(crypto.randomInt(0, 10000)).padStart(4, '0');
    }
    await client.query('UPDATE shipments SET delivery_code = $2 WHERE id = $1', [trip.shipment_id, code]);
  });
  await replyTrip(req, res, id);
});

export default router;
