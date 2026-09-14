# Staging Worker first-time bootstrap

Prepared only. Nothing here has been run. Run from
`cloudflare/workers/r2-profile-upload`, as the owner, after reading each step.

Why a placeholder: the real staging config lists four required secrets, and
Wrangler validates them before `wrangler deploy --env staging`. Secrets can only
be stored on an existing Worker, and `wrangler secret put` deploys a new version
immediately. So the name is first claimed by a Worker that can do nothing.

1. `npm test` must pass.
2. Deploy the placeholder:
   `wrangler deploy --config staging-bootstrap/wrangler.toml`.
   It has no bindings, triggers, route or workers.dev URL, and returns 404 for
   everything. Confirm it in the dashboard.
3. Create the staging-only credentials outside the repo:
   - a new Supabase secret key named for staging, revocable on its own;
   - an R2 API token scoped to `broker-wallet-media-staging` only;
   - a long random `STAGING_TEST_KEY`.
4. Store them on the placeholder, each prompted interactively and never passed
   on the command line (each `put` redeploys the placeholder, which is
   harmless):
   `wrangler secret put SUPABASE_SECRET_KEY --name r2-profile-upload-staging`
   `wrangler secret put R2_ACCESS_KEY_ID --name r2-profile-upload-staging`
   `wrangler secret put R2_SECRET_ACCESS_KEY --name r2-profile-upload-staging`
   `wrangler secret put STAGING_TEST_KEY --name r2-profile-upload-staging`
   Then `wrangler secret list --name r2-profile-upload-staging` must list
   exactly those four names.
5. Create the bucket: `wrangler r2 bucket create broker-wallet-media-staging`.
6. Deploy the real code: `wrangler deploy --env staging`. This replaces the
   placeholder on the same Worker, keeps its secrets, adds the bucket binding,
   the `*/5` cron and the workers.dev URL. Confirm there is no route and no
   custom domain.
7. Check the gate before anything else: a request without
   `X-Broker-Wallet-Staging-Key`, and one with a wrong value, must both return
   403 `{"error":"Forbidden"}`.

Alternatives such as a secrets file passed to `deploy` or `versions upload`, or
`wrangler versions secret put`, depend on the installed Wrangler version.
Confirm them in that version's `--help` before relying on them. The placeholder
path above needs neither.

Retention: the staging Worker, its bucket and its staging-only secrets may be
kept after the staging test, and currently ARE retained, until the production
Delete Account real-device acceptance has succeeded. Cleanup is a separate, later
step, not part of the staging test.

Cleanup, once production acceptance has succeeded: `wrangler delete --env staging`; confirm no
`account_deletion_jobs` row has `bucket = 'broker-wallet-media-staging'`; empty
and delete the bucket; revoke the staging Supabase secret key, the staging R2
token and the `STAGING_TEST_KEY` value; confirm no disposable test users remain.
