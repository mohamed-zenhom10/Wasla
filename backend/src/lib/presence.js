import { query } from '../db.js';
import { AppError } from '../errors.js';
import { cleanCoordinate, invalid } from './validate.js';

const STATE_SQL = `SELECT dp.verification_status, dp.is_online, dp.active_vehicle_id, dp.location_updated_at,
    ST_X(dp.current_location::geometry) AS lng, ST_Y(dp.current_location::geometry) AS lat,
    accepted_latest_policies(dp.user_id) AS policies,
    driver_balance(dp.user_id)::numeric(12,2) AS balance,
    driver_debt_limit(dp.user_id)::numeric(12,2) AS debt_limit,
    v.status AS vehicle_status, v.vehicle_type_id, v.plate_number, v.make, v.model, v.color,
    COALESCE(lic.expires_on > current_date, false) AS license_valid,
    license_fits_vehicle(dp.user_id, v.id) AS license_fits,
    EXISTS (
      SELECT 1 FROM vehicle_documents d
      WHERE d.vehicle_id = v.id AND d.document_type = 'vehicle_license_front' AND d.review_status = 'approved'
        AND d.superseded_at IS NULL AND d.expires_on > current_date
    ) AS vehicle_license_valid,
    (SELECT s.started_at FROM driver_online_sessions s
     WHERE s.driver_id = dp.user_id AND s.ended_at IS NULL) AS online_since
  FROM driver_profiles dp
  LEFT JOIN vehicles v ON v.id = dp.active_vehicle_id
  LEFT JOIN LATERAL driver_current_license(dp.user_id) lic ON true
  WHERE dp.user_id = $1`;

const BLOCKERS = {
  not_approved: 'Your application is not approved yet',
  no_active_vehicle: 'You do not have an active vehicle yet',
  vehicle_not_active: 'Your vehicle is not active',
  policies_not_accepted: 'Accept the new terms first',
  license_expired: 'Your driving license is missing or expired',
  license_too_low: 'Your driving license category is too low for your vehicle',
  vehicle_license_expired: 'Your vehicle license is missing or expired',
  debt_over_limit: 'Your debt is over the limit, settle it first',
};

export function readPoint(body) {
  return { lat: cleanCoordinate(body.lat, 'lat', 90), lng: cleanCoordinate(body.lng, 'lng', 180) };
}

export function readAccuracy(body) {
  const value = body.accuracyM;
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 100000) {
    throw invalid('accuracyM', 'accuracyM must be a number from 0 to 100000');
  }
  return Math.round(value * 100) / 100;
}

export async function loadState(client, userId, lock = false) {
  const { rows: [state] } = await client.query(lock ? `${STATE_SQL} FOR UPDATE OF dp` : STATE_SQL, [userId]);
  return state || null;
}

export function blockersOf(state) {
  if (!state || state.verification_status !== 'approved') {
    return ['not_approved'];
  }
  const blockers = [];
  if (!state.active_vehicle_id) {
    blockers.push('no_active_vehicle');
  } else if (state.vehicle_status !== 'active') {
    blockers.push('vehicle_not_active');
  }
  if (!state.policies) {
    blockers.push('policies_not_accepted');
  }
  if (!state.license_valid) {
    blockers.push('license_expired');
  } else if (state.active_vehicle_id && !state.license_fits) {
    blockers.push('license_too_low');
  }
  if (state.active_vehicle_id && !state.vehicle_license_valid) {
    blockers.push('vehicle_license_expired');
  }
  if (Number(state.balance) < -Number(state.debt_limit)) {
    blockers.push('debt_over_limit');
  }
  return blockers;
}

export function blockerError(blocker, state) {
  const extra = blocker === 'debt_over_limit' ? { balance: state.balance, debtLimit: state.debt_limit } : undefined;
  return new AppError(409, blocker.toUpperCase(), BLOCKERS[blocker], extra);
}

export function toStatus(state) {
  const blockers = blockersOf(state);
  if (!state) {
    return {
      online: false, onlineSince: null, canGoOnline: false, blockers, vehicle: null, location: null,
      balance: '0.00', debtLimit: null,
    };
  }
  return {
    online: state.is_online,
    onlineSince: state.online_since,
    canGoOnline: blockers.length === 0,
    blockers,
    vehicle: state.active_vehicle_id ? {
      id: state.active_vehicle_id,
      vehicleTypeId: state.vehicle_type_id,
      plateNumber: state.plate_number,
      make: state.make,
      model: state.model,
      color: state.color,
    } : null,
    location: state.location_updated_at ? {
      lat: Number(state.lat), lng: Number(state.lng), updatedAt: state.location_updated_at,
    } : null,
    balance: state.balance,
    debtLimit: state.debt_limit,
  };
}

export async function loadStatus(userId) {
  return toStatus(await loadState({ query }, userId));
}
