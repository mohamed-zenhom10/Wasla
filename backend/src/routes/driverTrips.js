import { Router } from 'express';
import { withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { bodyOf } from '../lib/fields.js';
import {
  cleanId, cleanChoice, cleanInteger, cleanText,
} from '../lib/validate.js';
import { loadState, blockersOf, blockerError } from '../lib/presence.js';
import {
  closeOldOffers, makeOffers, listOffers, createTrip,
} from '../lib/dispatch.js';
import {
  FINISHED, loadTrip, currentTrip, listTrips,
} from '../lib/trips.js';

const router = Router();
const PAGE_SIZE = 20;
const BEFORE_LOADING = ['assigned', 'heading_to_pickup', 'arrived_at_pickup'];

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
  res.status(201).json({ trip: await loadTrip(tripId, req.user.id) });
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
  res.json({ trip: await currentTrip(req.user.id) });
});

router.get('/trips/:id', async (req, res) => {
  res.json({ trip: await loadTrip(cleanId(req.params.id), req.user.id) });
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
