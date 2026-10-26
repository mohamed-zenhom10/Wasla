import crypto from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import config from '../config.js';

const secret = new TextEncoder().encode(config.jwtSecret);
const ACCESS_MINUTES = 15;
const REFRESH_DAYS = 30;

export function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export async function createSession(client, userId, userAgent) {
  const refreshToken = crypto.randomBytes(32).toString('base64url');
  const { rows: [session] } = await client.query(
    `INSERT INTO auth_sessions (user_id, refresh_token_hash, user_agent, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(days => $4))
     RETURNING id`,
    [userId, hashToken(refreshToken), userAgent ? userAgent.slice(0, 300) : null, REFRESH_DAYS],
  );

  const accessToken = await new SignJWT({ sid: session.id })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(String(userId))
    .setIssuedAt()
    .setExpirationTime(`${ACCESS_MINUTES}m`)
    .sign(secret);

  return { accessToken, refreshToken, expiresIn: ACCESS_MINUTES * 60 };
}

export async function readAccessToken(token) {
  const { payload } = await jwtVerify(token, secret, { algorithms: ['HS256'] });
  return { userId: payload.sub, sessionId: payload.sid };
}
