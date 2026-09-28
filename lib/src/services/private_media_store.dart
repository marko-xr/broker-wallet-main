import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;

/// What a private-media form or gallery needs from its records' service:
/// the record's media as this device holds it, as the server lists it, and
/// as the upload queue is sending it — always addressed by media identity,
/// never by URL.
///
/// Implemented by `OwnerService` for Owner records. (The Offer screens reach
/// the same queue, Worker and cache through `OfferService` directly.)
abstract interface class PrivateMediaStore {
  /// Which records' media this store serves.
  MediaParent get parent;

  /// The signed-in account, or null when there is no session.
  String? get currentOwnerId;

  /// What this device already holds for [recordId], with no network at all.
  List<OfferMediaRef> cachedMedia(String recordId);

  /// The record's confirmed media with fresh signed links, or null when the
  /// backend has no separate media stage.
  Future<OfferMediaResolution?> resolveMedia({
    required String recordId,
    required String ownerId,
  });

  /// The record's items still in the upload queue, with their state.
  List<OfferMediaRef> pendingMedia(String recordId);

  /// Notifies whenever a queued item changes.
  Listenable get uploadChanges;

  /// Each queued item of this store's records that the server has accepted.
  Stream<OfferMediaUploadCompleted> get uploadCompletions;

  /// Loads the persisted upload queue so pending items can be shown.
  Future<void> loadUploads();

  /// The user's Retry for a queued item.
  Future<void> retryUpload(String mediaObjectId);

  /// The user's Remove for a queued item.
  Future<void> cancelUpload(String mediaObjectId);
}
