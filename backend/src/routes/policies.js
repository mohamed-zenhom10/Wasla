import { Router } from 'express';
import { query } from '../db.js';

const router = Router();

router.get('/', async (req, res) => {
  const { rows } = await query(
    `SELECT p.doc_type, p.version_number, p.content_ar, p.content_en, p.published_at
     FROM unnest(ARRAY['terms', 'privacy']) AS t
     JOIN policy_versions p ON p.id = latest_policy_version(t)`,
  );

  res.json({
    policies: rows.map((row) => ({
      type: row.doc_type,
      version: row.version_number,
      contentAr: row.content_ar,
      contentEn: row.content_en,
      publishedAt: row.published_at,
    })),
  });
});

export default router;
