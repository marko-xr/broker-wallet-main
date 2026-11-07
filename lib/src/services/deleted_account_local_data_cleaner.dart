import 'package:hive/hive.dart';

import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/services/favorites_local_cache.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/offline_data_service.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart'
    show OfferMediaCleanupReport, OfflineMediaService;
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/quotations_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart'
    show FavoriteService;
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_files.dart';
import 'package:broker_wallet/src/services/quotation_pdf_vault.dart';

typedef ProfileMediaForgetter = Future<void> Function({
  Iterable<String>? mediaIds,
});

typedef OfferMediaForgetter = Future<OfferMediaCleanupReport> Function({
  String? ownerId,
});

/// Drops every queued Offer media upload of one account; returns how many
/// could not be removed completely.
typedef OfferMediaUploadPurger = Future<int> Function(String ownerId);

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
///  * that account's own queued Offer media uploads and their local copies;
///  * that account's own Favorites cache box (`cached_favorites_<uid>`, see
///    `FavoriteService.boxNameForUid`) — deleted from disk outright rather
///    than merely cleared, and safe to do unconditionally because the box
///    name is unique to this uid and can never be a different, currently
///    signed-in account's box;
///  * that account's encrypted Favorites copy and its key
///    ([FavoritesLocalCache]), and its decrypted copy in memory;
///  * that account's encrypted copies of its six entity lists and of its
///    Quotations list ([QuotationsLocalCache]), with their keys.
///
///  * that account's Quotation PDFs ([QuotationPdfFiles.forgetAccount]): its
///    work folder, and each PDF in the documents folder that names a
///    Quotation of its verified saved list — read before that list goes;
///    and its encrypted copies, their key and its viewing copies
///    ([QuotationPdfVault.forgetAccount]).
///
/// Not removed: a Quotation PDF in the documents folder whose account is not
/// proven (no readable saved list names it), which stays untouched (tracker
/// §7AY, D-P4).
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
    OfferMediaUploadPurger? purgeOfferMediaUploads,
    Future<int> Function(String uid)? forgetQuotationPdfs,
  })  : _forgetProfileMedia = forgetProfileMedia ??
            OfflineMediaService.instance.forgetProfileMedia,
        _forgetOfferMedia =
            forgetOfferMedia ?? OfflineMediaService.instance.forgetOfferMedia,
        _purgeOfferMediaUploads = purgeOfferMediaUploads ??
            ((ownerId) => OfferMediaUploadQueue.instance.purgeOwner(ownerId)),
        _forgetQuotationPdfs = forgetQuotationPdfs ??
            ((uid) async =>
                await QuotationPdfFiles().forgetAccount(uid) +
                await QuotationPdfVault().forgetAccount(uid));

  final ProfileMediaForgetter _forgetProfileMedia;
  final OfferMediaForgetter _forgetOfferMedia;
  final OfferMediaUploadPurger _purgeOfferMediaUploads;
  final Future<int> Function(String uid) _forgetQuotationPdfs;

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
    FavoritesMemory.forget(deletedUid);
    await _step(() => const FavoritesLocalCache().forgetAccount(deletedUid));
    await _step(() => const RequestsLocalCache().forgetAccount(deletedUid));
    await _step(() => const OffersLocalCache().forgetAccount(deletedUid));
    await _step(() => const OwnersLocalCache().forgetAccount(deletedUid));
    await _step(() => const OfficesLocalCache().forgetAccount(deletedUid));
    await _step(() => const BrokersLocalCache().forgetAccount(deletedUid));
    await _step(() => const WatchmenLocalCache().forgetAccount(deletedUid));
    // Its saved list proves which PDFs are its own: before the list goes.
    await _step(() => _forgetQuotationPdfs(deletedUid));
    await _step(() => const QuotationsLocalCache().forgetAccount(deletedUid));
    await _step(() => CountCacheService.instance.clearAccount(deletedUid));

    // Queued uploads first, so none keeps sending a deleted account's file.
    // Their local copies carry the account's file-name prefix, so the sweep
    // below removes any this step leaves; the report reflects that sweep.
    await _step(() => _purgeOfferMediaUploads(deletedUid));

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
    await _step(CountCacheService.instance.clearLegacyCache);
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
