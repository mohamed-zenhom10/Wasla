import { query } from '../db.js';
import { AppError } from '../errors.js';

export const EXECUTING = ['heading_to_pickup', 'arrived_at_pickup', 'loaded', 'heading_to_dropoff', 'arrived_at_dropoff'];
export const FINISHED = ['delivered', 'cancelled'];

export const JOB_COLUMNS = `s.id AS shipment_id, s.cargo_category_id, s.size_option_id, s.cargo_description,
  s.item_count, s.is_fragile, s.weight_kg, s.helpers_count,
  s.pickup_address, s.pickup_notes,
  ST_X(s.pickup_location::geometry) AS pickup_lng, ST_Y(s.pickup_location::geometry) AS pickup_lat,
  s.dropoff_address, s.dropoff_notes,
  ST_X(s.dropoff_location::geometry) AS dropoff_lng, ST_Y(s.dropoff_location::geometry) AS dropoff_lat,
  s.pickup_type, s.pickup_window_start, s.pickup_window_end, s.route_distance_m, s.route_duration_s,
  s.payment_method, s.fare_paid_by,
  q.amount AS fare_amount, q.customer_amount,
  round(q.amount * q.commission_rate, 2) AS commission_amount,
  q.amount - round(q.amount * q.commission_rate, 2) AS driver_earning`;

const TRIP_SQL = `SELECT t.id, t.status, t.planned_start_at, t.planned_end_at, t.started_at, t.loaded_at,
    t.delivered_at, t.cancelled_at, t.cancellation_party, t.cancellation_reason, t.vehicle_fit,
    t.delivery_code_verified_at, t.created_at,
    ${JOB_COLUMNS},
    s.recipient_name, s.recipient_phone, cu.full_name AS customer_name, cu.phone AS customer_phone
  FROM trips t
  JOIN shipments s ON s.id = t.shipment_id
  JOIN price_quotes q ON q.id = t.price_quote_id
  JOIN users cu ON cu.id = s.customer_id`;

function toPlace(row, prefix) {
  return {
    address: row[`${prefix}_address`],
    lat: Number(row[`${prefix}_lat`]),
    lng: Number(row[`${prefix}_lng`]),
    notes: row[`${prefix}_notes`],
  };
}

export function toJob(row) {
  return {
    shipmentId: row.shipment_id,
    cargoCategoryId: row.cargo_category_id,
    sizeOptionId: row.size_option_id,
    cargoDescription: row.cargo_description,
    itemCount: row.item_count,
    isFragile: row.is_fragile,
    weightKg: row.weight_kg === null ? null : Number(row.weight_kg),
    helpersCount: row.helpers_count,
    pickup: toPlace(row, 'pickup'),
    dropoff: toPlace(row, 'dropoff'),
    pickupType: row.pickup_type,
    pickupWindowStart: row.pickup_window_start,
    pickupWindowEnd: row.pickup_window_end,
    routeDistanceM: row.route_distance_m,
    routeDurationS: row.route_duration_s,
    paymentMethod: row.payment_method,
    farePaidBy: row.fare_paid_by,
    fareAmount: row.fare_amount,
    commissionAmount: row.commission_amount,
    driverEarning: row.driver_earning,
    cashToCollect: row.payment_method === 'cash' ? row.customer_amount : '0.00',
  };
}

export function toTrip(row) {
  const live = !FINISHED.includes(row.status);
  return {
    id: row.id,
    status: row.status,
    ...toJob(row),
    customer: { name: row.customer_name, phone: live ? row.customer_phone : null },
    recipient: row.recipient_name ? { name: row.recipient_name, phone: live ? row.recipient_phone : null } : null,
    vehicleFit: row.vehicle_fit,
    deliveryCodeVerified: row.delivery_code_verified_at !== null,
    plannedStartAt: row.planned_start_at,
    plannedEndAt: row.planned_end_at,
    startedAt: row.started_at,
    loadedAt: row.loaded_at,
    deliveredAt: row.delivered_at,
    cancelledAt: row.cancelled_at,
    cancellationParty: row.cancellation_party,
    cancellationReason: row.cancellation_reason,
    createdAt: row.created_at,
  };
}

export async function loadTrip(id, driverId) {
  const { rows: [row] } = await query(`${TRIP_SQL} WHERE t.id = $1 AND t.driver_id = $2`, [id, driverId]);
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Trip not found');
  }
  return toTrip(row);
}

export async function currentTrip(driverId) {
  const { rows: [row] } = await query(
    `${TRIP_SQL}
     WHERE t.driver_id = $1 AND t.status <> ALL($2::text[])
     ORDER BY (t.status <> 'assigned') DESC, t.planned_start_at, t.id
     LIMIT 1`,
    [driverId, FINISHED],
  );
  return row ? toTrip(row) : null;
}

export async function listTrips(driverId, finished, limit, offset) {
  const { rows } = await query(
    `${TRIP_SQL}
     WHERE t.driver_id = $1 AND (t.status = ANY($2::text[])) = $3
     ORDER BY ${finished ? 't.created_at DESC, t.id DESC' : 't.planned_start_at, t.id'}
     LIMIT $4 OFFSET $5`,
    [driverId, FINISHED, finished, limit, offset],
  );
  return rows.map(toTrip);
}

export async function shipmentTrip(shipmentId) {
  const { rows: [row] } = await query(
    `SELECT t.id, t.status, t.driver_id, t.planned_start_at, t.started_at, t.loaded_at, t.delivered_at,
            u.full_name, u.phone, v.vehicle_type_id, v.plate_number, v.make, v.model, v.color
     FROM trips t
     JOIN users u ON u.id = t.driver_id
     JOIN vehicles v ON v.id = t.vehicle_id
     WHERE t.shipment_id = $1 AND t.status <> 'cancelled'`,
    [shipmentId],
  );
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    status: row.status,
    driver: { id: row.driver_id, name: row.full_name, phone: row.status === 'delivered' ? null : row.phone },
    vehicle: {
      vehicleTypeId: row.vehicle_type_id,
      plateNumber: row.plate_number,
      make: row.make,
      model: row.model,
      color: row.color,
    },
    plannedStartAt: row.planned_start_at,
    startedAt: row.started_at,
    loadedAt: row.loaded_at,
    deliveredAt: row.delivered_at,
  };
}
