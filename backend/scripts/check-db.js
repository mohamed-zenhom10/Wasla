import { pool, withTransaction, checkRuntimeRole } from '../src/db.js';

const yesNo = (value) => (value ? 'yes' : 'no');
let failed = false;

function check(label, value, ok) {
  console.log(`${ok ? 'OK  ' : 'FAIL'}  ${label.padEnd(28)} ${value}`);
  if (!ok) failed = true;
}

try {
  const role = await checkRuntimeRole();

  const { rows: [info] } = await pool.query(`
    SELECT current_database() AS database,
           (SELECT extversion FROM pg_extension WHERE extname = 'postgis') AS postgis,
           (SELECT count(*)::int FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
              AND table_name <> 'spatial_ref_sys') AS tables,
           has_table_privilege('admin_audit_log', 'INSERT') AS audit_insert,
           has_table_privilege('wallet_transactions', 'UPDATE') AS wallet_update
  `);

  const inside = await withTransaction({ id: 1, role: 'admin' }, async (client) => {
    const { rows } = await client.query(
      'SELECT app_actor_id() AS id, app_actor_role() AS role, pg_backend_pid() AS pid',
    );
    return rows[0];
  });
  const { rows: [after] } = await pool.query(
    'SELECT app_actor_id() AS id, app_actor_role() AS role, pg_backend_pid() AS pid',
  );

  check('database', info.database, true);
  check('login user', role.user_name, true);
  check('superuser', yesNo(role.is_superuser), !role.is_superuser);
  check('owns tables', yesNo(role.owns_tables), !role.owns_tables);
  check('member of wasla_runtime', yesNo(role.is_runtime), role.is_runtime);
  check('postgis', info.postgis || 'missing', Boolean(info.postgis));
  check('tables', info.tables, info.tables === 61);
  check('insert into admin_audit_log', yesNo(info.audit_insert), !info.audit_insert);
  check('update wallet_transactions', yesNo(info.wallet_update), !info.wallet_update);
  check('actor inside transaction', `${inside.id} / ${inside.role}`, inside.id === '1' && inside.role === 'admin');
  check('actor after commit', `${after.id ?? 'none'} / ${after.role}`, after.id === null && after.role === 'system');
  check('same connection', `${inside.pid} = ${after.pid}`, true);

  console.log(failed ? '\nSome checks failed' : '\nAll checks passed');
} catch (err) {
  failed = true;
  console.error(`Cannot check database: ${err.message || err.code}`);
} finally {
  await pool.end();
}

process.exitCode = failed ? 1 : 0;
