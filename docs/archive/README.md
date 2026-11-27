# Documentation archive

Frozen history. Nothing here is the current status: read `docs/CURRENT_CHECKPOINT.md` for that.
Never edit an archived file; add new history to the topic document it belongs to.

## `CURRENT_CHECKPOINT_HISTORY_TO_2026-11-27.md`

The complete `docs/CURRENT_CHECKPOINT.md` as it stood until 2026-11-27, archived on 2026-11-28 (task 01E) when the
active checkpoint was replaced by a short status page.

Provenance, verifiable with Git:

| Part | Lines | Source |
|---|---|---|
| Everything up to Phone auth C4 | 1–18074 | `6951b29:docs/CURRENT_CHECKPOINT.md` (blob `1fc818c`), the version on `fix/import-path-casing` and its base `ceb488d` |
| Subscriptions, payments, web, store compliance, Task 01 / 01B backup | 18075–18323 | The 249 lines that WIP commit `2118fea` (branch `backup/subscriptions-payments-web-wip`) appended |

The file is byte-identical to `2118fea:docs/CURRENT_CHECKPOINT.md` (blob `fde0278`): `git hash-object` on it must print
`fde0278b902b5ee529aef7045628a07b390c4782`. `2118fea` only appended lines, so lines 1–18074 are byte-identical to the
`6951b29` version.

Rough map (line numbers in the archive):

| Lines | Period | Content |
|---|---|---|
| 1–2507 | 2026-08 to 2026-09 | Auth/profile recovery, Supabase signup/login/logout, profile name, R2 profile image, Email Change, Password, Delete Account |
| 2508–6136 | 2026-09 | Favorites acceptance, Offer private media, Owner private media |
| 6137–9589 | 2026-09-28 to 2026-10-05 | UI performance, Quotation save RPC and private media, form/chip UI, Search, Share, Home filters, Favorites UI |
| 9590–12340 | 2026-10-05 to 2026-10-13 | Quotation save performance, Single Active Device rollout (checklist #5), Owner media re-verification (#6) |
| 12341–13313 | 2026-10-12 to 2026-10-17 | Offer/Owner land-plan and plot-plan attachments (#7 closed) |
| 13314–15168 | 2026-10-17 to 2026-10-22 | Toolkit S1–S5 (Scanner, Combine PDFs, Images to PDF, Signature, UAE links), Toolkit cloud documents C1–C3.6 |
| 15169–15782 | 2026-10-23 to 2026-10-30 | Responsive layout hardening R1–R8A |
| 15783–16372 | 2026-10/11 | Firebase removal phases 1–7D, final pass, quota-bridge cleanup |
| 16373–16845 | 2026-11-02 to 2026-11-19 | List dividers, launch screen, Details port, small UI fixes, Notifications N1 |
| 16846–16931 | 2026-11-20 | Android identity `com.nmodigital.brokerwallet` |
| 16932–17745 | 2026-11-20 to 2026-11-21 | Notifications N2/N3: hosted validation, apply, push-dispatch, scheduler, Android acceptance, iOS readiness |
| 17746–18074 | 2026-11-22 | Phone auth B1, C1–C4 (Model X) |
| 18075–18323 | 2026-11-23 to 2026-11-27 | Subscriptions Profile UI, backend and quotas, payments (Tap, Google Play), Flutter Web, prices, store compliance, Task 01 backup, Task 01B restore plan |

Search it with `grep -n '^## ' docs/archive/CURRENT_CHECKPOINT_HISTORY_TO_2026-11-27.md` for the full heading list.
