import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanText } from '../../lib/validate.js';
import { bodyOf, readReason, readFields } from '../../lib/fields.js';

const router = Router();
const MAX_LENGTH = 100000;

const policyFields = {
  type: {
    column: 'doc_type', clean: (v, f) => cleanChoice(v, f, ['terms', 'privacy']), required: true, fixed: true,
  },
  contentAr: { column: 'content_ar', clean: (v, f) => cleanText(v, f, MAX_LENGTH), required: true },
  contentEn: { column: 'content_en', clean: (v, f) => cleanText(v, f, MAX_LENGTH), required: true },
};

function toPolicy(row) {
  return {
    id: row.id,
    type: row.doc_type,
    version: row.version_number,
    contentAr: row.content_ar,
    contentEn: row.content_en,
    publishedAt: row.published_at,
    createdBy: row.created_by,
    createdAt: row.created_at,
  };
}

function published() {
  return new AppError(409, 'ALREADY_PUBLISHED', 'A published version cannot be changed, create a new version');
}

router.get('/', async (req, res) => {
  const { rows } = await query('SELECT * FROM policy_versions ORDER BY doc_type, version_number DESC');
  res.json({ policies: rows.map(toPolicy) });
});

router.post('/', async (req, res) => {
  const body = bodyOf(req);
  const values = readFields(body, policyFields, 'create');
  const actor = { id: req.user.id, role: 'admin', reason: readReason(body) };
  const row = await withTransaction(actor, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`policy:${values.doc_type}`]);
    const { rows: [draft] } = await client.query(
      'SELECT id FROM policy_versions WHERE doc_type = $1 AND published_at IS NULL',
      [values.doc_type],
    );
    if (draft) {
      throw new AppError(409, 'DRAFT_EXISTS', 'There is already a draft for this policy, edit it instead', {
        id: draft.id,
      });
    }
    const { rows: [created] } = await client.query(
      `INSERT INTO policy_versions (doc_type, version_number, content_ar, content_en, created_by)
       SELECT $1::text, COALESCE(MAX(version_number), 0) + 1, $2::text, $3::text, $4::bigint
       FROM policy_versions WHERE doc_type = $1::text
       RETURNING *`,
      [values.doc_type, values.content_ar, values.content_en, req.user.id],
    );
    return created;
  });
  res.status(201).json({ policy: toPolicy(row) });
});

router.patch('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const values = readFields(body, policyFields, 'update');
  const actor = { id: req.user.id, role: 'admin', reason: readReason(body) };
  const row = await withTransaction(actor, async (client) => {
    const { rows: [current] } = await client.query(
      'SELECT published_at FROM policy_versions WHERE id = $1 FOR UPDATE',
      [id],
    );
    if (!current) {
      throw new AppError(404, 'NOT_FOUND', 'Policy version not found');
    }
    if (current.published_at) {
      throw published();
    }
    const { rows: [updated] } = await client.query(
      `UPDATE policy_versions
       SET content_ar = COALESCE($2, content_ar), content_en = COALESCE($3, content_en)
       WHERE id = $1
       RETURNING *`,
      [id, values.content_ar ?? null, values.content_en ?? null],
    );
    return updated;
  });
  res.json({ policy: toPolicy(row) });
});

router.post('/:id/publish', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const actor = { id: req.user.id, role: 'admin', reason: readReason(body) };
  const row = await withTransaction(actor, async (client) => {
    const { rows: [current] } = await client.query(
      'SELECT published_at FROM policy_versions WHERE id = $1 FOR UPDATE',
      [id],
    );
    if (!current) {
      throw new AppError(404, 'NOT_FOUND', 'Policy version not found');
    }
    if (current.published_at) {
      throw published();
    }
    const { rows: [updated] } = await client.query(
      'UPDATE policy_versions SET published_at = now() WHERE id = $1 RETURNING *',
      [id],
    );
    return updated;
  });
  res.json({ policy: toPolicy(row) });
});

export default router;
