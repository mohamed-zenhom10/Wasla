# Wasla API

Backend for Wasla, built with Node.js, Express and PostgreSQL. The database files are in `database/`.

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

Then copy `.env.example` to `.env`, put the same password in `DB_PASSWORD`, and run:

```
npm install
npm run check:db
npm run dev
```

The API runs on http://localhost:3000 and http://localhost:3000/api/health should return `{"status":"ok","database":"up"}`.
