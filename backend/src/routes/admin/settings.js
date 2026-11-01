import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { bodyOf, readReason, readFields } from '../../lib/fields.js';
import { settingFields, toSettings } from '../../lib/catalog.js';

const router = Router();

router.get('/', async (req, res) => {
  const { rows: [row] } = await query('SELECT * FROM platform_settings WHERE id = 1');
  res.json({ settings: toSettings(row, true) });
});

router.patch('/', async (req, res) => {
  const body = bodyOf(req);
  const values = readFields(body, settingFields, 'update');
  const actor = { id: req.user.id, role: 'admin', reason: readReason(body) };
  const columns = Object.keys(values);
  const row = await withTransaction(actor, async (client) => {
    const { rows: [updated] } = await client.query(
      `UPDATE platform_settings
       SET ${columns.map((column, i) => `${column} = $${i + 2}`).join(', ')},
           updated_by = $1, updated_at = now()
       WHERE id = 1
       RETURNING *`,
      [req.user.id, ...Object.values(values)],
    );
    return updated;
  });
  res.json({ settings: toSettings(row, true) });
});

export default router;
