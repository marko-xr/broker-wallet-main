import 'package:hive/hive.dart';

import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/offline_data_service.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport, OfflineMediaService;
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart'
    show FavoriteService;

typedef ProfileMediaForgetter = Future<void> Function({
  Iterable<String>? mediaIds,
});

typedef OfferMediaForgetter = Future<OfferMediaCleanupReport> Function({
  String? ownerId,
});

/// Removes what this device holds for an account that the server has deleted.
///
/// It runs only after the deletion is authoritative, and it clears exactly the
/// inventory below — never "all app storage":
///
/// Always, because each entry is keyed by the deleted account's id:
///  * the last-known-good profile snapshot, if it is that account's;
///  * the password-recovery marker, if it is that account's;
///  * the `saved_items_offline` / `user_data_offline` entries for that id;
///  * the legacy `local_profile` / `pending_profile_uploads` entries for that
///    id;
///  * that account's own profile avatar cache entries;
///  * that account's own Offer-media catalogue, the cached image bytes behind
///    it, and its adopted originals — all keyed by that account's id;
///  * that account's own Favorites cache box (`cached_favorites_<uid>`, see
///    `FavoriteService.boxNameForUid`) — deleted from disk outright rather
///    than merely cleared, and safe to do unconditionally because the box
///    name is unique to this uid and can never be a different, currently
///    signed-in account's box.
///
/// Only when the deleted account was the one signed in on this device, because
/// these single-slot caches belong to whichever account was signed in:
///  * the cached user model and auth flag;
///  * cached item counts;
///  * every profile avatar cache entry and the `profile_media` directory.
///
/// Deliberately kept: language (`languageCode`) and theme (`themeMode`), which
/// are device preferences, and the Toolkit's locally created documents
/// (scanned, signed, combined and converted PDFs), which are files on this
/// device rather than account data — whether those should go with an account
/// is a product decision that has not been made.
///
/// Every step is best effort and independent: the account is already gone, so
/// a cache that cannot be cleared must not stop the others or the sign-out.
class DeletedAccountLocalDataCleaner {
  DeletedAccountLocalDataCleaner({
    ProfileMediaForgetter? forgetProfileMedia,
    OfferMediaForgetter? forgetOfferMedia,
  })  : _forgetProfileMedia = forgetProfileMedia ??
            OfflineMediaService.instance.forgetProfileMedia,
        _forgetOfferMedia =
            forgetOfferMedia ?? OfflineMediaService.instance.forgetOfferMedia;

  final ProfileMediaForgetter _forgetProfileMedia;
  final OfferMediaForgetter _forgetOfferMedia;

  static const List<String> _uidKeyedBoxes = [
    'local_profile',
    'pending_profile_uploads',
  ];

  /// Returns what the Offer-media step managed to remove.
  ///
  /// That step is the only one holding private image bytes, so it is the only
  /// one whose partial failure the caller may need to know about. Every step
  /// still stands alone: the account is already gone and a cache that cannot
  /// be cleared must not stop the others or the sign-out.
  Future<OfferMediaCleanupReport> clear({
    required String deletedUid,
    required bool wasSignedInAccount,
    Iterable<String> profileMediaIds = const [],
  }) async {
    if (deletedUid.isEmpty) return const OfferMediaCleanupReport.empty();

    await _step(
      () =>
          OfflineAuthService.instance.clearProfileSnapshotIfOwnedBy(deletedUid),
    );
    if (PasswordRecoveryStateStore.ownerUid == deletedUid) {
      await _step(PasswordRecoveryStateStore.forget);
    }
    await _step(() => OfflineDataService.instance.clearUserCache(deletedUid));
    for (final box in _uidKeyedBoxes) {
      await _step(() async {
        if (Hive.isBoxOpen(box)) await Hive.box(box).delete(deletedUid);
      });
    }
    await _step(
      () => Hive.deleteBoxFromDisk(FavoriteService.boxNameForUid(deletedUid)),
    );

    // Offer media is catalogued and named per account id, so the deleted
    // account's entries are removable precisely whether or not it was the
    // signed-in one.
    // Starts as "did not complete": if the step throws, `_step` swallows it
    // by design, and an unset report would otherwise read as a clean success
    // while private originals were still on the device.
    var offerMedia = const OfferMediaCleanupReport.empty().withSweepFailed();
    await _step(() async {
      offerMedia = await _forgetOfferMedia(ownerId: deletedUid);
    });

    if (!wasSignedInAccount) {
      await _step(() => _forgetProfileMedia(mediaIds: profileMediaIds));
      return offerMedia;
    }

    await _step(OfflineAuthService.instance.clearAuthCache);
    await _step(CountCacheService.instance.clearCache);
    await _step(() => _forgetProfileMedia());
    return offerMedia;
  }

  Future<void> _step(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // See the class comment: each step stands alone.
    }
  }
}
