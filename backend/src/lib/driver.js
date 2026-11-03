import crypto from 'node:crypto';
import config from '../config.js';
import { query } from '../db.js';
import { AppError } from '../errors.js';
import { imageUrl } from './storage.js';
import { invalid } from './validate.js';
import { toPayoutAccount } from './payout.js';

export const DRIVER_DOCUMENTS = [
  'profile_photo', 'national_id_front', 'national_id_back', 'driving_license_front', 'driving_license_back',
];
export const VEHICLE_DOCUMENTS = [
  'vehicle_license_front', 'vehicle_license_back',
  'vehicle_photo_front', 'vehicle_photo_side', 'vehicle_photo_rear', 'vehicle_photo_cargo',
];

const ARABIC_DIGITS = /[\u0660-\u0669]/g;

function validDate(year, month, day) {
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

export function cleanDate(value, field) {
  const match = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(typeof value === 'string' ? value.trim() : '');
  if (!match || !validDate(Number(match[1]), Number(match[2]), Number(match[3]))) {
    throw invalid(field, `${field} must be a real date like 2028-05-14`);
  }
  return match[0];
}

export function cleanNationalId(value, field) {
  const id = typeof value === 'string'
    ? value.replace(ARABIC_DIGITS, (d) => String(d.charCodeAt(0) - 0x0660)).replace(/[\s-]/g, '')
    : '';
  const match = /^([23])([0-9]{2})([0-9]{2})([0-9]{2})[0-9]{7}$/.exec(id);
  const year = match ? (match[1] === '2' ? 1900 : 2000) + Number(match[2]) : 0;
  if (!match || !validDate(year, Number(match[3]), Number(match[4]))) {
    throw invalid(field, 'nationalId must be the 14 digits of an Egyptian national ID');
  }
  return { id, birthDate: `${year}-${match[3]}-${match[4]}` };
}

export function nationalIdHash(id) {
  return crypto.createHmac('sha256', config.nationalIdKey).update(id).digest('hex');
}

export function ageOn(birthDate, today = new Date()) {
  const [year, month, day] = birthDate.split('-').map(Number);
  let age = today.getUTCFullYear() - year;
  if (today.getUTCMonth() + 1 < month || (today.getUTCMonth() + 1 === month && today.getUTCDate() < day)) {
    age -= 1;
  }
  return age;
}

export function applicationClosed(status) {
  return new AppError(409, 'APPLICATION_LOCKED', `The application is ${status}, it cannot be changed now`, { status });
}

const DOCUMENT_COLUMNS = `id, document_type, license_category, storage_key, expires_on::text AS expires_on,
  review_status, rejection_code, rejection_reason, uploaded_at, reviewed_at, reviewed_by`;

function toDocument(row, baseUrl, admin) {
  const document = {
    id: row.id,
    type: row.document_type,
    status: row.review_status,
    expiresOn: row.expires_on,
    rejectionCode: row.rejection_code,
    rejectionReason: row.rejection_reason,
    uploadedAt: row.uploaded_at,
    reviewedAt: row.reviewed_at,
    url: imageUrl(row.storage_key, baseUrl),
  };
  if (row.document_type === 'driving_license_front') {
    document.licenseCategory = row.license_category;
  }
  if (admin) {
    document.reviewedBy = row.reviewed_by;
  }
  return document;
}

function toVehicle(row, documents, admin) {
  const vehicle = {
    id: row.id,
    vehicleTypeId: row.vehicle_type_id,
    plateNumber: row.plate_number,
    make: row.make,
    model: row.model,
    manufactureYear: row.manufacture_year,
    color: row.color,
    maxPayloadKg: Number(row.max_payload_kg),
    status: row.status,
    documents,
  };
  if (admin) {
    vehicle.cargoLengthM = row.cargo_length_m === null ? null : Number(row.cargo_length_m);
    vehicle.cargoWidthM = row.cargo_width_m === null ? null : Number(row.cargo_width_m);
    vehicle.cargoHeightM = row.cargo_height_m === null ? null : Number(row.cargo_height_m);
  }
  return vehicle;
}

export async function missingForSubmit(client, userId) {
  const { rows: [row] } = await client.query(
    `SELECT driver_submission_missing($1) AS missing,
            EXISTS (
              SELECT 1 FROM vehicles v JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
              WHERE v.driver_id = $1 AND v.status IN ('pending_review', 'active')
                AND license_rank(vt.min_license_category) > COALESCE((
                  SELECT max(license_rank(d.license_category)) FROM driver_documents d
                  WHERE d.driver_id = $1 AND d.document_type = 'driving_license_front'
                    AND d.superseded_at IS NULL AND d.review_status IN ('pending', 'approved')), 99)
            ) AS license_too_low`,
    [userId],
  );
  return row.license_too_low ? [...row.missing, 'license_too_low'] : row.missing;
}

export async function approvalMissing(client, userId) {
  const { rows: [row] } = await client.query(
    `SELECT driver_approval_missing($1) AS missing,
            (driver_current_license($1)).id IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM vehicles v WHERE v.driver_id = $1 AND v.status IN ('pending_review', 'active')
                AND license_fits_vehicle($1, v.id)
            ) AS license_too_low`,
    [userId],
  );
  return row.license_too_low ? [...row.missing, 'license_too_low'] : row.missing;
}

export async function loadApplication(userId, baseUrl, admin = false) {
  const [profile, documents, vehicles, vehicleDocuments, payout] = await Promise.all([
    query(
      `SELECT verification_status, submitted_at, reviewed_at, rejection_reason, city_id,
              date_of_birth::text AS date_of_birth, national_id_last4, max_helpers, active_vehicle_id
       FROM driver_profiles WHERE user_id = $1`,
      [userId],
    ),
    query(
      `SELECT ${DOCUMENT_COLUMNS} FROM driver_documents
       WHERE driver_id = $1 AND superseded_at IS NULL ORDER BY document_type, uploaded_at`,
      [userId],
    ),
    query('SELECT * FROM vehicles WHERE driver_id = $1 ORDER BY id', [userId]),
    query(
      `SELECT d.vehicle_id, d.id, d.document_type, d.storage_key, d.expires_on::text AS expires_on,
              d.review_status, d.rejection_code, d.rejection_reason, d.uploaded_at, d.reviewed_at, d.reviewed_by
       FROM vehicle_documents d JOIN vehicles v ON v.id = d.vehicle_id
       WHERE v.driver_id = $1 AND d.superseded_at IS NULL ORDER BY d.document_type, d.uploaded_at`,
      [userId],
    ),
    query('SELECT * FROM payout_accounts WHERE user_id = $1 AND superseded_at IS NULL', [userId]),
  ]);

  const p = profile.rows[0];
  let missing = [];
  if (!p) {
    missing = ['profile'];
  } else if (p.verification_status === 'draft') {
    missing = await missingForSubmit({ query }, userId);
  }
  const payoutAccount = toPayoutAccount(payout.rows[0]);
  if (admin && payoutAccount) {
    payoutAccount.accountNumber = payout.rows[0].account_number;
  }

  return {
    status: p ? p.verification_status : 'not_started',
    submittedAt: p ? p.submitted_at : null,
    reviewedAt: p ? p.reviewed_at : null,
    rejectionReason: p ? p.rejection_reason : null,
    profile: p ? {
      cityId: p.city_id,
      dateOfBirth: p.date_of_birth,
      nationalIdLast4: p.national_id_last4,
      maxHelpers: p.max_helpers,
      activeVehicleId: p.active_vehicle_id,
    } : null,
    documents: documents.rows.map((row) => toDocument(row, baseUrl, admin)),
    vehicles: vehicles.rows.map((row) => toVehicle(
      row,
      vehicleDocuments.rows.filter((d) => d.vehicle_id === row.id).map((d) => toDocument(d, baseUrl, admin)),
      admin,
    )),
    payoutAccount,
    missing,
    ...(admin && p && p.verification_status === 'pending'
      ? { approvalMissing: await approvalMissing({ query }, userId) } : {}),
  };
}
