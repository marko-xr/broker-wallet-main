# Quotation private media staging acceptance

An end-to-end check of the Quotation private-media routes
(`/quotation-media/authorize|confirm|remove` and `GET /quotation-media`) on the
**staging** Worker (`r2-profile-upload-staging`, private bucket
`broker-wallet-media-staging`) against hosted Supabase, plus a regression pass
over the Offer, Owner and profile routes the Worker also serves. Run by the
owner in the owner's own terminal. It refuses any URL that is not
`https://r2-profile-upload-staging.<subdomain>.workers.dev`, so it can never
reach the production Worker or bucket.

Node built-ins only; no `npm install`. Not part of `npm test`.

## Accounts

| | Who | Used for |
| --- | --- | --- |
| A | the designated test-only account (uid `317d7619-01da-4420-8c7f-fe7c3fc2d6e7`, from `BW_TEST_*`) | owns every Quotation under test |
| B | a **temporary** second account you create for this run | the cross-user checks only |

The runner refuses to write anything unless A's signed-in uid equals the
designated uid, and unless B is a different account. Only then does it claim
each account's active app session (next section).

## Single Active Device (session claim)

Since migration `20261005175500` the database (and the Worker once it carries
the gate) refuses every session that is not the account's one **active**
Broker Wallet session, and a password sign-in creates a new, unclaimed one. So
after the identity checks the runner **claims** A's and B's sessions through the
same RPC the app uses (`claim_current_app_session`, in `app_session_claim.mjs`)
and has the database confirm each (`is_current_app_session`) before it writes
anything. It never chooses a session id and never sends a secret key.

**Claiming ends every other session of that account.** If account A is signed in
on a phone or emulator, that device is signed out. The launcher therefore asks
you to type `CLAIM` first, and the runner refuses to run without that
acknowledgement. Never point it at a real or production user.

### Creating account B (you do this; nothing is pasted into chat)

1. Supabase dashboard → project `broker-wallet` → **Authentication → Users →
   Add user → Create new user**. Use a clearly test-only address such as
   `broker-wallet-e2e-b-<yyyymmdd>@example.test`, a strong random password, and
   tick **Auto Confirm User**. The existing trigger on `auth.users` creates the
   profile row.
2. Note the new user's UUID (optional; it makes the runner check it).
3. Either put the values in your User environment (`BW_TEST_B_EMAIL`,
   `BW_TEST_B_PASSWORD`, `BW_TEST_B_USER_ID`) or just type them into the
   launcher's masked prompts.

Delete account B when the run and the cleanup are done (dashboard →
Authentication → Users → delete). Never reuse it.

## Run

From the repository root, in PowerShell 7:

```powershell
./cloudflare/workers/r2-profile-upload/staging-acceptance/run_quotation_media_staging_acceptance.ps1
```

The launcher first asks you to type `CLAIM` (see above). It uses the staging URL
of this repo's staging Worker by default and reads `BW_E2E_STAGING_KEY` (the gate
key), `BW_TEST_EMAIL`/`BW_TEST_PASSWORD`/`BW_TEST_USER_ID` (A) and `BW_TEST_B_*`
(B) from your environment, asking with masked input for anything missing. It
clears its copies when the run ends.

Exit codes: 0 all passed, 1 at least one failure, 2 configuration error.

## What it checks

| Section | Checks |
| --- | --- |
| gate / unauthenticated / invalid-auth | no key and wrong key: 403 on every Quotation route; key without a session: 401; invalid token: 401 |
| setup | creates three temporary Quotations through `save_quotation` (A twice, B once) and reads them back |
| logo-refuse | role name `logo` rejected, `expectedMediaId` required, non-image MIME, > 10 MiB, zero bytes |
| logo | JPEG → PNG → WebP → JPEG: authorize, exact private key, signed short-lived PUT to the private staging bucket, pending row, early confirm refused, confirm, hosted read-back (slot, version, media row, link), signed GET exact bytes, no stored URL, idempotent confirm/authorize, replacement retires the previous media and its bytes, two racing replacements (stale refused, slot unchanged), stale remove refused, stale pending cancelled |
| pdf | non-PDF types and > 20 MiB refused, upload/confirm/read-back/GET, logo untouched, JPEG bytes declared as PDF refused (422), regeneration retires the first, stale regeneration, stale remove |
| role-parent | logo cannot bind as PDF and the reverse, a media id cannot cross to another Quotation (confirm, remove, authorize) |
| deleted | a soft-deleted Quotation refuses authorize, confirm, list and remove |
| direct-write | clients cannot write `office_logo_media_id`, `pdf_media_id`, `version`, delete a Quotation, insert into `quotation_media` or `media_objects`, call the confirm/remove RPCs, or smuggle media ids through `save_quotation` |
| cross-user | B cannot list/authorize/confirm/remove against A's Quotation, cannot reuse A's media ids, cannot bind B's media to A's Quotation, cannot read A's rows (RLS) or call `save_quotation` on it; A's state is byte-identical afterwards; B's own flow works (positive control) |
| regression | Offer and Owner: authorize/PUT/confirm/list/GET/remove unchanged, each under its own prefix; Quotation ids and media never collide with Offer/Owner routes; profile lookup/refusals unchanged (read-only) |
| removal | logo then PDF removal, read-back, bytes gone, idempotent re-remove |
| session-gate | last; Single Active Device on account B's sessions only. **D)** no session and an invalid token: 401 on all 24 gated routes (the 15 profile/media routes, the 8 Offer/Owner land-plan routes `/offer-plan…` and `/owner-plan…`, and `/account/delete`). **A)** the claimed session is accepted and the database confirms it. **C)** a second sign-in that never claims is not current in the database and is refused on all 24 routes (403 `session_superseded`), and displaces nothing. **B)** a third sign-in that claims is accepted while the session it replaced is refused on all 24, no longer current, and cannot reclaim (its claim is refused `session_superseded`); the active claimant may repeat its claim. Random ids match no record, and `/account/delete` is sent with no password, so nothing can be written or deleted |

Run against a staging Worker that does **not yet** carry the active-session gate,
`session-gate` is expected to FAIL (and only its Worker-refusal checks: the
never-claimed and superseded sessions are still accepted); after the gate
candidate is deployed to staging it must PASS.

Output and the JSON report (`reports/`, gitignored) hold PASS/FAIL, HTTP
statuses, Worker codes and record/media ids (including A's and B's uids). Never a
token, key, password, email, object key or URL.

## What it leaves behind

Sweeps are off, so it removes nothing automatically beyond what the routes do.
The report's `created` section lists every Quotation (including one
soft-deleted), Offer, Owner and media id it made, for a narrow cleanup of exactly
those ids. `deleted`-section leaves one never-uploaded pending row.

## Offline self-test

`node quotation_media_offline_selftest.mjs` runs the real `worker.js` and this
runner (and the production smoke) against in-memory fakes (no network) and
injects faults to prove the checks fail when they should. The fake models the
hosted active-session authority (a fresh session claims once, a displaced one
cannot reclaim, an unclaimed session sees no rows), so a runner that forgot to
claim fails there, and three faults (a gate that accepts a never-claimed session,
supersession ignored, a displaced session that can reclaim) must be detected by
`session-gate`. It proves nothing about hosted Supabase or R2.
