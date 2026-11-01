import { Router } from 'express';
import { requireAuth, requireRole } from '../../middleware/auth.js';
import { loadCatalog } from '../../lib/catalog.js';
import catalogRouter from './catalog.js';
import zonesRouter from './zones.js';
import settingsRouter from './settings.js';
import policiesRouter from './policies.js';

const router = Router();

router.use(requireAuth, requireRole('admin'));

router.get('/catalog', async (req, res) => {
  res.json(await loadCatalog(true));
});

router.use(catalogRouter);
router.use('/zones', zonesRouter);
router.use('/settings', settingsRouter);
router.use('/policies', policiesRouter);

export default router;
