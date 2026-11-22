# Phone account security design (C2, 2026-11-22; Model X approved and implemented locally in C3)

Scope: the account-linking policy (P-A2 review), Phone Change and Delete Account for phone accounts.
Evidence is Supabase Auth (GoTrue) source at the hosted tag **v2.198.0**
(`https://github.com/supabase/auth/blob/v2.198.0/…`) plus this repository.

**Status after C3 (2026-11-22):** the owner chose **Model X** (section 2). Implemented locally, uncommitted, nothing
hosted:
- migration `20261122130000_phone_identity_model_x.sql` (guard, sign-in methods, verification records, grants) with
  pgTAP `phone_identity_model_x_test.sql`, rollback-only validation and rollback scripts;
- Worker `phone_verification.js`: `/account/contact-phone/start|confirm` and `/account/phone-identity/start|confirm`
  (section 3 used the working names `/account/phone/change/*`). No provider is chosen; the routes answer 503
  `verification_unavailable`;
- the app's Add Phone uses the contact-number routes; Add Email sets the password only after confirmation.

**Status after C4 (2026-11-22):** Delete Account for phone accounts (section 4) is implemented locally:
migration `20261122140000_phone_account_deletion.sql` (session-bound, single-use challenges),
`POST /account/delete/challenge` and `POST /account/delete { code }` in `account_deletion.js`, and the code step in
the Delete Account sheet. Change Phone has its screen (number dialog + two-code dialog) on the C3 routes. The Model X
rollback now keeps sign-in methods and contact numbers in a backup that a re-apply restores. Still uncommitted and
not hosted. Every hosted step needs the owner's explicit approval.

## 1. Facts that decide the design

| # | Fact | Evidence |
|---|---|---|
| E1 | A `phone_change` confirmation does **not** need the account's session: `POST /verify` finds the user by the pending number and issues a **new session** to whoever sends the code. | `internal/api/verify.go` (`verifyUserAndToken` → `FindUserByPhoneChangeAndAudience`; `verifyPost` → `issueRefreshToken`) |
| E2 | SMS sign-in, `phone_change` confirmation, implicit email links (`GET /verify`) and email/token_hash codes all issue tokens with the same method `otp`. A token hook cannot tell them apart. | `verify.go` `verifyGet`/`verifyPost`; `internal/hooks/v0hooks` input |
| E3 | `PUT /user {phone}` ignores the Phone-provider switch; the SMS is sent before the database write, so a trigger can stop the change but not the SMS. | `internal/api/user.go`, `internal/api/phone.go` |
| E4 | A Custom Access Token hook runs for **every** issuance including refresh; an error the hook does not catch itself (missing function, revoked grant, 2 s timeout, `query_canceled`) fails password sign-in and refresh for everyone. | `internal/tokens/service.go`, `internal/hooks/hookspgfunc` |
| E5 | `resend(type: phone_change)` looks the account up by its **confirmed** phone. For a first phone (`auth.users.phone` empty) it finds nothing and returns success without sending. | `internal/api/resend.go`; app `SupabaseAuthRepository.resendPhoneVerification` |
| E6 | Hosted today: Twilio configured, Phone provider off, 0 phone numbers, 5 email accounts. | A0 read-only check |

**Consequences for the existing Add Phone flow (pre-existing, CODE_PROVEN, never runtime):**
- **F-AP-1 (High):** whoever receives the code for a pending number (a mistyped number, a recycled number) can obtain a
  session for the email account by E1, claim Single Active Device and read its data. This is reachable whenever the
  SMS provider actually delivers (E3, E6).
- **F-AP-2 (Medium):** the Add Phone "resend" never sends a code (E5) yet reports success.

## 2. Account-linking policy — decision proposal

**P-A2 as written is not recommended.** An independent review (2026-11-22) found:
- It cannot separate SMS sign-in from email links or codes (E2). It would refuse implicit recovery or magic links,
  and email OTPs, for email accounts with a phone.
- It puts every sign-in and refresh behind a hook whose uncaught failures lock out all users (E4).
- It still lets the holder of a newly verified number receive a session (E1).

**Recommended: Model X — "one sign-in identifier per account".**
1. **Phone-primary accounts** (created by phone): Supabase OTP is their sign-in. Possession of the number is the
   identity (inherent, accepted).
2. **Email-primary accounts never hold `auth.users.phone`.**
   - A database guard refuses `phone`/`phone_change` for them, using a primary-method flag fixed when the account is
     created.
   - So no SMS sign-in is possible for them by construction: GoTrue finds no user for that number.
3. **Their verified phone is a contact attribute.**
   - It is verified by a Worker for the **signed-in, Single-Active-Device-current session only**, through the SMS
     provider's verification API.
   - It is stored in `profiles` by the service role and is never a login identifier.
4. **Phone-primary number change** goes through the Worker and the Auth Admin API (section 3), never through the
   unbound `phone_change` flow.

Trade-offs:
- It supersedes the DECISIONS line "phone verification stays on Supabase Auth's own phone-change flow" **for email
  accounts**; that is an owner decision.
- The provider adapter can only be written after the SMS provider is chosen.

Rejected:
- **P-B** (any confirmed phone signs in): fails the SIM-swap goal.
- **Claim-only refusal:** the refused GoTrue session can still change password, email, phone and identities.
- **MFA phone factor:** a paid add-on, and it forces AAL2 on later email, password and phone changes.

Fallback, only if Model X is refused: P-A2 with all six review changes:
- a creation-time primary flag;
- a same-transaction confirmation signal (an `AFTER UPDATE OF phone_change` trigger setting a transaction GUC) instead
  of a time window;
- refusal only for email-primary accounts with a confirmed phone and no signal;
- no writes in the hook;
- `raise log` on refusal;
- a disable-before-drop runbook.

It keeps residual F-AP-1.

## 3. Phone Change — final design (phone-primary accounts)

Server-authoritative, Worker-mediated, Supabase Admin API for the write.
1. `POST /account/phone/change/start {newPhone}`.
   - The Worker checks:
     - the verified identity (`/auth/v1/user`);
     - `is_current_app_session` (a superseded or stolen session is refused);
     - no recovery `amr`;
     - a UAE mobile target that no other account holds.
   - **Proof of the current number:** the Worker requests a Supabase sign-in code for the confirmed phone (taken from
     the identity, never from the client; `create_user:false`). A password is accepted instead when the account has an
     email identity.
   - **Proof of the new number:** the Worker asks the provider's verification API to send a code to `newPhone`.
   - It stores a single-use change record: user, session id, target, expiry 10 min, attempt counter.
     Service role only.
2. `POST /account/phone/change/confirm {currentCode|password, newCode}`.
   - The same checks run again, on the **same** session id as the record.
   - The current-number code is verified with `/auth/v1/verify` (`type=sms`, server-side); the check session it creates
     is revoked before anything else, and the uid must match.
   - The new-number code is verified with the provider's API.
   - Then `PUT /auth/v1/admin/users/{id} {phone, phone_confirm:true}`, and the record is consumed.
   - No session is ever issued to the holder of either number.
3. **Replay and concurrency:**
   - The record is consumed with one conditional `UPDATE … WHERE consumed_at IS NULL RETURNING`.
   - Supabase clears its code on use.
   - Provider codes are single-use.
   - The attempt cap is 5.
4. **SMS cost:** at most one current-number code and one new-number code per record, within Supabase's 60 s per-user
   limit plus provider limits. UAE-only targets.

## 4. Delete Account — final design (phone-primary accounts)

Primary-method based. Email-primary accounts keep the **existing password path unchanged**.
- **`POST /account/delete/challenge`:**
  - Checks: identity, `is_current_app_session`, no recovery `amr`, and a phone-primary account with a confirmed phone.
  - Action: the Worker requests a Supabase sign-in code for the confirmed phone, taken from the identity
    (`create_user:false`, `Sb-Forwarded-For`).
- **`POST /account/delete {code}`:**
  - Checks: the same, again.
  - Verification: `/auth/v1/verify type=sms` server-side, then `user.id === identity.id`.
  - The check session's revocation **must succeed** before `claimDeletionJob`; otherwise the request fails with 503.
  - After that, the existing deletion lifecycle runs unchanged.
- **A phone-primary account that later set a password** may use the password path instead (useful if the number is
  lost).
- **Proofs:**
  - The number comes from the verified identity, and `auth.users.phone` is UNIQUE, so the request cannot target
    another account.
  - Codes are single-use, and `account_deletion_jobs` is keyed by user, so there is no replay.
  - The check session is never claimed, so Single Active Device is not bypassed.
  - A stolen token cannot delete without the current SMS.
- **With the Phone provider off,** the challenge cannot send a code: the response says "temporarily unavailable". It
  never falls back to something weaker.

## 5. Interim protection (until section 2 is decided and built)

The Add Phone flow must not reach real users with real SMS while F-AP-1 is open. Options for the owner:
- (a) keep the SMS provider without production delivery, as today with a trial/unconfigured sender;
- (b) a guard migration refusing all `phone_change` requests;
- (c) Model X.

Phone sign-in stays off (`PHONE_AUTH_ENABLED=false`, Phone provider off).

## 6. Staging tests required before any enablement (isolated project, test numbers, never the shared project)

1. SMS sign-in to an email-primary account's number is impossible: no user is found, or the request is refused; no
   session, no SMS.
2. Email-primary flows all still work:
   - password sign-in and refresh;
   - PKCE sign-up, recovery and email-change links;
   - a Dashboard-sent recovery link.
3. Phone-primary sign-in, refresh and Single Active Device claim.
4. Phone change: a stolen or superseded session is refused. A wrong current or new code consumes attempts. A reused
   record is refused. No session is issued by any code.
5. Delete Account (phone-primary): a code is accepted once; replay, uid mismatch, superseded session and recovery
   session are refused; the check session is revoked.
6. Measure B1 hook error shapes and `user_metadata` content for a real `/otp` sign-up.
