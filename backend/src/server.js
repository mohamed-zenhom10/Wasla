import app from './app.js';
import config from './config.js';
import { pool, checkRuntimeRole } from './db.js';

try {
  await checkRuntimeRole();
} catch (err) {
  console.error(`Cannot start: ${err.message || err.code}`);
  await pool.end();
  process.exit(1);
}

const server = app.listen(config.port, () => {
  console.log(`Wasla API running on http://localhost:${config.port}`);
});

function shutdown() {
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
