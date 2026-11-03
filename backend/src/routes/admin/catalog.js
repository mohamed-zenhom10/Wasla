import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId } from '../../lib/validate.js';
import {
  bodyOf, readReason, readFields, insertRow, updateRow,
} from '../../lib/fields.js';
import {
  categoryFields, sizeFields, vehicleTypeFields, cityFields, reviewTagFields,
  toCategory, toSize, toVehicleType, toCity, toReviewTag,
} from '../../lib/catalog.js';

const router = Router();

function adminActor(req, body) {
  return { id: req.user.id, role: 'admin', reason: readReason(body) };
}

function addCreate(path, table, fields, key, toJson) {
  router.post(path, async (req, res) => {
    const body = bodyOf(req);
    const values = readFields(body, fields, 'create');
    const row = await withTransaction(
      adminActor(req, body),
      (client) => insertRow(client, table, fields, values, '*'),
    );
    res.status(201).json({ [key]: toJson(row) });
  });
}

function addUpdate(path, table, fields, key, toJson) {
  router.patch(`${path}/:id`, async (req, res) => {
    const id = cleanId(req.params.id);
    const body = bodyOf(req);
    const values = readFields(body, fields, 'update');
    const row = await withTransaction(
      adminActor(req, body),
      (client) => updateRow(client, table, fields, id, values, '*'),
    );
    res.json({ [key]: toJson(row) });
  });
}

async function categorySizes(categoryId) {
  const { rows } = await query(
    'SELECT * FROM cargo_size_options WHERE cargo_category_id = $1 ORDER BY sort_order, id',
    [categoryId],
  );
  return rows.map(toSize);
}

addCreate('/cargo-categories', 'cargo_categories', categoryFields, 'cargoCategory', (row) => toCategory(row, []));
router.patch('/cargo-categories/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const values = readFields(body, categoryFields, 'update');
  const row = await withTransaction(
    adminActor(req, body),
    (client) => updateRow(client, 'cargo_categories', categoryFields, id, values, '*'),
  );
  res.json({ cargoCategory: toCategory(row, await categorySizes(id)) });
});

router.post('/cargo-categories/:id/sizes', async (req, res) => {
  const categoryId = cleanId(req.params.id);
  const body = bodyOf(req);
  const values = readFields(body, sizeFields, 'create');
  const row = await withTransaction(adminActor(req, body), async (client) => {
    const { rows: [category] } = await client.query(
      'SELECT id FROM cargo_categories WHERE id = $1',
      [categoryId],
    );
    if (!category) {
      throw new AppError(404, 'NOT_FOUND', 'Cargo category not found');
    }
    return insertRow(client, 'cargo_size_options', sizeFields, { cargo_category_id: categoryId, ...values }, '*');
  });
  res.status(201).json({ size: toSize(row) });
});
addUpdate('/cargo-sizes', 'cargo_size_options', sizeFields, 'size', toSize);

addCreate('/vehicle-types', 'vehicle_types', vehicleTypeFields, 'vehicleType', toVehicleType);
addUpdate('/vehicle-types', 'vehicle_types', vehicleTypeFields, 'vehicleType', toVehicleType);

addCreate('/cities', 'cities', cityFields, 'city', toCity);
addUpdate('/cities', 'cities', cityFields, 'city', toCity);

addCreate('/review-tags', 'review_tags', reviewTagFields, 'reviewTag', toReviewTag);
addUpdate('/review-tags', 'review_tags', reviewTagFields, 'reviewTag', toReviewTag);

export default router;
