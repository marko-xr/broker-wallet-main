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

Current known issue:
Supabase notifications Realtime subscription throws RealtimeSubscribeException.
public.notifications is not currently in the supabase_realtime publication.

NEXT STEP ONLY:
Recovery Step 2 — notifications Realtime subscription only.

DO NOT TOUCH YET:

- Profile save/name
- Profile image/R2
- password
- phone/OTP
- delete account
- Search
- Favorites
- unrelated router/auth changes
