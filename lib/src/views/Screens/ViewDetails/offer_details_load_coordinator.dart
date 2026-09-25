import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';

typedef OfferMetadataLoader = Future<OfferModel?> Function(String offerId);
typedef OfferMediaResolver = Future<OfferMediaResolution?> Function({
  required String offerId,
  required String ownerId,
});
typedef CachedOfferMediaReader = List<OfferMediaRef> Function(String offerId);

/// Coordinates the three sources Offer Details draws from, in the order they
/// can actually produce pixels.
///
/// 1. **Locally held media**, read synchronously at construction. Private R2
///    media is addressed by a durable `media_objects.id` rather than by its
///    signed URL, so bytes this device already holds can be drawn on the very
///    first frame — before any network call exists.
/// 2. **The authoritative Offer row**, which gates private textual fields.
/// 3. **Freshly signed media URLs**, for anything not held locally and to pick
///    up media added elsewhere.
///
/// Stages 2 and 3 run *concurrently*. Media resolution needs only the Offer id
/// and the owning account — never the Offer row — so making it wait behind the
/// metadata read added a whole round trip to every open for no authorization
/// benefit: the Worker re-verifies ownership server-side regardless, and the
/// session/owner agreement is re-checked here before any result is adopted.
///
/// A monotonically increasing generation rejects late results after a
/// different Offer starts loading or the owning widget is disposed.
class OfferDetailsLoadCoordinator {
  OfferDetailsLoadCoordinator({
    required OfferModel initialOffer,
    required bool initialMetadataResolved,
    required OfferMetadataLoader loadMetadata,
    required OfferMediaResolver resolveMedia,
    required void Function() onChanged,
    CachedOfferMediaReader? readCachedMedia,
  })  : _offer = initialOffer,
        _metadataResolved = initialMetadataResolved,
        _loadMetadata = loadMetadata,
        _resolveMedia = resolveMedia,
        _readCachedMedia = readCachedMedia,
        _onChanged = onChanged {
    _seedFromLocalMedia();
  }

  final OfferMetadataLoader _loadMetadata;
  final OfferMediaResolver _resolveMedia;
  final CachedOfferMediaReader? _readCachedMedia;
  void Function()? _onChanged;

  OfferModel _offer;
  List<OfferMediaRef> _mediaItems = const <OfferMediaRef>[];
  bool _mediaIsAuthoritative = false;
  bool _metadataResolved;
  bool _isMetadataLoading = false;
  bool _isMediaLoading = false;
  bool _metadataLoadFailed = false;
  bool _mediaLoadFailed = false;
  bool _mediaAccessRevoked = false;
  bool _detailsUnavailable = false;
  int _generation = 0;
  bool _disposed = false;

  OfferModel get offer => _offer;

  /// Media in display order: locally held items until an authoritative
  /// resolution replaces them wholesale.
  List<OfferMediaRef> get mediaItems => _mediaItems;

  /// Whether anything can be drawn right now — locally held bytes or a live
  /// signed URL. Drives showing the gallery instead of a loading state.
  bool get hasRenderableMedia => _mediaItems.any((item) => item.isRenderable);

  /// Whether the displayed media set came from the server this session.
  bool get mediaIsAuthoritative => _mediaIsAuthoritative;

  bool get isMetadataLoading => _isMetadataLoading;
  bool get isMediaLoading => _isMediaLoading;
  bool get metadataLoadFailed => _metadataLoadFailed;
  bool get mediaLoadFailed => _mediaLoadFailed;

  /// The server answered authoritatively that this account has no such Offer.
  ///
  /// Distinct from [mediaLoadFailed], which is a retryable transport problem.
  /// Nothing is displayed and retrying is not offered, because a retry cannot
  /// change the answer.
  bool get mediaAccessRevoked => _mediaAccessRevoked;
  bool get detailsUnavailable => _detailsUnavailable;

  bool get isLoading => _isMetadataLoading || _isMediaLoading;
  bool get hasRecoverableFailure => _metadataLoadFailed || _mediaLoadFailed;
  bool get hasMediaProblem => _mediaLoadFailed || _mediaAccessRevoked;

  /// Draws on what this device already holds, with no network and no await.
  ///
  /// Only consults the local catalogue when the caller arrived with no media
  /// of its own; a model that already carries resolved URLs is the better
  /// source and is used as-is.
  void _seedFromLocalMedia() {
    final offerId = _offer.id?.trim();
    if (offerId == null || offerId.isEmpty) return;
    if (_offer.mediaUrls.isNotEmpty) {
      _mediaItems = _refsFromOffer();
      return;
    }

    final reader = _readCachedMedia;
    if (reader == null) return;
    try {
      final cached = reader(offerId);
      if (cached.isNotEmpty) _mediaItems = cached;
    } catch (_) {
      // A cold local cache is not an error; the network path still runs.
    }
  }

  /// Media refs for an Offer model that already carries resolved URLs, so a
  /// caller-supplied model renders through the same path as a resolution.
  List<OfferMediaRef> _refsFromOffer() {
    final urls = _offer.mediaUrls;
    final ids = _offer.mediaObjectIds;
    final aligned = ids.length == urls.length;
    return <OfferMediaRef>[
      for (var i = 0; i < urls.length; i++)
        OfferMediaRef(
          mediaObjectId: aligned ? ids[i] : '',
          cacheKey: aligned
              ? offerMediaCacheKey(
                  ownerId: _offer.userId,
                  mediaObjectId: ids[i],
                )
              : null,
          signedUrl: urls[i],
        ),
    ];
  }

  Future<void> load({bool refreshMetadata = false}) async {
    if (_disposed) return;
    final offerId = _offer.id?.trim();
    if (offerId == null || offerId.isEmpty) {
      _detailsUnavailable = true;
      _isMetadataLoading = false;
      _isMediaLoading = false;
      _notify();
      return;
    }

    final generation = ++_generation;
    _detailsUnavailable = false;
    _metadataLoadFailed = false;
    _mediaLoadFailed = false;
    _mediaAccessRevoked = false;

    final needsMetadata = refreshMetadata || !_metadataResolved;
    // The owner is known up front for any Offer that arrived from an
    // owner-scoped list or a previous authoritative read, which covers every
    // real entry point into this screen.
    final knownOwnerId = _offer.userId.trim();

    Future<OfferMediaResolution?>? mediaFuture;
    if (knownOwnerId.isNotEmpty) {
      _isMediaLoading = true;
      mediaFuture = _startMedia(offerId, knownOwnerId);
    }

    _isMetadataLoading = needsMetadata;
    _notify();

    var resolvedOffer = _offer;
    if (needsMetadata) {
      try {
        final metadata = await _loadMetadata(offerId);
        if (!_accepts(generation, offerId)) return;
        _isMetadataLoading = false;
        if (metadata == null || metadata.id?.trim() != offerId) {
          _detailsUnavailable = true;
          _isMediaLoading = false;
          _notify();
          return;
        }
        resolvedOffer = metadata;
        _offer = _withCurrentMedia(metadata);
        _metadataResolved = true;
        _notify();
      } catch (_) {
        if (!_accepts(generation, offerId)) return;
        _isMetadataLoading = false;
        _isMediaLoading = false;
        _metadataLoadFailed = true;
        _notify();
        return;
      }
    }

    // The authoritative row is the authority on who owns this Offer. If media
    // was started against a different owner — only reachable from a stale
    // caller-supplied model — that result is discarded and re-requested.
    final ownerId = resolvedOffer.userId.trim();
    if (ownerId.isEmpty) {
      if (!_accepts(generation, offerId)) return;
      _isMediaLoading = false;
      _mediaLoadFailed = true;
      _notify();
      return;
    }
    if (mediaFuture == null || ownerId != knownOwnerId) {
      _isMediaLoading = true;
      _notify();
      mediaFuture = _startMedia(offerId, ownerId);
    }

    try {
      final media = await mediaFuture;
      if (!_accepts(generation, offerId)) return;
      _isMediaLoading = false;
      if (media == null) {
        // A backend with no separate media stage keeps what metadata gave us.
        _mediaItems = _refsFromOffer();
        _mediaIsAuthoritative = true;
        _notify();
        return;
      }
      if (media.offerId != offerId || media.ownerId != ownerId) {
        throw StateError('Resolved media does not belong to this Offer.');
      }
      _mediaItems = media.items;
      _mediaIsAuthoritative = true;
      _offer = applyOfferMedia(_offer, media);
      _notify();
    } on OfferMediaException catch (error) {
      if (!_accepts(generation, offerId)) return;
      _isMediaLoading = false;
      if (error.isAccessDenied) {
        // Proven gone for this account. The service has already removed this
        // device's copy; stop presenting it so nothing can redisplay it from
        // memory, and do not offer a retry that cannot succeed.
        _mediaItems = const <OfferMediaRef>[];
        _mediaAccessRevoked = true;
        _offer = applyOfferMedia(
          _offer,
          OfferMediaResolution(
            offerId: offerId,
            ownerId: _offer.userId,
            items: const <OfferMediaRef>[],
          ),
        );
      } else {
        // Nothing about access is established — offline, a timeout, an
        // upstream failure or a rejected token — so whatever is already on
        // screen stays, and a retry is offered.
        _mediaLoadFailed = true;
      }
      _notify();
    } catch (_) {
      if (!_accepts(generation, offerId)) return;
      _isMediaLoading = false;
      _mediaLoadFailed = true;
      _notify();
    }
  }

  /// Starts media resolution without letting a failure escape as an unhandled
  /// async error while the metadata read is still being awaited.
  Future<OfferMediaResolution?> _startMedia(String offerId, String ownerId) {
    final future = _resolveMedia(offerId: offerId, ownerId: ownerId);
    future.then((_) {}, onError: (Object _) {});
    return future;
  }

  /// Keeps whatever media is currently displayable when a fresh metadata row
  /// arrives, so a refresh never blanks an image that is already on screen.
  OfferModel _withCurrentMedia(OfferModel metadata) {
    if (_mediaItems.isEmpty) return metadata;
    final urls = <String>[
      for (final item in _mediaItems)
        if (item.hasSignedUrl) item.signedUrl!,
    ];
    if (urls.isEmpty) return metadata;
    return metadata.copyWith(
      mediaUrls: urls,
      mediaUrl: urls.first,
      mediaObjectIds: [for (final item in _mediaItems) item.mediaObjectId],
    );
  }

  /// Retry is only meaningful for a transport problem.
  Future<void> retry() {
    if (_mediaAccessRevoked && !_metadataLoadFailed) return Future.value();
    return load(refreshMetadata: _metadataLoadFailed);
  }

  Future<void> reload() => load(refreshMetadata: true);

  void invalidate() {
    _generation += 1;
    _isMetadataLoading = false;
    _isMediaLoading = false;
  }

  bool _accepts(int generation, String offerId) =>
      !_disposed && generation == _generation && _offer.id?.trim() == offerId;

  void _notify() {
    if (!_disposed) _onChanged?.call();
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _onChanged = null;
  }
}
