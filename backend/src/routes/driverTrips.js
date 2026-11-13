import express, { Router } from 'express';
import { withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { bodyOf } from '../lib/fields.js';
import {
  cleanId, cleanChoice, cleanInteger, cleanText,
} from '../lib/validate.js';
import {
  IMAGE_TYPES, MAX_IMAGE_MB, readImage, saveImage,
} from '../lib/storage.js';
import { POINT_SQL } from '../lib/route.js';
import {
  readPoint, readAccuracy, loadState, blockersOf, blockerError,
} from '../lib/presence.js';
import {
  closeOldOffers, makeOffers, listOffers, createTrip,
} from '../lib/dispatch.js';
import {
  EXECUTING, FINISHED, loadTrip, currentTrip, listTrips, trackPoint,
} from '../lib/trips.js';

const router = Router();
const PAGE_SIZE = 20;
const MAX_PHOTOS = 6;
const BEFORE_LOADING = ['assigned', 'heading_to_pickup', 'arrived_at_pickup'];
const PHOTO_STATUS = { pickup: 'arrived_at_pickup', delivery: 'arrived_at_dropoff' };
const imageBody = express.raw({ type: IMAGE_TYPES, limit: `${MAX_IMAGE_MB}mb` });

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

function actorOf(req, reason) {
  return { id: req.user.id, role: 'driver', reason };
}

function offerGone() {
  return new AppError(409, 'OFFER_GONE', 'This request is no longer available');
}

router.get('/offers', async (req, res) => {
  const offers = await withTransaction(actorOf(req), async (client) => {
    const state = await loadState(client, req.user.id, true);
    await closeOldOffers(client, req.user.id);
    if (!state || !state.is_online || blockersOf(state).length > 0) {
      return [];
    }
    await makeOffers(client, req.user.id);
    return listOffers(client, req.user.id);
  });
  res.json({ offers });
});

async function lockOffer(client, id, driverId) {
  const { rows: [offer] } = await client.query(
    `SELECT o.id, o.shipment_id, o.price_quote_id, o.driver_id, o.vehicle_id, o.response,
            o.expires_at <= now() AS is_late
     FROM dispatch_offers o
     WHERE o.id = $1 AND o.driver_id = $2 AND o.shipment_id IS NOT NULL
     FOR UPDATE`,
    [id, driverId],
  );
  if (!offer) {
    throw new AppError(404, 'NOT_FOUND', 'Request not found');
  }
  if (offer.response === 'expired' || (offer.response === 'pending' && offer.is_late)) {
    throw new AppError(409, 'OFFER_EXPIRED', 'The time to answer this request is over');
  }
  if (offer.response !== 'pending') {
    throw offerGone();
  }
  return offer;
}

router.post('/offers/:id/accept', async (req, res) => {
  const id = cleanId(req.params.id);
  const tripId = await withTransaction(actorOf(req), async (client) => {
    const state = await loadState(client, req.user.id, true);
    const [blocker] = blockersOf(state);
    if (blocker) {
      throw blockerError(blocker, state);
    }
    if (!state.is_online) {
      throw new AppError(409, 'NOT_ONLINE', 'You are offline, go online first');
    }
    const offer = await lockOffer(client, id, req.user.id);
    const { rows: [shipment] } = await client.query(
      'SELECT status FROM shipments WHERE id = $1 FOR UPDATE',
      [offer.shipment_id],
    );
    if (shipment.status !== 'searching_driver' || offer.vehicle_id !== state.active_vehicle_id) {
      throw offerGone();
    }
    return createTrip(client, offer);
  });
  res.status(201).json({ trip: await loadTrip(tripId, req.user.id, baseUrl(req)) });
});

router.post('/offers/:id/decline', async (req, res) => {
  const id = cleanId(req.params.id);
  const offers = await withTransaction(actorOf(req), async (client) => {
    const offer = await lockOffer(client, id, req.user.id);
    await client.query(
      `UPDATE dispatch_offers SET response = 'rejected', responded_at = now() WHERE id = $1`,
      [offer.id],
    );
    return listOffers(client, req.user.id);
  });
  res.json({ offers });
});

router.get('/trips', async (req, res) => {
  const status = req.query.status === undefined ? 'active'
    : cleanChoice(req.query.status, 'status', ['active', 'finished']);
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
  const trips = await listTrips(req.user.id, status === 'finished', PAGE_SIZE + 1, (page - 1) * PAGE_SIZE);
  res.json({ trips: trips.slice(0, PAGE_SIZE), page, hasMore: trips.length > PAGE_SIZE });
});

router.get('/trips/current', async (req, res) => {
  res.json({ trip: await currentTrip(req.user.id, baseUrl(req)) });
});

router.get('/trips/:id', async (req, res) => {
  res.json({ trip: await loadTrip(cleanId(req.params.id), req.user.id, baseUrl(req)) });
});

async function lockTrip(client, id, driverId, status) {
  const { rows: [trip] } = await client.query(
    `SELECT t.id, t.status, t.vehicle_id, t.shipment_id, t.price_quote_id, t.delivery_code_verified_at,
            s.payment_method, s.fare_paid_by, q.customer_amount
     FROM trips t
     JOIN shipments s ON s.id = t.shipment_id
     JOIN price_quotes q ON q.id = t.price_quote_id
     WHERE t.id = $1 AND t.driver_id = $2
     FOR UPDATE OF t`,
    [id, driverId],
  );
  if (!trip) {
    throw new AppError(404, 'NOT_FOUND', 'Trip not found');
  }
  if (trip.status !== status) {
    throw new AppError(409, 'WRONG_STEP', `The trip is ${trip.status}`, { status: trip.status });
  }
  return trip;
}

async function moveTrip(client, id, status) {
  await client.query('UPDATE trips SET status = $2 WHERE id = $1', [id, status]);
}

async function countPhotos(client, id, stage) {
  const { rows: [row] } = await client.query(
    'SELECT count(*)::int AS n FROM trip_photos WHERE trip_id = $1 AND stage = $2',
    [id, stage],
  );
  return row.n;
}

async function saveLocation(client, driverId, body) {
  if (body.lat === undefined && body.lng === undefined) {
    return;
  }
  const point = readPoint(body);
  const accuracy = readAccuracy(body);
  await client.query(
    `UPDATE driver_profiles SET current_location = ${POINT_SQL('$2', '$3')}, location_updated_at = now()
     WHERE user_id = $1 AND is_online`,
    [driverId, point.lng, point.lat],
  );
  await trackPoint(client, driverId, point, accuracy);
}

async function replyTrip(req, res, id) {
  res.json({ trip: await loadTrip(id, req.user.id, baseUrl(req)) });
}

router.post('/trips/:id/start', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const point = readPoint(body);
  const accuracy = readAccuracy(body);
  await withTransaction(actorOf(req), async (client) => {
    const state = await loadState(client, req.user.id, true);
    const trip = await lockTrip(client, id, req.user.id, 'assigned');
    const [blocker] = blockersOf(state);
    if (blocker) {
      throw blockerError(blocker, state);
    }
    if (state.active_vehicle_id !== trip.vehicle_id) {
      throw new AppError(409, 'VEHICLE_CHANGED', 'This trip was accepted with another vehicle, cancel it');
    }
    const { rows: [running] } = await client.query(
      'SELECT id FROM trips WHERE driver_id = $1 AND status = ANY($2::text[]) AND id <> $3 LIMIT 1',
      [req.user.id, EXECUTING, id],
    );
    if (running) {
      throw new AppError(409, 'ANOTHER_TRIP_RUNNING', 'Finish your current trip first', { tripId: running.id });
    }
    await client.query(
      `UPDATE driver_profiles
       SET current_location = ${POINT_SQL('$2', '$3')}, location_updated_at = now(), is_online = true
       WHERE user_id = $1`,
      [req.user.id, point.lng, point.lat],
    );
    await moveTrip(client, id, 'heading_to_pickup');
    await trackPoint(client, req.user.id, point, accuracy);
  });
  await replyTrip(req, res, id);
});

router.post('/trips/:id/arrive-pickup', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  await withTransaction(actorOf(req), async (client) => {
    await lockTrip(client, id, req.user.id, 'heading_to_pickup');
    await saveLocation(client, req.user.id, body);
    await moveTrip(client, id, 'arrived_at_pickup');
  });
  await replyTrip(req, res, id);
});

router.put('/trips/:id/photos/:stage', imageBody, async (req, res) => {
  const id = cleanId(req.params.id);
  const stage = cleanChoice(req.params.stage, 'stage', ['pickup', 'delivery']);
  const image = readImage(req);
  const check = async (client) => {
    await lockTrip(client, id, req.user.id, PHOTO_STATUS[stage]);
    if (await countPhotos(client, id, stage) >= MAX_PHOTOS) {
      throw new AppError(409, 'TOO_MANY_PHOTOS', `A trip can have at most ${MAX_PHOTOS} ${stage} photos`);
    }
  };
  await withTransaction(null, check);
  const key = await saveImage(image, `wasla/trips/${id}`);
  await withTransaction(actorOf(req), async (client) => {
    await check(client);
    await client.query(
      'INSERT INTO trip_photos (trip_id, stage, storage_key, uploaded_by) VALUES ($1, $2, $3, $4)',
      [id, stage, key, req.user.id],
    );
  });
  res.status(201).json({ trip: await loadTrip(id, req.user.id, baseUrl(req)) });
});

async function collectCash(client, trip, driverId, payer, status) {
  await client.query(
    `INSERT INTO payments (shipment_id, price_quote_id, method, payer, amount, status,
                           collected_on_trip_id, collected_by_driver_id)
     VALUES ($1, $2, 'cash', $3, $4, $5, $6, $7)`,
    [trip.shipment_id, trip.price_quote_id, payer, trip.customer_amount, status, trip.id, driverId],
  );
}

function cashNotCollected(trip) {
  return new AppError(409, 'CASH_NOT_COLLECTED', 'Collect the cash first', { amount: trip.customer_amount });
}

router.post('/trips/:id/loaded', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  await withTransaction(actorOf(req), async (client) => {
    const trip = await lockTrip(client, id, req.user.id, 'arrived_at_pickup');
    if (await countPhotos(client, id, 'pickup') === 0) {
      throw new AppError(409, 'PHOTO_REQUIRED', 'Take at least one photo of the cargo first');
    }
    if (trip.payment_method === 'cash' && trip.fare_paid_by === 'sender') {
      if (body.cashCollected !== true) {
        throw cashNotCollected(trip);
      }
      await collectCash(client, trip, req.user.id, 'sender', 'collected');
    }
    await moveTrip(client, id, 'loaded');
  });
  await replyTrip(req, res, id);
});

router.post('/trips/:id/depart', async (req, res) => {
  const id = cleanId(req.params.id);
  const vehicleFit = cleanChoice(bodyOf(req).vehicleFit, 'vehicleFit', ['suitable', 'too_small', 'too_large']);
  await withTransaction(actorOf(req), async (client) => {
    await lockTrip(client, id, req.user.id, 'loaded');
    await client.query('UPDATE trips SET vehicle_fit = $2 WHERE id = $1', [id, vehicleFit]);
    await moveTrip(client, id, 'heading_to_dropoff');
  });
  await replyTrip(req, res, id);
});

router.post('/trips/:id/arrive-dropoff', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  await withTransaction(actorOf(req), async (client) => {
    await lockTrip(client, id, req.user.id, 'heading_to_dropoff');
    await saveLocation(client, req.user.id, body);
    await moveTrip(client, id, 'arrived_at_dropoff');
  });
  await replyTrip(req, res, id);
});

router.post('/trips/:id/verify-code', async (req, res) => {
  const id = cleanId(req.params.id);
  const { code } = bodyOf(req);
  if (typeof code !== 'string' || !/^[0-9]{4}$/.test(code)) {
    throw new AppError(400, 'INVALID_INPUT', 'code must be 4 digits', { field: 'code' });
  }
  const result = await withTransaction(actorOf(req), async (client) => {
    const trip = await lockTrip(client, id, req.user.id, 'arrived_at_dropoff');
    if (trip.delivery_code_verified_at) {
      return { correct: true };
    }
    const { rows: [left] } = await client.query(
      `SELECT ps.max_delivery_code_attempts - t.delivery_code_attempts AS n
       FROM trips t CROSS JOIN platform_settings ps WHERE t.id = $1`,
      [id],
    );
    if (left.n <= 0) {
      return { locked: true };
    }
    const { rows: [row] } = await client.query('SELECT verify_delivery_code($1, $2) AS ok', [id, code]);
    return { correct: row.ok, attemptsLeft: left.n - 1 };
  });
  if (result.locked || (!result.correct && result.attemptsLeft <= 0)) {
    throw new AppError(409, 'CODE_LOCKED', 'Too many wrong codes, contact support for a new code');
  }
  if (!result.correct) {
    throw new AppError(409, 'WRONG_CODE', 'The code is wrong', { attemptsLeft: result.attemptsLeft });
  }
  await replyTrip(req, res, id);
});

router.post('/trips/:id/deliver', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  await withTransaction(actorOf(req), async (client) => {
    const trip = await lockTrip(client, id, req.user.id, 'arrived_at_dropoff');
    if (!trip.delivery_code_verified_at) {
      throw new AppError(409, 'CODE_NOT_VERIFIED', 'Enter the delivery code first');
    }
    if (await countPhotos(client, id, 'delivery') === 0) {
      throw new AppError(409, 'PHOTO_REQUIRED', 'Take at least one photo of the delivered cargo first');
    }
    if (trip.payment_method === 'cash' && trip.fare_paid_by === 'recipient') {
      if (body.payment === 'collected') {
        await collectCash(client, trip, req.user.id, 'recipient', 'collected');
      } else if (body.payment === 'refused') {
        await collectCash(client, trip, req.user.id, 'recipient', 'charged_to_sender');
      } else {
        throw cashNotCollected(trip);
      }
    }
    await moveTrip(client, id, 'delivered');
  });
  await replyTrip(req, res, id);
});

router.post('/trips/:id/cancel', async (req, res) => {
  const id = cleanId(req.params.id);
  const reason = cleanText(bodyOf(req).reason, 'reason', 500);
  await withTransaction(actorOf(req, reason), async (client) => {
    const { rows: [trip] } = await client.query(
      'SELECT status FROM trips WHERE id = $1 AND driver_id = $2 FOR UPDATE',
      [id, req.user.id],
    );
    if (!trip) {
      throw new AppError(404, 'NOT_FOUND', 'Trip not found');
    }
    if (FINISHED.includes(trip.status)) {
      throw new AppError(409, 'TRIP_FINISHED', `The trip is ${trip.status}`, { status: trip.status });
    }
    if (!BEFORE_LOADING.includes(trip.status)) {
      throw new AppError(409, 'CARGO_LOADED', 'The cargo is loaded, contact support to cancel');
    }
    await client.query(
      "UPDATE trips SET status = 'cancelled', cancellation_reason = $2 WHERE id = $1",
      [id, reason],
    );
  });
  res.json({ trip: await loadTrip(id, req.user.id) });
});

export default router;
