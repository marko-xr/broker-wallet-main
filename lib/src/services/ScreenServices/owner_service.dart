import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/owners_model.dart';
import '../../repositories/repository_provider.dart';
import '../encrypted_account_list_cache.dart';
import '../media_parent.dart';
import '../offer_media_cache_identity.dart';
import '../offer_media_policy.dart';
import '../offer_media_upload_queue.dart';
import '../offline_media_service.dart';
import '../owners_local_cache.dart';
import '../private_media_store.dart';
import '../r2_offer_media_upload_service.dart';
import '../supabase_core_entities_service.dart';

/// What saving an Owner record did to its media.
///
/// The Owner row itself is saved whenever this is returned. New media is
/// handed to the upload queue — never reported as uploaded here — and each
/// removal is reported as it actually went.
class OwnerMediaSaveResult {
  const OwnerMediaSaveResult({
    required this.ownerRecordId,
    required this.queuedCount,
    this.failedRemovalIds = const <String>[],
    this.failedToQueueIds = const <String>[],
  });

  final String ownerRecordId;

  /// New items now in the upload queue.
  final int queuedCount;

  /// Existing items that could not be removed; they are still on the Owner.
  final List<String> failedRemovalIds;

  /// New items whose file could not be taken into the app's own storage.
  final List<String> failedToQueueIds;

  bool get isComplete => failedRemovalIds.isEmpty && failedToQueueIds.isEmpty;
}

/// Owner records: Supabase (canonical) or the legacy Firebase store, and —
/// in Supabase mode — the Owner's private media through the same Media
/// Worker, upload queue and local cache as Offer media ([MediaParent.owner]).
class OwnerService implements PrivateMediaStore {
  OwnerService({
    R2OfferMediaUploadService Function()? ownerMediaUpload,
    OfferMediaUploadQueue Function()? uploadQueue,
    SupabaseCoreEntitiesService Function()? coreEntities,
    OwnersLocalCache localCache = const OwnersLocalCache(),
    String? Function()? currentUserId,
  })  : _ownerMediaUploadFactory = ownerMediaUpload ??
            (() => R2OfferMediaUploadService(parent: MediaParent.owner)),
        _uploadQueueFactory =
            uploadQueue ?? (() => OfferMediaUploadQueue.instance),
        _coreEntitiesFactory = coreEntities ?? SupabaseCoreEntitiesService.new,
        _localCache = localCache,
        _currentUserIdOverride = currentUserId;

  final OwnersLocalCache _localCache;
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

  final R2OfferMediaUploadService Function() _ownerMediaUploadFactory;
  final OfferMediaUploadQueue Function() _uploadQueueFactory;
  final SupabaseCoreEntitiesService Function() _coreEntitiesFactory;

  // Created on first use, then reused, so constructing this service never
  // reaches `Supabase.instance` (the Firebase path never needs it).
  late final SupabaseCoreEntitiesService _supabase = _coreEntitiesFactory();
  late final R2OfferMediaUploadService _ownerMediaUpload =
      _ownerMediaUploadFactory();

  OfferMediaUploadQueue get _uploadQueue => _uploadQueueFactory();

  String generateNewOwnerId() {
    return const Uuid().v4();
  }

  Future<String?> saveOwner(OwnerModel owner, {String? ownerId}) async {
    return _supabase.saveOwner(owner, ownerRecordId: ownerId);
  }

  /// Saves the Owner row, applies media removals, and hands new media to the
  /// persistent upload queue (Supabase mode) — the Owner counterpart of
  /// `OfferService.saveOfferWithMedia`.
  ///
  /// Never uploads and never waits for an upload: the queue shows each new
  /// item's progress and outcome, and an item is not presented as uploaded
  /// until the server has accepted it. The Owner row is saved first and is
  /// never rolled back for a media problem. Removals run before new items are
  /// queued, so the places they free are available to them.
  ///
  /// Every new item already carries its `mediaObjectId`, so calling this again
  /// after a partial failure cannot duplicate anything.
  Future<OwnerMediaSaveResult> saveOwnerWithMedia({
    required OwnerModel owner,
    required String ownerRecordId,
    List<OfferMediaDraft> newMedia = const <OfferMediaDraft>[],
    List<String> removedMediaIds = const <String>[],
    List<String> cancelledUploadIds = const <String>[],
  }) async {
    if (!SupabaseConfig.useSupabaseAuth) {
      throw StateError('saveOwnerWithMedia is the Supabase media path.');
    }
    final ownerId = _supabase.currentOwnerId;
    if (ownerId == null || ownerId.isEmpty) {
      throw StateError('A Supabase session is required.');
    }

    final existing = await _supabase.getOwner(ownerRecordId);
    if (existing == null) {
      await _supabase.saveOwner(owner, ownerRecordId: ownerRecordId);
    } else {
      await _supabase.updateOwner(ownerRecordId, owner);
    }

    final queue = _uploadQueue;
    final failedRemovals = <String>[];
    for (final mediaObjectId in removedMediaIds) {
      try {
        await _ownerMediaUpload.removeMedia(
          offerId: ownerRecordId,
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
        // reconciliation of the Owner's media.
      }
    }
    if (failedRemovals.length < removedMediaIds.length) {
      // Places were freed: anything that found the Owner full goes on.
      await queue.releaseBlocked(
        ownerId: ownerId,
        offerId: ownerRecordId,
        parent: MediaParent.owner,
      );
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
          offerId: ownerRecordId,
          drafts: newMedia,
          parent: MediaParent.owner,
        );
        queuedCount = result.queued.length;
        failedToQueue = result.failedIds;
      } catch (_) {
        failedToQueue = [for (final draft in newMedia) draft.mediaObjectId];
      }
    }

    return OwnerMediaSaveResult(
      ownerRecordId: ownerRecordId,
      queuedCount: queuedCount,
      failedRemovalIds: failedRemovals,
      failedToQueueIds: failedToQueue,
    );
  }

  Future<String> saveOwnerWithMediaFast({
    required OwnerModel owner,
    required List<File> mediaFiles,
    String? ownerId,
  }) async {
    // Supabase mode saves media through [saveOwnerWithMedia] and its upload
    // queue. This legacy entry point uploads nothing there.
    if (mediaFiles.isNotEmpty) {
      throw StateError('Owner media is saved through saveOwnerWithMedia.');
    }
    return _supabase.saveOwner(owner, ownerRecordId: ownerId);
  }

  Future<void> updateOwner(String ownerId, OwnerModel owner) async {
    await _supabase.updateOwner(ownerId, owner);
  }

  Stream<List<OwnerModel>> getUserOwners() {
    return _supabase.getOwners();
  }

  /// The Owners list for the Owners screen: this account's encrypted saved
  /// copy at once (when there is one), then the server's list, which replaces
  /// it and is saved for next time. A server failure is passed on as before;
  /// a screen that already shows the saved copy keeps it. Media is not part
  /// of the copy.
  Stream<List<OwnerModel>> watchUserOwnersLocalFirst() => localFirstList(
        server: getUserOwners,
        cache: _localCache,
        currentUserId: _currentUserId,
      );

  Future<void> deleteOwner(String ownerId) async {
    // Once the server has confirmed it, the offline list never shows it
    // again.
    await deleteThenRemember(
      cache: _localCache,
      id: ownerId,
      currentUserId: _currentUserId,
      delete: () => _supabase.deleteOwner(ownerId),
    );
    // Nothing queued for a deleted Owner may upload, and nothing this
    // device holds for it is shown again. The server removes its stored
    // media itself once the retention period has passed.
    final accountId = _supabase.currentOwnerId;
    if (accountId != null && accountId.isNotEmpty) {
      unawaited(_forgetDeletedOwnerMedia(accountId, ownerId));
    }
  }

  Future<OwnerModel?> getOwner(String ownerId) async {
    return _supabase.getOwner(ownerId);
  }

  /// The Owner records with these ids this account may see, in a few
  /// requests rather than one per id. Missing and deleted ones are left out.
  /// Their media is resolved apart ([resolveMedia]).
  Future<List<OwnerModel>> getOwnersByIds(List<String> ownerIds) =>
      _supabase.getOwnersByIds(ownerIds);

  // ---------------------------------------------------------------------------
  // Owner private media (Supabase mode), addressed by identity, never by URL.
  // ---------------------------------------------------------------------------

  @override
  MediaParent get parent => MediaParent.owner;

  /// The signed-in account, or null when there is no session.
  @override
  String? get currentOwnerId => _supabase.currentOwnerId;

  /// What this device already holds for the Owner record [recordId], with no
  /// network at all. Always empty on the Firebase backend.
  @override
  List<OfferMediaRef> cachedMedia(String recordId) {
    if (!SupabaseConfig.useSupabaseAuth) return const <OfferMediaRef>[];
    return _supabase.cachedOwnerMedia(recordId);
  }

  /// The Owner record's current confirmed media with fresh signed links.
  /// Null on the Firebase backend, which has no separate media stage.
  @override
  Future<OfferMediaResolution?> resolveMedia({
    required String recordId,
    required String ownerId,
  }) async {
    if (!SupabaseConfig.useSupabaseAuth) return null;
    return _supabase.resolveOwnerMedia(
      ownerRecordId: recordId,
      ownerId: ownerId,
    );
  }

  /// Items of the Owner record [recordId] still in the upload queue, as the
  /// media UI draws them (Supabase mode).
  @override
  List<OfferMediaRef> pendingMedia(String recordId) {
    if (!SupabaseConfig.useSupabaseAuth) return const <OfferMediaRef>[];
    return _uploadQueue.pendingRefsFor(
      ownerId: _supabase.currentOwnerId,
      offerId: recordId,
      parent: MediaParent.owner,
    );
  }

  /// Notifies whenever a queued media item changes (Supabase mode).
  @override
  Listenable get uploadChanges => _uploadQueue;

  /// Each queued Owner media item the server has accepted.
  @override
  Stream<OfferMediaUploadCompleted> get uploadCompletions => _uploadQueue
      .completions
      .where((event) => event.parent == MediaParent.owner);

  /// Loads the persisted upload queue so pending items can be shown.
  @override
  Future<void> loadUploads() async {
    if (!SupabaseConfig.useSupabaseAuth) return;
    try {
      await _uploadQueue.ensureOpen();
    } catch (_) {
      // Without storage there is nothing queued to show.
    }
  }

  /// The user's Retry for a queued item that failed for a reason that can
  /// pass.
  @override
  Future<void> retryUpload(String mediaObjectId) =>
      _uploadQueue.retry(mediaObjectId);

  /// The user's Remove for a queued item: its upload stops and anything the
  /// server already holds for it is withdrawn.
  @override
  Future<void> cancelUpload(String mediaObjectId) =>
      _uploadQueue.cancel(mediaObjectId);

  Future<void> _forgetDeletedOwnerMedia(
    String accountId,
    String ownerRecordId,
  ) async {
    try {
      await _uploadQueue.forgetRecord(
        ownerId: accountId,
        recordId: ownerRecordId,
        parent: MediaParent.owner,
      );
    } catch (_) {}
    try {
      await OfflineMediaService.instance.forgetOfferMediaForOffer(
        ownerId: accountId,
        offerId: ownerRecordId,
      );
    } catch (_) {}
  }
}
