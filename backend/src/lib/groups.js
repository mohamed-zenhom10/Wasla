import { query } from '../db.js';
import { AppError } from '../errors.js';
import { imageUrl } from './storage.js';
import { estimateRoute, POINT_SQL } from './route.js';
import { shipmentTrip } from './trips.js';
import { checkCoupon, minOrderError } from './coupons.js';
import { invalid, cleanInteger, cleanChoice, cleanRef } from './validate.js';
import {
  shipmentFields, SHIPMENT_COLUMNS, stateOf, buildColumns, insertShipment, updateShipment, cleanPlace, cleanTime,
  scheduledStart, fittingTypes, quoteParts, insertQuote, cents, toPlace, WINDOW_MINUTES,
} from './shipments.js';

export const MIN_STOPS = 2;
const REMOVED = 'removed_from_group';

export const groupFields = {
  pickup: { column: 'pickup', clean: cleanPlace, required: true },
  helpersCount: { column: 'helpersCount', clean: (v, f) => cleanInteger(v, f, 0, 20) },
};

const STOP_KEYS = [
  'cargoCategoryId', 'sizeOptionId', 'cargoDescription', 'itemCount', 'isFragile', 'weightKg', 'dropoff',
  'paymentMethod', 'farePaidBy', 'recipientName', 'recipientPhone',
];

export const stopFields = Object.fromEntries(STOP_KEYS.map((key) => [key, shipmentFields[key]]));

const GROUP_STATUS = `(SELECT CASE
    WHEN count(*) = 0 THEN 'draft'
    WHEN count(*) FILTER (WHERE x.status <> 'cancelled') = 0 THEN 'cancelled'
    WHEN bool_or(x.status = 'draft') THEN 'draft'
    WHEN bool_and(x.status = 'delivered') FILTER (WHERE x.status <> 'cancelled') THEN 'delivered'
    WHEN bool_or(x.status IN ('in_progress', 'delivered')) THEN 'in_progress'
    WHEN bool_or(x.status = 'driver_assigned') THEN 'driver_assigned'
    ELSE 'searching_driver' END
  FROM shipments x WHERE x.group_id = g.id)`;

const GROUP_COLUMNS = `g.*,
  ST_X(g.pickup_location::geometry) AS pickup_lng, ST_Y(g.pickup_location::geometry) AS pickup_lat`;

const idList = (stops) => stops.map((stop) => stop.id).join(',');
const IN_LIST = (param) => `ANY(string_to_array(${param}, ',')::bigint[])`;

function groupPickup(group) {
  return {
    address: group.pickup_address,
    lat: Number(group.pickup_lat),
    lng: Number(group.pickup_lng),
    notes: group.pickup_notes,
  };
}

function liveStatus(stops) {
  const statuses = stops.map((stop) => stop.status);
  if (statuses.includes('draft')) {
    return 'draft';
  }
  if (statuses.every((status) => status === 'delivered')) {
    return 'delivered';
  }
  if (statuses.some((status) => status === 'in_progress' || status === 'delivered')) {
    return 'in_progress';
  }
  if (statuses.includes('driver_assigned')) {
    return 'driver_assigned';
  }
  return 'searching_driver';
}

export async function lockGroup(client, id, customerId) {
  const { rows: [group] } = await client.query(
    `SELECT ${GROUP_COLUMNS} FROM shipment_groups g WHERE g.id = $1 AND g.customer_id = $2 FOR UPDATE`,
    [id, customerId],
  );
  if (!group) {
    throw new AppError(404, 'NOT_FOUND', 'Grouped order not found');
  }
  const { rows: stops } = await client.query(
    `SELECT ${SHIPMENT_COLUMNS},
            EXISTS (SELECT 1 FROM price_quotes q WHERE q.shipment_id = s.id AND q.status = 'accepted') AS priced
     FROM shipments s WHERE s.group_id = $1 AND s.status <> 'cancelled'
     ORDER BY s.delivery_sequence
     FOR UPDATE OF s`,
    [id],
  );
  let status = 'draft';
  if (stops.length > 0) {
    status = liveStatus(stops);
  } else {
    const { rows: [all] } = await client.query('SELECT count(*)::int AS n FROM shipments WHERE group_id = $1', [id]);
    status = all.n > 0 ? 'cancelled' : 'draft';
  }
  return { group, stops, status };
}

function wrongStatus(status) {
  return new AppError(409, 'WRONG_STATUS', `The grouped order is ${status}`, { status });
}

export function requireDraft(locked) {
  if (locked.status !== 'draft') {
    throw wrongStatus(locked.status);
  }
}

export function requireEditable(locked) {
  requireDraft(locked);
  if (locked.stops.some((stop) => stop.priced)) {
    throw new AppError(409, 'PRICE_ACCEPTED', 'The price was accepted, withdraw it first to change the order');
  }
}

export function findStop(locked, stopId) {
  const stop = locked.stops.find((item) => item.id === stopId);
  if (!stop) {
    throw new AppError(404, 'NOT_FOUND', 'Drop-off not found');
  }
  return stop;
}

function stopState(row) {
  const state = stateOf(row);
  return Object.fromEntries(STOP_KEYS.map((key) => [key, state[key]]));
}

async function buildStop(client, group, state, changed) {
  if (!state.recipientName || !state.recipientPhone) {
    throw invalid(state.recipientName ? 'recipientPhone' : 'recipientName',
      'Every drop-off needs the recipient name and phone');
  }
  const columns = await buildColumns(client, {
    ...state,
    pickup: groupPickup(group),
    helpersCount: group.helpers_count,
    requestedVehicleTypeId: null,
    pickupType: 'now',
    pickupAt: null,
  }, changed);
  delete columns.pickup_type;
  delete columns.pickup_window_start;
  delete columns.pickup_window_end;
  return columns;
}

async function expireQuotes(client, groupId) {
  await client.query(
    `UPDATE price_quotes q SET status = 'expired'
     FROM shipments s
     WHERE s.id = q.shipment_id AND s.group_id = $1 AND q.status = 'offered'`,
    [groupId],
  );
}

export async function createGroup(client, customerId, state) {
  const { rows: [row] } = await client.query(
    `INSERT INTO shipment_groups (customer_id, pickup_address, pickup_location, pickup_notes, helpers_count)
     VALUES ($1, $2, ${POINT_SQL('$3', '$4')}, $5, $6) RETURNING id`,
    [customerId, state.pickup.address, state.pickup.lng, state.pickup.lat, state.pickup.notes,
      state.helpersCount || 0],
  );
  return row.id;
}

export async function updateGroup(client, locked, changes) {
  const { group, stops } = locked;
  const pickup = changes.pickup || groupPickup(group);
  const helpers = changes.helpersCount === undefined ? group.helpers_count : changes.helpersCount;
  const routes = [];
  for (const stop of stops) {
    try {
      routes.push(await estimateRoute(client, pickup, toPlace(stop, 'dropoff')));
    } catch (err) {
      if (err.code === 'SAME_PLACE') {
        throw new AppError(400, 'SAME_PLACE', 'The pickup is too close to one of the drop-offs', {
          field: 'pickup', stopId: stop.id,
        });
      }
      throw err;
    }
  }
  await client.query(
    `UPDATE shipment_groups
     SET pickup_address = $2, pickup_location = ${POINT_SQL('$3', '$4')}, pickup_notes = $5, helpers_count = $6
     WHERE id = $1`,
    [group.id, pickup.address, pickup.lng, pickup.lat, pickup.notes, helpers],
  );
  for (const [i, stop] of stops.entries()) {
    await client.query(
      'UPDATE shipments SET route_distance_m = $2, route_duration_s = $3 WHERE id = $1',
      [stop.id, routes[i].distanceM, routes[i].durationS],
    );
  }
}

export async function addStop(client, locked, customerId, state) {
  const { group, stops } = locked;
  const { rows: [settings] } = await client.query('SELECT max_group_stops FROM platform_settings WHERE id = 1');
  if (stops.length >= settings.max_group_stops) {
    throw new AppError(409, 'TOO_MANY_STOPS', `A grouped order can have at most ${settings.max_group_stops} drop-offs`,
      { max: settings.max_group_stops });
  }
  const columns = await buildStop(client, group, state, Object.keys(state));
  const { rows: [next] } = await client.query(
    'SELECT COALESCE(max(delivery_sequence), 0) + 1 AS n FROM shipments WHERE group_id = $1',
    [group.id],
  );
  const start = stops.length ? new Date(stops[0].pickup_window_start) : new Date();
  const id = await insertShipment(client, customerId, {
    ...columns,
    group_id: group.id,
    delivery_sequence: next.n,
    pickup_type: stops.length ? stops[0].pickup_type : 'now',
    pickup_window_start: start.toISOString(),
    pickup_window_end: new Date(start.getTime() + WINDOW_MINUTES * 60000).toISOString(),
  });
  await expireQuotes(client, group.id);
  return id;
}

export async function updateStop(client, locked, stopId, changes, changed) {
  const stop = findStop(locked, stopId);
  const columns = await buildStop(client, locked.group, { ...stopState(stop), ...changes }, changed);
  await updateShipment(client, stop.id, columns);
}

export async function removeStop(client, locked, stopId) {
  const stop = findStop(locked, stopId);
  if (locked.stops.length === 1) {
    throw new AppError(409, 'LAST_STOP', 'This is the last drop-off, cancel the grouped order instead');
  }
  await client.query(
    "UPDATE shipments SET status = 'cancelled', cancellation_reason = $2 WHERE id = $1",
    [stop.id, REMOVED],
  );
  await expireQuotes(client, locked.group.id);
}

export async function reorderStops(client, locked, value) {
  if (!Array.isArray(value)) {
    throw invalid('stopIds', 'stopIds must be a list of the drop-off ids in the new order');
  }
  const ids = value.map((item) => cleanRef(item, 'stopIds'));
  const live = locked.stops.map((stop) => stop.id);
  if (ids.length !== live.length || new Set(ids).size !== ids.length || !ids.every((id) => live.includes(id))) {
    throw invalid('stopIds', 'Send every drop-off of the order once');
  }
  const numbers = locked.stops.map((stop) => stop.delivery_sequence).sort((a, b) => a - b);
  await client.query(
    `UPDATE shipments s SET delivery_sequence = x.n
     FROM (SELECT unnest(string_to_array($2, ','))::bigint AS id, unnest(string_to_array($3, ','))::int AS n) x
     WHERE s.id = x.id AND s.group_id = $1`,
    [locked.group.id, ids.join(','), numbers.join(',')],
  );
}

export async function readTiming(client, body) {
  const pickupType = cleanChoice(body.pickupType, 'pickupType', ['now', 'scheduled']);
  const hasTime = body.pickupAt !== undefined && body.pickupAt !== null;
  if (pickupType === 'now') {
    if (hasTime) {
      throw invalid('pickupAt', 'pickupAt is only for a scheduled pickup');
    }
    return { pickupType, start: null };
  }
  const start = await scheduledStart(client, hasTime ? cleanTime(body.pickupAt, 'pickupAt') : null);
  return { pickupType, start: start.toISOString() };
}

export async function priceGroup(client, locked, timing, coupon) {
  const { stops } = locked;
  if (stops.length < MIN_STOPS) {
    throw new AppError(409, 'GROUP_TOO_SMALL', `A grouped order needs at least ${MIN_STOPS} drop-offs`,
      { min: MIN_STOPS });
  }
  const ids = idList(stops);
  const { rows: [missing] } = await client.query(
    `SELECT s.id FROM shipments s
     WHERE s.id = ${IN_LIST('$1')}
       AND NOT EXISTS (SELECT 1 FROM shipment_item_images i WHERE i.shipment_id = s.id)
     ORDER BY s.delivery_sequence LIMIT 1`,
    [ids],
  );
  if (missing) {
    throw new AppError(400, 'PHOTO_REQUIRED', 'Add at least one photo to every drop-off before pricing', {
      stopId: missing.id,
    });
  }

  const { rows: timed } = await client.query(
    `UPDATE shipments
     SET pickup_type = $2,
         pickup_window_start = COALESCE($3::timestamptz, now()),
         pickup_window_end = COALESCE($3::timestamptz, now()) + make_interval(mins => $4)
     WHERE id = ${IN_LIST('$1')}
     RETURNING id, details_version`,
    [ids, timing.pickupType, timing.start, WINDOW_MINUTES],
  );
  const versions = Object.fromEntries(timed.map((row) => [row.id, row.details_version]));

  const { rows: [load] } = await client.query(
    `SELECT sum(s.weight_kg) AS weight, sum(z.approx_volume_m3) AS volume,
            (SELECT group_discount_pct FROM platform_settings WHERE id = 1) AS pct
     FROM shipments s LEFT JOIN cargo_size_options z ON z.id = s.size_option_id
     WHERE s.id = ${IN_LIST('$1')}`,
    [ids],
  );
  const types = await fittingTypes(client, load.weight, load.volume);
  await expireQuotes(client, locked.group.id);

  const minimum = coupon ? cents(coupon.min_order_amount) : null;
  let couponUsed = false;
  for (const type of types) {
    const prices = stops.map((stop) => {
      const parts = quoteParts(type, stop);
      const base = parts.transport + parts.helpers;
      const groupDiscount = Math.round(base * Number(load.pct));
      return {
        ...parts,
        stop,
        groupDiscount,
        total: base - groupDiscount,
        details: { ...parts.details, groupDiscountPct: load.pct },
      };
    });
    let target = null;
    if (coupon) {
      for (const price of prices) {
        if (price.total >= minimum && (!target || price.total > target.total)) {
          target = price;
        }
      }
    }
    for (const price of prices) {
      const used = await insertQuote(client, {
        ...price,
        shipmentId: price.stop.id,
        type,
        helpersCount: price.stop.helpers_count,
        version: versions[price.stop.id],
        couponId: price === target ? coupon.id : null,
      });
      couponUsed = couponUsed || used;
    }
  }
  if (coupon && !couponUsed) {
    throw minOrderError(coupon);
  }
  return types[0].id;
}

export async function acceptGroupPrice(client, locked, vehicleTypeId, customerId) {
  const { group, stops } = locked;
  const { rows: quotes } = await client.query(
    `SELECT q.id, q.shipment_id, q.coupon_id, q.amount, q.shipment_version <> s.details_version AS outdated,
            q.expires_at < now() AS expired
     FROM price_quotes q JOIN shipments s ON s.id = q.shipment_id
     WHERE s.group_id = $1 AND s.status <> 'cancelled' AND q.vehicle_type_id = $2 AND q.status = 'offered'`,
    [group.id, vehicleTypeId],
  );
  if (quotes.length === 0) {
    const { rows: [old] } = await client.query(
      `SELECT 1 FROM price_quotes q JOIN shipments s ON s.id = q.shipment_id
       WHERE s.group_id = $1 AND q.vehicle_type_id = $2 LIMIT 1`,
      [group.id, vehicleTypeId],
    );
    if (!old) {
      throw new AppError(404, 'NOT_FOUND', 'Price not found');
    }
  }
  const covered = new Set(quotes.map((quote) => quote.shipment_id));
  if (quotes.length !== stops.length || !stops.every((stop) => covered.has(stop.id))) {
    throw new AppError(409, 'QUOTE_OUTDATED', 'The order changed after this price, ask for a new price');
  }
  if (quotes.some((quote) => quote.expired)) {
    throw new AppError(409, 'QUOTE_EXPIRED', 'This price expired, ask for a new price');
  }
  if (quotes.some((quote) => quote.outdated)) {
    throw new AppError(409, 'QUOTE_OUTDATED', 'The order changed after this price, ask for a new price');
  }
  const withCoupon = quotes.find((quote) => quote.coupon_id);
  if (withCoupon) {
    const coupon = await checkCoupon(client, 'id = $1', withCoupon.coupon_id, customerId);
    const { rows: [order] } = await client.query('SELECT $1::numeric >= $2::numeric AS enough', [
      withCoupon.amount, coupon.min_order_amount,
    ]);
    if (!order.enough) {
      throw minOrderError(coupon);
    }
  }
  await client.query(
    `UPDATE price_quotes SET status = 'accepted' WHERE id = ${IN_LIST('$1')}`,
    [quotes.map((quote) => quote.id).join(',')],
  );
  await client.query(
    `UPDATE price_quotes q SET status = 'rejected'
     FROM shipments s
     WHERE s.id = q.shipment_id AND s.group_id = $1 AND q.status = 'offered'`,
    [group.id],
  );
}

export async function withdrawGroupPrice(client, locked) {
  requireDraft(locked);
  if (!locked.stops.some((stop) => stop.priced)) {
    throw new AppError(409, 'PRICE_NOT_ACCEPTED', 'No price is accepted for this order');
  }
  await client.query(
    `UPDATE price_quotes q SET status = 'withdrawn'
     FROM shipments s
     WHERE s.id = q.shipment_id AND s.group_id = $1 AND s.status = 'draft' AND q.status = 'accepted'`,
    [locked.group.id],
  );
}

export async function requestGroup(client, locked, customerId) {
  requireDraft(locked);
  const { group, stops } = locked;
  if (stops.length < MIN_STOPS) {
    throw new AppError(409, 'GROUP_TOO_SMALL', `A grouped order needs at least ${MIN_STOPS} drop-offs`,
      { min: MIN_STOPS });
  }
  if (!stops.every((stop) => stop.priced)) {
    throw new AppError(409, 'PRICE_NOT_ACCEPTED', 'Accept a price first');
  }
  const { rows: [order] } = await client.query(
    `SELECT min(s.pickup_window_end) < now() AS too_old,
            COALESCE(sum(q.customer_amount) FILTER (WHERE s.payment_method = 'wallet'), 0) AS from_wallet
     FROM shipments s JOIN price_quotes q ON q.shipment_id = s.id AND q.status = 'accepted'
     WHERE s.group_id = $1 AND s.status = 'draft'`,
    [group.id],
  );
  if (order.too_old) {
    throw new AppError(409, 'PRICE_TOO_OLD', 'The pickup time passed, withdraw the price and ask for a new one');
  }
  const { rows: [customer] } = await client.query(
    `SELECT accepted_latest_policies($1) AS policies, customer_balance($1) AS balance,
            customer_available_balance($1) AS available,
            customer_available_balance($1) < $2::numeric AS too_low`,
    [customerId, order.from_wallet],
  );
  if (!customer.policies) {
    throw new AppError(409, 'POLICIES_NOT_ACCEPTED', 'Accept the new terms first');
  }
  if (Number(customer.balance) < 0) {
    throw new AppError(409, 'WALLET_NEGATIVE', 'Your wallet is negative, top it up first', {
      balance: customer.balance,
    });
  }
  if (customer.too_low) {
    throw new AppError(409, 'WALLET_TOO_LOW', 'Your wallet balance is not enough, top it up or pay cash', {
      available: customer.available, needed: order.from_wallet,
    });
  }
  await client.query(
    "UPDATE shipments SET status = 'searching_driver' WHERE group_id = $1 AND status = 'draft'",
    [group.id],
  );
}

export async function cancelGroup(client, locked, reason) {
  if (locked.status !== 'draft' && locked.status !== 'searching_driver') {
    throw wrongStatus(locked.status);
  }
  await client.query(
    `UPDATE shipments SET status = 'cancelled', cancellation_reason = $2
     WHERE group_id = $1 AND status IN ('draft', 'searching_driver')`,
    [locked.group.id, reason],
  );
}

function toOption(rows, recommended) {
  const first = rows[0];
  return {
    vehicleTypeId: first.vehicle_type_id,
    status: first.status,
    recommended: first.status === 'offered' && first.vehicle_type_id === recommended,
    transportAmount: first.total_transport,
    helpersAmount: first.total_helpers,
    groupDiscountAmount: first.total_group_discount,
    couponCode: (rows.find((row) => row.coupon_code) || {}).coupon_code || null,
    couponDiscountAmount: first.total_coupon_discount,
    amount: first.total_amount,
    customerAmount: first.total_customer_amount,
    expiresAt: first.first_expiry,
    acceptedAt: first.accepted_at,
    stops: rows.map((row) => ({
      stopId: row.shipment_id,
      quoteId: row.id,
      transportAmount: row.transport_amount,
      helpersCount: row.helpers_count,
      helperFee: row.helper_fee,
      helpersAmount: row.helpers_amount,
      groupDiscountAmount: row.group_discount_amount,
      couponDiscountAmount: row.coupon_discount_amount,
      amount: row.amount,
      customerAmount: row.customer_amount,
      pricingDetails: row.pricing_details,
    })),
  };
}

function toStop(row, order, photos, trip, baseUrl) {
  return {
    id: row.id,
    order,
    status: row.status,
    cargoCategoryId: row.cargo_category_id,
    sizeOptionId: row.size_option_id,
    cargoDescription: row.cargo_description,
    itemCount: row.item_count,
    isFragile: row.is_fragile,
    weightKg: row.weight_kg === null ? null : Number(row.weight_kg),
    dropoff: toPlace(row, 'dropoff'),
    routeDistanceM: row.route_distance_m,
    routeDurationS: row.route_duration_s,
    paymentMethod: row.payment_method,
    farePaidBy: row.fare_paid_by,
    recipient: row.recipient_phone ? { name: row.recipient_name, phone: row.recipient_phone } : null,
    deliveryCode: row.delivery_code,
    photos: photos.filter((photo) => photo.shipment_id === row.id).map((photo) => ({
      id: photo.id, url: imageUrl(photo.storage_key, baseUrl), uploadedAt: photo.uploaded_at,
    })),
    trip,
  };
}

export async function loadGroup(id, baseUrl, recommendedId) {
  const { rows: [group] } = await query(
    `SELECT ${GROUP_COLUMNS}, ${GROUP_STATUS} AS status FROM shipment_groups g WHERE g.id = $1`,
    [id],
  );
  const { rows: all } = await query(
    `SELECT ${SHIPMENT_COLUMNS} FROM shipments s WHERE s.group_id = $1 ORDER BY s.delivery_sequence`,
    [id],
  );
  const stops = group.status === 'cancelled'
    ? all.filter((stop) => stop.cancellation_reason !== REMOVED)
    : all.filter((stop) => stop.status !== 'cancelled');
  const ids = idList(stops);
  const [photos, quotes, trips] = await Promise.all([
    query(
      `SELECT shipment_id, id, storage_key, uploaded_at FROM shipment_item_images
       WHERE shipment_id = ${IN_LIST('$1')} ORDER BY id`,
      [ids],
    ),
    query(
      `SELECT q.*, c.code AS coupon_code,
              sum(q.transport_amount) OVER w AS total_transport,
              sum(q.helpers_amount) OVER w AS total_helpers,
              sum(q.group_discount_amount) OVER w AS total_group_discount,
              sum(q.coupon_discount_amount) OVER w AS total_coupon_discount,
              sum(q.amount) OVER w AS total_amount,
              sum(q.customer_amount) OVER w AS total_customer_amount,
              min(q.expires_at) OVER w AS first_expiry,
              count(*) OVER w AS n
       FROM price_quotes q
       JOIN shipments s ON s.id = q.shipment_id
       JOIN vehicle_types vt ON vt.id = q.vehicle_type_id
       LEFT JOIN coupons c ON c.id = q.coupon_id
       WHERE q.shipment_id = ${IN_LIST('$1')}
         AND (q.status = 'accepted' OR (q.status = 'offered' AND q.expires_at > now()
              AND q.shipment_version = s.details_version))
       WINDOW w AS (PARTITION BY q.status, q.vehicle_type_id)
       ORDER BY vt.max_payload_kg, vt.id, s.delivery_sequence`,
      [ids],
    ),
    Promise.all(stops.map((stop) => (stop.status === 'draft' ? null : shipmentTrip(stop.id)))),
  ]);

  const options = new Map();
  for (const row of quotes.rows) {
    const key = `${row.status}:${row.vehicle_type_id}`;
    if (!options.has(key)) {
      options.set(key, []);
    }
    options.get(key).push(row);
  }
  const complete = [...options.values()].filter((rows) => Number(rows[0].n) === stops.length);
  const offered = complete.filter((rows) => rows[0].status === 'offered');
  const accepted = complete.find((rows) => rows[0].status === 'accepted');
  const recommended = recommendedId === undefined ? (offered[0] ? offered[0][0].vehicle_type_id : null) : recommendedId;

  const first = stops[0];
  const cancelled = group.status === 'cancelled'
    ? [...stops].sort((a, b) => new Date(b.cancelled_at) - new Date(a.cancelled_at))[0] : null;
  return {
    id: group.id,
    status: group.status,
    pickup: { ...groupPickup(group), zoneId: first ? first.pickup_zone_id : null },
    helpersCount: group.helpers_count,
    pickupType: first ? first.pickup_type : null,
    pickupWindowStart: first ? first.pickup_window_start : null,
    pickupWindowEnd: first ? first.pickup_window_end : null,
    createdAt: group.created_at,
    cancelledAt: cancelled ? cancelled.cancelled_at : null,
    cancellationParty: cancelled ? cancelled.cancellation_party : null,
    cancellationReason: cancelled ? cancelled.cancellation_reason : null,
    stops: stops.map((stop, i) => toStop(stop, i + 1, photos.rows, trips[i], baseUrl)),
    quotes: offered.map((rows) => toOption(rows, recommended)),
    acceptedPrice: accepted ? toOption(accepted, null) : null,
  };
}

export const GROUP_LIST_SQL = `SELECT * FROM (
  SELECT g.id, g.pickup_address, g.created_at, ${GROUP_STATUS} AS status,
         x.stops, x.pickup_window_start, p.vehicle_type_id, p.customer_amount
  FROM shipment_groups g
  LEFT JOIN LATERAL (
    SELECT COALESCE(NULLIF(count(*) FILTER (WHERE s.status <> 'cancelled'), 0), count(*))::int AS stops,
           min(s.pickup_window_start) FILTER (WHERE s.status <> 'cancelled') AS pickup_window_start
    FROM shipments s WHERE s.group_id = g.id
  ) x ON true
  LEFT JOIN LATERAL (
    SELECT min(q.vehicle_type_id) AS vehicle_type_id, sum(q.customer_amount) AS customer_amount
    FROM price_quotes q JOIN shipments s ON s.id = q.shipment_id
    WHERE s.group_id = g.id AND s.status <> 'cancelled' AND q.status = 'accepted'
  ) p ON true
  WHERE g.customer_id = $1
) l`;

export function toGroupSummary(row) {
  return {
    id: row.id,
    status: row.status,
    pickupAddress: row.pickup_address,
    stopsCount: row.stops,
    pickupWindowStart: row.pickup_window_start,
    vehicleTypeId: row.vehicle_type_id,
    customerAmount: row.customer_amount,
    createdAt: row.created_at,
  };
}
