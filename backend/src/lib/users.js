import { query } from '../db.js';

export async function loadProfile(userId) {
  const { rows: [user] } = await query(
    `SELECT u.id, u.full_name, u.email, u.phone, u.preferred_language,
            u.email_verified_at IS NOT NULL AS email_verified,
            ARRAY(SELECT r.code FROM user_roles ur JOIN roles r ON r.id = ur.role_id
                  WHERE ur.user_id = u.id ORDER BY r.code) AS roles,
            NOT accepted_latest_policies(u.id) AND EXISTS (
              SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id
              WHERE ur.user_id = u.id AND r.code IN ('customer', 'driver')
            ) AS needs_policy_acceptance
     FROM users u
     WHERE u.id = $1`,
    [userId],
  );

  return {
    id: user.id,
    fullName: user.full_name,
    email: user.email,
    phone: user.phone,
    language: user.preferred_language,
    emailVerified: user.email_verified,
    roles: user.roles,
    needsPolicyAcceptance: user.needs_policy_acceptance,
  };
}
