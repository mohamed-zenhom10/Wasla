import { Router } from 'express';
<<<<<<< HEAD
import { withTransaction } from '../db.js';
import { requireAuth } from '../middleware/auth.js';
import { loadProfile } from '../lib/users.js';
=======
import { query, withTransaction } from '../db.js';
import { requireAuth } from '../middleware/auth.js';
import { loadProfile } from '../lib/users.js';
import { bodyOf, readFields } from '../lib/fields.js';
import { cleanChoice, cleanText, cleanOptionalText, invalid } from '../lib/validate.js';
import { toPayoutAccount } from '../lib/payout.js';
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a

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

<<<<<<< HEAD
=======
const payoutFields = {
  method: { column: 'method', clean: (v, f) => cleanChoice(v, f, ['bank_account', 'wallet']), required: true },
  holderName: { column: 'holder_name', clean: (v, f) => cleanText(v, f, 100), required: true },
  bankName: { column: 'bank_name', clean: (v, f) => cleanOptionalText(v, f, 100) },
  accountNumber: {
    column: 'account_number',
    clean: (v, f) => {
      const number = typeof v === 'string' ? v.replace(/[\s-]/g, '').toUpperCase() : '';
      if (!/^\+?[A-Z0-9]{6,34}$/.test(number)) {
        throw invalid(f, 'accountNumber must be 6 to 34 letters or numbers');
      }
      return number;
    },
    required: true,
  },
};

async function currentPayoutAccount(userId) {
  const { rows: [row] } = await query(
    'SELECT * FROM payout_accounts WHERE user_id = $1 AND superseded_at IS NULL',
    [userId],
  );
  return toPayoutAccount(row);
}

router.get('/payout-account', requireAuth, async (req, res) => {
  res.json({ payoutAccount: await currentPayoutAccount(req.user.id) });
});

router.put('/payout-account', requireAuth, async (req, res) => {
  const values = readFields(bodyOf(req), payoutFields, 'create');
  if (values.method === 'bank_account' && !values.bank_name) {
    throw invalid('bankName', 'bankName is required for a bank account');
  }
  const role = ['driver', 'customer', 'admin'].find((r) => req.user.roles.includes(r));
  await withTransaction({ id: req.user.id, role }, (client) => client.query(
    `INSERT INTO payout_accounts (user_id, method, holder_name, bank_name, account_number)
     VALUES ($1, $2, $3, $4, $5)`,
    [req.user.id, values.method, values.holder_name, values.bank_name || null, values.account_number],
  ));
  res.status(201).json({ payoutAccount: await currentPayoutAccount(req.user.id) });
});

>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
export default router;
