import express, { Router } from 'express';
import { query, withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { bodyOf, readFields } from '../lib/fields.js';
import { cleanId, cleanChoice, cleanInteger, cleanOptionalText } from '../lib/validate.js';
import {
  IMAGE_TYPES, MAX_IMAGE_MB, readImage, saveImage,
} from '../lib/storage.js';
import {
  shipmentFields, stateOf, buildColumns, insertShipment, updateShipment, priceShipment, loadShipment, lockShipment,
  requireDraft, toShipmentSummary, SUMMARY_SQL, STATUS_FILTERS,
} from '../lib/shipments.js';
import { BEFORE_LOADING, loadTracking, lockLiveTrip } from '../lib/trips.js';

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

async function reply(req, res, id, status = 200) {
  res.status(status).json({ shipment: await loadShipment(id, baseUrl(req)) });
}

async function acceptedQuote(client, id) {
  const { rows: [quote] } = await client.query(
    "SELECT * FROM price_quotes WHERE shipment_id = $1 AND status = 'accepted'",
    [id],
  );
  return quote;
}

function priceLocked() {
  return new AppError(409, 'PRICE_ACCEPTED', 'The price was accepted, withdraw it first to change the shipment');
}

router.get('/', async (req, res) => {
  const status = req.query.status === undefined ? null
    : cleanChoice(req.query.status, 'status', Object.keys(STATUS_FILTERS));
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
  const { rows } = await query(
    `${SUMMARY_SQL}
     WHERE s.customer_id = $1 AND ($2::text IS NULL OR s.status = ANY(string_to_array($2, ',')))
     ORDER BY s.created_at DESC, s.id DESC
     LIMIT ${PAGE_SIZE + 1} OFFSET $3`,
    [req.user.id, status ? STATUS_FILTERS[status].join(',') : null, (page - 1) * PAGE_SIZE],
  );
  res.json({
    shipments: rows.slice(0, PAGE_SIZE).map(toShipmentSummary),
    page,
    hasMore: rows.length > PAGE_SIZE,
  });
});

router.post('/', async (req, res) => {
  const body = bodyOf(req);
  const state = readFields(body, shipmentFields, 'create');
  const id = await withTransaction(actorOf(req), async (client) => {
    const columns = await buildColumns(client, state, Object.keys(body));
    return insertShipment(client, req.user.id, columns);
  });
  await reply(req, res, id, 201);
});

router.get('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const { rows: [own] } = await query('SELECT 1 FROM shipments WHERE id = $1 AND customer_id = $2', [id, req.user.id]);
  if (!own) {
    throw new AppError(404, 'NOT_FOUND', 'Shipment not found');
  }
  await reply(req, res, id);
});

router.get('/:id/tracking', async (req, res) => {
  const id = cleanId(req.params.id);
  const { rows: [own] } = await query('SELECT 1 FROM shipments WHERE id = $1 AND customer_id = $2', [id, req.user.id]);
  if (!own) {
    throw new AppError(404, 'NOT_FOUND', 'Shipment not found');
  }
  res.json({ tracking: await loadTracking(id) });
});

router.patch('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const changes = readFields(body, shipmentFields, 'update');
  await withTransaction(actorOf(req), async (client) => {
    const row = await lockShipment(client, id, req.user.id);
    requireDraft(row);
    if (await acceptedQuote(client, id)) {
      throw priceLocked();
    }
    const columns = await buildColumns(client, { ...stateOf(row), ...changes }, Object.keys(body));
    await updateShipment(client, id, columns);
  });
  await reply(req, res, id);
});

router.put('/:id/photos', imageBody, async (req, res) => {
  const id = cleanId(req.params.id);
  const image = readImage(req);
  const check = async (client) => {
    const row = await lockShipment(client, id, req.user.id);
    requireDraft(row);
    if (await acceptedQuote(client, id)) {
      throw priceLocked();
    }
    const { rows: [count] } = await client.query(
      'SELECT count(*)::int AS n FROM shipment_item_images WHERE shipment_id = $1',
      [id],
    );
    if (count.n >= MAX_PHOTOS) {
      throw new AppError(409, 'TOO_MANY_PHOTOS', `A shipment can have at most ${MAX_PHOTOS} photos`);
    }
  };
  await withTransaction(null, check);
  const key = await saveImage(image, `wasla/shipments/${id}`);
  await withTransaction(actorOf(req), async (client) => {
    await check(client);
    await client.query('INSERT INTO shipment_item_images (shipment_id, storage_key) VALUES ($1, $2)', [id, key]);
  });
  await reply(req, res, id, 201);
});

router.delete('/:id/photos/:photoId', async (req, res) => {
  const id = cleanId(req.params.id);
  const photoId = cleanId(req.params.photoId);
  await withTransaction(actorOf(req), async (client) => {
    const row = await lockShipment(client, id, req.user.id);
    requireDraft(row);
    if (await acceptedQuote(client, id)) {
      throw priceLocked();
    }
    const { rowCount } = await client.query(
      'DELETE FROM shipment_item_images WHERE id = $1 AND shipment_id = $2 RETURNING id',
      [photoId, id],
    );
    if (rowCount === 0) {
      throw new AppError(404, 'NOT_FOUND', 'Photo not found');
    }
  });
  await reply(req, res, id);
});

router.post('/:id/quotes', async (req, res) => {
  const id = cleanId(req.params.id);
  const recommended = await withTransaction(actorOf(req), async (client) => {
    const row = await lockShipment(client, id, req.user.id);
    requireDraft(row);
    if (await acceptedQuote(client, id)) {
      throw priceLocked();
    }
    return priceShipment(client, row);
  });
  res.status(201).json({ shipment: await loadShipment(id, baseUrl(req), recommended) });
});

router.post('/:id/quotes/:quoteId/accept', async (req, res) => {
  const id = cleanId(req.params.id);
  const quoteId = cleanId(req.params.quoteId);
  await withTransaction(actorOf(req), async (client) => {
    const row = await lockShipment(client, id, req.user.id);
    requireDraft(row);
    if (await acceptedQuote(client, id)) {
      throw new AppError(409, 'PRICE_ACCEPTED', 'A price is already accepted for this shipment');
    }
    const { rows: [quote] } = await client.query(
      `SELECT status, shipment_version, expires_at < now() AS expired
       FROM price_quotes WHERE id = $1 AND shipment_id = $2`,
      [quoteId, id],
    );
    if (!quote) {
      throw new AppError(404, 'NOT_FOUND', 'Price not found');
    }
    if (quote.status !== 'offered') {
      throw new AppError(409, 'QUOTE_NOT_AVAILABLE', `This price is ${quote.status}, ask for a new price`);
    }
    if (quote.expired) {
      throw new AppError(409, 'QUOTE_EXPIRED', 'This price expired, ask for a new price');
    }
    if (quote.shipment_version !== row.details_version) {
      throw new AppError(409, 'QUOTE_OUTDATED', 'The shipment changed after this price, ask for a new price');
    }
    await client.query("UPDATE price_quotes SET status = 'accepted' WHERE id = $1", [quoteId]);
    await client.query(
      "UPDATE price_quotes SET status = 'rejected' WHERE shipment_id = $1 AND status = 'offered'",
      [id],
    );
  });
  await reply(req, res, id);
});

router.post('/:id/withdraw-price', async (req, res) => {
  const id = cleanId(req.params.id);
  await withTransaction(actorOf(req), async (client) => {
    const row = await lockShipment(client, id, req.user.id);
    requireDraft(row);
    const quote = await acceptedQuote(client, id);
    if (!quote) {
      throw new AppError(409, 'PRICE_NOT_ACCEPTED', 'No price is accepted for this shipment');
    }
    await client.query("UPDATE price_quotes SET status = 'withdrawn' WHERE id = $1", [quote.id]);
  });
  await reply(req, res, id);
});

router.post('/:id/request', async (req, res) => {
  const id = cleanId(req.params.id);
  await withTransaction(actorOf(req), async (client) => {
    const row = await lockShipment(client, id, req.user.id);
    requireDraft(row);
    const quote = await acceptedQuote(client, id);
    if (!quote) {
      throw new AppError(409, 'PRICE_NOT_ACCEPTED', 'Accept a price first');
    }
    if (new Date(row.pickup_window_end).getTime() < Date.now()) {
      throw new AppError(409, 'PRICE_TOO_OLD', 'The pickup time passed, withdraw the price and ask for a new one');
    }
    const { rows: [customer] } = await client.query(
      `SELECT accepted_latest_policies($1) AS policies, customer_balance($1) AS balance,
              customer_available_balance($1) AS available`,
      [req.user.id],
    );
    if (!customer.policies) {
      throw new AppError(409, 'POLICIES_NOT_ACCEPTED', 'Accept the new terms first');
    }
    if (Number(customer.balance) < 0) {
      throw new AppError(409, 'WALLET_NEGATIVE', 'Your wallet is negative, top it up first', {
        balance: customer.balance,
      });
    }
    if (row.payment_method === 'wallet' && Number(customer.available) < Number(quote.customer_amount)) {
      throw new AppError(409, 'WALLET_TOO_LOW', 'Your wallet balance is not enough, top it up or pay cash', {
        available: customer.available, needed: quote.customer_amount,
      });
    }
    await client.query("UPDATE shipments SET status = 'searching_driver' WHERE id = $1", [id]);
  });
  await reply(req, res, id);
});

router.post('/:id/cancel', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const reason = body.reason === undefined ? null : cleanOptionalText(body.reason, 'reason', 500);
  await withTransaction(actorOf(req, reason), async (client) => {
    const firstTrip = await lockLiveTrip(client, id);
    const row = await lockShipment(client, id, req.user.id);
    if (row.status === 'draft' || row.status === 'searching_driver') {
      await client.query(
        "UPDATE shipments SET status = 'cancelled', cancellation_reason = $2 WHERE id = $1",
        [id, reason],
      );
      return;
    }
    if (row.status !== 'driver_assigned' && row.status !== 'in_progress') {
      throw new AppError(409, 'WRONG_STATUS', `The shipment is ${row.status}`, { status: row.status });
    }
    const trip = firstTrip || await lockLiveTrip(client, id);
    if (!BEFORE_LOADING.includes(trip.status)) {
      throw new AppError(409, 'CARGO_LOADED', 'The cargo is loaded, contact support to cancel');
    }
    if (trip.status !== 'assigned' && body.acceptFee !== true) {
      throw new AppError(409, 'CANCEL_FEE', 'The driver is on the way, cancelling now has a fee',
        { fee: trip.cancellation_fee });
    }
    await client.query(
      "UPDATE trips SET status = 'cancelled', cancellation_reason = $2 WHERE id = $1",
      [trip.id, reason],
    );
  });
  await reply(req, res, id);
});

export default router;
