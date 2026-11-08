import crypto from 'node:crypto';
import { query } from '../db.js';
import { AppError } from '../errors.js';
import { imageUrl } from './storage.js';
import { estimateRoute, POINT_SQL } from './route.js';
import {
  invalid, cleanRef, cleanText, cleanOptionalText, cleanInteger, cleanBoolean, cleanChoice, cleanMeasure,
  cleanCoordinate, cleanPhone,
} from './validate.js';

const WINDOW_MINUTES = 60;
const MAX_SCHEDULE_DAYS = 30;

function cleanPlace(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw invalid(field, `${field} must have address, lat and lng`);
  }
  return {
    address: cleanText(value.address, `${field}.address`, 300),
    lat: cleanCoordinate(value.lat, `${field}.lat`, 90),
    lng: cleanCoordinate(value.lng, `${field}.lng`, 180),
    notes: value.notes === undefined ? null : cleanOptionalText(value.notes, `${field}.notes`, 300),
  };
}

function cleanTime(value, field) {
  const time = typeof value === 'string' ? new Date(value) : null;
  if (!time || Number.isNaN(time.getTime()) || !/^\d{4}-\d{2}-\d{2}T/.test(value)) {
    throw invalid(field, `${field} must be a date and time like 2026-11-20T09:30:00+02:00`);
  }
  return time.toISOString();
}

const optionalRef = (v, f) => (v === null ? null : cleanRef(v, f));

export const shipmentFields = {
  cargoCategoryId: { column: 'cargoCategoryId', clean: cleanRef, required: true },
  sizeOptionId: { column: 'sizeOptionId', clean: optionalRef },
  cargoDescription: { column: 'cargoDescription', clean: (v, f) => cleanText(v, f, 500), required: true },
  itemCount: { column: 'itemCount', clean: (v, f) => cleanInteger(v, f, 1, 1000), required: true },
  isFragile: { column: 'isFragile', clean: cleanBoolean },
  weightKg: { column: 'weightKg', clean: (v, f) => (v === null ? null : cleanMeasure(v, f)) },
  helpersCount: { column: 'helpersCount', clean: (v, f) => cleanInteger(v, f, 0, 20) },
  requestedVehicleTypeId: { column: 'requestedVehicleTypeId', clean: optionalRef },
  pickup: { column: 'pickup', clean: cleanPlace, required: true },
  dropoff: { column: 'dropoff', clean: cleanPlace, required: true },
  pickupType: { column: 'pickupType', clean: (v, f) => cleanChoice(v, f, ['now', 'scheduled']), required: true },
  pickupAt: { column: 'pickupAt', clean: (v, f) => (v === null ? null : cleanTime(v, f)) },
  paymentMethod: { column: 'paymentMethod', clean: (v, f) => cleanChoice(v, f, ['cash', 'wallet']), required: true },
  farePaidBy: { column: 'farePaidBy', clean: (v, f) => cleanChoice(v, f, ['sender', 'recipient']) },
  recipientName: { column: 'recipientName', clean: (v, f) => cleanOptionalText(v, f, 100) },
  recipientPhone: { column: 'recipientPhone', clean: (v, f) => (v === null || v === '' ? null : cleanPhone(v, f)) },
};

export const SHIPMENT_COLUMNS = `s.*,
  ST_X(s.pickup_location::geometry) AS pickup_lng, ST_Y(s.pickup_location::geometry) AS pickup_lat,
  ST_X(s.dropoff_location::geometry) AS dropoff_lng, ST_Y(s.dropoff_location::geometry) AS dropoff_lat`;

export function stateOf(row) {
  return {
    cargoCategoryId: row.cargo_category_id,
    sizeOptionId: row.size_option_id,
    cargoDescription: row.cargo_description,
    itemCount: row.item_count,
    isFragile: row.is_fragile,
    weightKg: row.weight_kg,
    helpersCount: row.helpers_count,
    requestedVehicleTypeId: row.requested_vehicle_type_id,
    pickup: {
      address: row.pickup_address, lat: Number(row.pickup_lat), lng: Number(row.pickup_lng), notes: row.pickup_notes,
    },
    dropoff: {
      address: row.dropoff_address,
      lat: Number(row.dropoff_lat),
      lng: Number(row.dropoff_lng),
      notes: row.dropoff_notes,
    },
    pickupType: row.pickup_type,
    pickupAt: row.pickup_type === 'scheduled' ? new Date(row.pickup_window_start).toISOString() : null,
    paymentMethod: row.payment_method,
    farePaidBy: row.fare_paid_by,
    recipientName: row.recipient_name,
    recipientPhone: row.recipient_phone,
  };
}

export async function buildColumns(client, state, changed) {
  const { rows: [category] } = await client.query(
    'SELECT is_active FROM cargo_categories WHERE id = $1',
    [state.cargoCategoryId],
  );
  if (!category || !category.is_active) {
    throw invalid('cargoCategoryId', 'Cargo category not found');
  }
  if (state.sizeOptionId) {
    const { rows: [size] } = await client.query(
      'SELECT is_active FROM cargo_size_options WHERE id = $1 AND cargo_category_id = $2',
      [state.sizeOptionId, state.cargoCategoryId],
    );
    if (!size || !size.is_active) {
      throw invalid('sizeOptionId', 'This size is not one of the sizes of the cargo category');
    }
  }
  if (state.requestedVehicleTypeId) {
    const { rows: [type] } = await client.query(
      'SELECT is_active FROM vehicle_types WHERE id = $1',
      [state.requestedVehicleTypeId],
    );
    if (!type || !type.is_active) {
      throw invalid('requestedVehicleTypeId', 'Vehicle type not found');
    }
  }

  const now = Date.now();
  let start = new Date(now);
  if (state.pickupType === 'scheduled') {
    if (!state.pickupAt) {
      throw invalid('pickupAt', 'pickupAt is required for a scheduled pickup');
    }
    const { rows: [settings] } = await client.query(
      'SELECT min_schedule_lead_minutes FROM platform_settings WHERE id = 1',
    );
    start = new Date(state.pickupAt);
    if (start.getTime() < now + settings.min_schedule_lead_minutes * 60000) {
      throw invalid('pickupAt', `Schedule the pickup at least ${settings.min_schedule_lead_minutes} minutes from now`);
    }
    if (start.getTime() > now + MAX_SCHEDULE_DAYS * 86400000) {
      throw invalid('pickupAt', `A scheduled pickup can be at most ${MAX_SCHEDULE_DAYS} days from now`);
    }
  } else if (changed.includes('pickupAt') && state.pickupAt) {
    throw invalid('pickupAt', 'pickupAt is only for a scheduled pickup');
  }

  const farePaidBy = state.farePaidBy || 'sender';
  if ((state.recipientName === null || state.recipientName === undefined)
      !== (state.recipientPhone === null || state.recipientPhone === undefined)) {
    throw invalid(state.recipientName ? 'recipientPhone' : 'recipientName', 'Send the recipient name and phone');
  }
  if (farePaidBy === 'recipient') {
    if (state.paymentMethod !== 'cash') {
      throw invalid('paymentMethod', 'The recipient can only pay cash');
    }
    if (!state.recipientPhone) {
      throw invalid('recipientPhone', 'The recipient name and phone are needed when the recipient pays');
    }
  }

  const route = await estimateRoute(client, state.pickup, state.dropoff);
  return {
    cargo_category_id: state.cargoCategoryId,
    size_option_id: state.sizeOptionId || null,
    cargo_description: state.cargoDescription,
    item_count: state.itemCount,
    is_fragile: Boolean(state.isFragile),
    weight_kg: state.weightKg || null,
    helpers_count: state.helpersCount || 0,
    requested_vehicle_type_id: state.requestedVehicleTypeId || null,
    pickup_address: state.pickup.address,
    pickup_location: state.pickup,
    pickup_notes: state.pickup.notes,
    dropoff_address: state.dropoff.address,
    dropoff_location: state.dropoff,
    dropoff_notes: state.dropoff.notes,
    pickup_type: state.pickupType,
    pickup_window_start: start.toISOString(),
    pickup_window_end: new Date(start.getTime() + WINDOW_MINUTES * 60000).toISOString(),
    route_distance_m: route.distanceM,
    route_duration_s: route.durationS,
    payment_method: state.paymentMethod,
    fare_paid_by: farePaidBy,
    recipient_name: state.recipientName || null,
    recipient_phone: state.recipientPhone || null,
  };
}

function sqlParts(columns, firstParam) {
  const names = [];
  const values = [];
  const params = [];
  for (const [name, value] of Object.entries(columns)) {
    names.push(name);
    if (name.endsWith('_location')) {
      values.push(POINT_SQL(`$${firstParam + params.length}`, `$${firstParam + params.length + 1}`));
      params.push(value.lng, value.lat);
    } else {
      values.push(`$${firstParam + params.length}`);
      params.push(value);
    }
  }
  return { names, values, params };
}

export async function insertShipment(client, customerId, columns) {
  const { names, values, params } = sqlParts(
    { ...columns, customer_id: customerId, delivery_code: String(crypto.randomInt(0, 10000)).padStart(4, '0') },
    1,
  );
  const { rows: [row] } = await client.query(
    `INSERT INTO shipments (${names.join(', ')}) VALUES (${values.join(', ')}) RETURNING id`,
    params,
  );
  return row.id;
}

export async function updateShipment(client, id, columns) {
  const { names, values, params } = sqlParts(columns, 2);
  await client.query(
    `UPDATE shipments SET ${names.map((name, i) => `${name} = ${values[i]}`).join(', ')} WHERE id = $1`,
    [id, ...params],
  );
}

function toPlace(row, prefix) {
  return {
    address: row[`${prefix}_address`],
    lat: Number(row[`${prefix}_lat`]),
    lng: Number(row[`${prefix}_lng`]),
    notes: row[`${prefix}_notes`],
    zoneId: row[`${prefix}_zone_id`],
  };
}

export function toShipmentSummary(row) {
  return {
    id: row.id,
    status: row.status,
    cargoCategoryId: row.cargo_category_id,
    cargoDescription: row.cargo_description,
    pickupAddress: row.pickup_address,
    dropoffAddress: row.dropoff_address,
    pickupType: row.pickup_type,
    pickupWindowStart: row.pickup_window_start,
    createdAt: row.created_at,
  };
}

export const SUMMARY_SQL = 'SELECT s.* FROM shipments s';

export const STATUS_FILTERS = {
  active: ['searching_driver', 'driver_assigned', 'in_progress'],
  draft: ['draft'],
  searching_driver: ['searching_driver'],
  driver_assigned: ['driver_assigned'],
  in_progress: ['in_progress'],
  delivered: ['delivered'],
  cancelled: ['cancelled'],
};

export async function loadShipment(id, baseUrl) {
  const { rows: [row] } = await query(`SELECT ${SHIPMENT_COLUMNS} FROM shipments s WHERE s.id = $1`, [id]);
  const [photos, history] = await Promise.all([
    query('SELECT id, storage_key, uploaded_at FROM shipment_item_images WHERE shipment_id = $1 ORDER BY id', [id]),
    query(
      `SELECT from_status, to_status, change_source, reason, created_at
       FROM shipment_status_history WHERE shipment_id = $1 ORDER BY id`,
      [id],
    ),
  ]);

  return {
    id: row.id,
    status: row.status,
    cargoCategoryId: row.cargo_category_id,
    sizeOptionId: row.size_option_id,
    cargoDescription: row.cargo_description,
    itemCount: row.item_count,
    isFragile: row.is_fragile,
    weightKg: row.weight_kg === null ? null : Number(row.weight_kg),
    helpersCount: row.helpers_count,
    requestedVehicleTypeId: row.requested_vehicle_type_id,
    pickup: toPlace(row, 'pickup'),
    dropoff: toPlace(row, 'dropoff'),
    pickupType: row.pickup_type,
    pickupWindowStart: row.pickup_window_start,
    pickupWindowEnd: row.pickup_window_end,
    routeDistanceM: row.route_distance_m,
    routeDurationS: row.route_duration_s,
    paymentMethod: row.payment_method,
    farePaidBy: row.fare_paid_by,
    recipient: row.recipient_phone ? { name: row.recipient_name, phone: row.recipient_phone } : null,
    deliveryCode: row.delivery_code,
    createdAt: row.created_at,
    cancelledAt: row.cancelled_at,
    cancellationParty: row.cancellation_party,
    cancellationReason: row.cancellation_reason,
    photos: photos.rows.map((p) => ({
      id: p.id, url: imageUrl(p.storage_key, baseUrl), uploadedAt: p.uploaded_at,
    })),
    timeline: history.rows.map((h) => ({
      from: h.from_status, to: h.to_status, by: h.change_source, reason: h.reason, at: h.created_at,
    })),
  };
}

export async function lockShipment(client, id, customerId) {
  const { rows: [row] } = await client.query(
    `SELECT ${SHIPMENT_COLUMNS} FROM shipments s WHERE s.id = $1 AND ($2::bigint IS NULL OR s.customer_id = $2)
     FOR UPDATE OF s`,
    [id, customerId],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Shipment not found');
  }
  return row;
}

export function requireDraft(row) {
  if (row.status !== 'draft') {
    throw new AppError(409, 'WRONG_STATUS', `The shipment is ${row.status}`, { status: row.status });
  }
}
