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

To create an admin account:

```
npm run create-admin
```
