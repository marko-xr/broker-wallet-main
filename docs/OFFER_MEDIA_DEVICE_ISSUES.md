<!--
Copied into the repository on 2026-09-26 from the owner's register
`BROKER_WALLET_OFFER_MEDIA_DEVICE_ISSUES_2026-09-26.md`. The register below is
kept as supplied. Live status, evidence and the diagnosis of Task A are in
`docs/CURRENT_CHECKPOINT.md`, section "OFFER MEDIA — SAMSUNG DEVICE FAILURE,
TASK A". Status at the time of copying:

- TASK A (P0): ACTIVE — root causes proven from device evidence, fixes
  implemented locally (CODE_PROVEN); Samsung acceptance NOT yet run.
- TASK B (P1): QUEUED — not started; begins only after Task A passes on device.
- TASK C: DEFERRED — private Offer documents, only if separately approved.

Status update, 2026-09-26 (evening):
- Ready-video network playback: VERIFIED_REAL_DEVICE — all five videos play
  (signed-URL extension defect fixed).
- Video seeking (A-UX-1): root cause proven (app overlays over a portrait
  video's seek bar), fixed, CODE_PROVEN — Samsung check pending.
- Saved-video posters (A-UX-2): root cause proven (frames existed only on the
  uploading device; a reinstall wiped them), fixed client-side, CODE_PROVEN —
  Samsung check pending.
- Debug diagnostics no longer print object paths, account ids or raw errors.
- TASK B requirements unchanged and still queued as the next separate
  checkpoint: multiple videos in one pick; one combined Gallery action for
  photos and videos; no redundant app-made permission popups; compact Camera /
  Gallery / Documents sheet; Documents not enabled for Offers until a secure
  document backend exists.

Status update, 2026-09-26 (late):
- Owner confirmed on Samsung (VERIFIED_REAL_DEVICE): five videos play, seeking
  works, saved-video thumbnails appear after reopening, signed-R2 playback
  defect resolved. Unverified reliability scenarios are pending as
  MEDIA-12…MEDIA-20 in the master test plan.
- TASK B: IMPLEMENTED, CODE_PROVEN (21 new tests) — Samsung acceptance
  pending. Gallery = one native Photo Picker selection of photos and videos
  (remaining-capacity limit), no app-made permission dialog and no
  media-library permission request; compact Camera (Photo/Video) / Gallery /
  Documents sheet; Documents shown as not available for Offers.
- TASK C (private Offer documents): still DEFERRED; not started.

Status update, 2026-09-27:
- Combined Gallery multi-selection: VERIFIED_REAL_DEVICE (five videos and five
  images in one operation).
- P0 disposed-controller crash: root cause proven (the shared player manager
  disposed a controller a mounted player still held); fixed with holder-counted
  ownership; 11 regression tests; Samsung check pending.
- Camera: the second Photo/Video sheet is removed; + → Camera opens an in-app
  camera with its own Photo / Video switch (owner-approved official `camera`
  package); 8 tests; Samsung check pending.

Status update, 2026-09-27 (later):
- In-app camera: FAILED on Samsung (crash after the permission grant in
  `camera_android_camerax`, releaseFlutterSurfaceTexture before the preview
  surface existed). Owner reversed the decision: no in-app camera; removed
  with the `camera` package and its manifest change.
- Camera now uses the phone's own camera app again (`image_picker`
  `pickImage` / `pickVideo` with `ImageSource.camera`), from two direct
  actions in the attachment sheet: Take photo and Record video. Output is
  screened and queued exactly like a Gallery pick. SOURCE ONLY; tests updated
  but not run; Samsung check pending.
- Gallery combined selection: unchanged, still VERIFIED_REAL_DEVICE.
- Disposed-controller fix: still pending the owner's device confirmation.

Status update, 2026-09-27 (owner acceptance):
- TASK A (P0): CLOSED — owner-accepted, VERIFIED_REAL_DEVICE: save and
  reopen with media, private playback, seeking, persisted thumbnails,
  switching videos with no disposed-controller exception.
- TASK B (P1): CLOSED — owner-accepted, VERIFIED_REAL_DEVICE: combined
  Gallery selection of videos and images, no redundant permission popup,
  system camera photo and video from two direct actions, no custom camera.
- Not owner-verified and kept open in the deferred master test plan:
  MEDIA-12…MEDIA-26 (interruption, restart, confirm idempotency, link expiry,
  removal, second account, server refusals, camera permission refusal,
  process death, on-device limits, iOS, sweeps, legacy full-screen viewer).
- TASK C (private Offer documents): still DEFERRED.
- Next independent checkpoint: Owner Media (not started).
-->

# Broker Wallet — Offer Media Device Issues & Separate UX Backlog

Date: 2026-09-26. Project is under development and has no real released users. Production-quality backend is used for development; do not interpret Worker production deployment as public app release.

## Verified checkpoint (not the same as device acceptance)
- Supabase hosted migration: `20260926092220_offer_media_confirm_rpc`, applied and verified.
- Worker staging E2E: **72 passed, 0 failed**. Test covered private JPEG/PNG/WebP/MP4, server duration, 206 range, retries/idempotency, removal, limit of 10, isolation.
- Worker production deployment: `ecaf125d-a0e3-4c26-add6-5f2c684c2516`, bucket `broker-wallet-media`, `OFFER_MEDIA_SWEEP_MODE=off`.
- Samsung Flutter acceptance: **FAILED / OPEN**. Do not declare Offer Media complete.
- No real users or public release. Owner Media remains out of scope.

## TASK A — P0: Fix real-device upload, local preview, and video playback. EXECUTE NOW.

### Reproduction supplied by owner
A Samsung device selected 5 images and 5 videos for an Offer. On reopening the Offer, some images showed a blurred placeholder or a circular percentage indicator for minutes; some subsequently resolved. Video uploads took a long time, some showed `توقف الرفع اضغط إعادة المحاولة للمحاولة مجددا`, and the viewer showed `لا يمكن تشغيل هذا الفيديو الآن. إعادة المحاولة` even after a long wait. The backend E2E used a 7.44 MiB MP4, not this mixed 10-item mobile workload.

### Diagnosis; prove exact cause rather than guess
1. Record Android version, connection type, app git HEAD, build mode, file sizes, duration, MIME and actual codec (no private file names in public logs). Check each video's size <=100 MiB and duration <=3 minutes, image <=10 MiB after conversion. Show clear immediate permanent rejection if a file fails policy.
2. Instrument ONE reproduction using sanitized events per `mediaObjectId`: selected/copied-local, queued, authorize/status, signed PUT start/end, bytes sent, HTTP status/error category, confirm outcome, database `media_objects.status` and `offer_media` link, list/GET, signed URL refresh, video player initialization/error/cause. Record aggregate duration and task-level elapsed time without printing tokens, credentials or full presigned URLs.
3. Read current implementation of `offer_media_upload_queue.dart`, `r2_offer_media_upload_service.dart`, `offer_media_selection.dart`, `offer_media_session.dart`, `offer_media_url_cache.dart`, details load coordinator, gallery/preview/video player widgets and lifecycle. Check queue owner scope, file persistence, state notification after await, stale controllers, navigation and app restart, retry deadline/backoff and classification.
4. Investigate 300-second signed PUT expiry, upload request timeout/cancel and whether retries re-authorize a fresh signed URL under the same media UUID; compare actual upload throughput and response codes. Do not widen TTL or introduce multipart just on intuition. R2 single PUT is non-resumable; only use multipart if measured real workload warrants it and the existing architecture remains private.
5. For pending media, display persistent local full-resolution-enough thumbnail/poster and playable local video from copied app-owned file (if local bytes exist); display upload progress separately. Do NOT start remote playback for a non-ready item. After ready, bind by stable media ID, obtain/refresh private signed URL before network initialization, recreate controller on expired URL, handle range requests and dispose stale controllers. Diagnose codecs separately from HTTP issues.
6. Pending/failed/needsRetry must never look ready. Provide meaningful localized transient/permanent failure messages and a functional per-item retry. `needsRetry` after exhaustion should preserve local bytes and stable UUID. No duplicates on retry, no indiscriminate re-upload after a successful PUT; confirm existing object where possible.
7. Ensure picker temporary files are copied into durable app storage before queueing, and handle Android `retrieveLostData()` appropriately. Avoid claiming guaranteed OS background upload when app is suspended/killed; ensure reliable foreground and reopen/resume behavior as designed.
8. Do not change hosted Supabase or Cloudflare without a measured need and the owner's approval. Keep sweep OFF, do not delete historical media, no Owner feature edits.

### Task A acceptance (physical Samsung, current source)
- Fresh Offer with **five images and five compliant videos**: accurate local previews immediately and honest individual progress; save, leave page, reopen, each item transitions to ready and persisted list without stale blurred/pending state.
- Each ready video plays after save and after a delay/reopen; if file is still pending, local playback works where local bytes exist, otherwise clear upload status rather than misleading network playback error.
- Retry interruption/airplane mode and app restart; successful PUT followed by interrupted confirm is idempotent, no extra links/objects. Expired GET URL gets refreshed, player reinitializes; verify 206 as relevant.
- Reject oversize/overlong/unsupported codec with clear messages. Verify correct failure states vs no endless spinner. Preserve cross-account isolation, max 10, removal and profile/account-deletion regressions.
- Targeted Flutter and Worker tests + `flutter analyze`, then device result with evidence. Only close Task A after actual device pass.

## TASK B — P1: Offer media picker & permission UX. KEEP AS SEPARATE TRACKED TASK; START AFTER TASK A.

### Reported issues
1. Gallery video selection currently allows only one video per visit; owner must tap + repeatedly.
2. An unnecessary app-authored permission/explanation popup appears before the operating-system permission UI, creating double acknowledgement.
3. The media-type menu is lengthy (separate camera, video camera, image gallery, video gallery, docs, etc.). Owner wants a compact WhatsApp-like three-action sheet.

### Expected implementation
- Use a maintained official Flutter picker API compatible with project Flutter SDK (`image_picker` >=1.2.0 has `pickMultiVideo`; `pickMultipleMedia` picks mixed images/videos). Prefer ONE Gallery action enabling multiple mixed selections up to available combined slots, validate again after selection; account for platform limits/fallback. Do not write a custom gallery without evidence it is necessary.
- Compact localized accessible bottom sheet with **Camera** (photo or video), **Gallery** (multi-select mixed photo/video), **Documents** (only enabled in flows with supported secure document architecture; current Offer photo/video backend must not silently accept arbitrary docs). For Camera use a clear photo/video mode inside camera flow or compact action, preserving camera/microphone permissions.
- Prefer Android system Photo Picker for selective gallery access; it does not require broad photo/media runtime permissions. Remove redundant custom permission popup where not needed; request truly required camera/mic permissions once in context and show rationale only when appropriate or after denial. Handle denial/cancel gracefully. Audit manifest/transitive permissions and iOS Info.plist as applicable.
- Preserve max 10 mixed media, local file copy, selected-count feedback, duplicate prevention, Arabic/English strings, accessibility and usable dark theme.

### Task B acceptance
- Choose 5 videos at once and/or mixed photos/videos from Gallery; no repeated + flow. Limit and invalid files clearly handled.
- Only necessary OS permission UI appears for Gallery; Camera prompts as required. No permanent broad gallery access requested for selective picks.
- Compact three-action sheet matches supported functionality; docs are not misleadingly enabled in Offer unless a separate private-document backend is implemented and approved.
- Add widget/picker tests, then verify on actual Samsung and relevant iOS path where available.

## TASK C — Dependency: Documents backend (OUT OF CURRENT OFFER MEDIA SCOPE)
Owner desires a Documents selection route for arbitrary documents. Current Offer private-media validation supports images/videos only. If documents are to attach to Offers, design a separate approved private document workflow (MIME/extension limits, size, secure upload/get, malware/unsafe-file policy, metadata, preview/download, removal and quota) before enabling that action there. Do not disguise documents as image/video files.

## Execution / approval boundaries
Execute Task A now using current repository and actual sanitized diagnostics; preserve Task B as separate documented issue until Task A device acceptance. No speculative redeploy, no repeat of 72 staging tests unless Worker changes warrant it; no sweeping/deleting existing data. Fix real root causes and rerun affected tests. Update `docs/CURRENT_CHECKPOINT.md` with task status and links to this issue record (or copy the issue content to the repository), without claiming the feature is done early.

## External official references checked
- Cloudflare R2 presigned URLs: https://developers.cloudflare.com/r2/api/s3/presigned-urls/
- Cloudflare R2 upload and multipart trade-offs: https://developers.cloudflare.com/r2/objects/upload-objects/
- Flutter image_picker and temporary file/lost data notes: https://pub.dev/packages/image_picker
- Flutter official picker source with `pickMultipleMedia` and `pickMultiVideo`: https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker/lib/image_picker.dart
- Flutter image_picker changelog (pickMultiVideo in 1.2.0): https://pub.dev/packages/image_picker/changelog
- Android Photo Picker and temporary URI access: https://developer.android.com/training/data-storage/shared/photo-picker
- Android minimal permissions: https://developer.android.com/privacy-and-security/minimize-permission-requests
- Android runtime permission rationale guidance: https://developer.android.com/training/permissions/requesting
- Flutter video_player: https://pub.dev/packages/video_player
- Android Media3 playback error diagnostics: https://developer.android.com/media/media3/exoplayer/listening-to-player-events
