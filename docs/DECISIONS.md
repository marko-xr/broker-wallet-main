# Durable decisions

- Migration is staged.
- Supabase is the canonical identity/profile authority in Supabase mode.
- Production media target is private Cloudflare R2.
- Do not weaken security.
- Require a real-device gate after every checkpoint.
- Use a one-small-change workflow.
- Facebook authentication is removed. Google and Apple sign-in are deferred.
- Phone verification stays on Supabase Auth's own phone-change flow. Real SMS
  provider setup is deferred until the business/trade license and UAE sender
  registration exist; paying for production SMS just to unblock development is
  not justified. Until then:
  - keep the existing Phone implementation and its database security as they
    are; do not remove or redesign them;
  - no fake SMS credentials, no custom OTP system, no weakening of Supabase
    Phone security;
  - no test OTP bypass unless chosen later as a separate development-only
    checkpoint;
  - unrelated work is not blocked on this external dependency.
- Only the stale `phone_change` cleanup is Supabase's documented mitigation for
  phone-change ambiguity. The write-time single-holder guard trigger is this
  project's own hardening on Supabase Auth's internal columns: re-run
  `supabase/validation/phone_security_validation.sql` after Supabase Auth
  upgrades.
- Existing-account Email Change uses Supabase Auth's native authenticated
  `updateUser(email)` flow. Do not add a current-password reauthentication step
  unless a future Supabase-supported configuration explicitly requires it.
- During Email Change, `auth.users.email` remains canonical and
  `User.newEmail` is pending presentation only. Never persist a competing
  client-side pending email or write `public.profiles.email` from Flutter.
- Supabase exposes resend for `email_change` but no supported server-side
  cancellation API in the pinned client. The app may close the form, but must
  not label that as cancelling a pending server request.
- Supabase auth deep links stay on automatic URI detection. The app narrows
  `detectSessionInUriPredicate` to links actually carrying `access_token` or
  `code` instead of disabling detection, so Supabase remains the only thing
  that exchanges a session while error-only and message-only callbacks are
  handled in the app. Never disable `detectSessionInUri` globally — signup
  email verification depends on Supabase exchanging its own link.
- An error delivered on Supabase's `onAuthStateChange` stream is not evidence
  that the session ended. Supabase republishes failed refreshes and every
  `AuthException` its deep-link observer catches onto that stream, so every
  subscriber must supply `onError`, and no subscriber may treat a stream error
  as a sign-out. An authoritative sign-out always arrives as a null identity.
- An auth callback is a trigger, never a source of truth. Under Secure Email
  Change the first confirmation returns only an informational `message` whose
  wording Supabase may change, so outcomes are always read back from the
  authoritative Supabase user rather than parsed out of the link.
- Under Secure Email Change, resending — and equally requesting a different
  address — calls GoTrue's `sendEmailChange`, which regenerates both
  confirmation tokens and resets `email_change_confirm_status` to 0. Older
  links stop working and any approval already given must be repeated; UI copy
  must say so. This is also why "Use a different email" is a legitimate
  recovery action while a fake "Cancel email change" is not.
