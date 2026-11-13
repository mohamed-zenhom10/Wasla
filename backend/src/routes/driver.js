import express, { Router } from 'express';
import { query, withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { bodyOf, readFields, insertRow, updateRow } from '../lib/fields.js';
import {
  cleanId, cleanRef, cleanText, cleanInteger, cleanChoice, invalid,
} from '../lib/validate.js';
import {
  IMAGE_TYPES, MAX_IMAGE_MB, readImage, saveImage,
} from '../lib/storage.js';
import {
  DRIVER_DOCUMENTS, VEHICLE_DOCUMENTS, cleanDate, cleanNationalId, nationalIdHash, ageOn,
  applicationClosed, missingForSubmit, loadApplication,
} from '../lib/driver.js';
import { POINT_SQL } from '../lib/route.js';
import {
  readPoint, readAccuracy, loadState, blockersOf, blockerError, loadStatus,
} from '../lib/presence.js';
import tripsRouter from './driverTrips.js';
import { EXECUTING, trackPoint } from '../lib/trips.js';

const router = Router();
const LICENSES = ['private', 'professional_3', 'professional_2', 'professional_1'];
const imageBody = express.raw({ type: IMAGE_TYPES, limit: `${MAX_IMAGE_MB}mb` });

router.use(requireAuth, requireRole('driver'));
router.use(tripsRouter);

function actorOf(req) {
  return { id: req.user.id, role: 'driver' };
}

function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

async function reply(req, res, status = 200) {
  res.status(status).json({ application: await loadApplication(req.user.id, baseUrl(req)) });
}

async function lockProfile(client, userId) {
  const { rows: [profile] } = await client.query(
    'SELECT verification_status FROM driver_profiles WHERE user_id = $1 FOR UPDATE',
    [userId],
  );
  return profile ? profile.verification_status : null;
}

function requireProfile(status) {
  if (!status) {
    throw new AppError(409, 'PROFILE_REQUIRED', 'Save the personal information first');
  }
}

const profileFields = {
  cityId: { column: 'city_id', clean: cleanRef, required: true },
  dateOfBirth: { column: 'date_of_birth', clean: cleanDate, required: true },
  nationalId: { column: 'national_id', clean: cleanNationalId, required: true },
  maxHelpers: { column: 'max_helpers', clean: (v, f) => cleanInteger(v, f, 0, 20) },
};

router.get('/application', async (req, res) => {
  await reply(req, res);
});

router.put('/profile', async (req, res) => {
  const body = bodyOf(req);
  await withTransaction(actorOf(req), async (client) => {
    const status = await lockProfile(client, req.user.id);
    if (status && status !== 'draft') {
      throw applicationClosed(status);
    }
    const values = readFields(body, profileFields, status ? 'update' : 'create');

    if ((values.national_id === undefined) !== (values.date_of_birth === undefined)) {
      throw invalid(values.national_id ? 'dateOfBirth' : 'nationalId', 'Send dateOfBirth and nationalId together');
    }
    if (values.national_id) {
      if (values.national_id.birthDate !== values.date_of_birth) {
        throw invalid('dateOfBirth', 'dateOfBirth does not match the national ID');
      }
      const { rows: [settings] } = await client.query('SELECT min_driver_age FROM platform_settings WHERE id = 1');
      if (ageOn(values.date_of_birth) < settings.min_driver_age) {
        throw invalid('dateOfBirth', `Drivers must be at least ${settings.min_driver_age} years old`);
      }
      values.national_id_hash = nationalIdHash(values.national_id.id);
      values.national_id_last4 = values.national_id.id.slice(-4);
      delete values.national_id;
    }
    if (values.city_id) {
      const { rows: [city] } = await client.query('SELECT is_active FROM cities WHERE id = $1', [values.city_id]);
      if (!city || !city.is_active) {
        throw invalid('cityId', 'We do not work in this city yet');
      }
    }

    if (status) {
      await updateRow(client, 'driver_profiles', profileFields, req.user.id, values, 'user_id', 'user_id');
    } else {
      await insertRow(client, 'driver_profiles', profileFields, { user_id: req.user.id, ...values }, 'user_id');
    }
  });
  await reply(req, res);
});

function readLicenseCategory(req, type) {
  const value = req.query.licenseCategory;
  if (type === 'driving_license_front') {
    return cleanChoice(value, 'licenseCategory', LICENSES);
  }
  if (value !== undefined) {
    throw invalid('licenseCategory', 'licenseCategory is only for driving_license_front');
  }
  return null;
}

function checkDocumentStatus(status) {
  requireProfile(status);
  if (status === 'rejected') {
    throw applicationClosed(status);
  }
}

router.put('/documents/:type', imageBody, async (req, res) => {
  const type = cleanChoice(req.params.type, 'type', DRIVER_DOCUMENTS);
  const category = readLicenseCategory(req, type);
  const image = readImage(req);
  checkDocumentStatus(await withTransaction(null, (client) => lockProfile(client, req.user.id)));

  const key = await saveImage(image, `wasla/drivers/${req.user.id}`);
  await withTransaction(actorOf(req), async (client) => {
    checkDocumentStatus(await lockProfile(client, req.user.id));
    await client.query(
      `INSERT INTO driver_documents (driver_id, document_type, license_category, storage_key)
       VALUES ($1, $2, $3, $4)`,
      [req.user.id, type, category, key],
    );
  });
  await reply(req, res, 201);
});

const vehicleFields = {
  vehicleTypeId: { column: 'vehicle_type_id', clean: cleanRef, required: true },
  plateNumber: {
    column: 'plate_number',
    clean: (v, f) => cleanText(v, f, 20).replace(/\s+/g, ' ').toUpperCase(),
    required: true,
  },
  make: { column: 'make', clean: (v, f) => cleanText(v, f, 50), required: true },
  model: { column: 'model', clean: (v, f) => cleanText(v, f, 50), required: true },
  manufactureYear: {
    column: 'manufacture_year',
    clean: (v, f) => cleanInteger(v, f, 1980, new Date().getUTCFullYear() + 1),
    required: true,
  },
  color: { column: 'color', clean: (v, f) => cleanText(v, f, 30), required: true },
};

async function checkVehicleType(client, values) {
  if (values.vehicle_type_id === undefined) {
    return;
  }
  const { rows: [type] } = await client.query(
    'SELECT is_active FROM vehicle_types WHERE id = $1',
    [values.vehicle_type_id],
  );
  if (!type || !type.is_active) {
    throw invalid('vehicleTypeId', 'Vehicle type not found');
  }
}

async function ownVehicle(client, req) {
  const id = cleanId(req.params.id);
  const { rows: [vehicle] } = await client.query(
    'SELECT id, status FROM vehicles WHERE id = $1 AND driver_id = $2 FOR UPDATE',
    [id, req.user.id],
  );
  if (!vehicle) {
    throw new AppError(404, 'NOT_FOUND', 'Vehicle not found');
  }
  return vehicle;
}

router.post('/vehicles', async (req, res) => {
  const body = bodyOf(req);
  const values = readFields(body, vehicleFields, 'create');
  await withTransaction(actorOf(req), async (client) => {
    const status = await lockProfile(client, req.user.id);
    requireProfile(status);
    if (status === 'pending' || status === 'rejected') {
      throw applicationClosed(status);
    }
    await checkVehicleType(client, values);
    await insertRow(client, 'vehicles', vehicleFields, { driver_id: req.user.id, ...values }, 'id');
  });
  await reply(req, res, 201);
});

router.patch('/vehicles/:id', async (req, res) => {
  const body = bodyOf(req);
  const values = readFields(body, vehicleFields, 'update');
  await withTransaction(actorOf(req), async (client) => {
    const status = await lockProfile(client, req.user.id);
    const vehicle = await ownVehicle(client, req);
    if (status === 'pending' || status === 'rejected') {
      throw applicationClosed(status);
    }
    if (vehicle.status !== 'pending_review') {
      throw new AppError(409, 'VEHICLE_LOCKED', 'This vehicle was already reviewed, it cannot be changed');
    }
    await checkVehicleType(client, values);
    await updateRow(client, 'vehicles', vehicleFields, vehicle.id, values, 'id');
  });
  await reply(req, res);
});

async function checkVehicleUpload(client, req) {
  const status = await lockProfile(client, req.user.id);
  const vehicle = await ownVehicle(client, req);
  if (status === 'rejected') {
    throw applicationClosed(status);
  }
  if (vehicle.status === 'rejected' || vehicle.status === 'inactive') {
    throw new AppError(409, 'VEHICLE_LOCKED', `This vehicle is ${vehicle.status}`);
  }
  return vehicle;
}

router.put('/vehicles/:id/documents/:type', imageBody, async (req, res) => {
  const type = cleanChoice(req.params.type, 'type', VEHICLE_DOCUMENTS);
  const image = readImage(req);
  const vehicle = await withTransaction(null, (client) => checkVehicleUpload(client, req));

  const key = await saveImage(image, `wasla/drivers/${req.user.id}/vehicles/${vehicle.id}`);
  await withTransaction(actorOf(req), async (client) => {
    await checkVehicleUpload(client, req);
    await client.query(
      'INSERT INTO vehicle_documents (vehicle_id, document_type, storage_key) VALUES ($1, $2, $3)',
      [vehicle.id, type, key],
    );
  });
  await reply(req, res, 201);
});

router.post('/application/submit', async (req, res) => {
  const body = bodyOf(req);
  if (body.confirm !== true) {
    throw invalid('confirm', 'The driver must confirm that the documents are theirs');
  }
  await withTransaction(actorOf(req), async (client) => {
    const status = await lockProfile(client, req.user.id);
    requireProfile(status);
    if (status !== 'draft') {
      throw applicationClosed(status);
    }
    const missing = await missingForSubmit(client, req.user.id);
    if (missing.length > 0) {
      throw new AppError(400, 'APPLICATION_INCOMPLETE', 'Some steps are not done yet', { missing });
    }
    await client.query(
      "UPDATE driver_profiles SET verification_status = 'pending' WHERE user_id = $1",
      [req.user.id],
    );
  });
  await reply(req, res);
});

async function replyStatus(req, res) {
  res.json({ status: await loadStatus(req.user.id) });
}

router.get('/status', replyStatus);

router.post('/online', async (req, res) => {
  const point = readPoint(bodyOf(req));
  await withTransaction(actorOf(req), async (client) => {
    const state = await loadState(client, req.user.id, true);
    const [blocker] = blockersOf(state);
    if (blocker) {
      throw blockerError(blocker, state);
    }
    await client.query(
      `UPDATE driver_profiles
       SET current_location = ${POINT_SQL('$2', '$3')}, location_updated_at = now(), is_online = true
       WHERE user_id = $1`,
      [req.user.id, point.lng, point.lat],
    );
  });
  await replyStatus(req, res);
});

router.post('/offline', async (req, res) => {
  await withTransaction(actorOf(req), async (client) => {
    const { rows: [running] } = await client.query(
      'SELECT id FROM trips WHERE driver_id = $1 AND status = ANY($2::text[]) LIMIT 1',
      [req.user.id, EXECUTING],
    );
    if (running) {
      throw new AppError(409, 'TRIP_RUNNING', 'Finish your trip before going offline', { tripId: running.id });
    }
    await client.query('UPDATE driver_profiles SET is_online = false WHERE user_id = $1 AND is_online', [req.user.id]);
  });
  await replyStatus(req, res);
});

router.post('/location', async (req, res) => {
  const body = bodyOf(req);
  const point = readPoint(body);
  const accuracy = readAccuracy(body);
  const { rowCount } = await query(
    `UPDATE driver_profiles SET current_location = ${POINT_SQL('$2', '$3')}, location_updated_at = now()
     WHERE user_id = $1 AND is_online`,
    [req.user.id, point.lng, point.lat],
  );
  if (rowCount === 0) {
    throw new AppError(409, 'NOT_ONLINE', 'You are offline, go online first');
  }
  await trackPoint({ query }, req.user.id, point, accuracy);
  await replyStatus(req, res);
});

export default router;
