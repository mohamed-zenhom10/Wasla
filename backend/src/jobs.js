import { withTransaction } from './db.js';

const EVERY_MS = 30000;

async function closeSilentDrivers(client) {
  await client.query(
    `UPDATE driver_profiles dp SET is_online = false
     WHERE dp.is_online
       AND dp.location_updated_at < now() - make_interval(
             secs => (SELECT auto_offline_after_seconds FROM platform_settings WHERE id = 1))
       AND NOT EXISTS (
         SELECT 1 FROM trips t WHERE t.driver_id = dp.user_id AND t.status IN (
           'heading_to_pickup', 'arrived_at_pickup', 'loaded', 'heading_to_dropoff', 'arrived_at_dropoff'))`,
  );
}

const JOBS = [closeSilentDrivers];

async function runJobs() {
  for (const job of JOBS) {
    try {
      await withTransaction(null, job);
    } catch (err) {
      console.error(`Job ${job.name} failed: ${err.message}`);
    }
  }
}

export function startJobs() {
  let running = false;
  const timer = setInterval(async () => {
    if (running) {
      return;
    }
    running = true;
    try {
      await runJobs();
    } finally {
      running = false;
    }
  }, EVERY_MS);
  return () => clearInterval(timer);
}
