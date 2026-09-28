import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../repositories/repository_provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/owners_model.dart';
import '../fast_media_upload_service.dart';
import '../map_data_cache_service.dart';
import '../media_parent.dart';
import '../offer_media_cache_identity.dart';
import '../offer_media_policy.dart';
import '../offer_media_upload_queue.dart';
import '../offline_media_service.dart';
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
  })  : _ownerMediaUploadFactory = ownerMediaUpload ??
            (() => R2OfferMediaUploadService(parent: MediaParent.owner)),
        _uploadQueueFactory =
            uploadQueue ?? (() => OfferMediaUploadQueue.instance),
        _coreEntitiesFactory = coreEntities ?? SupabaseCoreEntitiesService.new;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final FastMediaUploadService _fastUploadService = FastMediaUploadService();
  final _mapDataCache = MapDataCacheService();

  final R2OfferMediaUploadService Function() _ownerMediaUploadFactory;
  final OfferMediaUploadQueue Function() _uploadQueueFactory;
  final SupabaseCoreEntitiesService Function() _coreEntitiesFactory;

  // Created on first use, then reused, so constructing this service never
  // reaches `Supabase.instance` (the Firebase path never needs it).
  late final SupabaseCoreEntitiesService _supabase = _coreEntitiesFactory();
  late final R2OfferMediaUploadService _ownerMediaUpload =
      _ownerMediaUploadFactory();

  OfferMediaUploadQueue get _uploadQueue => _uploadQueueFactory();

  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;
  static const String _collectionName = 'users';

  String generateNewOwnerId() {
    if (SupabaseConfig.useSupabaseAuth) return const Uuid().v4();
    if (_currentUserId == null) throw Exception('User not authenticated');
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc()
        .id;
  }

  Future<String?> saveOwner(OwnerModel owner, {String? ownerId}) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return _supabase.saveOwner(owner, ownerRecordId: ownerId);
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    final String docId = ownerId ?? generateNewOwnerId();
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(docId)
        .set(owner
            .copyWith(
              id: docId,
              userId: _currentUserId!,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toFirestore());
    _mapDataCache.invalidateCache();
    return docId;
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
    if (SupabaseConfig.useSupabaseAuth) {
      // Supabase mode saves media through [saveOwnerWithMedia] and its upload
      // queue. This legacy entry point uploads nothing there.
      if (mediaFiles.isNotEmpty) {
        throw StateError('Owner media is saved through saveOwnerWithMedia.');
      }
      return _supabase.saveOwner(owner, ownerRecordId: ownerId);
    }

    if (_currentUserId == null) throw Exception('User not authenticated');
    final ownerData = {
      'userId': owner.userId,
      'name': owner.name,
      'phoneNumber': owner.phoneNumber,
      'countryCode': owner.countryCode,
      'typeOfProperties': owner.typeOfProperties,
      'propertyLocation': owner.propertyLocation,
      'notes': owner.notes,
      'pickUpLocation': owner.pickUpLocation,
      'pickUpLatitude': owner.pickUpLatitude,
      'pickUpLongitude': owner.pickUpLongitude,
      'pickUpAddress': owner.pickUpAddress,
      'uploadedFileName': owner.uploadedFileName,
      'mediaUrl': owner.mediaUrl,
      'createdAt': owner.createdAt,
      'updatedAt': owner.updatedAt,
    };
    return _fastUploadService.saveDataWithMedia(
      data: ownerData,
      mediaFiles: mediaFiles,
      collection: 'owners',
      documentId: ownerId,
    );
  }

  Future<void> updateOwner(String ownerId, OwnerModel owner) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.updateOwner(ownerId, owner);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(ownerId)
        .update(owner
            .copyWith(id: ownerId, updatedAt: DateTime.now())
            .toFirestore());
    _mapDataCache.invalidateCache();
  }

  Stream<List<OwnerModel>> getUserOwners() {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOwners();
    if (_currentUserId == null) return Stream.value([]);
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => OwnerModel.fromFirestore(doc)).toList());
  }

  Future<void> deleteOwner(String ownerId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.deleteOwner(ownerId);
      // Nothing queued for a deleted Owner may upload, and nothing this
      // device holds for it is shown again. The server removes its stored
      // media itself once the retention period has passed.
      final accountId = _supabase.currentOwnerId;
      if (accountId != null && accountId.isNotEmpty) {
        unawaited(_forgetDeletedOwnerMedia(accountId, ownerId));
      }
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(ownerId)
        .delete();
    _mapDataCache.invalidateCache();
  }

  Future<OwnerModel?> getOwner(String ownerId) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOwner(ownerId);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final doc = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(ownerId)
        .get();
    return doc.exists ? OwnerModel.fromFirestore(doc) : null;
  }

  // ---------------------------------------------------------------------------
  // Owner private media (Supabase mode), addressed by identity, never by URL.
  // ---------------------------------------------------------------------------

  @override
  MediaParent get parent => MediaParent.owner;

  /// The signed-in account, or null when there is no session.
  @override
  String? get currentOwnerId =>
      SupabaseConfig.useSupabaseAuth ? _supabase.currentOwnerId : _currentUserId;

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
