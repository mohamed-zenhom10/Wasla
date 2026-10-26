import crypto from 'node:crypto';
import { AppError } from '../errors.js';
import { sendCode } from './mailer.js';

const CODE_MINUTES = 10;
const RESEND_SECONDS = 60;
const MAX_ATTEMPTS = 5;

const CODE_ERRORS = {
  CODE_EXPIRED: [400, 'CODE_EXPIRED', 'The code is expired or was already used, ask for a new one'],
  WRONG_CODE: [400, 'WRONG_CODE', 'The code is not correct'],
  TOO_MANY_ATTEMPTS: [429, 'TOO_MANY_ATTEMPTS', 'Too many wrong tries, ask for a new code'],
};

function hashCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

export async function issueCode(client, email, purpose, language) {
  const { rows: [last] } = await client.query(
    `SELECT floor(extract(epoch FROM now() - created_at))::int AS age
     FROM otp_codes WHERE email = $1 AND purpose = $2
     ORDER BY created_at DESC LIMIT 1`,
    [email, purpose],
  );
  if (last && last.age < RESEND_SECONDS) {
    throw new AppError(429, 'CODE_RECENTLY_SENT', 'Wait a little before asking for a new code', {
      retryAfter: RESEND_SECONDS - last.age,
    });
  }

  const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
  await client.query(
    `INSERT INTO otp_codes (email, code_hash, purpose, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(mins => $4))`,
    [email, hashCode(code), purpose, CODE_MINUTES],
  );
  await sendCode(email, purpose, code, language);
}

export async function checkCode(client, email, purpose, code) {
  const { rows: [otp] } = await client.query(
    `SELECT id, code_hash, attempts, consumed_at IS NOT NULL AS used, expires_at < now() AS expired
     FROM otp_codes WHERE email = $1 AND purpose = $2
     ORDER BY created_at DESC LIMIT 1
     FOR UPDATE`,
    [email, purpose],
  );

  if (!otp || otp.used || otp.expired) {
    return 'CODE_EXPIRED';
  }
  if (otp.attempts >= MAX_ATTEMPTS) {
    return 'TOO_MANY_ATTEMPTS';
  }
  if (!crypto.timingSafeEqual(Buffer.from(hashCode(code)), Buffer.from(otp.code_hash))) {
    await client.query('UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1', [otp.id]);
    return 'WRONG_CODE';
  }

  await client.query('UPDATE otp_codes SET consumed_at = now() WHERE id = $1', [otp.id]);
  return null;
}

export function codeError(problem) {
  return new AppError(...CODE_ERRORS[problem]);
}
