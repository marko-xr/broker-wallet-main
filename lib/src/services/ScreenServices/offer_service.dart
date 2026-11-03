import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/offers_model.dart';
import '../../repositories/repository_provider.dart';
import '../encrypted_account_list_cache.dart';
import '../offer_media_cache_identity.dart';
import '../offer_media_policy.dart';
import '../offer_media_upload_queue.dart';
import '../offers_local_cache.dart';
import '../offline_media_service.dart';
import '../r2_offer_media_upload_service.dart';
import '../supabase_core_entities_service.dart';

/// What saving an Offer did to its media.
///
/// The Offer row itself is saved whenever this is returned. New media is
/// handed to the upload queue — never reported as uploaded here — and each
/// removal is reported as it actually went.
class OfferMediaSaveResult {
  const OfferMediaSaveResult({
    required this.offerId,
    required this.queuedCount,
    this.failedRemovalIds = const <String>[],
    this.failedToQueueIds = const <String>[],
  });

  final String offerId;

  /// New items now in the upload queue.
  final int queuedCount;

  /// Existing items that could not be removed; they are still on the Offer.
  final List<String> failedRemovalIds;

  /// New items whose file could not be taken into the app's own storage.
  final List<String> failedToQueueIds;

  bool get isComplete => failedRemovalIds.isEmpty && failedToQueueIds.isEmpty;
}

class OfferService {
  OfferService({
    R2OfferMediaUploadService Function()? offerMediaUpload,
    OfferMediaUploadQueue Function()? uploadQueue,
    SupabaseCoreEntitiesService Function()? coreEntities,
    OffersLocalCache localCache = const OffersLocalCache(),
    String? Function()? currentUserId,
  })  : _offerMediaUploadFactory =
            offerMediaUpload ?? R2OfferMediaUploadService.new,
        _uploadQueueFactory =
            uploadQueue ?? (() => OfferMediaUploadQueue.instance),
        _coreEntitiesFactory = coreEntities ?? SupabaseCoreEntitiesService.new,
        _localCache = localCache,
        _currentUserIdOverride = currentUserId;

  final OffersLocalCache _localCache;
  final String? Function()? _currentUserIdOverride;

  /// The canonical signed-in account, or null when there is none (or no
  /// auth repository yet).
  String? _currentUserId() {
    final override = _currentUserIdOverride;
    if (override != null) return override();
    try {
      return RepositoryProvider.instance.authRepository.currentUserId;
    } catch (_) {
      return null;
    }
  }

  // Created on first use, then reused: the Offer media form and gallery read
  // the signed-in account on every rebuild while an upload reports progress.
  late final SupabaseCoreEntitiesService _supabase = _coreEntitiesFactory();

  final R2OfferMediaUploadService Function() _offerMediaUploadFactory;
  final OfferMediaUploadQueue Function() _uploadQueueFactory;
  final SupabaseCoreEntitiesService Function() _coreEntitiesFactory;

  // Created on first use, so constructing this service never reaches
  // `Supabase.instance`.
  late final R2OfferMediaUploadService _offerMediaUpload =
      _offerMediaUploadFactory();

  OfferMediaUploadQueue get _uploadQueue => _uploadQueueFactory();

  String generateNewOfferId() {
    return const Uuid().v4();
  }

  Future<String?> saveOffer(OfferModel offer, {String? offerId}) async {
    return _supabase.saveOffer(offer, offerId: offerId);
  }

  /// Saves the Offer row, applies media removals, and hands new media to the
  /// persistent upload queue (Supabase mode).
  ///
  /// Never uploads and never waits for an upload: the queue shows each new
  /// item's progress and outcome, and an item is not presented as uploaded
  /// until the server has accepted it. The Offer row is saved first and is
  /// never rolled back for a media problem. Removals run before new items are
  /// queued, so the places they free are available to them.
  ///
  /// Every new item already carries its `mediaObjectId`, so calling this again
  /// after a partial failure cannot duplicate anything: a draft that is
  /// already queued is not queued twice, and a removal is idempotent.
  Future<OfferMediaSaveResult> saveOfferWithMedia({
    required OfferModel offer,
    required String offerId,
    List<OfferMediaDraft> newMedia = const <OfferMediaDraft>[],
    List<String> removedMediaIds = const <String>[],
    List<String> cancelledUploadIds = const <String>[],
  }) async {
    if (!SupabaseConfig.useSupabaseAuth) {
      throw StateError('saveOfferWithMedia is the Supabase media path.');
    }
    final ownerId = _supabase.currentOwnerId;
    if (ownerId == null || ownerId.isEmpty) {
      throw StateError('A Supabase session is required.');
    }

    final existing = await _supabase.getOfferMetadata(offerId);
    if (existing == null) {
      await _supabase.saveOffer(offer, offerId: offerId);
    } else {
      await _supabase.updateOffer(offerId, offer);
    }

    final queue = _uploadQueue;
    final failedRemovals = <String>[];
    for (final mediaObjectId in removedMediaIds) {
      try {
        await _offerMediaUpload.removeMedia(
          offerId: offerId,
          mediaObjectId: mediaObjectId,
        );
      } catch (_) {
        failedRemovals.add(mediaObjectId);
        continue;
      }
      try {
        await OfflineMediaService.instance.forgetOfferMediaItems(
          ownerId: ownerId,
          mediaObjectIds: [mediaObjectId],
        );
      } catch (_) {
        // Removed on the server; this device's copy goes with the next
        // reconciliation of the Offer's media.
      }
    }
    if (failedRemovals.length < removedMediaIds.length) {
      // Places were freed: anything that found the Offer full goes on.
      await queue.releaseBlocked(ownerId: ownerId, offerId: offerId);
    }

    for (final mediaObjectId in cancelledUploadIds) {
      await queue.cancel(mediaObjectId);
    }

    var queuedCount = 0;
    var failedToQueue = const <String>[];
    if (newMedia.isNotEmpty) {
      try {
        final result = await queue.enqueue(
          ownerId: ownerId,
          offerId: offerId,
          drafts: newMedia,
        );
        queuedCount = result.queued.length;
        failedToQueue = result.failedIds;
      } catch (_) {
        failedToQueue = [for (final draft in newMedia) draft.mediaObjectId];
      }
    }

    return OfferMediaSaveResult(
      offerId: offerId,
      queuedCount: queuedCount,
      failedRemovalIds: failedRemovals,
      failedToQueueIds: failedToQueue,
    );
  }

  /// Items of [offerId] still in the upload queue, as the Offer media UI
  /// draws them (Supabase mode).
  List<OfferMediaRef> pendingOfferMedia(String offerId) {
    if (!SupabaseConfig.useSupabaseAuth) return const <OfferMediaRef>[];
    return _uploadQueue.pendingRefsFor(
      ownerId: _supabase.currentOwnerId,
      offerId: offerId,
    );
  }

  Future<String> saveOfferWithMediaFast({
    required OfferModel offer,
    required List<File> mediaFiles,
    String? offerId,
  }) async {
    // Supabase mode saves through [saveOfferWithMedia] and its upload queue.
    // This legacy entry point uploads nothing there.
    if (mediaFiles.isNotEmpty) {
      throw StateError('Offer media is saved through saveOfferWithMedia.');
    }
    final id = offerId ?? _supabase.generateId();
    await saveOfferWithMedia(offer: offer, offerId: id);
    return id;
  }

  Future<void> removeMediaUrls(String offerId, List<String> urlsToRemove) async {
    if (urlsToRemove.isNotEmpty) {
      throw StateError(
        'Media mutation is disabled until the Cloudflare R2 migration batch is applied.',
      );
    }
  }

  Future<void> updateOffer(String offerId, OfferModel offer) async {
    await _supabase.updateOffer(offerId, offer);
  }

  Stream<List<OfferModel>> getUserOffers() {
    return _supabase.getOffers();
  }

  /// The Offers list for the Offers screen: this account's encrypted saved
  /// copy at once (when there is one), then the server's list, which replaces
  /// it and is saved for next time. A server failure is passed on as before;
  /// a screen that already shows the saved copy keeps it. Media is not part
  /// of the copy.
  Stream<List<OfferModel>> watchUserOffersLocalFirst() => localFirstList(
        server: getUserOffers,
        cache: _localCache,
        currentUserId: _currentUserId,
      );

  Future<void> deleteOffer(String offerId) async {
    // Once the server has confirmed it, the offline list never shows it
    // again.
    await deleteThenRemember(
      cache: _localCache,
      id: offerId,
      currentUserId: _currentUserId,
      delete: () => _supabase.deleteOffer(offerId),
    );
    // Nothing queued for a deleted Offer may upload, and nothing this
    // device holds for it is shown again. The server removes its stored
    // media itself once the retention period has passed.
    final ownerId = _supabase.currentOwnerId;
    if (ownerId != null && ownerId.isNotEmpty) {
      unawaited(_forgetDeletedOfferMedia(ownerId, offerId));
    }
  }

  Future<OfferModel?> getOffer(String offerId) async {
    return _supabase.getOffer(offerId);
  }

  /// Reads the authoritative Offer fields without waiting for private-media
  /// URL signing. Firebase's legacy document already carries its stable media
  /// URLs, so its existing single read remains unchanged.
  Future<OfferModel?> getOfferMetadata(String offerId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return _supabase.getOfferMetadata(offerId);
    }
    return getOffer(offerId);
  }

  /// The signed-in account, or null when there is no session.
  String? get currentOwnerId => _supabase.currentOwnerId;

  /// What this device already holds for [offerId], with no network at all.
  ///
  /// Always empty on the Firebase backend, whose Storage URLs are stable and
  /// therefore already cache correctly keyed by URL — only private R2 media,
  /// whose signed URL rotates on every read, needs a durable identity.
  List<OfferMediaRef> cachedOfferMedia(String offerId) {
    if (!SupabaseConfig.useSupabaseAuth) return const <OfferMediaRef>[];
    return _supabase.cachedOfferMedia(offerId);
  }

  /// Resolves only private media for an Offer whose core row has already been
  /// authorized, without re-reading the Offer row.
  ///
  /// Returns null on the Firebase backend, which has no separate media stage:
  /// its document already carries its media URLs, so the caller must keep what
  /// metadata gave it rather than treating "no media stage" as "no media".
  Future<OfferMediaResolution?> resolveOfferMedia({
    required String offerId,
    required String ownerId,
  }) async {
    if (!SupabaseConfig.useSupabaseAuth) return null;
    return _supabase.resolveOfferMedia(offerId: offerId, ownerId: ownerId);
  }

  /// Notifies whenever a queued Offer media item changes (Supabase mode).
  Listenable get offerMediaUploadChanges => _uploadQueue;

  /// Each queued Offer media item the server has accepted.
  Stream<OfferMediaUploadCompleted> get offerMediaUploadCompletions =>
      _uploadQueue.completions;

  /// Loads the persisted upload queue so pending items can be shown.
  Future<void> loadOfferMediaUploads() async {
    if (!SupabaseConfig.useSupabaseAuth) return;
    try {
      await _uploadQueue.ensureOpen();
    } catch (_) {
      // Without storage there is nothing queued to show.
    }
  }

  /// The user's Retry for a queued item that failed for a reason that can
  /// pass.
  Future<void> retryOfferMediaUpload(String mediaObjectId) =>
      _uploadQueue.retry(mediaObjectId);

  /// The user's Remove for a queued item: its upload stops and anything the
  /// server already holds for it is withdrawn.
  Future<void> cancelOfferMediaUpload(String mediaObjectId) =>
      _uploadQueue.cancel(mediaObjectId);

  Future<void> _forgetDeletedOfferMedia(String ownerId, String offerId) async {
    try {
      await _uploadQueue.forgetOffer(ownerId: ownerId, offerId: offerId);
    } catch (_) {}
    try {
      await OfflineMediaService.instance
          .forgetOfferMediaForOffer(ownerId: ownerId, offerId: offerId);
    } catch (_) {}
  }
}
