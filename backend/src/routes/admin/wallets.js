import { Router } from 'express';
import { query, withTransaction } from '../../db.js';
import { AppError } from '../../errors.js';
import { cleanId, cleanInteger, cleanText, cleanMoney, invalid } from '../../lib/validate.js';
import { bodyOf, readReason } from '../../lib/fields.js';
import {
  cleanAdjustment, loadWallet, listEntries, loadDriverWallet, listDriverEntries,
} from '../../lib/wallet.js';

const router = Router();

const KINDS = {
  customers: {
    exists: `SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
             WHERE ur.user_id = $1 AND r.code = 'customer'`,
    insert: `INSERT INTO customer_wallet_transactions (customer_id, entry_type, amount, created_by, note)
             VALUES ($1, 'manual_adjustment', $2, $3, $4)`,
    wallet: loadWallet,
    entries: listEntries,
  },
  drivers: {
    exists: 'SELECT 1 FROM driver_profiles WHERE user_id = $1',
    insert: `INSERT INTO wallet_transactions (driver_id, entry_type, amount, created_by, note)
             VALUES ($1, 'manual_adjustment', $2, $3, $4)`,
    wallet: loadDriverWallet,
    entries: listDriverEntries,
  },
};

function kindOf(req) {
  const kind = KINDS[req.params.kind];
  if (!kind) {
    throw new AppError(404, 'NOT_FOUND', 'Route not found');
  }
  return kind;
}

async function walletView(kind, id, page) {
  const { rows: [user] } = await query(
    `SELECT u.id, u.full_name, u.email, u.phone FROM users u WHERE u.id = $1 AND EXISTS (${kind.exists})`,
    [id],
  );
  if (!user) {
    throw new AppError(404, 'NOT_FOUND', 'Wallet not found');
  }
  return {
    owner: { id: user.id, fullName: user.full_name, email: user.email, phone: user.phone },
    wallet: await kind.wallet(id),
    ...await kind.entries(id, page),
  };
}

router.get('/wallets/:kind/:id', async (req, res) => {
  const page = req.query.page === undefined ? 1 : cleanInteger(Number(req.query.page), 'page', 1, 100000);
  res.json(await walletView(kindOf(req), cleanId(req.params.id), page));
});

router.post('/wallets/:kind/:id/adjust', async (req, res) => {
  const kind = kindOf(req);
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  const amount = cleanAdjustment(body.amount, 'amount');
  const reason = cleanText(body.reason, 'reason', 500);
  await withTransaction({ id: req.user.id, role: 'admin', reason }, async (client) => {
    const { rows: [owner] } = await client.query(kind.exists, [id]);
    if (!owner) {
      throw new AppError(404, 'NOT_FOUND', 'Wallet not found');
    }
    await client.query(kind.insert, [id, amount, req.user.id, reason]);
  });
  res.status(201).json(await walletView(kind, id, 1));
});

router.put('/drivers/:id/debt-limit', async (req, res) => {
  const id = cleanId(req.params.id);
  const body = bodyOf(req);
  if (body.debtLimit === undefined) {
    throw invalid('debtLimit', 'debtLimit is required');
  }
  const limit = body.debtLimit === null ? null : cleanMoney(body.debtLimit, 'debtLimit');
  await withTransaction({ id: req.user.id, role: 'admin', reason: readReason(body) }, async (client) => {
    const { rowCount } = await client.query(
      'UPDATE driver_profiles SET debt_limit_override = $2 WHERE user_id = $1',
      [id, limit],
    );
    if (rowCount === 0) {
      throw new AppError(404, 'NOT_FOUND', 'Driver not found');
    }
  });
  res.json(await walletView(KINDS.drivers, id, 1));
});

export default router;
