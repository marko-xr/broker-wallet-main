Branch:
recovery-profile-auth

Recovery baseline started from:
cc0951e

Verified Supabase-mode device behavior:

- Signup: PASS
- Home: PASS
- Profile: PASS
- Cold restart while authenticated: PASS
- Manual logout: PASS
- Restart after logout remains unauthenticated: PASS
- Login again: PASS

Completed recovery fix:
Notification token cleanup is best-effort and can no longer prevent authoritative
Supabase logout.

Authoritative logout verification observed:

- Supabase logout completed
- Supabase session after logout absent
- AuthViewModel unauthenticated

Recovery Step 2 — PASS

Verified on hosted Supabase:

- public.notifications is in the supabase_realtime publication.
- migration 20260822000500_add_notifications_to_realtime.sql was applied.
- RealtimeSubscribeException for public.notifications is gone on real device.
- Supabase logout remains PASS.

Important newly confirmed problem:

- Normal `flutter run` still defaults Auth/Profile to Firebase because
  `USE_SUPABASE_AUTH` defaults false.
- Supabase currently requires URL + publishable key dart-defines.
- In Supabase mode, startup map preload still performs Firestore reads for
  offers/owners/offices/watchmen.

NEXT STEP ONLY:
Recovery Step 3 — make Supabase the normal default Auth/Profile runtime and
stop only those startup Firestore map-preload reads.

DO NOT mark Step 3 complete.

DO NOT TOUCH YET:

- Profile save/name
- Profile image/R2
- password
- phone/OTP
- delete account
- Search
- Favorites
- unrelated router/auth changes
