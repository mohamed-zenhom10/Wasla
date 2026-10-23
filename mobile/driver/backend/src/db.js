import pg from 'pg';
import config from './config.js';

const ACTOR_ROLES = ['customer', 'driver', 'admin'];

export const pool = new pg.Pool({
  ...config.db,
  max: 10,
  application_name: 'wasla-api',
});

pool.on('error', (err) => {
  console.error('Unexpected database error:', err.message);
});

export function query(text, params) {
  return pool.query(text, params);
}

export async function withTransaction(actor, work) {
  if (actor && (!actor.id || !ACTOR_ROLES.includes(actor.role))) {
    throw new Error('Invalid actor');
  }

  const client = await pool.connect();
  let broken = false;

  try {
    await client.query('BEGIN');
    if (actor) {
      await client.query(
        `SELECT set_config('app.actor_id', $1, true),
                set_config('app.actor_role', $2, true),
                set_config('app.change_reason', $3, true)`,
        [String(actor.id), actor.role, actor.reason || ''],
      );
    }
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {
      broken = true;
    }
    throw err;
  } finally {
    client.release(broken);
  }
}

export async function checkRuntimeRole() {
  const { rows } = await pool.query(`
    SELECT current_user AS user_name,
           r.rolsuper AS is_superuser,
           pg_has_role(current_user, 'wasla_runtime', 'MEMBER') AS is_runtime,
           COALESCE((SELECT tableowner = current_user FROM pg_tables
                     WHERE schemaname = 'public' AND tablename = 'users'), false) AS owns_tables
    FROM pg_roles r
    WHERE r.rolname = current_user
  `);
  const role = rows[0];

  if (role.is_superuser) {
    throw new Error(`${role.user_name} is a superuser, use the API login instead`);
  }
  if (role.owns_tables) {
    throw new Error(`${role.user_name} owns the database tables, use the API login instead`);
  }
  if (!role.is_runtime) {
    throw new Error(`${role.user_name} is not a member of wasla_runtime`);
  }
  return role;
}
