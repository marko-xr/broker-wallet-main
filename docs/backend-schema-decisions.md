# Broker Wallet backend schema decisions

## Purpose

This document records the decisions used by the Stage 1 Supabase baseline migration. It is based on the current Flutter/Firebase models, Firebase rules, quota Functions, and `docs/backend-migration-plan.md`. The Stage 1 migration is structural only: it does not move Firebase test data, switch the Flutter app to Supabase, configure Cloudflare R2, or configure RevenueCat.

## Baseline decisions implemented

### Identity and ownership

- Supabase Auth is the future identity root.
- `public.profiles.id` is the same UUID as `auth.users.id`.
- Every owner-controlled aggregate stores `owner_id uuid` referencing `profiles(id)`.
- RLS uses `auth.uid()` and prevents access to another user's private records.
- A trusted `auth.users` trigger creates the minimal `profiles` row.
- No Firebase UID compatibility/mapping table is created because the existing Firebase data is test-only and no production data migration is required.

### Active domain only

The Stage 1 baseline includes the live application domains:

- requests
- offers
- owners
- offices
- brokers
- watchmen
- quotations
- favorites
- feedback
- notifications / push-device registration
- media metadata
- RevenueCat projection / quota bookkeeping
- app-version and server operational tables

The legacy top-level `properties` and `user_favorites` abstraction is intentionally excluded. It is not part of the active user-subcollection flows inspected in the current app.

Toolkit artifact tables (`scanner`, `signature`, `imageToPdf`, `combinePdfs`) and transcoding-job storage are also excluded from the baseline because their persisted payloads are not defined by the inspected Dart domain models. Their names remain represented in the quota-section enum so later quota work can remain compatible with the current Functions.

### Numeric and geographic types

- Money: `numeric(14,2)`.
- Square footage: `numeric(14,2)`.
- Rooms / bathrooms / installment sequence: integers with nonnegative or positive checks as appropriate.
- Latitude/longitude: `double precision` with valid range checks and paired-nullability checks.
- Currency code: three-character uppercase text; current default is `AED`.
- Timestamps: `timestamptz`.

Legacy Flutter string price/square-footage values will be parsed by the future adapter layer. Stage 1 does not change the current Dart models.

### Transaction and status values

Canonical listing transaction values:

- `rent`
- `sell`

Canonical property-status values:

- `available`
- `active`
- `sold`
- `rented`
- `canceled`
- `not_available`
- `fulfilled`
- `closed`
- `expired`

Offer rows accept the current offer workflow: `available`, `sold`, `rented`, `canceled`, `not_available`.

Request rows accept the current request workflow: `active`, `fulfilled`, `closed`, `expired`. Legacy request `available` values are an adapter-normalization concern and are not a new canonical database value for requests.

### Payment method values

Canonical PostgreSQL payment methods are:

- `cash`
- `cheque`
- `bank_transfer`
- `other`

The current Dart quotation UI uses `bankTransfer`; the future adapter will map that value to/from `bank_transfer` without changing Stage 1 Flutter code.

### Property type vocabulary

- `property_type` and `specific_property_type` remain text in the baseline.
- The database does not invent a closed specific-property-type enum before the product vocabulary is finalized.
- Empty/legacy-compatible text is permitted where the current UI already permits it.

### Areas

`selectedAreas[]` is normalized into:

- `request_areas`
- `offer_areas`

Each row stores the area text plus an ordinal. This preserves display order and allows area indexes without using a PostgreSQL array.

### Offline synchronization fields

Owner-editable synchronized aggregates receive:

- client-generated/accepted UUID primary keys
- `version bigint not null default 1`
- server-managed `updated_at`
- nullable `deleted_at` tombstone

The update trigger increments `version` on every update. Hard delete is not granted to ordinary clients for synchronized top-level aggregates; future Flutter adapters will soft-delete by updating `deleted_at` and use `version` for optimistic concurrency.

### Favorites

Favorites use six concrete tables rather than one polymorphic table:

- `favorite_offers`
- `favorite_requests`
- `favorite_owners`
- `favorite_offices`
- `favorite_brokers`
- `favorite_watchmen`

This gives every favorite a real target foreign key. Current product behavior is private/per-user, so RLS additionally requires the target to belong to the authenticated user. A read-only `favorites_unified` view is provided for a future Flutter adapter.

### Quotation normalization

Quotation header/scalar fields remain on `quotations`.

Repeated/calculated sections are relational:

- `quotation_downpayments`
- `quotation_government_fees`
- `quotation_administrative_fees`

Current display date/start/end values remain text because the Flutter model explicitly treats them as display strings.

The schema stores current total fields but Stage 1 does not yet decide whether future UI/server logic permits manual override versus server-calculated totals. That is an enforcement decision, not a table-structure blocker.

### Media and future Cloudflare R2

`media_objects` stores permanent object metadata only, including:

- bucket
- object key
- content type / format
- dimensions / duration / size
- lifecycle status
- original filename

No signed URL or permanent public URL is stored as authoritative media state.

Concrete attachment tables are used:

- `offer_media`
- `owner_media`
- `quotation_media`
- `profile_media`

Ownership-validation triggers ensure attached media belongs to the same owner as the target aggregate. Stage 1 does not create an R2 bucket or credentials and does not change Firebase Storage usage.

### RevenueCat authority

RevenueCat will be the future subscription source of truth and its `appUserID` will be the Supabase Auth UUID string.

The baseline contains:

- `revenuecat_entitlements`
- `plan_limits`
- `usage_counters`
- `revenuecat_webhook_events`

Ordinary clients can read only their own entitlement/usage projection (and authenticated plan-limit reference rows) and cannot write subscription, webhook, or quota authority data.

No RevenueCat entitlement/product mapping is seeded in Stage 1.

### Quota counter conflict

The current Firebase implementation contains conflicting concepts:

- current item count
- lifetime-created count
- older documentation/tests with differing free limits

The baseline therefore preserves separate authoritative counter fields:

- `current_item_count`
- `lifetime_created_count`
- `period_item_count`
- `period_started_at`

`plan_limits.counter_basis` can select `current`, `lifetime_created`, or `period` later. No production limit rows are seeded until the product-owner decision is finalized. This prevents Stage 1 from silently choosing the wrong commercial behavior.

### App versions

`app_versions` is keyed by platform and supports separate `android` and `ios` release rows. No live version row is seeded because the existing production payload/release values have not been finalized.

### Notifications and push

The schema keeps in-app notifications and a protected `push_devices` registry. FCM is not removed during Stage 1. Raw push token rows have no ordinary client read/write access and are intended to be managed later through a protected backend registration endpoint.

### Feedback

Users may insert feedback and read their own submissions. The database derives name/email snapshots from the profile and forces new feedback status to `unread`. Ordinary clients cannot change processing status.

## RLS/grant model

Stage 1 uses both RLS and PostgreSQL grants:

- RLS limits rows by authenticated ownership.
- Column grants prevent updates to server-owned fields even on an owned row.
- Synchronized top-level aggregates are client SELECT/INSERT/UPDATE but not hard DELETE.
- Child aggregate rows (areas/quotation children) allow owner-bound CRUD.
- Favorites allow SELECT/INSERT/DELETE and no UPDATE.
- RevenueCat/webhook/quota authority, media lifecycle, push token lifecycle, idempotency data, and audit data are server-write-only.
- Notifications are backend-created; recipients may read/delete and update only read state.

No service-role key is intended to exist in the Flutter application.

## Deliberately deferred product decisions

These do not block the Stage 1 table structures but must be resolved before their later enforcement/integration stages:

1. Exact RevenueCat entitlement identifier and Android/iOS product mapping.
2. Whether a free plan exists at launch, which quota sections are limited, the limit values, and which counter basis applies.
3. RevenueCat grace-period/billing-issue behavior.
4. Whether quotation totals can be manually overridden or must always be derived.
5. Final controlled `specific_property_type` vocabulary, if a closed vocabulary is desired.
6. Whether the legacy generic `properties` abstraction should ever return; baseline assumes no.
7. Final app-version rows, update URLs, and release notes.
8. Toolkit persisted artifact design if those tools later require server persistence rather than only quota accounting.

## Stage 1 acceptance gate

The baseline is not considered complete until the developer workstation can run, from the repository root:

```bash
npx supabase start
npx supabase db reset
npx supabase test db
```

All migrations and pgTAP tests must pass locally before any `supabase db push` is allowed against the hosted `broker-wallet` project.
