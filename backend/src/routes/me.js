import { Router } from 'express';
import { withTransaction } from '../db.js';
import { requireAuth } from '../middleware/auth.js';
import { loadProfile } from '../lib/users.js';

const router = Router();

router.get('/', requireAuth, async (req, res) => {
  res.json({ user: await loadProfile(req.user.id) });
});

router.post('/accept-policies', requireAuth, async (req, res) => {
  await withTransaction(null, (client) => client.query(
    `INSERT INTO policy_acceptances (user_id, policy_version_id)
     SELECT $1, v.id
     FROM (SELECT latest_policy_version(t) AS id FROM unnest(ARRAY['terms', 'privacy']) AS t) v
     WHERE v.id IS NOT NULL
     ON CONFLICT (user_id, policy_version_id) DO NOTHING`,
    [req.user.id],
  ));
  res.json({ user: await loadProfile(req.user.id) });
});

export default router;
