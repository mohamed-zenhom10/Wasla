import { JOB_COLUMNS, toJob } from './trips.js';

const PLANNED_START = `CASE WHEN s.pickup_type = 'now' THEN now() ELSE GREATEST(now(), s.pickup_window_start) END`;
const PLANNED_END = `${PLANNED_START} + make_interval(secs => COALESCE(s.route_duration_s, 3600)) + interval '60 minutes'`;

export async function closeOldOffers(client, driverId = null) {
  await client.query(
    `UPDATE dispatch_offers o
     SET response = CASE WHEN s.status = 'searching_driver' THEN 'expired' ELSE 'cancelled' END
     FROM shipments s, driver_profiles dp
     WHERE s.id = o.shipment_id AND dp.user_id = o.driver_id AND o.response = 'pending'
       AND ($1::bigint IS NULL OR o.driver_id = $1)
       AND (o.expires_at <= now() OR s.status <> 'searching_driver' OR NOT dp.is_online)`,
    [driverId],
  );
}

export async function makeOffers(client, driverId) {
  await client.query(
    `INSERT INTO dispatch_offers (shipment_id, price_quote_id, driver_id, vehicle_id, distance_to_pickup_m, expires_at)
     SELECT s.id, q.id, dp.user_id, v.id,
            round(ST_Distance(dp.current_location, s.pickup_location))::int,
            now() + make_interval(secs => ps.driver_offer_timeout_seconds)
     FROM driver_profiles dp
     JOIN vehicles v ON v.id = dp.active_vehicle_id
     CROSS JOIN platform_settings ps
     JOIN shipments s ON s.status = 'searching_driver' AND s.group_id IS NULL
     JOIN price_quotes q ON q.shipment_id = s.id AND q.status = 'accepted' AND q.vehicle_type_id = v.vehicle_type_id
     WHERE dp.user_id = $1 AND dp.is_online
       AND dp.location_updated_at > now() - make_interval(secs => ps.location_stale_seconds)
       AND ST_DWithin(dp.current_location, s.pickup_location, ps.dispatch_radius_m)
       AND COALESCE(s.weight_kg, 0) <= v.max_payload_kg
       AND s.helpers_count <= dp.max_helpers
       AND s.customer_id <> dp.user_id
       AND (s.pickup_type = 'now'
            OR s.pickup_window_start - make_interval(mins => ps.scheduled_search_lead_minutes) <= now())
       AND NOT EXISTS (
         SELECT 1 FROM dispatch_offers o
         WHERE o.shipment_id = s.id AND o.driver_id = dp.user_id AND o.response IN ('pending', 'rejected', 'accepted'))
       AND NOT EXISTS (
         SELECT 1 FROM trips t
         WHERE t.driver_id = dp.user_id AND t.status NOT IN ('delivered', 'cancelled')
           AND ((s.pickup_type = 'now' AND t.planned_start_at <= now())
                OR tstzrange(t.planned_start_at, t.planned_end_at, '[)') && tstzrange(${PLANNED_START}, ${PLANNED_END}, '[)')))
     ORDER BY s.id`,
    [driverId],
  );
}

function toOffer(row) {
  return {
    id: row.offer_id,
    sentAt: row.sent_at,
    expiresAt: row.expires_at,
    secondsLeft: row.seconds_left,
    distanceToPickupM: row.distance_to_pickup_m,
    ...toJob(row),
  };
}

export async function listOffers(client, driverId) {
  const { rows } = await client.query(
    `SELECT o.id AS offer_id, o.sent_at, o.expires_at, o.distance_to_pickup_m,
            GREATEST(0, ceil(extract(epoch FROM o.expires_at - now())))::int AS seconds_left,
            ${JOB_COLUMNS}
     FROM dispatch_offers o
     JOIN shipments s ON s.id = o.shipment_id
     JOIN price_quotes q ON q.id = o.price_quote_id
     WHERE o.driver_id = $1 AND o.response = 'pending' AND o.expires_at > now() AND s.status = 'searching_driver'
     ORDER BY o.distance_to_pickup_m, o.id`,
    [driverId],
  );
  return rows.map(toOffer);
}

export async function createTrip(client, offer) {
  const { rows: [trip] } = await client.query(
    `INSERT INTO trips (shipment_id, driver_id, vehicle_id, price_quote_id, fare_amount, commission_rate,
                        planned_start_at, planned_end_at)
     SELECT s.id, $2, $3, q.id, q.amount, q.commission_rate, ${PLANNED_START}, ${PLANNED_END}
     FROM shipments s JOIN price_quotes q ON q.id = $4 AND q.shipment_id = s.id
     WHERE s.id = $1
     RETURNING id`,
    [offer.shipment_id, offer.driver_id, offer.vehicle_id, offer.price_quote_id],
  );
  await client.query(
    `UPDATE dispatch_offers SET response = 'accepted', responded_at = now(), trip_id = $2 WHERE id = $1`,
    [offer.id, trip.id],
  );
  await client.query(
    `UPDATE dispatch_offers SET response = CASE WHEN shipment_id = $1 THEN 'cancelled' ELSE 'expired' END
     WHERE response = 'pending' AND (shipment_id = $1 OR driver_id = $2)`,
    [offer.shipment_id, offer.driver_id],
  );
  return trip.id;
}

export async function cancelUnmatched(client) {
  await client.query(
    `UPDATE shipments s SET status = 'cancelled', cancellation_reason = 'no_driver_found'
     FROM platform_settings ps
     WHERE s.status = 'searching_driver' AND s.group_id IS NULL
       AND COALESCE(s.search_started_at, GREATEST(
             (SELECT max(h.created_at) FROM shipment_status_history h
              WHERE h.shipment_id = s.id AND h.to_status = 'searching_driver'),
             CASE WHEN s.pickup_type = 'scheduled'
                  THEN s.pickup_window_start - make_interval(mins => ps.scheduled_search_lead_minutes) END))
           + make_interval(mins => ps.driver_search_timeout_minutes) <= now()`,
  );
}
