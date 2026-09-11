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
