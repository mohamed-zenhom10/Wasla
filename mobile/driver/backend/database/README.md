# Database

PostgreSQL 18 + PostGIS database for Wasla.

## Files

- `schema/wasla_schema.sql` - tables, constraints, triggers and seed data
- `security/runtime_role.sql` - restricted role for the backend (`wasla_runtime`)
- `tests/run_all_tests_postgis.sql` - builds the database and runs all tests
- `docs/wasla_erd.pdf` - ERD

## Setup

```sql
CREATE DATABASE wasls;
\c wasls
\i schema/wasla_schema.sql
\i security/runtime_role.sql
```

The backend should connect with a user that has the `wasla_runtime` role, not `postgres`.

## Tests

Run on a new empty database named `wasla_unified_test`:

```sql
CREATE DATABASE wasla_unified_test;
\c wasla_unified_test
\i tests/run_all_tests_postgis.sql
```

All tests should pass, and the last line should be `UNIFIED_FUNCTIONAL_COMPLETE`.

Seed values (prices, commission, fees) are placeholders for now.
