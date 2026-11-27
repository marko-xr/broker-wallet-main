# Subscription system: production runbook

Status on 2026-11-26: source complete for the backend, Google Play (app and server), Tap (server and web) and UAE VAT
documents. Verified locally on PostgreSQL and in a local browser with **fake** providers. Nothing here has run on a
hosted environment, no real payment has been made, and no step runs without the owner's approval of that step.

Architecture: Supabase is the only authority for entitlements and quotas. **Tap Payments** bills cards on the web.
**Google Play Billing** (direct, `in_app_purchase_android` 0.5.5, Play Billing Library 9.1.0) bills Android. RevenueCat,
Stripe and Ziina are not part of the system. The baseline `revenuecat_*` tables stay in the historical migration, unused.

## 1. Hosted read-only preflight (2026-11-26, SELECT only)

| Item | Finding |
|---|---|
| Database | PostgreSQL 17.6, project `rbvcnvqpdqrhywcgxkne` |
| Migrations applied | Up to `20261121090000`. **Not applied:** the three phone-auth migrations `20261122*` and the three subscription migrations |
| Subscription objects | None exist on production yet |
| Accounts | 5 auth users, 5 profiles, 0 profiles with a verified phone |
| `plan_limits`, `usage_counters`, `app_versions` | All empty: no Free limits, no counters, no minimum-version record |
| Client writes today | Column-level INSERT/UPDATE grants on the six record tables, plus RLS (all public tables have RLS) |
| Scheduled jobs | `pg_cron` and `pg_net` installed; three notification jobs active |
| **Backups** | `supabase backups list`: **no backup listed, PITR off.** Take and verify a manual dump before any migration |
| Over the Free limit (`actual` baseline) | offers 2 accounts (max 15), owners 1 (9), quotations 1 (16), scanner 1 (8), signature 1 (6) |

The CLI's temporary login role is the one hosted side effect of these reads.

**Dependency:** the subscription migrations do not use any object from the phone-auth migrations, but `supabase db push`
applies pending files in order. Either apply the phone-auth migrations first (their own approval), or apply the
subscription files from a scratch project and later reconcile history with `--include-all`.

## 2. Configuration matrix

Public values may sit in a client build. Secrets live only in Supabase function secrets or Worker secrets.

| Name | Where | Kind | Value or source |
|---|---|---|---|
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Flutter (all platforms) | Public | Per environment |
| `SUBSCRIPTION_BACKEND=true` | Flutter | Public | Every store build after cutover |
| `BW_DEPLOYMENT_ENV` | Flutter, test-control function | Public | `production` / `staging` |
| `BW_PUBLIC_RELEASE=true` | Flutter | Public | Store and production web builds only |
| `GOOGLE_PLAY_PRODUCT_ID` | Flutter + functions | Public | `broker_wallet_plus` (app default) |
| `GOOGLE_PLAY_MONTHLY_BASE_PLAN` / `_ANNUAL_BASE_PLAN` | Flutter | Public | `monthly` / `annual` (app defaults) |
| `GOOGLE_PLAY_BASE_PLANS` | Functions | Config | `{"monthly":"monthly","annual":"annual"}` |
| `GOOGLE_PLAY_PACKAGE_NAME` | Functions (+ Flutter link) | Public | `com.nmodigital.brokerwallet` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Functions | **Secret** | Service-account key JSON |
| `GOOGLE_PLAY_PUSH_AUDIENCE` | Functions | Config | Audience set on the push subscription |
| `GOOGLE_PLAY_PUSH_SERVICE_ACCOUNT` | Functions | Config | Email of the push service account |
| `BILLING_TOKEN_KEY` | Functions | **Secret** | Base64 of 32 random bytes. Losing it loses Play reconciliation |
| `TAP_SECRET_KEY` | Functions | **Secret** | `sk_test_…` on Staging, `sk_live_…` on Production only |
| `TAP_PUBLIC_KEY` | Functions (served to the browser) | Public | Must match the mode |
| `TAP_MERCHANT_ID` | Functions | Config | From Tap dashboard |
| `TAP_LIVE_MODE` | Functions | Config | `true` on Production only |
| `TAP_BILLING_ENABLED` / `TAP_RENEWALS_ENABLED` | Functions | Switch | Off until each is proven. Renewals charge saved cards |
| `TAP_RETURN_URL` | Functions | Config | `https://app.brokerwallet.ae/subscription-return` |
| `BILLING_ALLOWED_ORIGINS` | Functions | Config | `https://app.brokerwallet.ae` |
| `SUBSCRIPTION_RECONCILE_SECRET` | Functions + scheduler | **Secret** | 32+ random bytes |
| `SUPABASE_SERVICE_ROLE_KEY` | Functions (injected by Supabase) | **Secret** | Never in a client |
| `SUBSCRIPTION_ENFORCEMENT` | Worker var | Switch | `on` at cutover |
| `GOOGLE_MAPS_WEB_API_KEY` | Flutter web build | Public | Browser key: HTTP-referrer restricted to `app.brokerwallet.ae`, Maps JavaScript API only |
| Supplier tax profile | Database row `billing_tax_profile` | Data | Legal name, 15-digit TRN, address. Set by the owner as `postgres` |
| Android card choice | Database row `billing_channel_policy` | Data | Off. Turning it on needs a recorded basis |

## 3. Safe order

1. **Take and verify a backup** (no automatic backup exists today): `docs/PRODUCTION_DATABASE_BACKUP_RUNBOOK.md`.
2. Owner decisions: baseline (`actual` recommended), phone-auth migrations first or not. (Prices are decided: section 4.)
3. Apply `20261123100000`, `20261123120000`, `20261124100000`. They are additive: current app builds keep working.
4. Run `supabase/validation/subscription_production_verify.sql`.
5. Set the supplier tax profile row (TRN and address).
6. Deploy `subscription-webhooks` and `subscription-billing` with `--no-verify-jwt`. **Never** deploy
   `subscription-test-control` to Production.
7. Deploy the Worker with `SUBSCRIPTION_ENFORCEMENT` unset.
8. Release Android, web and iOS builds with `SUBSCRIPTION_BACKEND=true`. Record their minimum versions in `app_versions`.
9. In one window: set `SUBSCRIPTION_ENFORCEMENT=on` and run, as `postgres`:
   `select public.subscription_cutover('actual', 'ENFORCE');`
10. Run the verification script and section 9.
11. Schedule `POST /subscription-billing/reconcile` hourly (pg_cron + pg_net, with `x-reconcile-secret`).

A build without the backend flag fails its saves after step 9 with a permission error. It loses no data.

## 4. Baseline and prices

- `actual`: every surviving row counts. The accounts in section 1 become read-only in those sections at cutover.
- `capped`: counts stop at 5, so those accounts cannot add more there but are not read-only.
**Final prices (owner decision 2026-11-26; AED 199.20 and 17% are obsolete).** UAE VAT 5% is included.

| Plan | Charged | Net | VAT | Shown as |
|---|---|---|---|---|
| Plus Monthly | AED 20.00 once a month | AED 19.05 | AED 0.95 | AED 20.00 / month |
| Plus Yearly | AED 180.00 **once a year**, never in installments | AED 171.43 | AED 8.57 | AED 180.00 / year, AED 15.00 a month, save 25% |

Exact in integer fils: 12 × 2000 = 24000; (24000 − 18000) × 100 = 25 × 24000; 18000 / 12 = 1500 with no remainder.
VAT = round-half-up(total × 5 / 105): 2000 → 95, 18000 → 857.

The price is fixed in four places that must always change together: `public.tap_price()` and the `tap_orders_amount`
check (`20261123120000`), `SubscriptionPolicy` (Flutter display reference) and the Play Console base plans. The Edge
Function's `/tap/session` amount is display only; the charge amount always comes from `tap_price()`. A Google Play build
shows Google's own localized price when it has one.

**Changing a price later.** No paid subscription exists yet, so 180.00 replaces nothing. After launch a change is a new
migration, never an edit of an applied one. Tap renewals take `tap_price()` at renewal time, so a change reaches existing
card subscribers at their next renewal: give them notice first (or add a per-agreement price lock before changing it).
On Google Play use the console's price change flow: existing subscribers keep their price until Google's
notification/consent rules for a price increase are met.

## 5. Rollback

| Situation | Action | Data effect |
|---|---|---|
| Problem after cutover | `select public.subscription_cutback('RESTORE DIRECT WRITES');`, Worker flag off | History kept. Proven on PostgreSQL 17 locally, not on the hosted version |
| Problem with Tap | `TAP_RENEWALS_ENABLED`, then `TAP_BILLING_ENABLED` off | Existing Plus periods stay |
| Bad function deploy | Redeploy the previous version | None |
| Migrations must go, before any real history | `subscription_payment_channels_rollback.sql`, `subscription_billing_rollback.sql`, then `subscription_entitlements_quotas_rollback.sql` | Each refuses once records exist |
| Data damage | Restore the step-1 backup | Owner decision |

## 6. Provider setup

**Google Play Console** (app `com.nmodigital.brokerwallet`)

1. Create the app record. Upload a build that contains the billing library (any internal-testing build).
2. Monetize > Subscriptions > Create subscription: Product ID `broker_wallet_plus`, name "Broker Wallet Plus".
3. Add base plan `monthly`: auto-renewing, billing period 1 month, price AED 20.00, UAE.
4. Add base plan `annual`: auto-renewing, billing period 1 year (not a prepaid or installment plan), price AED 180.00,
   UAE. Add no offers or free trials. Activate both base plans only with the owner's approval.
5. Google Cloud: enable Google Play Android Developer API; create a service account; in Play Console > Users and
   permissions invite it with "View financial data" and "Manage orders and subscriptions".
6. Pub/Sub: create topic `play-rtdn`; grant `google-play-developer-notifications@system.gserviceaccount.com` the
   Publisher role; create a **push** subscription to
   `https://<project>.supabase.co/functions/v1/subscription-webhooks/google-play` with **authentication enabled**
   (service account and audience = the two `GOOGLE_PLAY_PUSH_*` values).
7. Monetize > Monetization setup > Real-time developer notifications: topic `projects/<id>/topics/play-rtdn`,
   subscriptions and voided purchases; send the test message.
8. Add license testers. Prove section 9's Play list.

**Tap**

- Ask Tap to enable Save Card and non-3DS merchant-initiated charges, and register `app.brokerwallet.ae`.
- With test keys confirm: `onSuccess` returns the `tok_` id; captured charges and card authorizations return `card.id`
  and `payment_agreement.id`; the AED 1.00 card-verification hold is accepted; webhook retry behaviour.
- Responsibility split: Tap holds cards, runs 3-D Secure, executes each charge and sends webhooks. Broker Wallet decides
  when a renewal is due (hourly job), creates each charge once under a unique order and idempotency key, verifies every
  result by reading it back from Tap, retries a failed renewal at most three times, stops on cancellation, issues the
  tax documents and owns the entitlement. Tap's legacy Subscriptions API is not used.

## 7. Store policy gates (checked 2026-11-24 and 2026-11-26)

**Apple, UAE storefront: release blocker.** Guideline 3.1.1 requires in-app purchase for unlocked features; 3.1.3(b)
allows honouring a web purchase only if the same item is also sold as in-app purchase; 3.1.1(a)'s link entitlements do
not cover the UAE. The no-IAP model has no identified basis. The proposed web-activation sheet is debug-only and is
absent from release builds (checked in the release web bundle).

**Google Play, UAE:** none of Google's billing-choice pages names the UAE. The Tap choice inside Android is shown only in
a debug build on Staging, or when the owner sets `billing_channel_policy.android_card_choice` with a recorded basis.

**Store-compliance hook (rule pack v2.5.1, re-run 2026-11-26): critical findings 5 → 1.**

| Finding | Status |
|---|---|
| `targetSdk` 35 (Play requires 36 since 31 August 2026) | **Fixed:** `targetSdk = 36`. Predictive back, which API 36 turns on by default, is pinned off (`enableOnBackInvokedCallback="false"`) so approved back behaviour does not change. No orientation lock or edge-to-edge opt-out exists, so the large-screen and edge-to-edge changes of API 36 do not apply |
| All-files storage access | **False positive:** the permission was never declared; the scanner matched a comment, now reworded. The source-guard tests still prove no `<uses-permission>` for it |
| No `PrivacyInfo.xcprivacy` | **Fixed:** `ios/Runner/PrivacyInfo.xcprivacy`, registered in the Runner target's resources. No tracking; required-reason APIs from the app's own code (file timestamps C617.1, elapsed time 35F9.1, own preferences CA92.1); collected data: name, email, phone, user ID, push token, precise location, photos/videos, user content, purchase history, all for app functionality. **The owner must make the App Store Connect privacy answers match this list.** 11 iOS plugins ship no manifest of their own (Firebase wrappers, doc scanner, image compress, open_filex, pdfium, printing, smart_auth, Syncfusion viewer, video_compress, video_thumbnail): Apple's upload check will name any API still undeclared |
| Staging URL in a release string | **False positive, still blocking:** `cloudflare/workers/r2-profile-upload/staging-acceptance/reports/…/config.toml` is a gitignored local report, in no build. The hook blocks `flutter build` while it exists, so the owner either removes that local folder or runs the build |
| Sign in with Apple missing (4.8) | Open, iOS. Google sign-in requires an equivalent privacy login on iOS |
| `ITSAppUsesNonExemptEncryption` unset | Open, owner/legal answer. The app encrypts files itself (AES vault), so `false` may not be correct |
| Release R8 minification | Open. Recommended before February 2027; its own checkpoint with a release build on a device |
| `brokerwallet://auth` without App Links / Universal Links | Open, hardening (PKCE already protects the code) |

Other high findings come from gitignored `graphify-out/`, `functions/package-lock.json` metadata or a doc comment and are
not in the app. The Android compile of the billing plugin is **still not verified** (the hook blocks the build).

## 8. UAE VAT

Prices include 5% VAT. Every captured Tap payment gets a tax invoice (`BW-INV-<year>-NNNNNN`, gapless), every full refund
a credit note (`BW-CN-…`), with supplier name, TRN, address, net, VAT and total in fils. No card sale can start until the
tax profile is complete. Not covered: partial-refund credit notes, PDF or e-mail delivery of invoices, and the VAT
treatment of Google Play sales (Google issues its own receipts): confirm all three with the company's tax adviser.

## 9. Release verification checklist

- [ ] Backup taken and restore rehearsed
- [x] Prices decided: AED 20.00 monthly, AED 180.00 yearly (2026-11-26)
- [ ] Baseline and phone-auth order decided
- [ ] Play Console base plans show AED 20.00 / 1 month and AED 180.00 / 1 year; a Tap test capture of the annual plan is 180.00 with VAT 8.57
- [ ] `subscription_production_verify.sql` passes before and after cutover
- [ ] `subscription-test-control` is not deployed to Production
- [ ] Negative tests on Staging through real REST
- [ ] Staging flow: OFF, 5 creations, 6th refused, ON, 6-8, OFF refused, 3 edits per item
- [ ] Play sandbox: purchase, acknowledgement, renewal, grace, hold, cancel, expiry, refund, restore, restore on another account refused
- [ ] Tap test mode: payment, 3-D Secure, webhook, renewal, decline, card change, cancel, refund, invoice and credit note
- [ ] Web: the "not ready" areas in section 10 resolved or hidden by the owner
- [ ] Physical Android; iPhone plans-only screen
- [ ] Android 16 phone on the API 36 build: back on every screen, system-bar insets, scanner camera, file export,
      notifications and reminders
- [ ] Apple decision recorded; section 7 hook findings fixed
- [ ] `subscription_ops_report.sql` shows no alerts after the first live purchase

## 10. Flutter Web (audited in a local browser, 2026-11-26)

| Works | Fails or unverified |
|---|---|
| Startup, sign-in, session restore, refresh on inner pages | **Scanner, Document Signature: crash on open** (`Platform` in the browser) |
| Home, record lists, add-Offer form, Quotation form | Images to PDF, Combine PDFs: same call, expected to crash |
| Search, Favorites, Profile | Maps: the browser location permission is fixed (2026-11-26) and the Maps script loads at startup from `GOOGLE_MAPS_WEB_API_KEY`; with no key, maps stay unavailable. Not yet verified with a real key |
| Plans, card checkout, return, billing, renewal, card change, tax documents | Media upload, Quotation PDF, sharing: use device files, unverified |
| | Realtime notifications on web: not tested |

The four Toolkit tools are file-based end to end (`dart:io` files, app folders, a native document scanner), so a
`Platform` guard alone would only move the crash a line further. Making them work in a browser needs a browser storage
and download design; hiding or labelling them on the web is a user-facing change. Both wait for the owner's decision.

The hosted `app.brokerwallet.ae` serves an older build (version 1.0.0+1). Its Cloudflare project was not inspected
(wrangler needs an API token in a non-interactive shell).

## 11. Monitoring

Run `supabase/validation/subscription_ops_report.sql` daily and after each release. Act on any row under an ALERT heading.
