import { Router } from 'express';
import { requireAuth, requireRole } from '../../middleware/auth.js';
import { loadCatalog } from '../../lib/catalog.js';
import catalogRouter from './catalog.js';
import zonesRouter from './zones.js';
import settingsRouter from './settings.js';
import policiesRouter from './policies.js';
import driversRouter from './drivers.js';
import shipmentsRouter from './shipments.js';
import tripsRouter from './trips.js';
import topupsRouter from './topups.js';
import settlementsRouter from './settlements.js';
import walletsRouter from './wallets.js';
import payoutsRouter from './payouts.js';
import withdrawalsRouter from './withdrawals.js';
import couponsRouter from './coupons.js';

const router = Router();

router.use(requireAuth, requireRole('admin'));

router.get('/catalog', async (req, res) => {
  res.json(await loadCatalog(true));
});

router.use(catalogRouter);
router.use(driversRouter);
router.use(tripsRouter);
router.use(walletsRouter);
router.use('/zones', zonesRouter);
router.use('/settings', settingsRouter);
router.use('/policies', policiesRouter);
router.use('/shipments', shipmentsRouter);
router.use('/topups', topupsRouter);
router.use('/settlements', settlementsRouter);
router.use('/payouts', payoutsRouter);
router.use('/withdrawals', withdrawalsRouter);
router.use('/coupons', couponsRouter);

export default router;
