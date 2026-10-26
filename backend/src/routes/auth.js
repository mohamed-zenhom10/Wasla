import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { query, withTransaction } from '../db.js';
import { AppError } from '../errors.js';
import { issueCode, checkCode, codeError } from '../lib/otp.js';
import { createSession, hashToken } from '../lib/tokens.js';
import { loadProfile } from '../lib/users.js';
import {
  cleanEmail, cleanPassword, cleanName, cleanPhone, cleanCode, cleanToken,
} from '../lib/validate.js';
import { rateLimit, emailOf } from '../middleware/rateLimit.js';

const router = Router();
const SIGNUP_ROLES = ['customer', 'driver'];

const loginLimit = rateLimit({ minutes: 15, max: 10, key: (req) => `${req.ip}|${emailOf(req)}` });
const registerLimit = rateLimit({ minutes: 60, max: 50, key: (req) => req.ip });
const emailLimit = rateLimit({ minutes: 15, max: 20, key: (req) => req.ip });

router.post('/register', registerLimit, async (req, res) => {
  const body = req.body || {};
  const fullName = cleanName(body.fullName);
  const email = cleanEmail(body.email);
  const phone = cleanPhone(body.phone);
  const password = cleanPassword(body.password);
  const language = body.language === 'en' ? 'en' : 'ar';

  if (!SIGNUP_ROLES.includes(body.role)) {
    throw new AppError(400, 'INVALID_INPUT', 'Role must be customer or driver', { field: 'role' });
  }
  if (body.acceptPolicies !== true) {
    throw new AppError(400, 'POLICIES_NOT_ACCEPTED', 'You must accept the terms and privacy policy');
  }

  const passwordHash = await bcrypt.hash(password, 10);

  const userId = await withTransaction(null, async (client) => {
    const { rows: [user] } = await client.query(
      `INSERT INTO users (full_name, email, phone, password_hash, preferred_language)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id`,
      [fullName, email, phone, passwordHash, language],
    );
    await client.query(
      `INSERT INTO policy_acceptances (user_id, policy_version_id)
       SELECT $1, v.id
       FROM (SELECT latest_policy_version(t) AS id FROM unnest(ARRAY['terms', 'privacy']) AS t) v
       WHERE v.id IS NOT NULL`,
      [user.id],
    );
    await client.query(
      'INSERT INTO user_roles (user_id, role_id) SELECT $1, id FROM roles WHERE code = $2',
      [user.id, body.role],
    );
    await issueCode(client, email, 'verify_email', language);
    return user.id;
  });

  res.status(201).json({
    message: 'Account created, check your email for the code',
    user: await loadProfile(userId),
  });
});

router.post('/verify-email', async (req, res) => {
  const body = req.body || {};
  const email = cleanEmail(body.email);
  const code = cleanCode(body.code);

  const result = await withTransaction(null, async (client) => {
    const problem = await checkCode(client, email, 'verify_email', code);
    if (problem) {
      return { problem };
    }
    const { rows: [user] } = await client.query(
      `UPDATE users SET email_verified_at = now()
       WHERE email = $1 AND account_status = 'active'
       RETURNING id`,
      [email],
    );
    if (!user) {
      return { problem: 'CODE_EXPIRED' };
    }
    const tokens = await createSession(client, user.id, req.get('user-agent'));
    return { userId: user.id, tokens };
  });

  if (result.problem) {
    throw codeError(result.problem);
  }
  res.json({ ...result.tokens, user: await loadProfile(result.userId) });
});

router.post('/resend-code', emailLimit, async (req, res) => {
  const email = cleanEmail((req.body || {}).email);

  const { rows: [user] } = await query(
    `SELECT preferred_language, email_verified_at IS NOT NULL AS verified
     FROM users WHERE email = $1 AND account_status = 'active'`,
    [email],
  );
  if (!user) {
    throw new AppError(404, 'ACCOUNT_NOT_FOUND', 'No account with this email');
  }
  if (user.verified) {
    throw new AppError(409, 'ALREADY_VERIFIED', 'This email is already verified');
  }

  await withTransaction(null, (client) => issueCode(client, email, 'verify_email', user.preferred_language));
  res.json({ message: 'A new code was sent' });
});

router.post('/login', loginLimit, async (req, res) => {
  const body = req.body || {};
  const email = cleanEmail(body.email);
  const password = typeof body.password === 'string' ? body.password : '';

  const { rows: [user] } = await query(
    `SELECT id, password_hash, account_status, email_verified_at IS NOT NULL AS verified
     FROM users WHERE email = $1`,
    [email],
  );

  const correct = user && user.password_hash && await bcrypt.compare(password, user.password_hash);
  if (!correct) {
    throw new AppError(401, 'WRONG_EMAIL_OR_PASSWORD', 'Email or password is not correct');
  }
  if (user.account_status !== 'active') {
    throw new AppError(403, 'ACCOUNT_SUSPENDED', 'This account is suspended');
  }
  if (!user.verified) {
    throw new AppError(403, 'EMAIL_NOT_VERIFIED', 'Verify your email first');
  }

  const tokens = await withTransaction(null, (client) => (
    createSession(client, user.id, req.get('user-agent'))
  ));
  res.json({ ...tokens, user: await loadProfile(user.id) });
});

router.post('/refresh', async (req, res) => {
  const refreshToken = cleanToken((req.body || {}).refreshToken);

  const tokens = await withTransaction(null, async (client) => {
    const { rows: [session] } = await client.query(
      `UPDATE auth_sessions s SET revoked_at = now()
       FROM users u
       WHERE s.refresh_token_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > now()
         AND u.id = s.user_id AND u.account_status = 'active'
       RETURNING s.user_id`,
      [hashToken(refreshToken)],
    );
    if (!session) {
      return null;
    }
    return createSession(client, session.user_id, req.get('user-agent'));
  });

  if (!tokens) {
    throw new AppError(401, 'SESSION_ENDED', 'Your session ended, log in again');
  }
  res.json(tokens);
});

router.post('/logout', async (req, res) => {
  const refreshToken = cleanToken((req.body || {}).refreshToken);
  await query(
    'UPDATE auth_sessions SET revoked_at = now() WHERE refresh_token_hash = $1 AND revoked_at IS NULL',
    [hashToken(refreshToken)],
  );
  res.status(204).end();
});

router.post('/forgot-password', emailLimit, async (req, res) => {
  const email = cleanEmail((req.body || {}).email);

  const { rows: [user] } = await query(
    "SELECT preferred_language FROM users WHERE email = $1 AND account_status = 'active'",
    [email],
  );
  if (user) {
    await withTransaction(null, (client) => issueCode(client, email, 'reset_password', user.preferred_language));
  }
  res.json({ message: 'If this email has an account, a code was sent' });
});

router.post('/reset-password', async (req, res) => {
  const body = req.body || {};
  const email = cleanEmail(body.email);
  const code = cleanCode(body.code);
  const password = cleanPassword(body.newPassword, 'newPassword');
  const passwordHash = await bcrypt.hash(password, 10);

  const problem = await withTransaction(null, async (client) => {
    const codeProblem = await checkCode(client, email, 'reset_password', code);
    if (codeProblem) {
      return codeProblem;
    }
    const { rows: [user] } = await client.query(
      `UPDATE users SET password_hash = $2, email_verified_at = COALESCE(email_verified_at, now())
       WHERE email = $1 AND account_status = 'active'
       RETURNING id`,
      [email, passwordHash],
    );
    if (!user) {
      return 'CODE_EXPIRED';
    }
    await client.query(
      'UPDATE auth_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
      [user.id],
    );
    return null;
  });

  if (problem) {
    throw codeError(problem);
  }
  res.json({ message: 'Password changed, log in with the new password' });
});

export default router;
