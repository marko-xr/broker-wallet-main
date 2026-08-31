# Stage 3 core CRUD runtime Firebase isolation

This patch fixes the remaining direct Firebase quota calls in the six core add flows when `USE_SUPABASE_AUTH=true`.

## Supabase mode
- Requests, Offers, Owners, Offices, Brokers, and Watchmen no longer touch Firebase Auth/Firestore before a Supabase create.
- The existing Supabase CRUD services and RLS remain the data path.
- Offer/Owner media remains intentionally blocked until the Cloudflare R2 batch.
- Final paid quota enforcement remains deferred until RevenueCat product/entitlement mapping and plan limits are finalized.

## Firebase fallback mode
The original Firebase quota check and counter increment behavior remains available through `CoreEntityQuotaBridge` when `USE_SUPABASE_AUTH=false`.
