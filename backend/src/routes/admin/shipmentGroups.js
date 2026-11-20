import { Router } from 'express';
import { query } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanChoice, cleanInteger } from '../../lib/validate.js';
import { STATUS_FILTERS } from '../../lib/shipments.js';
import {
  loadGroup, loadGroupTracking, ADMIN_GROUP_LIST_SQL, toGroupSummary,
} from '../../lib/groups.js';

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
    `SELECT l.*, count(*) OVER () AS total FROM (${ADMIN_GROUP_LIST_SQL}) l
     WHERE ($3::text IS NULL OR l.status = ANY(string_to_array($3, ',')))
     ORDER BY l.created_at DESC, l.id DESC
     LIMIT ${PAGE_SIZE} OFFSET $4`,
    [like, search, status ? STATUS_FILTERS[status].join(',') : null, (page - 1) * PAGE_SIZE],
  );
  res.json({
    groups: rows.map((row) => ({
      ...toGroupSummary(row),
      customer: { id: row.customer_id, name: row.customer_name },
      driver: row.driver_id ? { id: row.driver_id, name: row.driver_name } : null,
    })),
    page,
    pageSize: PAGE_SIZE,
    total: rows.length ? Number(rows[0].total) : 0,
  });
});

router.get('/:id', async (req, res) => {
  const id = cleanId(req.params.id);
  const { rows: [row] } = await query(
    `SELECT g.customer_id, u.full_name, u.email, u.phone
     FROM shipment_groups g JOIN users u ON u.id = g.customer_id
     WHERE g.id = $1`,
    [id],
  );
  if (!row) {
    throw new AppError(404, 'NOT_FOUND', 'Grouped order not found');
  }
  const [group, tracking] = await Promise.all([
    loadGroup(id, `${req.protocol}://${req.get('host')}`),
    loadGroupTracking(id),
  ]);
  res.json({
    customer: { id: row.customer_id, fullName: row.full_name, email: row.email, phone: row.phone },
    group,
    tracking,
  });
});

export default router;
