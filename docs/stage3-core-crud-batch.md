# Stage 3 Core CRUD Batch

This batch switches the six core Broker Wallet entity services to Supabase when
`USE_SUPABASE_AUTH=true` while preserving the existing Firebase implementations
when the flag is false.

Covered in this batch:

- Requests: create, read/list, edit, status update, soft delete, request areas.
- Offers: create, read/list, edit, status update, soft delete, offer areas.
- Owners: create, read/list, edit, soft delete.
- Offices: create, read/list, edit, soft delete.
- Brokers: create, read/list, edit, soft delete.
- Watchmen: create, read/list, edit, soft delete.
- List refresh behavior after mutations.
- The previous Request-list migration guard is removed because Request writes
  now have a Supabase implementation.

Security behavior:

- Operations use the authenticated Supabase session and the existing RLS rules.
- Core entities use `deleted_at` soft deletion; client hard delete remains
  unavailable by design.
- Firebase behavior is unchanged when `USE_SUPABASE_AUTH=false`.

Not included yet:

- Cloudflare R2 media writes. In Supabase-auth mode, Offer/Owner creation with
  selected media fails explicitly instead of silently uploading to Firebase or
  discarding the files. Creating those records without media is supported.
- RevenueCat-backed quota enforcement.
- Quotations, Favorites, Search, Map aggregation, Notifications, and Feedback
  full Supabase migration.

Recommended batch checkpoint:

1. `flutter analyze --no-fatal-infos --no-fatal-warnings`
2. Run with Supabase auth enabled.
3. Open Requests and confirm the existing test Request is visible.
4. Add/edit/delete one Request.
5. Add one Broker and one Office, reopen their lists, edit them, then soft-delete.
6. Add Offer/Owner without media for this checkpoint.
7. Confirm Home counts update after a fresh Home load.

Current smoke-test path:

- Run the CRUD smoke test on Flutter Web at `http://localhost:3000` so Android
  build-tooling incompatibilities do not block functional validation.

Next production batch — P0:

- Align the Android Gradle Plugin and Gradle versions with the Flutter toolchain
  and all Android plugins. The current AGP 9+ / Gradle 8.11.1 combination fails
  for plugins such as `flutter_local_notifications` with errors including
  `Configuration 'implementation' not found` and `Failed to create transforms`.
- Validate the alignment with a clean dependency resolution and a successful
  Android debug/release build; rerun the CRUD smoke test on Android before
  production release.
- Migrate Cloudflare R2 media before enabling media-dependent Offer/Owner
  workflows for release.
