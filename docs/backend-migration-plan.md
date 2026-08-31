# Broker Wallet backend migration plan

## Scope and guardrails

This document is based on a static inspection of the Flutter application, Firebase rules/configuration, and the `functions/` source on branch `update-backend`. It proposes a target design only. No Firebase code or package should be removed until the replacement path is implemented and verified; authentication remains unchanged in the early stages. Existing Firebase records are test data, so no production data migration is required.

The current Supabase CLI directory and project link are left untouched. This plan does not authorize remote changes, SQL execution, credential handling, or a Git commit.

## Architecture decision gate

The following decisions are mandatory inputs to any future SQL design. “Blocking before SQL?” means that the selected approach must be reflected in a reviewed migration; it does not authorize creating that migration now.

| Decision | Selected approach | Reason | Blocking before SQL? | Remaining question |
|---|---|---|---|---|
| Supabase identity and ownership | `public.profiles.id` references `auth.users(id)`; every owner-controlled table uses `owner_id uuid`; RLS compares ownership with `auth.uid()`; inserts and ownership-changing updates require `owner_id = auth.uid()` | Makes Supabase Auth the identity root and prevents clients from creating or moving rows for another owner | Yes | Whether any test data is retained; retained Firebase UIDs would require a private one-time identity mapping |
| RevenueCat authority | RevenueCat is the subscription source of truth; RevenueCat `appUserID` equals the Supabase Auth user UUID; use separate `revenuecat_entitlements`, `plan_limits`, `usage_counters`, and `revenuecat_webhook_events` tables, all server-maintained | Separates provider state, product limits, authoritative consumption, and webhook idempotency; prevents client plan/quota escalation | Yes | Exact entitlement identifiers, product/plan mapping, limits, reset periods, and webhook retention |
| Favorites integrity | Use six separate favorite tables, one for each active entity type, with ordinary FKs to the target table and composite `(owner_id, target_id)` primary keys; reject a single polymorphic favorites table | Gives database-enforced referential integrity without pretending a type/id pair has an ordinary FK | Yes | Whether favorites may ever target another user’s shared/public entity |
| Media attachment integrity | Use separate `offer_media`, `owner_media`, `quotation_media`, and `profile_media` tables with real FKs; reject a generic polymorphic attachment table | The inspected models attach media only to profiles, offers, owners, and quotations; separate tables enforce target and owner integrity | Yes | Whether toolkit artifacts or future entities need additional attachment tables |
| Cloudflare R2 | PostgreSQL stores permanent R2 object keys and metadata only; a protected backend creates short-lived upload/download URLs; lifecycle is `pending_upload`, `uploaded`, `ready`, `failed`, `pending_delete`, `deleted` | Keeps the private bucket private, avoids persisting expiring URLs, and makes interrupted upload/finalization/deletion recoverable | Yes | Worker location (Supabase Edge Function versus Cloudflare Worker), size/MIME limits, and orphan retention interval |
| Offline synchronization | Client-generated UUIDs, server-managed `version`, `updated_at`, nullable `deleted_at` tombstones, durable idempotent outbox retries, and explicit conflict rules | Supabase does not supply Firestore-style offline writes/cache reconciliation; these operational fields make replay and deletion convergence deterministic | Yes | Tombstone retention period and which editable screens should offer user-assisted conflict resolution |
| Push notifications | Retain `firebase_messaging`/FCM during backend migration as the only remaining Firebase client capability if other Firebase packages are retired; otherwise select and implement a replacement push client/server before removing it | Removing `firebase_messaging` removes the current FCM client and push notifications will not silently continue | No for core schema; yes before Firebase package removal/production cutover | Whether product policy permits FCM as the sole remaining Firebase package or requires another push provider |
| Normalization | Relational child tables for independently ordered, filtered, calculated, constrained, or updated values; JSONB only for small non-queryable open metadata (`profiles.preferences`, notification payload, audit details, webhook payload, toolkit metadata if retained) | Preserves relational integrity/queryability without over-modeling intentionally open display/diagnostic metadata | Yes | Actual toolkit payload shapes must be inspected before any optional toolkit schema is proposed |
| Legacy property repository | Exclude top-level `properties` and `user_favorites` from the baseline schema until the feature is confirmed active | Its model conflicts with the active user-subcollection domain and ownership is not present in the inspected `Property` model | Yes | Keep and model it, replace it with offers/requests, or remove it later |

## Current Firebase architecture

### Runtime topology

- `main.dart` initializes Firebase Core with generated Android/iOS options and configures Firestore persistence (`persistenceEnabled: true`, unlimited cache). Startup tolerates Firebase initialization failure and continues in a limited offline mode.
- `RepositoryProvider` selects `FirebaseAuthRepository`, `FirestoreUserRepository`, `FirestorePropertyRepository`, and `FirestoreNotificationRepository`.
- The repository abstraction is incomplete. Active screen data uses direct Firebase services (`RequestService`, `OfferService`, `OwnerService`, `OfficeService`, `BrokerService`, `WatchmenService`, `QuotationService`, `FavoritesService`) and several view models call Firebase directly.
- The primary Firestore hierarchy is `users/{uid}` with business records in user-owned subcollections. The document body also repeats `userId`.
- A separate, apparently legacy/general `PropertyRepository` uses top-level `properties` and `user_favorites`; this is not the same data shape as offers/requests.
- Favorites used by the current UI are stored at `users/{uid}/favorites/items/{type_itemId}`. The item document contains `itemId`, `type`, and `addedAt`; display data is fetched from the matching user-owned entity subcollection and cached in Hive.
- Notifications and FCM tokens are stored at `users/{uid}/notifications/{notificationId}` and `users/{uid}/fcmTokens/{token}`.
- Feedback is top-level `feedback/{id}`. Lookup helpers are top-level `email_lookup`, `phone_lookup`, and `pending_email_verifications`.
- Quota counts and plan state are denormalized on the user document. Cloud Functions enforce/add/reconcile counts and write `audit_logs` and per-user `idempotency_tokens`.
- Firebase Storage contains profile images, property/entity media, user documents, quotation assets, and test uploads. Several upload services optimistically create local/Firestore records before background upload.
- Firebase Functions implement quota-protected creation, quota reconciliation, matching notifications, quota/subscription/reminder notifications, app-update checks, and optional/commented HLS transcoding exports.

### Ownership and relationships

The Firestore path is the strongest ownership boundary. For domain subcollections, `users/{uid}` owns every child record; `userId` should equal the parent UID but can drift because it is duplicated. Offers, requests, owners, offices, brokers, watchmen, quotations, favorites, notifications, and FCM tokens are not shared across parent users by the current rules and queries.

Notification `offerId`, `requestId`, and `senderUserId` are soft references. Current Firestore favorites use a type-tagged `(type, itemId)` reference. Media URLs are embedded in entity documents rather than represented as foreign-keyed records. Quotations embed downpayments and fee structures as arrays/maps.

### Current security behavior

`firestore.rules` generally restricts `users/{uid}` and descendants to the authenticated owner. Quota-controlled direct writes are denied for counted sections and are intended to go through callable Functions. Feedback creation is authenticated and owner-bound; reads/updates/deletes are denied to clients. App configuration is authenticated-read/admin-write. Lookup documents allow unauthenticated `get`, which leaks whether an email/phone is registered. The rules contain duplicate/overlapping matches and broad fallback matches, which makes their effective behavior harder to reason about.

Storage rules require sign-in and usually path ownership for writes. Some media reads are available to any signed-in user. File type and size checks differ by path.

## Complete Firebase dependency inventory

### Flutter packages

| Package | Current purpose |
|---|---|
| `firebase_core` | Firebase initialization and generated `FirebaseOptions` |
| `firebase_auth` | Email/password, Google, Facebook, phone OTP, verification, profile/account operations, auth state |
| `cloud_firestore` | Profiles, entities, favorites, quotations, feedback, notifications, tokens, config, analytics, quota metadata, lookup documents |
| `cloud_functions` | `addItemWithQuota`, `syncUserQuota`, `reconcileUserCounts`, and `checkAppUpdate` callable clients |
| `firebase_storage` | Profile images, entity media, quotation logos/PDF-related assets, optimized uploads, deletion/metadata |
| `firebase_messaging` | FCM token registration, foreground/background delivery, notification settings integration |

Related persistence packages are `hive`, `hive_flutter`, and `hive_generator`. SharedPreferences also caches quota counts/auth-related state. No Supabase or RevenueCat Flutter SDK dependency is currently declared.

### Firebase Auth usage

- `FirebaseAuthRepository` implements `AuthRepository` and also accesses Firestore for profile/lookup synchronization.
- `AuthService` is a parallel auth implementation with user, phone lookup, and email lookup writes.
- `AuthViewModel` and sign-up/login/OTP/email verification view models consume Firebase user/session semantics.
- `EmailVerificationService` persists pending verification metadata.
- `ProfessionalEmailService` accepts a Firebase `User`.
- Most screen services and many view models use `FirebaseAuth.instance.currentUser.uid` directly.
- Analytics, map/search, quota, subscription, profile uploads, favorites, notifications, and quotations derive ownership from the Firebase UID.
- Supported flows include email/password, Google, Facebook, phone OTP, email verification, password reset, account deletion, email/phone linking, reauthentication, and profile changes.

### Firestore usage and collection inventory

| Firestore path | Purpose |
|---|---|
| `users/{uid}` | User profile, verification flags, embedded subscription/preferences, plan/quota counts, login timestamps |
| `users/{uid}/requests/{id}` | Property requirements |
| `users/{uid}/offers/{id}` | Property offers with media and map coordinates |
| `users/{uid}/owners/{id}` | Owner contacts with property/media/map information |
| `users/{uid}/offices/{id}` | Office contacts/map information |
| `users/{uid}/brokers/{id}` | Broker contacts |
| `users/{uid}/watchmen/{id}` | Watchman/building contacts/map information |
| `users/{uid}/quotations/{id}` | Quotation header, embedded installments/fees, logo/PDF URLs |
| `users/{uid}/favorites/items/{type_itemId}` | Current type-tagged favorites |
| `users/{uid}/notifications/{id}` | In-app notifications |
| `users/{uid}/fcmTokens/{token}` | Push device tokens and metadata |
| `users/{uid}/idempotency_tokens/{token}` | Quota Function idempotency records |
| `users/{uid}/{scanner,signature,imageToPdf,combinePdfs}/{id}` | Toolkit quota-counted records; persisted model shape is not defined in the inspected Dart domain models |
| `feedback/{id}` | User feedback |
| `email_lookup/{normalizedEmail}` | Email-to-UID lookup |
| `phone_lookup/{e164Phone}` | Phone-to-UID lookup |
| `pending_email_verifications/{id}` | Temporary verification workflow |
| `app_config/latest_version` | Mobile version/update configuration |
| `audit_logs/{id}` | Admin Function quota/reconciliation audit |
| `transcoding_jobs/{id}` | Optional HLS job state used by currently unexported transcoding functions |
| `properties/{id}` | Legacy/general map `Property` records |
| `user_favorites/{uid}` | Legacy/general property ID array |

Direct Firestore access also appears in analytics, app version, auth, email verification, feedback, fast profile/media uploads, map caching/view model, search, subscription/plan views, add-screen quota metadata updates, and toolkit views.

### Firebase Storage usage

Storage is accessed through `FastMediaUploadService`, `FastProfileUploadService`, `MediaUploadService`, compatibility/universal/optimized upload services, video upload/transcoding helpers, quotation upload code, and media deletion paths. Observed or rule-defined prefixes include:

- `profile_images/{uid}/...`
- `property_media/{uid}/{collection}/{documentId}/...`
- `property_media/{uid}/{folder}/...`
- `user_documents/{uid}/...`
- `quotations/{uid}/...`
- `users/{uid}/quotations/{quotationId}/logos/...` (Dart path not explicitly represented in current Storage rules)
- `test_uploads/{uid}/...`

Entity documents store `mediaUrl`, `mediaUrls`, `uploadedFileName`, `officeLogoUrl`, `pdfUrl`, and profile image URLs. `MediaFileModel` additionally defines metadata but no clear active Firestore collection for it.

### Cloud Functions usage

Exported functions:

- `addItemWithQuota`: authenticated callable, validates an allowed section, idempotently creates a child document, updates counts, and writes audit data.
- `syncUserQuota`: recounts per-user domain/toolkit collections and updates user counts.
- `onUserUpdate`: Firestore trigger that performs related count synchronization.
- `reconcileUserCounts` and `reconcileAllUserCounts`: callable reconciliation/audit operations.
- `checkOfferMatchesRequests` and `checkRequestMatchesOffers`: create match notifications on new offers/requests.
- `checkQuotaThresholds`: creates quota notifications on user updates.
- `checkExpiringSubscriptions`: scheduled subscription reminders.
- `sendItemReminders`: scheduled stale-item reminders.
- `sendSystemUpdateNotification`: callable broadcast/update operation.
- `checkAppUpdate`: callable app-version response with Firestore fallback in Flutter.

HLS functions (`transcodeToHLS`, status, cleanup, completion, scheduled cleanup) exist in `transcoding.js` but are commented out in `functions/index.js`.

### Firebase-specific platform configuration

- `firebase.json`, `firestore.rules`, alternate quota rules, `firestore.indexes.json`, and `storage.rules`
- `lib/firebase_options.dart`
- Android: `android/app/google-services.json`, Google Services Gradle plugins/classpaths, and Firebase BoM declarations
- iOS: `ios/Runner/GoogleService-Info.plist`, `FirebaseCore` import/configuration in `AppDelegate.swift`, and `FirebaseAppDelegateProxyEnabled`
- Generated registrants for macOS and Windows contain Firebase plugins; other generated plugin files may be regenerated by Flutter
- `functions/package.json`, Admin SDK/Functions dependencies, source files, tests, and deployment configuration

These files remain until the Firebase paths are retired.

## Proposed PostgreSQL schema

This schema incorporates the complete persisted model inventory described by the field mappings below.

### Conventions

- Use `uuid` primary keys with `gen_random_uuid()` for new business records.
- `profiles.id uuid primary key references auth.users(id) on delete cascade`.
- Every user-owned table has `owner_id uuid not null references profiles(id) on delete cascade`.
- Use `timestamptz not null default now()` for creation/update times.
- Use `numeric(14,2)` for money, never floating point. During compatibility rollout, parse legacy empty strings before writing.
- Use `numeric` for square footage and `double precision` for latitude/longitude, with range checks.
- Prefer lowercase `snake_case`. Keep temporary Dart mapping adapters during migration.
- Enable RLS on every application table. No client receives a service-role key or R2 credential.
- **Proposed new operational fields:** owner-synchronized mutable rows add `version bigint not null default 1` and `deleted_at timestamptz null`; the server increments `version` whenever data changes, including soft deletion. These fields do not exist in the inspected Firebase models and exist solely for deterministic offline synchronization.

### Enums

Recommended PostgreSQL enums (or text columns plus checks if easier to evolve):

- `listing_transaction_type`: `rent`, `sell` (confirm whether UI can emit `sale`).
- `property_status`: `available`, `active`, `sold`, `rented`, `canceled`, `not_available`, `fulfilled`, `closed`, `expired`.
- `favorite_entity_type`: `offer`, `request`, `owner`, `office`, `broker`, `watchman`.
- `feedback_status`: `unread`, `read`, `resolved`.
- `notification_category`: `match`, `reminder`, `plan`, `system` (`quota` maps to `plan`).
- `media_type`: `image`, `video`, `pdf`, `unknown`.
- `payment_method`: `cash`, `cheque`, `bank_transfer`, `other`.
- `welcome_message_mode`: `auto`, `custom`, `hidden`.
- `subscription_plan`: initially `free`, `monthly`, `yearly`; RevenueCat product/entitlement mapping must be confirmed before enforcing this enum.

### Tables

#### `profiles`

`id`, `name`, `email`, `phone_number`, `profile_media_id`, `is_email_verified`, `is_phone_verified`, `preferences jsonb default '{}'`, `last_login_at`, `created_at`, `updated_at`.

Constraints: normalized email should be unique case-insensitively if stored here (`citext` recommended), normalized non-null phone unique, nonempty name where required, and `jsonb_typeof(preferences) = 'object'`. Verification truth should ultimately come from trusted auth/server claims, not arbitrary client updates.

#### RevenueCat subscription and quota tables

RevenueCat is the subscription source of truth. The RevenueCat `appUserID` must be the string form of the authenticated Supabase UUID.

- `revenuecat_entitlements`: `user_id`, `entitlement_id`, `product_id`, `plan_code`, `is_active`, `purchased_at`, `expires_at`, `environment`, `updated_at`. Composite PK `(user_id, entitlement_id)`. `plan_code` is a **proposed new server-derived operational field** mapping RevenueCat product/entitlement state to the legacy plan concept; clients cannot set it. This relational table is queried to authorize features and is independently updated by webhooks; it replaces the embedded Firestore subscription state.
- `plan_limits`: `plan_code`, `section`, `limit_value`, `reset_period`, `updated_at`. Composite PK `(plan_code, section)`. Limits are relational because quota checks filter by plan and section and limits change independently. Exact plan codes/limits are an SQL blocker.
- `usage_counters`: `owner_id`, `section`, `period_start`, `item_count`, `updated_at`. Composite PK `(owner_id, section, period_start)`. Counts are authoritative server-maintained values used transactionally with inserts; clients cannot write them.
- `revenuecat_webhook_events`: `event_id` PK, `event_type`, `app_user_id`, `received_at`, `processed_at`, `processing_status`, `payload jsonb`. This is server-only webhook idempotency. `payload` is JSONB because RevenueCat event payloads are externally versioned diagnostic input, are retained for replay/audit, and are not the entitlement query model.

No authenticated-client write policy is created for these four tables. Owners may select only their own entitlement and usage rows. Plan limits may be authenticated-read if the UI displays them. Webhook events are server-only for both read and write.

#### Domain tables

`requests`: `id`, `owner_id`, `request_type`, `selected_city`, `location_text`, `phone_number`, `country_code`, `min_price`, `max_price`, `square_footage`, `notes`, `property_type`, `specific_property_type`, `rooms`, `bathrooms`, `status`, `created_at`, `updated_at`.

`offers`: the request common fields with `offer_type` instead of `request_type`, plus `pickup_location_text`, `pickup_latitude`, `pickup_longitude`, `pickup_address`, `legacy_uploaded_file_name`, `status`, timestamps.

`owners`: `id`, `owner_id`, `name`, `phone_number`, `country_code`, `property_type_text`, `property_location`, `notes`, pickup text/coordinates/address, `legacy_uploaded_file_name`, timestamps.

`offices`: `id`, `owner_id`, `office_name`, `manager_name`, `country_code`, `phone_number`, `office_location`, `notes`, pickup text/coordinates/address, timestamps.

`brokers`: `id`, `owner_id`, `name`, `country_code`, `phone_number`, `notes`, timestamps.

`watchmen`: `id`, `owner_id`, `name`, `country_code`, `phone_number`, `building_name`, `notes`, `building_location`, pickup text/coordinates/address, timestamps.

Checks:

- `rooms >= 0`, `bathrooms >= 0`, money and square footage `>= 0`.
- `min_price <= max_price` when both are non-null.
- latitude from `-90` to `90`; longitude from `-180` to `180`; require both coordinates together.
- Offer statuses restricted to offer workflow values; request statuses restricted to request workflow values.
- Store phone number and country code separately for UI compatibility, but add a normalized E.164 derived/written column if phone-based related-item queries remain important.

#### Area normalization

`request_areas(request_id, ordinal, area)` and `offer_areas(offer_id, ordinal, area)`, with composite PK on `(request_id, area)` / `(offer_id, area)`, `ordinal >= 0`, and cascading FKs. This preserves list order without a PostgreSQL array and permits area indexes. If controlled geographic IDs become available, replace `area` text with an `area_id` FK while retaining a display snapshot.

#### `media_objects` and attachments

`media_objects`: `id`, `owner_id`, `bucket`, `object_key`, `media_type`, `format`, `content_type`, `size_bytes`, `width`, `height`, `duration_ms`, `thumbnail_media_id`, `original_file_name`, `status`, `created_at`, `updated_at`, `deleted_at`. `status` uses `pending_upload`, `uploaded`, `ready`, `failed`, `pending_delete`, or `deleted`. `object_key` is permanent; presigned URLs are never stored.

Use separate `offer_media`, `owner_media`, `quotation_media`, and `profile_media` tables. Each has real FKs to its entity and `media_objects`, a `role`, an `ordinal`, and a uniqueness constraint preventing duplicate attachment. `ordinal` is relational because media order is independently updated and displayed. `role` distinguishes existing primary/list/logo/PDF/thumbnail uses. An ownership-validation trigger must reject a link unless the entity owner and media owner are identical.

#### `favorites`

Use `favorite_offers`, `favorite_requests`, `favorite_owners`, `favorite_offices`, `favorite_brokers`, and `favorite_watchmen`. Each has composite PK `(owner_id, target_id)`, `added_at`, an owner FK to `profiles`, and an ordinary target FK to its concrete entity table. Cascades remove favorites when either the owning profile or target is deleted. A read-only union view may expose `entity_type`, `entity_id`, and `added_at` to Flutter.

The current product resolves favorites only inside the same user’s subcollections. RLS therefore requires both the favorite `owner_id` and target row `owner_id` to equal `auth.uid()`. If cross-user shared listings become a requirement, that access model must be designed before changing this rule.

#### Quotations

`quotations`: `id`, `owner_id`, `property_title`, `property_type`, `parking`, `subtitle`, `display_date`, `start_date_text`, `end_date_text`, `currency_code`, `professional_fee`, `total_amount`, `number_of_installments`, `payment_type`, `insurance_amount`, `insurance_returnable`, `office_name`, `office_logo_media_id`, `custom_note`, `welcome_message_mode`, `custom_welcome_message`, `pdf_media_id`, `created_at`, `updated_at`.

`quotation_downpayments`: `id`, `quotation_id`, `method`, `sequence_number`, `due_at`, `amount`, unique `(quotation_id, sequence_number)`.

`quotation_government_fees`: `quotation_id` PK, `percent_of_total_rent`, `municipality`, `electricity`, `sewerage`, `total`.

`quotation_administrative_fees`: `id`, `quotation_id`, `ordinal`, `title`, `amount`.

Use `char(3)` currency with an uppercase check. Keep the current date/start/end fields as text initially because the model explicitly treats them as display strings; convert only after input formats are confirmed. Fee amounts must be nonnegative; percentage should be in a confirmed range (proposed `0..100`).

#### Feedback, notifications, and devices

`feedback`: `id`, `owner_id`, `user_name_snapshot`, `user_email_snapshot`, `rating`, `comment`, `app_version`, `platform`, `device_info`, `status`, `created_at`, `updated_at`; check rating `1..5`.

`notifications`: `id`, `recipient_id`, `title`, `body`, `category`, `is_read`, `read_at`, `data jsonb`, `action_route`, `offer_id`, `request_id`, `match_score`, `sender_user_id`, `created_at`. FKs to users/offers/requests should use `on delete set null`. Check match score range after confirming whether code uses `0..1` or `0..100`.

`push_devices`: `id`, `owner_id`, `provider`, `token_ciphertext` or provider-token value in a protected server-only column, `platform`, `device_name`, `locale`, `last_seen_at`, `created_at`, unique `(provider, token_hash)`. Clients may register/unregister only their own device through an Edge Function; they should not select all raw tokens.

#### Operational/configuration tables

- `app_versions(platform, latest_version, minimum_version, update_url, release_notes, updated_at)`; authenticated read, privileged write.
- `idempotency_keys(owner_id, key, operation, response jsonb, expires_at, created_at)`, server-only.
- `audit_logs(id, actor_id, target_user_id, action, details jsonb, created_at)`, privileged read/write.

### Normalization rationale

Every child table exists because the child values have behavior that should not be hidden in a parent JSON document:

- `request_areas` and `offer_areas`: ordered and filtered independently by search/filter behavior.
- `quotation_downpayments`: ordered, individually dated, individually calculated, and updated as rows.
- `quotation_government_fees`: a fixed one-to-one calculated group with numeric constraints.
- `quotation_administrative_fees`: ordered, repeated, independently calculated rows.
- `offer_media`, `owner_media`, `quotation_media`, and `profile_media`: ordered/role-based attachments with concrete FKs and independent upload/deletion lifecycles.
- Six favorite tables: each favorite needs an enforceable concrete target FK and independent insert/delete behavior.
- `revenuecat_entitlements`, `plan_limits`, `usage_counters`, and `revenuecat_webhook_events`: provider state, authorization limits, metered usage, and event idempotency have different authorities and update cycles.

JSONB is restricted and justified as follows:

- `profiles.preferences`: the inspected model is an open `Map<String, dynamic>`; preferences are small user display/settings metadata and no current server query depends on individual keys.
- `notifications.data`: the inspected notification model exposes an open payload map whose keys vary by notification category; indexed columns hold queryable routing relationships.
- `audit_logs.details`: diagnostic action-specific context varies by audited operation; actor, target, action, and time remain relational.
- `idempotency_keys.response`: opaque replay output returned for the same operation; it is not queried as domain state.
- `revenuecat_webhook_events.payload`: externally versioned raw evidence used for troubleshooting/replay; normalized entitlement rows remain authoritative.

No domain list, fee structure, favorite target, media attachment, entitlement, limit, or usage count is stored in JSONB.

### Exact proposed table inventory

Fields described as `version` or `deleted_at` are **proposed new operational fields** for sync; they are not present in the inspected Firebase models. Any owner write permission below is RLS-bound to `auth.uid()` and never permits supplying or changing another owner’s UUID.

| Table name | Purpose | Primary key | Owner column | Important foreign keys | Deletion behavior | Offline-sync requirement | Client write permission |
|---|---|---|---|---|---|---|---|
| `profiles` | Application profile for Supabase identity | `id` | `id` | `id → auth.users.id` | Cascade from Auth user; profile media link handled separately | Cache; version/tombstone for editable profile projection | Owner UPDATE of editable fields only; INSERT normally auth trigger |
| `revenuecat_entitlements` | Current RevenueCat entitlement projection | `(user_id, entitlement_id)` | `user_id` | `user_id → profiles.id` | Cascade with profile | Read-through cache only; server wins | Server write only |
| `plan_limits` | Limits by plan and section | `(plan_code, section)` | none | none until plan-code mapping is finalized | Restrict while referenced logically | Refreshable reference cache | Server write only |
| `usage_counters` | Authoritative metered counts | `(owner_id, section, period_start)` | `owner_id` | `owner_id → profiles.id` | Cascade with profile | Read-through cache only; never outbox writes | Server write only |
| `revenuecat_webhook_events` | Webhook idempotency and audit | `event_id` | none (`app_user_id` is provider input) | no FK until event identity is validated | Retention job, never client cascade | None | Server write only |
| `requests` | User property requests | `id` | `owner_id` | `owner_id → profiles.id` | Soft delete/tombstone, later purge; cascade children | Full outbox/pull sync with version | Owner SELECT/INSERT/UPDATE; soft-delete by UPDATE |
| `request_areas` | Ordered request areas | `(request_id, area)` | derived through request | `request_id → requests.id` | Cascade with request | Synced as part of request aggregate | Owner CRUD through owned parent |
| `offers` | User property offers | `id` | `owner_id` | `owner_id → profiles.id` | Soft delete/tombstone, later purge; cascade children | Full outbox/pull sync with version | Owner SELECT/INSERT/UPDATE; soft-delete by UPDATE |
| `offer_areas` | Ordered offer areas | `(offer_id, area)` | derived through offer | `offer_id → offers.id` | Cascade with offer | Synced as part of offer aggregate | Owner CRUD through owned parent |
| `owners` | Owner contact records | `id` | `owner_id` | `owner_id → profiles.id` | Soft delete/tombstone, later purge | Full outbox/pull sync with version | Owner SELECT/INSERT/UPDATE; soft-delete by UPDATE |
| `offices` | Office contact records | `id` | `owner_id` | `owner_id → profiles.id` | Soft delete/tombstone, later purge | Full outbox/pull sync with version | Owner SELECT/INSERT/UPDATE; soft-delete by UPDATE |
| `brokers` | Broker contact records | `id` | `owner_id` | `owner_id → profiles.id` | Soft delete/tombstone, later purge | Full outbox/pull sync with version | Owner SELECT/INSERT/UPDATE; soft-delete by UPDATE |
| `watchmen` | Watchman/building contact records | `id` | `owner_id` | `owner_id → profiles.id` | Soft delete/tombstone, later purge | Full outbox/pull sync with version | Owner SELECT/INSERT/UPDATE; soft-delete by UPDATE |
| `media_objects` | Permanent R2 key and media metadata | `id` | `owner_id` | `owner_id → profiles.id`; optional thumbnail self-FK | State-driven delete; metadata tombstone after R2 deletion | Durable media outbox and state reconciliation | Protected-backend writes; owner SELECT |
| `offer_media` | Ordered/role-based offer media | `(offer_id, media_id)` | derived/validated | FKs to `offers`, `media_objects` | Cascade with offer; media object deleted only when unreferenced | Synced with offer/media finalization | Protected-backend writes; owner SELECT |
| `owner_media` | Ordered/role-based owner media | `(owner_record_id, media_id)` | derived/validated | FKs to `owners`, `media_objects` | Cascade with owner; media object deleted only when unreferenced | Synced with owner/media finalization | Protected-backend writes; owner SELECT |
| `quotation_media` | Quotation logo/PDF media | `(quotation_id, media_id)` | derived/validated | FKs to `quotations`, `media_objects` | Cascade with quotation; media object deleted only when unreferenced | Synced with quotation/media finalization | Protected-backend writes; owner SELECT |
| `profile_media` | Profile image attachment | `(profile_id, media_id)` | `profile_id` | FKs to `profiles`, `media_objects` | Cascade with profile; media object state-cleaned | Synced by protected upload flow | Protected-backend writes; owner SELECT |
| `favorite_offers` | Favorite offer links | `(owner_id, target_id)` | `owner_id` | FKs to `profiles`, `offers` | Cascade from owner or target | Idempotent insert/delete outbox | Owner INSERT/DELETE/SELECT; no UPDATE |
| `favorite_requests` | Favorite request links | `(owner_id, target_id)` | `owner_id` | FKs to `profiles`, `requests` | Cascade from owner or target | Idempotent insert/delete outbox | Owner INSERT/DELETE/SELECT; no UPDATE |
| `favorite_owners` | Favorite owner-contact links | `(owner_id, target_id)` | `owner_id` | FKs to `profiles`, `owners` | Cascade from owner or target | Idempotent insert/delete outbox | Owner INSERT/DELETE/SELECT; no UPDATE |
| `favorite_offices` | Favorite office links | `(owner_id, target_id)` | `owner_id` | FKs to `profiles`, `offices` | Cascade from owner or target | Idempotent insert/delete outbox | Owner INSERT/DELETE/SELECT; no UPDATE |
| `favorite_brokers` | Favorite broker links | `(owner_id, target_id)` | `owner_id` | FKs to `profiles`, `brokers` | Cascade from owner or target | Idempotent insert/delete outbox | Owner INSERT/DELETE/SELECT; no UPDATE |
| `favorite_watchmen` | Favorite watchman links | `(owner_id, target_id)` | `owner_id` | FKs to `profiles`, `watchmen` | Cascade from owner or target | Idempotent insert/delete outbox | Owner INSERT/DELETE/SELECT; no UPDATE |
| `quotations` | Quotation header and scalar terms | `id` | `owner_id` | `owner_id → profiles.id` | Soft delete/tombstone, later purge; cascade children | Full outbox/pull sync with version | Owner SELECT/INSERT/UPDATE; soft-delete by UPDATE |
| `quotation_downpayments` | Ordered installment payments | `id` | derived through quotation | `quotation_id → quotations.id` | Cascade with quotation | Synced as quotation aggregate | Owner CRUD through owned parent |
| `quotation_government_fees` | Fixed one-to-one government fee group | `quotation_id` | derived through quotation | `quotation_id → quotations.id` | Cascade with quotation | Synced as quotation aggregate | Owner CRUD through owned parent |
| `quotation_administrative_fees` | Ordered administrative fee rows | `id` | derived through quotation | `quotation_id → quotations.id` | Cascade with quotation | Synced as quotation aggregate | Owner CRUD through owned parent |
| `feedback` | User feedback and processing status | `id` | `owner_id` | `owner_id → profiles.id` | Retain or anonymize by approved policy | Outbox INSERT only; server status refresh | Owner INSERT/SELECT-own; no client UPDATE/DELETE |
| `notifications` | In-app notification inbox | `id` | `recipient_id` | FKs to profile and optional offer/request/sender | Cascade with recipient; optional refs set null | Pull/realtime cache; local read outbox | Recipient may mark read/delete; server creates |
| `push_devices` | FCM or replacement push registrations | `id` | `owner_id` | `owner_id → profiles.id` | Cascade with profile; unregister/revoke on logout | Registration retry only; no general cache | Protected-backend write; owner has no raw-token SELECT |
| `app_versions` | App update configuration | `platform` | none | none | Server-managed replacement | Refreshable reference cache | Server write only; authenticated SELECT |
| `idempotency_keys` | Server operation replay protection | `(owner_id, key)` | `owner_id` | `owner_id → profiles.id` | Expiry cleanup/cascade with profile | Client sends key; table not synchronized | Server write/read only |
| `audit_logs` | Quota/admin/security audit | `id` | none | optional actor/target profile FKs | Retention policy; references set null | None | Server write; admin read only |

The baseline intentionally excludes the legacy top-level property feature, toolkit artifact storage, and transcoding job storage until their architecture-gate questions are answered.

### Indexes

- All owner tables: `(owner_id, created_at desc)` and `(owner_id, updated_at desc)`.
- Requests/offers: `(owner_id, status, created_at desc)`, `(owner_id, request_type/offer_type, created_at desc)`, selected-city indexes, numeric price indexes, and area indexes on `(area, request_id/offer_id)`.
- Contacts: `(owner_id, lower(name))`; offices `(owner_id, lower(office_name))`; normalized phone indexes for cross-category related-item lookup.
- Coordinates: if proximity queries are needed, enable PostGIS and store `geography(Point,4326)` with GiST rather than relying only on latitude/longitude.
- Quotations: `(owner_id, created_at desc)` and trigram/FTS index on `property_title` for substring/prefix search.
- Favorites: PKs already support owner lookup; add target-side indexes if cascade/FK implementation needs them.
- Notifications: `(recipient_id, created_at desc)` and partial `(recipient_id, created_at desc) where is_read = false`.
- Push devices: `(owner_id)`, unique token hash.
- Feedback: `(status, created_at desc)` for admin processing.
- Media: unique `(bucket, object_key)`, `(owner_id, created_at desc)`, and status index for cleanup jobs.
- RevenueCat entitlements: `(user_id, is_active, expires_at)` and partial `(expires_at) where is_active`.
- Usage counters: PK already supports owner/section/period quota checks.
- Webhook events: processing-status and received-time indexes for retry/retention workers.

### Triggers and `updated_at`

- A single `set_updated_at()` `before update` trigger should assign `now()` on all mutable tables.
- A `handle_new_auth_user()` trigger may create a minimal `profiles` row from trusted `auth.users` metadata, but profile completion remains explicit.
- Media attachment validation must ensure the attachment owner equals both media owner and entity owner.
- Favorite integrity is enforced by the six concrete target foreign keys plus RLS ownership checks.
- RevenueCat webhooks insert `revenuecat_webhook_events.event_id` first and upsert RevenueCat entitlement projections idempotently through protected server code. Clients cannot write any entitlement, limit, usage, or webhook table.
- Quota enforcement, if retained, must be a transaction-safe database function/trigger or privileged RPC, never a client-maintained count.
- Avoid broad cascades from contact/media references except ownership-root deletion; use `set null` for optional notification/media snapshot references where history should survive.

## Firestore-to-PostgreSQL mapping

### `users/{uid}` → `profiles` and RevenueCat tables

| Firestore/model field | PostgreSQL target | Notes |
|---|---|---|
| document ID / `uid` | `profiles.id` | Supabase Auth UUID after auth migration; no legacy data import required |
| `name` | `profiles.name` | Required by model |
| `email` | `profiles.email` | Normalize; auth identity remains authoritative |
| `phoneNumber` | `profiles.phone_number` | Nullable, normalize E.164 |
| `profileImageUrl` | `profiles.profile_media_id` | Resolve via media metadata; temporary compatibility URL allowed |
| `createdAt` | `profiles.created_at` | `timestamptz` |
| `lastLoginAt` | `profiles.last_login_at` | Server-controlled |
| `isEmailVerified` | `profiles.is_email_verified` | Derive/server-sync |
| `isPhoneVerified` | `profiles.is_phone_verified` | Derive/server-sync |
| `preferences` map | `profiles.preferences jsonb` | Open-ended map |
| `subscription.plan` | derived from `revenuecat_entitlements` plus `plan_limits` | Legacy compatibility read only; RevenueCat product/entitlement mapping is an SQL blocker |
| `subscription.expiresAt` | `revenuecat_entitlements.expires_at` | Webhook-controlled |
| `subscription.isActive` | `revenuecat_entitlements.is_active` | Webhook-controlled |
| `subscription.features` list | active `revenuecat_entitlements.entitlement_id` rows | Relational because entitlements are independently authorized/expired |
| quota/count fields | `usage_counters.item_count` | Server-controlled and transactionally maintained |

`email_lookup` and `phone_lookup` should not become public tables. Use Supabase Auth identity management or a rate-limited Edge Function that returns only an allowed availability result. `pending_email_verifications` should be replaced by Supabase Auth verification flows, not migrated.

### `requests`

| Firestore field | PostgreSQL |
|---|---|
| document ID | `requests.id` |
| parent UID / `userId` | `requests.owner_id` |
| `requestType` | `requests.request_type` |
| `selectedCity` | `requests.selected_city` |
| `selectedAreas[]` | `request_areas.area` plus `ordinal` |
| `location` | `requests.location_text` |
| `phoneNumber` | `requests.phone_number` |
| `countryCode` | `requests.country_code` |
| `minPrice` | `requests.min_price numeric` |
| `maxPrice` | `requests.max_price numeric` |
| `squareFootage` | `requests.square_footage numeric` |
| `notes` | `requests.notes` |
| `propertyType` | `requests.property_type` nullable |
| `specificPropertyType` | `requests.specific_property_type` |
| `rooms` | `requests.rooms` |
| `bathrooms` | `requests.bathrooms` |
| `status` | `requests.status`; legacy `available` normalizes to `active` |
| `createdAt` / `updatedAt` | `created_at` / `updated_at` |

### `offers`

| Firestore field | PostgreSQL |
|---|---|
| document ID | `offers.id` |
| parent UID / `userId` | `offers.owner_id` |
| `offerType` | `offers.offer_type` |
| `selectedCity` | `offers.selected_city` |
| `selectedAreas[]` | `offer_areas.area` plus `ordinal` |
| `location` | `offers.location_text` |
| `phoneNumber`, `countryCode` | same-named offer columns |
| `minPrice`, `maxPrice`, `squareFootage` | numeric offer columns |
| `notes`, `propertyType`, `specificPropertyType` | corresponding offer columns |
| `rooms`, `bathrooms` | corresponding integer columns |
| `pickUpLocation` | `offers.pickup_location_text` |
| `pickUpLatitude`, `pickUpLongitude` | coordinate columns / later PostGIS point |
| `pickUpAddress` | `offers.pickup_address` |
| `uploadedFileName` | `offers.legacy_uploaded_file_name` or `media_objects.original_file_name` |
| `mediaUrl` | primary `offer_media` row |
| `mediaUrls[]` | ordered `offer_media` rows |
| `status` | `offers.status` |
| `createdAt`, `updatedAt` | timestamps |

### `owners`

| Firestore field | PostgreSQL |
|---|---|
| document ID | `owners.id` |
| parent UID / `userId` | `owners.owner_id` |
| `name` | `owners.name` |
| `phoneNumber`, `countryCode` | corresponding columns |
| `typeOfProperties` | `owners.property_type_text` |
| `propertyLocation` | `owners.property_location` |
| `notes` | `owners.notes` |
| pickup fields | corresponding pickup columns |
| `uploadedFileName` | legacy/media original filename |
| `mediaUrl`, `mediaUrls[]` | ordered `owner_media` rows |
| timestamps | `created_at`, `updated_at` |

### `offices`, `brokers`, and `watchmen`

| Collection.field | PostgreSQL |
|---|---|
| offices document ID / parent UID / `userId` | `offices.id` / `owner_id` |
| offices `officeName`, `managerName` | `office_name`, `manager_name` |
| offices `countryCode`, `phoneNumber`, `officeLocation`, `notes` | corresponding columns |
| offices pickup fields | corresponding pickup columns |
| offices timestamps | `created_at`, `updated_at` |
| brokers document ID / parent UID / `userId` | `brokers.id` / `owner_id` |
| brokers `name`, `countryCode`, `phoneNumber`, `notes` | corresponding columns |
| brokers timestamps | `created_at`, `updated_at` |
| watchmen document ID / parent UID / `userId` | `watchmen.id` / `owner_id` |
| watchmen `name`, `countryCode`, `phoneNumber`, `buildingName`, `notes`, `buildingLocation` | corresponding columns |
| watchmen pickup fields | corresponding pickup columns |
| watchmen timestamps | `created_at`, `updated_at` |

Nullable Dart `userId` and timestamps in offices/brokers/watchmen should become non-null database ownership/timestamps. Services already supply the current user and server time.

### Favorites

| Firestore/Hive field | PostgreSQL/local target |
|---|---|
| document ID `{type}_{itemId}` | not authoritative; composite target key |
| `itemId` | target FK |
| `type` | union-view `entity_type` / table choice |
| `addedAt` | favorite table `added_at` |
| cached `title`, `subtitle`, `imageUrl`, `thumbnailUrl`, `entityData`, `cachedAt` | Hive projection only; derive from target row/media, do not persist server-side |

Legacy `user_favorites/{uid}.propertyIds[]` has no selected baseline mapping. If the top-level property feature is confirmed active, it requires a separate architecture decision and schema revision.

### Quotations

Every `QuotationModel` field maps to the same snake-case column in `quotations`, except:

- `date`, `startDate`, `endDate` → `display_date`, `start_date_text`, `end_date_text`.
- `officeLogoUrl` → `office_logo_media_id`.
- `pdfUrl` → `pdf_media_id`.
- `downpayments[]` → `quotation_downpayments(method, sequence_number, due_at, amount)`.
- `governmentFees` map (`percentOfTotalRent`, `municipality`, `electricity`, `sewerage`, `total`) → one `quotation_government_fees` row.
- `administrativeFees.fees[]` (`title`, `amount`) → ordered `quotation_administrative_fees` rows. Its embedded `total` should be calculated or stored only if a contractual snapshot is required.

`paymentType` is separate from each downpayment `method`; keep both until their semantics are confirmed.

### Feedback

`id`, parent/auth `userId`, `userName`, `userEmail`, `rating`, `comment`, `createdAt`, `appVersion`, `platform`, `deviceInfo`, and `status` map respectively to `feedback.id`, `owner_id`, snapshot columns, rating/comment, timestamp, app/platform/device columns, and enum status.

### Notifications and FCM tokens

All `NotificationModel` fields map directly to snake-case notification columns. The Firestore parent UID becomes `recipient_id`. Firestore `readAt`, written by the repository but absent from the Dart model, maps to `notifications.read_at`. The open `data` map remains JSONB.

FCM token document ID/token maps to a protected device token record. `platform`, `updatedAt`, `deviceName`, and `locale` map to `push_devices`; token rotation should upsert and update `last_seen_at`.

### Other collections

- `properties`: fields `category`, nested `location.latitude/longitude`, `price`, and `imageUrl` have no selected baseline mapping; the top-level property feature must be confirmed or rejected first.
- `app_config/latest_version`: map observed version fields to `app_versions`; confirm exact environment data before implementation.
- `audit_logs`: retain action/actor/target/timestamp as columns and variable details as JSONB.
- `idempotency_tokens`: map to expiring `idempotency_keys`.
- Toolkit collections have no baseline PostgreSQL mapping until their persisted payloads and retention behavior are inspected.
- Current transcoding job documents have no baseline PostgreSQL mapping unless HLS is explicitly retained and separately designed.

## RLS policy design

Enable and force RLS for every table in `public`. The matrix below is the required policy contract. “Owner” always means the row owner equals `auth.uid()`; a child is owned only when its parent row is owned. Column-level grants or protected RPCs must prevent updates to `owner_id`, `version`, trusted timestamps, verification flags, provider state, counters, and processing status.

| Public table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profiles` | Own row only: `id = auth.uid()` | No client policy; trusted auth bootstrap only | Own editable profile columns only; `id` immutable | No client policy; account-deletion backend only |
| `revenuecat_entitlements` | Own rows only | No client policy | No client policy | No client policy |
| `plan_limits` | Authenticated read | No client policy | No client policy | No client policy |
| `usage_counters` | Own rows only | No client policy | No client policy | No client policy |
| `revenuecat_webhook_events` | No authenticated-client policy | No client policy | No client policy | No client policy |
| `requests` | Own rows, including tombstones needed for sync | Owner only; `owner_id = auth.uid()` | Owner only; `owner_id` immutable; optimistic `version` check | No hard-delete client policy; owner soft-deletes by setting `deleted_at` |
| `request_areas` | Only through owned request | Only through owned request | Only through owned request | Only through owned request |
| `offers` | Own rows, including tombstones needed for sync | Owner only | Owner only; `owner_id` immutable; optimistic `version` check | No hard-delete client policy; owner soft-deletes by update |
| `offer_areas` | Only through owned offer | Only through owned offer | Only through owned offer | Only through owned offer |
| `owners` | Own rows, including tombstones | Owner only | Owner only; immutable owner/version check | No hard-delete client policy; soft-delete by update |
| `offices` | Own rows, including tombstones | Owner only | Owner only; immutable owner/version check | No hard-delete client policy; soft-delete by update |
| `brokers` | Own rows, including tombstones | Owner only | Owner only; immutable owner/version check | No hard-delete client policy; soft-delete by update |
| `watchmen` | Own rows, including tombstones | Owner only | Owner only; immutable owner/version check | No hard-delete client policy; soft-delete by update |
| `media_objects` | Own metadata rows; never credentials/presigned URLs | No direct client policy; protected upload backend only | No direct client policy; protected finalize/delete backend only | No direct client policy; cleanup backend only |
| `offer_media` | Through owned offer and owned media | No direct client policy; protected media backend | No direct client policy; protected media backend | No direct client policy; protected media backend |
| `owner_media` | Through owned owner record and owned media | No direct client policy | No direct client policy | No direct client policy |
| `quotation_media` | Through owned quotation and owned media | No direct client policy | No direct client policy | No direct client policy |
| `profile_media` | Own profile attachment only | No direct client policy | No direct client policy | No direct client policy |
| `favorite_offers` | Own favorites whose target is also owned | Owner only and target owner must equal `auth.uid()` | No client policy; row is immutable | Owner only |
| `favorite_requests` | Own favorites whose target is also owned | Owner only and target owner must equal `auth.uid()` | No client policy | Owner only |
| `favorite_owners` | Own favorites whose target is also owned | Owner only and target owner must equal `auth.uid()` | No client policy | Owner only |
| `favorite_offices` | Own favorites whose target is also owned | Owner only and target owner must equal `auth.uid()` | No client policy | Owner only |
| `favorite_brokers` | Own favorites whose target is also owned | Owner only and target owner must equal `auth.uid()` | No client policy | Owner only |
| `favorite_watchmen` | Own favorites whose target is also owned | Owner only and target owner must equal `auth.uid()` | No client policy | Owner only |
| `quotations` | Own rows, including tombstones | Owner only | Owner only; immutable owner/version check | No hard-delete client policy; soft-delete by update |
| `quotation_downpayments` | Only through owned quotation | Only through owned quotation | Only through owned quotation | Only through owned quotation |
| `quotation_government_fees` | Only through owned quotation | Only through owned quotation | Only through owned quotation | Only through owned quotation |
| `quotation_administrative_fees` | Only through owned quotation | Only through owned quotation | Only through owned quotation | Only through owned quotation |
| `feedback` | Own submissions only | Owner only, with user snapshot fields derived/validated | No client policy; processing status is server/admin-only | No client policy |
| `notifications` | Recipient only | No client policy; trusted notification backend only | Recipient may update only `is_read`/`read_at` | Recipient only, if product retains delete behavior |
| `push_devices` | No raw-token client policy | No client policy; protected registration backend | No client policy; protected registration backend | No client policy; protected unregister backend |
| `app_versions` | Authenticated read; public read only if pre-auth startup requires it | No client policy | No client policy | No client policy |
| `idempotency_keys` | No authenticated-client policy | No client policy | No client policy | No client policy |
| `audit_logs` | No ordinary authenticated-client policy; separately authorized admin read | No client policy | No client policy | No client policy |

Server-only tables with no authenticated-client write policy are `revenuecat_entitlements`, `plan_limits`, `usage_counters`, `revenuecat_webhook_events`, `media_objects`, all four media attachment tables, `push_devices`, `app_versions`, `idempotency_keys`, and `audit_logs`. Notifications and feedback are partially server-owned as specified above.

Security-definer functions must set a safe `search_path`, validate `auth.uid()`, grant execute only to intended roles, and never accept an unverified owner UUID. RLS is not a replacement for R2 authorization: every sign/finalize/delete request must separately verify the database owner and media state.

## Push notification dependency decision

The current mobile push client is `firebase_messaging`, and the server targets FCM tokens stored in `users/{uid}/fcmTokens`. Moving Firestore, Auth, Storage, and Functions does not replace that client. Removing `firebase_messaging` would remove the current FCM registration/receive path; push notifications would stop unless another push implementation had already been built, configured, and verified.

Recommended approach: retain `firebase_core` plus `firebase_messaging` as the only remaining Firebase Flutter capability during and immediately after backend cutover, while moving token registration to the protected `push_devices` backend and sending through a trusted FCM server integration. This isolates push from the database migration and minimizes simultaneous risk. If the requirement is zero Firebase packages, selecting and implementing another APNs/Android push provider/client is a production-launch blocker and must precede removal. In-app notifications can use Supabase Realtime/polling, but that does not deliver background OS push and is not a silent substitute for FCM.

## Authentication migration design

Authentication must not change in the first implementation stages.

1. Introduce backend-neutral session/user interfaces while Firebase remains authoritative. Remove direct `FirebaseAuth.instance` access incrementally behind adapters, without changing behavior.
2. Create Supabase profile IDs only when a Supabase Auth user exists. Because current Firebase data is test-only, use a clean account cutover rather than attempting password-hash migration.
3. Configure required Supabase Auth providers and redirect/deep-link settings for email/password, Google, Facebook, and phone OTP. Confirm provider availability, SMS provider, regional/compliance needs, and account-linking semantics.
4. Reproduce email verification, password reset, reauthentication-sensitive email change, phone linking, account deletion, and offline-session behavior in a staging build.
5. During a bounded compatibility period, Firebase packages/code stay present behind a feature flag. Do not operate two writable identity authorities for the same user unless an explicit identity-link table and rollback procedure are designed.
6. At cutover, users create/sign in to new Supabase accounts. `profiles.id = auth.uid()`. Server trigger/bootstrap creates the profile, and authenticated setup captures missing name/phone preferences.
7. Only after adoption/rollback criteria are met should Firebase Auth and lookup-document code be retired.

Open concern: Supabase UUIDs will not equal Firebase UIDs. Since data is test-only, clean records avoid an identity mapping. If any data must be retained, add a private `legacy_identity_links(firebase_uid, supabase_user_id)` table and a controlled import.

## Cloudflare R2 media design

The existing `broker-wallet-media` bucket remains private.

- Store objects under immutable owner-scoped keys, for example `users/{supabase_uid}/{entity_type}/{entity_id}/{media_uuid}/original.ext`; thumbnails/variants use sibling keys.
- Store only the permanent bucket/object key and metadata in PostgreSQL. Never store an upload or download presigned URL.
- A trusted Edge Function/API issues short-lived presigned PUT/GET URLs after authenticating the Supabase JWT, validating `owner_id`, MIME type, extension, size, entity, and quota. R2 secrets remain server environment variables.
- Upload lifecycle:
  1. Protected `prepare` creates a `media_objects` row in `pending_upload` with permanent object key/expected metadata and returns a short-lived upload URL.
  2. A successful R2 upload advances the row to `uploaded` only through protected `finalize`.
  3. `finalize` performs a server-side HEAD/metadata check, validates size/type/checksum where available, creates the concrete attachment row, and advances to `ready`.
  4. A validation or non-retryable processing failure sets `failed` and records only a sanitized operational error outside client-writable columns.
  5. Deletion advances `ready`/`failed` to `pending_delete`; a protected worker removes the R2 object and then sets `deleted` plus `deleted_at`. Metadata is retained as a tombstone until the sync/retention window expires.
- A scheduled orphan worker finds expired `pending_upload`, `uploaded`, and `failed` rows without a valid attachment. It checks R2, deletes any object, and tombstones the row. The retention interval is a production-launch decision.
- Prepare, finalize, and delete use stable media UUID/idempotency keys. Retrying the same operation returns the same state rather than creating another object.
- Generate thumbnails/transcodes in a worker. If HLS is retained, write manifests/segments to R2 and track job state; otherwise remove the inactive transcoding design only in the eventual Firebase-removal stage.
- Preserve original filename only as metadata. Use generated keys to avoid traversal/collision and set explicit content type/disposition.
- Cache signed GET URLs only until shortly before expiry. Hive maps stable `media_id`/object identity to local files rather than mapping Firebase download URLs.
- Profile, offer, owner, quotation logo, and quotation PDF use the same media catalog with concrete attachment tables. Toolkit attachment tables are deferred until toolkit payloads are inventoried.
- R2 CORS must eventually allow only intended application origins/methods/headers, but remote configuration is outside this task.

## Offline Hive synchronization design

### Current behavior

- Firestore itself has persistent unlimited caching and snapshot listeners.
- `FirestoreUserRepository` and `FirestorePropertyRepository` explicitly read cache first, then server with timeouts.
- Hive boxes include `pending_uploads`, `local_media`, `url_mapping`, `pending_profile_uploads`, `local_profile`, `cached_favorites`, `analytics_cache`, `saved_items_offline`, and `user_data_offline`.
- `OfflineAuthService` stores a cached user model (SharedPreferences).
- `FastMediaUploadService` and quotation/profile upload paths save local data and files, enqueue uploads, write placeholder `local://` URLs/status, then update Firestore after Firebase Storage succeeds.
- `OfflineMediaService` maps remote Firebase URLs to local paths and cleans old files; its connectivity check is a TODO and currently returns `false`.
- Favorites use a denormalized Hive adapter and cache-first UI. `OptimisticFavoritesService` has an in-memory offline queue and simplified connectivity state, so the queue is not durable across process death.
- Analytics and counts are cache-first projections, not authoritative stores.

### Target behavior

Use Hive as a durable local projection/outbox, not an independent source of truth:

- `entity_cache`: key `{userId}:{entityType}:{id}`, server row JSON, `server_updated_at`, `last_synced_at`, schema version.
- `mutation_outbox`: client-generated UUID operation ID, user ID, entity/table, client-generated record UUID, operation (`insert`, `update`, `soft_delete`, `favorite_add`, `favorite_remove`), payload, expected base version, attempts, next retry, state, last error, created time.
- `media_outbox`: local path, client-generated media UUID, target entity/role/order, checksum, size/MIME, permanent R2 object key after prepare, server media state, upload attempt ID, attempts, next retry, last error.
- `sync_cursor`: per user/table last successful cursor. Prefer `(updated_at,id)` cursor ordering.

Rules:

- Namespace every cache/outbox key by authenticated Supabase user; encrypt sensitive cached data if the threat model requires it.
- Never replay an outbox belonging to a different signed-in user. Signing out clears session-sensitive caches or locks them until the same user returns.
- Assign UUIDs client-side for every offline-creatable entity, favorite operation, and media upload. Retries send the same record/operation UUID and idempotency key.
- Apply optimistic local changes immediately, then retry with exponential backoff and jitter when real connectivity plus a lightweight authenticated health check succeeds.
- Every synchronized mutable server row uses **proposed operational fields** `version bigint`, `updated_at timestamptz`, and `deleted_at timestamptz null`. An update supplies the cached expected version; the server atomically increments the version. A delete is an update that sets `deleted_at`, so pull sync receives a tombstone. Physical purge occurs only after the documented tombstone retention window.
- Conflict resolution is exact by operation type: duplicate inserts with the same UUID are idempotent; favorite add/remove converges to the operation with the later accepted server version; a local update against a changed/deleted server row is rejected with the current row; ordinary contact/profile scalar conflicts default to server-wins and preserve the rejected local payload for user retry; quotation/offer/request conflicts require an explicit user choice between server and local versions because they contain financially or operationally meaningful data; a server tombstone wins over a stale update unless the user deliberately creates a new UUID.
- Realtime accelerates refresh but does not replace cursor-based reconciliation after reconnect/app resume.
- Cache signed R2 URLs separately with expiry. Local media mapping uses stable media IDs, not expiring URLs.
- Failed/interrupted media handling is exact: keep the original local file and the same media UUID; if upload URL issuance failed, retry `prepare`; if transfer was interrupted, query protected media status and either retry upload to the same object key with a new short-lived URL or proceed to finalize when R2 already has the expected object; if finalize failed, retry finalize without re-upload; if the backend marks validation `failed`, keep the local file and show a retry/remove choice; removing it enqueues idempotent protected deletion. Never attach a `pending_upload`, `uploaded`, `failed`, or `pending_delete` object to visible entity media.
- Migrate/version Hive adapters safely. Existing pending Firebase uploads must be drained or explicitly abandoned before switching upload backends.

## Recommended implementation stages

### Files expected to change in each stage

Each stage below identifies its expected file scope. These are forecasts, not changes authorized or performed by this planning task.

### Stage 0 — Baseline and decisions

Finalize ambiguous fields, provider requirements, quota rules, retention, admin model, and whether legacy `properties`/`user_favorites` and HLS are active. Add tests around current repository behavior. No auth changes.

Expected files: documentation/tests only; possibly CI configuration. Firebase source remains unchanged.

### Stage 1 — Local schema migrations and generated types

Create local-only Supabase migrations for enums, tables, FKs, checks, indexes, triggers, and RLS; add seed/test fixtures and schema tests. Review SQL before any later approved remote apply.

**Implementation status (2026-08-21): IN PROGRESS.** The baseline migration, local seed placeholder, pgTAP schema/RLS tests, and schema-decision record have been prepared in the repository. No hosted Supabase schema has been changed. Stage 1 remains open until `supabase db reset` and `supabase test db` pass on the developer workstation.

Expected files: `supabase/migrations/*.sql`, `supabase/seed.sql` if used, and database tests. Flutter/Dart backend adapters remain intentionally unchanged until the later interface/adapter stages.

### Stage 2 — Backend-neutral data interfaces

Expand repository interfaces to cover the six domain sections, favorites, quotations, feedback, media, notifications, subscriptions, and sync. Route direct Firebase calls behind current Firebase adapters while preserving compile/runtime behavior.

Expected files: `lib/src/repositories/**`, new interface/DTO files, screen services and direct-access view models, dependency injection/provider setup, tests.

### Stage 3 — Supabase data adapters behind feature flags

Add Supabase client configuration using public URL/anon key only, implement PostgreSQL repositories and Realtime subscriptions, conversions, and local sync engine. Firebase remains available as rollback.

Expected files: `pubspec.yaml`, `pubspec.lock`, bootstrap/config files, Supabase repository implementations, model mappers, Hive adapters/generated files, services/view models, tests. Platform files only if deep links are needed later.

### Stage 4 — R2 media path

Implement server-side signing/finalization/deletion and client R2 upload/download/cache behavior. Migrate entity fields to stable media records while retaining compatibility reads for Firebase URLs.

Expected files: Supabase Edge Functions/server code, local migrations for media if not in Stage 1, media/upload/cache services, entity/quotation/profile view models/widgets, tests, and environment documentation. No secret files.

### Stage 5 — Notifications and Function replacements

Replace matching, quota, reminders, app-version checks, feedback administration, device registration, and reconciliation with PostgreSQL functions/triggers, Edge Functions, scheduled jobs, and a chosen push provider. Keep raw push credentials server-only.

Expected files: migrations, Edge Functions, notification/quota/app-version services and repositories, Flutter notification bootstrap/settings, server tests, deployment documentation.

### Stage 6 — RevenueCat subscriptions

Define products/entitlements, add client SDK configuration with public platform keys, implement authenticated customer identity, webhook verification/idempotency, and server-owned subscription projection. Replace manual plan writes.

Expected files: `pubspec.yaml`, subscription/payment view models/views, Supabase function/migration code, configuration docs, tests. Secret webhook/API keys exist only in managed server secrets.

### Stage 7 — Authentication migration

Implement Supabase Auth adapter and all required provider flows behind a flag, validate account linking/deep links/session recovery, then perform clean test-user cutover. Authentication changes only begin here after explicit approval.

Expected files: auth repositories/services/view models/screens, bootstrap, Android/iOS deep-link and provider configuration, Supabase auth hooks/functions, profile setup, tests.

### Stage 8 — Cutover and Firebase retirement

After rollback metrics and acceptance tests pass, stop Firebase writes, remove compatibility paths, then remove Firebase packages/code/config/Functions in a separate reviewed change. Validate all target platforms and offline recovery before deletion.

Expected files: `pubspec.*`, Firebase Dart files/imports, `functions/`, Firebase rules/config, Android/iOS Firebase configuration, generated registrants after Flutter regeneration, tests/docs. This is the only stage that removes Firebase.

## Risks and unresolved questions

### Baseline SQL blockers

Only these unresolved questions block a complete first baseline migration:

1. Confirm whether the top-level `properties`/`user_favorites` feature is active. If it is active, its missing ownership model must be designed and added to the baseline inventory; otherwise it remains excluded.
2. Define parsing and currency rules for string-valued `minPrice`, `maxPrice`, and `squareFootage` before using the selected numeric columns and checks.
3. Confirm the exact stored values for `requestType` and `offerType` before creating their enum/check constraints.
4. Decide whether `AdministrativeFees.total` and `GovernmentFees.total` are calculated outputs or authoritative stored snapshots.
5. Define RevenueCat plan-code derivation, quota sections, limit values, and reset-period representation required by `plan_limits` and `usage_counters`.
6. Confirm the exact `app_config/latest_version` payload before finalizing `app_versions`.

`propertyType`, `specificPropertyType`, and `typeOfProperties` remain text in the first migration, so their future vocabularies do not block SQL. `matchScore` remains nullable numeric without a range check until its scale is confirmed. Favorites use the selected same-owner policies in the first migration; future sharing is a later schema/RLS change.

### Optional-feature SQL blockers

These do not block the baseline migration because their tables are excluded from the final inventory:

1. Inventory the persisted payloads for `scanner`, `signature`, `imageToPdf`, and `combinePdfs` before proposing toolkit artifact tables.
2. Decide whether HLS/transcoding is retained and inventory its job payload before proposing transcoding tables.

### Flutter implementation blockers

1. `selectedCity`, `selectedAreas`, `location`, pickup location, and pickup address overlap; adapters/UI must define which inputs populate canonical searchable text versus display text.
2. Firestore reads default absent coordinates to `0.0`; Flutter mapping must send/read null for absent target coordinates rather than treating Null Island as a location.
3. Legacy request status `available` currently normalizes to `active`; compatibility mapping must preserve that behavior.
4. `favorites_repository.dart` is empty and the live favorites service bypasses repository injection; a backend-neutral interface is required.
5. Notification `readAt` is written but absent from `NotificationModel`; the model/repository contract must include it when implementation begins.
6. Quotation date/start/end values are display strings; Flutter must keep them as strings until a validated locale/timezone conversion is designed.
7. `paymentType` and per-downpayment `method` overlap; UI/domain semantics must be documented before mapper implementation.
8. `MediaFileModel` has useful metadata but no clearly active collection; the R2 adapter must decide whether to evolve it into the new media DTO without changing current behavior prematurely.
9. Current offline connectivity and favorites queues are incomplete/in-memory. The durable outbox, user namespacing, version conflict UI, tombstones, and interrupted-media flow must be implemented.
10. Supabase Realtime is only an accelerator; Flutter must implement cursor reconciliation and cannot assume Firestore offline semantics.

### Production-launch blockers

1. Decide whether FCM remains via `firebase_core`/`firebase_messaging` or implement and verify a replacement. Removing the current client without a replacement stops push notifications.
2. Configure and verify RevenueCat products, entitlements, offerings, webhook verification, restore behavior, customer identity, and production/sandbox separation.
3. Confirm Supabase Auth parity and external configuration for email/password, Google, Facebook, phone OTP/SMS region, verification, account linking, reset, and deletion.
4. Confirm that Firebase test data can be discarded. If anything must be retained, implement a private Firebase UID-to-Supabase UUID migration mapping.
5. Select the protected R2 backend runtime, set upload limits, define orphan/tombstone retention, and test authorization, retry, cleanup, and CORS.
6. Define tombstone retention, audit/webhook retention, cache encryption policy, conflict UX, and cross-user/device sign-out behavior.
7. Test the effective current Firestore rules, which contain duplicate/broad matches, so security parity is measured rather than assumed.
8. Inventory current Firebase Storage test objects and inconsistent paths before eventual cleanup; the quotation logo path is not clearly represented in existing rules.

### Non-blocking improvements

1. Consider controlled city/area reference tables and PostGIS after current display/search semantics are stable.
2. Consider collaboration/shared-contact policies later; the selected initial RLS remains private-owner-only.
3. Consider replacing stored fee totals with generated/reporting views once contractual requirements are known.
4. Consider full-text/trigram search refinements after query telemetry exists.
5. Consider removing dormant HLS and legacy property code during the final Firebase-retirement stage if confirmed unused.

## Acceptance criteria for later implementation

- Flutter compiles at the end of every stage, with Firebase still available until Stage 8.
- No secret is stored in Dart, Git, logs, database client-readable rows, or generated artifacts.
- Database tests prove cross-user isolation and trusted-field protection.
- Media tests prove one user cannot sign/read/delete another user's private R2 object.
- Offline tests cover process death, user switching, duplicate replay, conflicts, hard deletes, expired signed URLs, and long disconnection.
- Auth tests cover every existing flow before cutover.
- A documented rollback flag exists until Firebase retirement is explicitly approved.
