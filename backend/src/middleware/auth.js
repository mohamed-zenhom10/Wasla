import { query } from '../db.js';
import { AppError } from '../errors.js';
import { readAccessToken } from '../lib/tokens.js';

export async function requireAuth(req, res, next) {
  const [type, token] = (req.get('authorization') || '').split(' ');
  if (type !== 'Bearer' || !token) {
    throw new AppError(401, 'NOT_LOGGED_IN', 'You need to log in first');
  }

  let claims;
  try {
    claims = await readAccessToken(token);
  } catch (err) {
    if (err.code === 'ERR_JWT_EXPIRED') {
      throw new AppError(401, 'TOKEN_EXPIRED', 'Access token expired, refresh it');
    }
    throw new AppError(401, 'INVALID_TOKEN', 'Access token is not valid');
  }

  const { rows: [user] } = await query(
    `SELECT u.id, u.account_status,
            ARRAY(SELECT r.code FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                  WHERE ur.user_id = u.id) AS roles
     FROM auth_sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.id = $1 AND s.user_id = $2 AND s.revoked_at IS NULL AND s.expires_at > now()`,
    [claims.sessionId, claims.userId],
  );

  if (!user) {
    throw new AppError(401, 'SESSION_ENDED', 'Your session ended, log in again');
  }
  if (user.account_status !== 'active') {
    throw new AppError(403, 'ACCOUNT_SUSPENDED', 'This account is suspended');
  }

  req.user = { id: user.id, roles: user.roles, sessionId: claims.sessionId };
  next();
}

export function requireRole(role) {
  return (req, res, next) => {
    if (!req.user.roles.includes(role)) {
      throw new AppError(403, 'ROLE_REQUIRED', `This needs a ${role} account`);
    }
    next();
  };
}
