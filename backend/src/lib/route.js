import { AppError } from '../errors.js';

const ROAD_FACTOR = 1.3;
const AVERAGE_SPEED_KMH = 25;
const MIN_DISTANCE_M = 200;

export const POINT_SQL = (lng, lat) => `ST_SetSRID(ST_MakePoint(${lng}::float8, ${lat}::float8), 4326)::geography`;

export async function estimateRoute(client, pickup, dropoff) {
  const { rows: [row] } = await client.query(
    `SELECT ST_Distance(${POINT_SQL('$1', '$2')}, ${POINT_SQL('$3', '$4')}) AS meters`,
    [pickup.lng, pickup.lat, dropoff.lng, dropoff.lat],
  );
  const straight = Number(row.meters);
  if (straight < MIN_DISTANCE_M) {
    throw new AppError(400, 'SAME_PLACE', 'Pickup and drop-off are too close to each other', { field: 'dropoff' });
  }
  const distance = Math.round(straight * ROAD_FACTOR);
  return {
    distanceM: distance,
    durationS: Math.round(distance / ((AVERAGE_SPEED_KMH * 1000) / 3600)),
  };
}
