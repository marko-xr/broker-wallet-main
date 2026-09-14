import 'package:hive/hive.dart';

import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/offline_data_service.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';

typedef ProfileMediaForgetter = Future<void> Function({
  Iterable<String>? mediaIds,
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
///  * that account's own profile avatar cache entries.
///
/// Only when the deleted account was the one signed in on this device, because
/// these single-slot caches belong to whichever account was signed in:
///  * the cached user model and auth flag;
///  * cached item counts;
///  * the cached favorites box;
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
  DeletedAccountLocalDataCleaner({ProfileMediaForgetter? forgetProfileMedia})
      : _forgetProfileMedia = forgetProfileMedia ??
            OfflineMediaService.instance.forgetProfileMedia;

  final ProfileMediaForgetter _forgetProfileMedia;

  static const List<String> _uidKeyedBoxes = [
    'local_profile',
    'pending_profile_uploads',
  ];
  static const String _favoritesBox = 'cached_favorites';

  Future<void> clear({
    required String deletedUid,
    required bool wasSignedInAccount,
    Iterable<String> profileMediaIds = const [],
  }) async {
    if (deletedUid.isEmpty) return;

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

    if (!wasSignedInAccount) {
      await _step(() => _forgetProfileMedia(mediaIds: profileMediaIds));
      return;
    }

    await _step(OfflineAuthService.instance.clearAuthCache);
    await _step(CountCacheService.instance.clearCache);
    await _step(() async {
      if (Hive.isBoxOpen(_favoritesBox)) await Hive.box(_favoritesBox).clear();
    });
    await _step(() => _forgetProfileMedia());
  }

  Future<void> _step(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // See the class comment: each step stands alone.
    }
  }
}
