import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import {
  cleanId, cleanChoice, cleanText, cleanInteger, cleanMeasure, invalid,
} from '../../lib/validate.js';
import { bodyOf, readReason, readFields } from '../../lib/fields.js';
import { cleanDate, loadApplication, approvalMissing } from '../../lib/driver.js';
import { sendNotice } from '../../lib/mailer.js';

const router = Router();
const PAGE_SIZE = 20;
const LICENSES = ['private', 'professional_3', 'professional_2', 'professional_1'];
const DOCUMENT_CODES = ['blurry', 'expiry_unreadable', 'expired', 'name_mismatch', 'wrong_document', 'other'];
const PAYOUT_CODES = ['name_mismatch', 'invalid_account', 'unsupported_bank', 'other'];
const NEEDS_EXPIRY = ['national_id_front', 'driving_license_front', 'vehicle_license_front'];
const ONLY_WHEN_REJECTING = 'Only send a rejection reason when rejecting';
const SEND_BOTH = 'Send rejectionCode and rejectionReason';
const VEHICLE_TYPES = [
  'vehicle_license_front', 'vehicle_license_back',
  'vehicle_photo_front', 'vehicle_photo_side', 'vehicle_photo_rear', 'vehicle_photo_cargo',
];

function adminActor(req, reason) {
  return { id: req.user.id, role: 'admin', reason };
}

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

async function driverView(req, userId) {
  const { rows: [user] } = await query(
    `SELECT id, full_name, email, phone, preferred_language, account_status, created_at
     FROM users WHERE id = $1`,
    [userId],
  );
  return {
    driver: {
      id: user.id,
      fullName: user.full_name,
      email: user.email,
      phone: user.phone,
      language: user.preferred_language,
      accountStatus: user.account_status,
      createdAt: user.created_at,
    },
    application: await loadApplication(userId, baseUrl(req), true),
  };
}

async function notify(userId, kind, params) {
  const { rows: [user] } = await query('SELECT email, preferred_language FROM users WHERE id = $1', [userId]);
  if (user && user.email) {
    await sendNotice(user.email, user.preferred_language, kind, params);
  }
}

async function lockDriver(client, userId) {
  const { rows: [profile] } = await client.query(
    'SELECT verification_status FROM driver_profiles WHERE user_id = $1 FOR UPDATE',
    [userId],
  );
  if (!profile) {
    throw new AppError(404, 'NOT_FOUND', 'Driver application not found');
  }
  return profile.verification_status;
}

function wrongStatus(status) {
  return new AppError(409, 'WRONG_STATUS', `The application is ${status}`, { status });
}

router.get('/drivers', async (req, res) => {
  const status = req.query.status === undefined ? null
    : cleanChoice(req.query.status, 'status', ['draft', 'pending', 'needs_fix', 'approved', 'rejected']);
  const search = typeof req.query.search === 'string' && req.query.search.trim()
    ? `%${req.query.search.trim().replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);

  const { rows } = await query(
    `WITH list AS (
       SELECT u.id, u.full_name, u.email, u.phone, u.account_status, p.verification_status, p.city_id,
              p.submitted_at, p.reviewed_at,
              EXISTS (SELECT 1 FROM driver_documents d WHERE d.driver_id = p.user_id
                        AND d.superseded_at IS NULL AND d.review_status = 'rejected')
              OR EXISTS (SELECT 1 FROM vehicle_documents d JOIN vehicles v ON v.id = d.vehicle_id
                         WHERE v.driver_id = p.user_id AND d.superseded_at IS NULL AND d.review_status = 'rejected')
                AS needs_fix,
              (SELECT count(*) FROM driver_documents d WHERE d.driver_id = p.user_id
                 AND d.superseded_at IS NULL AND d.review_status = 'pending')
              + (SELECT count(*) FROM vehicle_documents d JOIN vehicles v ON v.id = d.vehicle_id
                 WHERE v.driver_id = p.user_id AND d.superseded_at IS NULL AND d.review_status = 'pending')
                AS pending_documents
       FROM driver_profiles p JOIN users u ON u.id = p.user_id
       WHERE ($2::text IS NULL OR u.full_name ILIKE $2 OR u.email ILIKE $2 OR u.phone LIKE $2)
     )
     SELECT *, count(*) OVER () AS total FROM list
     WHERE $1::text IS NULL
        OR ($1 = 'needs_fix' AND verification_status = 'pending' AND needs_fix)
        OR verification_status = $1
     ORDER BY submitted_at NULLS LAST, id
     LIMIT ${PAGE_SIZE} OFFSET $3`,
    [status, search, (page - 1) * PAGE_SIZE],
  );

  res.json({
    drivers: rows.map((row) => ({
      id: row.id,
      fullName: row.full_name,
      email: row.email,
      phone: row.phone,
      accountStatus: row.account_status,
      status: row.verification_status,
      cityId: row.city_id,
      submittedAt: row.submitted_at,
      reviewedAt: row.reviewed_at,
      needsFix: row.needs_fix,
      pendingDocuments: Number(row.pending_documents),
    })),
    page,
    pageSize: PAGE_SIZE,
    total: rows.length ? Number(rows[0].total) : 0,
  });
});

router.get('/drivers/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const { rows: [profile] } = await query('SELECT 1 FROM driver_profiles WHERE user_id = $1', [id]);
  if (!profile) {
    throw new AppError(404, 'NOT_FOUND', 'Driver application not found');
  }
  res.json(await driverView(req, id));
});

const reviewFields = {
  decision: { column: 'review_status', clean: (v, f) => cleanChoice(v, f, ['approve', 'reject']), required: true },
  expiresOn: { column: 'expires_on', clean: cleanDate },
  licenseCategory: { column: 'license_category', clean: (v, f) => cleanChoice(v, f, LICENSES) },
  rejectionCode: { column: 'rejection_code', clean: (v, f) => cleanChoice(v, f, DOCUMENT_CODES) },
  rejectionReason: { column: 'rejection_reason', clean: (v, f) => cleanText(v, f, 500) },
};

function readReview(body, type) {
  const values = readFields(body, reviewFields, 'create');
  const has = (column) => values[column] !== undefined;
  if (values.review_status === 'approve') {
    if (has('rejection_code') || has('rejection_reason')) {
      throw invalid(has('rejection_code') ? 'rejectionCode' : 'rejectionReason', ONLY_WHEN_REJECTING);
    }
    if (NEEDS_EXPIRY.includes(type) && !has('expires_on')) {
      throw invalid('expiresOn', 'Write the expiry date from the photo');
    }
    if (!NEEDS_EXPIRY.includes(type) && has('expires_on')) {
      throw invalid('expiresOn', 'This document has no expiry date');
    }
    if (has('expires_on') && values.expires_on <= new Date().toISOString().slice(0, 10)) {
      throw invalid('expiresOn', 'This document is expired, reject it with the code expired');
    }
    if (has('license_category') && type !== 'driving_license_front') {
      throw invalid('licenseCategory', 'licenseCategory is only for driving_license_front');
    }
    values.review_status = 'approved';
  } else {
    if (!has('rejection_code') || !has('rejection_reason')) {
      throw invalid(has('rejection_code') ? 'rejectionReason' : 'rejectionCode', SEND_BOTH);
    }
    if (has('expires_on') || has('license_category')) {
      throw invalid(has('expires_on') ? 'expiresOn' : 'licenseCategory', 'Only send this when approving');
    }
    values.review_status = 'rejected';
  }
  return values;
}

function reviewDocument(table) {
  const owner = table === 'driver_documents'
    ? 'd.driver_id'
    : '(SELECT v.driver_id FROM vehicles v WHERE v.id = d.vehicle_id)';

  return async (req, res) => {
    const id = cleanId(req.params.id);
    const body = bodyOf(req);
    let driverId;
    let values;

    await withTransaction(adminActor(req, readReason(body)), async (client) => {
      const { rows: [doc] } = await client.query(
        `SELECT d.document_type, d.review_status, d.superseded_at, ${owner} AS driver_id
         FROM ${table} d WHERE d.id = $1`,
        [id],
      );
      if (!doc) {
        throw new AppError(404, 'NOT_FOUND', 'Document not found');
      }
      driverId = doc.driver_id;
      values = readReview(body, doc.document_type);
      values.type = doc.document_type;

      const status = await lockDriver(client, driverId);
      if (status === 'draft' || status === 'rejected') {
        throw wrongStatus(status);
      }
      const { rows: [locked] } = await client.query(
        `SELECT review_status, superseded_at FROM ${table} WHERE id = $1 FOR UPDATE`,
        [id],
      );
      if (locked.superseded_at) {
        throw new AppError(409, 'DOCUMENT_REPLACED', 'The driver uploaded a newer photo, review that one');
      }
      if (locked.review_status !== 'pending') {
        throw new AppError(409, 'ALREADY_REVIEWED', `This document is already ${locked.review_status}`);
      }

      const columns = ['review_status', 'expires_on', 'rejection_code', 'rejection_reason', 'license_category']
        .filter((column) => values[column] !== undefined);
      await client.query(
        `UPDATE ${table} SET ${columns.map((column, i) => `${column} = $${i + 2}`).join(', ')} WHERE id = $1`,
        [id, ...columns.map((column) => values[column])],
      );
    });

    if (values.review_status === 'rejected') {
      await notify(driverId, 'document_rejected', {
        type: values.type, code: values.rejection_code, reason: values.rejection_reason,
      });
    }
    res.json(await driverView(req, driverId));
  };
}

router.post('/driver-documents/:id/review', reviewDocument('driver_documents'));
router.post('/vehicle-documents/:id/review', reviewDocument('vehicle_documents'));

async function readyVehicle(client, driverId, vehicleId) {
  const { rows } = await client.query(
    `SELECT v.id, license_fits_vehicle($1, v.id) AS fits
     FROM vehicles v
     WHERE v.driver_id = $1 AND v.status IN ('pending_review', 'active') AND ($2::bigint IS NULL OR v.id = $2)
       AND (SELECT count(DISTINCT d.document_type) FROM vehicle_documents d
            WHERE d.vehicle_id = v.id AND d.superseded_at IS NULL AND d.review_status = 'approved') = 6
       AND EXISTS (SELECT 1 FROM vehicle_documents d WHERE d.vehicle_id = v.id
                   AND d.document_type = 'vehicle_license_front' AND d.superseded_at IS NULL
                   AND d.review_status = 'approved' AND d.expires_on > current_date)
     ORDER BY license_fits_vehicle($1, v.id) DESC, v.id
     LIMIT 1`,
    [driverId, vehicleId],
  );
  return rows[0];
}

router.post('/drivers/:id/approve', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  await withTransaction(adminActor(req, readReason(body)), async (client) => {
    const status = await lockDriver(client, id);
    if (status !== 'pending') {
      throw wrongStatus(status);
    }
    const missing = await approvalMissing(client, id);
    const vehicle = await readyVehicle(client, id, null);
    if (missing.length > 0 || !vehicle || !vehicle.fits) {
      throw new AppError(400, 'APPROVAL_INCOMPLETE', 'Some documents are not approved yet', {
        missing: missing.length > 0 ? missing : ['license_too_low'],
      });
    }
    await client.query(
      "UPDATE driver_profiles SET verification_status = 'approved', rejection_reason = NULL WHERE user_id = $1",
      [id],
    );
    await client.query(
      "UPDATE vehicles SET status = 'active' WHERE id = $1 AND status = 'pending_review'",
      [vehicle.id],
    );
    await client.query('UPDATE driver_profiles SET active_vehicle_id = $2 WHERE user_id = $1', [id, vehicle.id]);
  });
  await notify(id, 'driver_approved');
  res.json(await driverView(req, id));
});

router.post('/drivers/:id/reject', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const reason = cleanText(body.reason, 'reason', 500);
  await withTransaction(adminActor(req, reason), async (client) => {
    const status = await lockDriver(client, id);
    if (status !== 'pending') {
      throw wrongStatus(status);
    }
    await client.query(
      "UPDATE driver_profiles SET verification_status = 'rejected', rejection_reason = $2 WHERE user_id = $1",
      [id, reason],
    );
  });
  await notify(id, 'driver_rejected', { reason });
  res.json(await driverView(req, id));
});

async function lockVehicle(client, id) {
  const { rows: [vehicle] } = await client.query(
    'SELECT id, driver_id, status FROM vehicles WHERE id = $1 FOR UPDATE',
    [id],
  );
  if (!vehicle) {
    throw new AppError(404, 'NOT_FOUND', 'Vehicle not found');
  }
  return vehicle;
}

const measure = (column) => ({ column, clean: (v, f) => (v === null ? null : cleanMeasure(v, f)) });
const vehicleFields = {
  maxPayloadKg: { column: 'max_payload_kg', clean: cleanMeasure },
  cargoLengthM: measure('cargo_length_m'),
  cargoWidthM: measure('cargo_width_m'),
  cargoHeightM: measure('cargo_height_m'),
};

router.patch('/vehicles/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const values = readFields(body, vehicleFields, 'update');
  let driverId;
  await withTransaction(adminActor(req, readReason(body)), async (client) => {
    const vehicle = await lockVehicle(client, id);
    driverId = vehicle.driver_id;
    if (vehicle.status === 'rejected' || vehicle.status === 'inactive') {
      throw new AppError(409, 'VEHICLE_LOCKED', `This vehicle is ${vehicle.status}`);
    }
    const columns = Object.keys(values);
    await client.query(
      `UPDATE vehicles SET ${columns.map((column, i) => `${column} = $${i + 2}`).join(', ')} WHERE id = $1`,
      [id, ...Object.values(values)],
    );
  });
  res.json(await driverView(req, driverId));
});

router.post('/vehicles/:id/activate', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  let driverId;
  await withTransaction(adminActor(req, readReason(body)), async (client) => {
    const vehicle = await lockVehicle(client, id);
    driverId = vehicle.driver_id;
    const status = await lockDriver(client, driverId);
    if (status !== 'approved') {
      throw new AppError(409, 'WRONG_STATUS', 'Approve the driver first, that also activates the vehicle', { status });
    }
    if (vehicle.status !== 'pending_review') {
      throw new AppError(409, 'VEHICLE_LOCKED', `This vehicle is ${vehicle.status}`);
    }
    const ready = await readyVehicle(client, driverId, id);
    if (!ready || !ready.fits) {
      const { rows } = await client.query(
        `SELECT document_type FROM vehicle_documents
         WHERE vehicle_id = $1 AND superseded_at IS NULL AND review_status = 'approved'`,
        [id],
      );
      const approved = rows.map((row) => row.document_type);
      const missing = VEHICLE_TYPES.filter((type) => !approved.includes(type));
      throw new AppError(400, 'APPROVAL_INCOMPLETE', 'Some vehicle documents are not approved yet', {
        missing: missing.length > 0 ? missing : [ready ? 'license_too_low' : 'vehicle_license_valid'],
      });
    }
    await client.query("UPDATE vehicles SET status = 'active' WHERE id = $1", [id]);
    await client.query(
      'UPDATE driver_profiles SET active_vehicle_id = $2 WHERE user_id = $1 AND active_vehicle_id IS NULL',
      [driverId, id],
    );
  });
  res.json(await driverView(req, driverId));
});

router.post('/vehicles/:id/reject', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const reason = cleanText(body.reason, 'reason', 500);
  let driverId;
  await withTransaction(adminActor(req, reason), async (client) => {
    const vehicle = await lockVehicle(client, id);
    driverId = vehicle.driver_id;
    if (vehicle.status !== 'pending_review') {
      throw new AppError(409, 'VEHICLE_LOCKED', `This vehicle is ${vehicle.status}`);
    }
    await client.query("UPDATE vehicles SET status = 'rejected' WHERE id = $1", [id]);
  });
  res.json(await driverView(req, driverId));
});

function toAccount(row) {
  return {
    id: row.id,
    userId: row.user_id,
    fullName: row.full_name,
    email: row.email,
    method: row.method,
    holderName: row.holder_name,
    bankName: row.bank_name,
    accountNumber: row.account_number,
    status: row.review_status,
    rejectionCode: row.rejection_code,
    rejectionReason: row.rejection_reason,
    createdAt: row.created_at,
    reviewedAt: row.reviewed_at,
  };
}

const ACCOUNT_QUERY = `SELECT a.*, u.full_name, u.email FROM payout_accounts a JOIN users u ON u.id = a.user_id`;

router.get('/payout-accounts', async (req, res) => {
  const status = req.query.status === undefined ? 'pending'
    : cleanChoice(req.query.status, 'status', ['pending', 'approved', 'rejected']);
  const { rows } = await query(
    `${ACCOUNT_QUERY} WHERE a.superseded_at IS NULL AND a.review_status = $1 ORDER BY a.created_at LIMIT 200`,
    [status],
  );
  res.json({ payoutAccounts: rows.map(toAccount) });
});

const accountReviewFields = {
  decision: { column: 'decision', clean: (v, f) => cleanChoice(v, f, ['approve', 'reject']), required: true },
  rejectionCode: { column: 'rejection_code', clean: (v, f) => cleanChoice(v, f, PAYOUT_CODES) },
  rejectionReason: { column: 'rejection_reason', clean: (v, f) => cleanText(v, f, 500) },
};

router.post('/payout-accounts/:id/review', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const values = readFields(body, accountReviewFields, 'create');
  const rejecting = values.decision === 'reject';
  if (rejecting && (!values.rejection_code || !values.rejection_reason)) {
    throw invalid(values.rejection_code ? 'rejectionReason' : 'rejectionCode', SEND_BOTH);
  }
  if (!rejecting && (values.rejection_code || values.rejection_reason)) {
    throw invalid(values.rejection_code ? 'rejectionCode' : 'rejectionReason', ONLY_WHEN_REJECTING);
  }

  const account = await withTransaction(adminActor(req, readReason(body)), async (client) => {
    const { rows: [current] } = await client.query(
      'SELECT user_id, review_status, superseded_at FROM payout_accounts WHERE id = $1 FOR UPDATE',
      [id],
    );
    if (!current) {
      throw new AppError(404, 'NOT_FOUND', 'Payout account not found');
    }
    if (current.superseded_at) {
      throw new AppError(409, 'DOCUMENT_REPLACED', 'The user added a newer account, review that one');
    }
    if (current.review_status !== 'pending') {
      throw new AppError(409, 'ALREADY_REVIEWED', `This account is already ${current.review_status}`);
    }
    await client.query(
      `UPDATE payout_accounts SET review_status = $2, rejection_code = $3, rejection_reason = $4 WHERE id = $1`,
      [id, rejecting ? 'rejected' : 'approved', values.rejection_code || null, values.rejection_reason || null],
    );
    const { rows: [row] } = await client.query(`${ACCOUNT_QUERY} WHERE a.id = $1`, [id]);
    return row;
  });

  if (rejecting) {
    await notify(account.user_id, 'payout_rejected', { code: values.rejection_code, reason: values.rejection_reason });
  }
  res.json({ payoutAccount: toAccount(account) });
});

export default router;
