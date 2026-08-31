# Broker Wallet Supabase local development

This directory contains the Stage 1 local PostgreSQL baseline. It is intentionally isolated from the current Flutter/Firebase runtime.

## Safety rule

Do **not** run `supabase db push` yet. Stage 1 must pass locally first.

## First local verification

Prerequisites:

- Docker Desktop installed and running.
- Node.js/npm available.

From the repository root:

```bash
npx supabase start
npx supabase db reset
npx supabase test db
```

If `npx supabase` is not available from this project yet, install the CLI as a development dependency first:

```bash
npm install --save-dev supabase
```

Then rerun the three commands above.

## What the commands do

- `supabase start`: starts the disposable local Supabase stack in Docker.
- `supabase db reset`: recreates the local database from `migrations/` and then runs `seed.sql`.
- `supabase test db`: runs the pgTAP SQL tests in `tests/`.

None of those commands should modify the hosted Supabase project.

## Stage 1 files

- `migrations/20260821000100_broker_wallet_baseline.sql`: baseline tables, constraints, triggers, indexes, RLS policies, and grants.
- `seed.sql`: intentionally contains no production product/quota/user data.
- `tests/schema_test.sql`: static schema/security contract checks.
- `tests/rls_test.sql`: runtime ownership, permission, trigger, and constraint checks.
