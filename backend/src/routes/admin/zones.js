import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import {
  cleanId, cleanRef, cleanBoundary, invalid, cleanText, cleanBoolean, cleanSlug,
} from '../../lib/validate.js';
import {
  bodyOf, readReason, readFields, insertRow, updateRow,
} from '../../lib/fields.js';
import { toZone, ZONE_COLUMNS } from '../../lib/catalog.js';

const router = Router();

const zoneFields = {
  cityId: { column: 'city_id', clean: cleanRef, required: true, fixed: true },
  code: { column: 'code', clean: cleanSlug, required: true, fixed: true },
  nameAr: { column: 'name_ar', clean: (v, f) => cleanText(v, f, 100), required: true },
  nameEn: { column: 'name_en', clean: (v, f) => cleanText(v, f, 100), required: true },
  boundary: {
    column: 'boundary',
    clean: cleanBoundary,
    required: true,
    sql: (param) => `ST_SetSRID(ST_GeomFromGeoJSON(${param}::text), 4326)::geography`,
  },
  isActive: { column: 'is_active', clean: cleanBoolean },
};

async function checkShape(client, boundary) {
  if (boundary === undefined) {
    return;
  }
  const { rows: [shape] } = await client.query(
    'SELECT ST_IsValid(ST_GeomFromGeoJSON($1::text)) AS valid',
    [boundary],
  );
  if (!shape.valid) {
    throw invalid('boundary', 'the boundary lines cross each other or the shape has no area');
  }
}

router.get('/', async (req, res) => {
  const { rows } = await query(`SELECT ${ZONE_COLUMNS} FROM service_zones ORDER BY name_en`);
  res.json({ zones: rows.map(toZone) });
});

router.post('/', async (req, res) => {
  const body = bodyOf(req);
  const values = readFields(body, zoneFields, 'create');
  const actor = { id: req.user.id, role: 'admin', reason: readReason(body) };
  const row = await withTransaction(actor, async (client) => {
    const { rows: [city] } = await client.query('SELECT id FROM cities WHERE id = $1', [values.city_id]);
    if (!city) {
      throw invalid('cityId', 'City not found');
    }
    await checkShape(client, values.boundary);
    return insertRow(client, 'service_zones', zoneFields, values, ZONE_COLUMNS);
  });
  res.status(201).json({ zone: toZone(row) });
});

router.patch('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const values = readFields(body, zoneFields, 'update');
  const actor = { id: req.user.id, role: 'admin', reason: readReason(body) };
  const row = await withTransaction(actor, async (client) => {
    await checkShape(client, values.boundary);
    return updateRow(client, 'service_zones', zoneFields, id, values, ZONE_COLUMNS);
  });
  res.json({ zone: toZone(row) });
});

router.get('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const { rows: [zone] } = await query(`SELECT ${ZONE_COLUMNS} FROM service_zones WHERE id = $1`, [id]);
  if (!zone) {
    throw new AppError(404, 'NOT_FOUND', 'Zone not found');
  }
  res.json({ zone: toZone(zone) });
});

export default router;
