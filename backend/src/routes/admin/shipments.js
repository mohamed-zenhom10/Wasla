import { Router } from 'express';
import { query } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanInteger } from '../../lib/validate.js';
import {
  loadShipment, toShipmentSummary, SUMMARY_SQL, STATUS_FILTERS,
} from '../../lib/shipments.js';

const router = Router();
const PAGE_SIZE = 20;

router.get('/', async (req, res) => {
  const status = req.query.status === undefined ? null
    : cleanChoice(req.query.status, 'status', Object.keys(STATUS_FILTERS));
  const search = typeof req.query.search === 'string' && req.query.search.trim()
    ? req.query.search.trim() : null;
  const like = search ? `%${search.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);

  const { rows } = await query(
    `SELECT list.*, count(*) OVER () AS total FROM (
       ${SUMMARY_SQL} JOIN users u ON u.id = s.customer_id
       WHERE ($1::text IS NULL OR s.status = ANY(string_to_array($1, ',')))
         AND ($2::text IS NULL OR s.id::text = $3 OR u.full_name ILIKE $2 OR u.email ILIKE $2 OR u.phone LIKE $2)
     ) list
     ORDER BY created_at DESC, id DESC
     LIMIT ${PAGE_SIZE} OFFSET $4`,
    [status ? STATUS_FILTERS[status].join(',') : null, like, search, (page - 1) * PAGE_SIZE],
  );
  res.json({
    shipments: rows.map((row) => ({ ...toShipmentSummary(row), customerId: row.customer_id })),
    page,
    pageSize: PAGE_SIZE,
    total: rows.length ? Number(rows[0].total) : 0,
  });
});

router.get('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const { rows: [row] } = await query(
    `SELECT s.customer_id, u.full_name, u.email, u.phone FROM shipments s JOIN users u ON u.id = s.customer_id
     WHERE s.id = $1`,
    [id],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Shipment not found');
  }
  res.json({
    customer: { id: row.customer_id, fullName: row.full_name, email: row.email, phone: row.phone },
    shipment: await loadShipment(id, `${req.protocol}://${req.get('host')}`),
  });
});

export default router;
