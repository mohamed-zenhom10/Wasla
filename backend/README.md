# Wasla API

Backend for Wasla, built with Node.js, Express and PostgreSQL. The database files are in `database/` and the endpoints are in `API.md`.

## Requirements

- Node.js 22 or newer
- PostgreSQL with PostGIS
- The `wasls` database built from `database/schema/wasla_schema.sql` and `database/security/runtime_role.sql`

## Setup

The API does not connect as `postgres`. Create a login for it once (as `postgres`, inside `wasls`):

```sql
CREATE ROLE wasla_app LOGIN PASSWORD 'your_password';
GRANT wasla_runtime TO wasla_app;
```

Then copy `.env.example` to `.env` and fill it:

- `DB_PASSWORD`: the same password
- `JWT_SECRET`: any random text, at least 32 characters
- `NATIONAL_ID_KEY`: another random text, at least 32 characters. Do not change it after drivers sign up, or the same national ID could be registered twice.
- `CLOUDINARY_URL`: the "API environment variable" from the Cloudinary dashboard. Driver photos are saved there. If it is empty, photos are saved in the `uploads` folder (only for running on your computer).
- `SMTP_*` and `MAIL_FROM`: the email account that sends the codes. If `SMTP_HOST` is empty, codes are printed in the terminal instead.
- `BREVO_API_KEY`: sends the codes with Brevo instead of SMTP (Render's free plan blocks SMTP). `MAIL_FROM` must be a sender verified on Brevo.
- `DB_SSL=true` for a hosted database like Neon, and `TRUST_PROXY=true` when the API runs behind a host like Render.
- `CLIENT_IP_HEADER=cf-connecting-ip` on Render, so the login and signup limits see the real address of each device.

Then run:

```
npm install
npm run check:db
npm run dev
```

The API runs on http://localhost:3000 and http://localhost:3000/api/health should return `{"status":"ok","database":"up"}`.

For an existing database, apply each unapplied SQL file in `database/updates/` in filename order before deploying code that uses it. If update `003_dispatch_radius.sql` has not already been applied, run it before `004_test_dispatch_mode.sql`:

```powershell
# Run this only if update 003 has not already been applied.
psql -d wasls -f database\updates\003_dispatch_radius.sql
# Apply after all earlier updates.
psql -d wasls -f database\updates\004_test_dispatch_mode.sql
```

Dispatch starts within 5 km and widens in 5 km steps to 30 km. It waits for pending 30-second driver offers, then waits 3 seconds after rejection or expiry before widening.

For an isolated test deployment only, set `DISPATCH_TEST_MODE=true` in the
backend environment and restart the API. Test offers ignore pickup distance,
vehicle type, payload, helper-capacity, and pickup-distance matching. Drivers
must still be approved and available, with an active vehicle, fresh location,
and no conflicting trip. The database migration `004_test_dispatch_mode.sql`
must be applied for test-mode offers to be accepted and started. Offers include
a test-mode marker that is shown in the Driver app.
Set the value back to `false` before handling real orders; do not enable this
on a backend serving production customers or drivers.

To check that photos can be saved:

```
npm run check:storage
```

To create an admin account:

```
npm run create-admin
```
