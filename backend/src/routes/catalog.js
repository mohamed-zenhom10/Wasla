import { Router } from 'express';
import { query } from '../db.js';
import { loadCatalog, toZone } from '../lib/catalog.js';
import { cleanCoordinate } from '../lib/validate.js';

const router = Router();

router.get('/', async (req, res) => {
  res.json(await loadCatalog(false));
});

router.get('/zone', async (req, res) => {
  const lat = cleanCoordinate(req.query.lat, 'lat', 90);
  const lng = cleanCoordinate(req.query.lng, 'lng', 180);
  const { rows: [zone] } = await query(
    `SELECT id, city_id, code, name_ar, name_en, is_active
     FROM service_zones
     WHERE id = zone_for(ST_SetSRID(ST_MakePoint($1::float8, $2::float8), 4326)::geography)`,
    [lng, lat],
  );
  res.json({ zone: zone ? toZone(zone) : null });
});

export default router;
