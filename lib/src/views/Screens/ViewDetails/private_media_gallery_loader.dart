import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/private_media_store.dart';

/// Loads one record's private media for a details screen — used by Owner
/// Details — in the order it can produce pixels, as Offer Details does
/// (see `OfferDetailsLoadCoordinator`, whose media half this mirrors):
///
/// 1. **What this device holds**, read synchronously at construction, so a
///    reopened record draws on its first frame with no network.
/// 2. **This device's items still in the upload queue**, each with its
///    state, playable from the local copy.
/// 3. **The server's list with freshly signed links**, which replaces the
///    local set wholesale — an empty answer clears it rather than leaving a
///    removed item addressable.
///
/// A proven "no such record for this account" (the Worker's authoritative
/// 404) clears everything and stops offering a retry; any other failure keeps
/// what is on screen and offers one. A monotonically increasing generation
/// rejects late results once the loader is disposed or reloads.
class PrivateMediaGalleryLoader {
  PrivateMediaGalleryLoader({
    required String recordId,
    required PrivateMediaStore store,
    required void Function() onChanged,
  })  : _recordId = recordId.trim(),
        _store = store,
        _onChanged = onChanged {
    _seedFromLocalMedia();
  }

  final String _recordId;
  final PrivateMediaStore _store;
  void Function()? _onChanged;

  List<OfferMediaRef> _mediaItems = const <OfferMediaRef>[];
  bool _mediaIsAuthoritative = false;
  bool _isLoading = false;
  bool _loadFailed = false;
  bool _accessRevoked = false;
  int _generation = 0;
  bool _disposed = false;

  String get recordId => _recordId;

  /// What the gallery shows: the record's media, then this device's items
  /// still in the upload queue — each with its upload state, and never
  /// twice. Nothing queued is shown once access is proven gone.
  List<OfferMediaRef> get displayItems {
    final pending = _pendingMedia();
    if (pending.isEmpty || _accessRevoked) return _mediaItems;
    final shown = {for (final item in _mediaItems) item.mediaObjectId};
    return <OfferMediaRef>[
      ..._mediaItems,
      for (final item in pending)
        if (shown.add(item.mediaObjectId)) item,
    ];
  }

  List<OfferMediaRef> _pendingMedia() {
    if (_recordId.isEmpty) return const <OfferMediaRef>[];
    try {
      return _store.pendingMedia(_recordId);
    } catch (_) {
      return const <OfferMediaRef>[];
    }
  }

  /// Whether anything can be drawn right now — locally held bytes, a live
  /// signed link or a video's still frame.
  bool get hasRenderableMedia => displayItems.any((item) => item.isRenderable);

  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;

  /// The server answered authoritatively that this account has no such
  /// record: nothing is displayed and no retry is offered.
  bool get accessRevoked => _accessRevoked;

  void _seedFromLocalMedia() {
    if (_recordId.isEmpty) return;
    try {
      final cached = _store.cachedMedia(_recordId);
      if (cached.isNotEmpty) _mediaItems = cached;
    } catch (_) {
      // A cold local cache is not an error; the network path still runs.
    }
  }

  Future<void> load() async {
    if (_disposed || _recordId.isEmpty) return;
    final ownerId = _store.currentOwnerId?.trim();
    if (ownerId == null || ownerId.isEmpty) return;

    final generation = ++_generation;
    _isLoading = true;
    _loadFailed = false;
    _accessRevoked = false;
    _notify();

    try {
      final media =
          await _store.resolveMedia(recordId: _recordId, ownerId: ownerId);
      if (!_accepts(generation)) return;
      _isLoading = false;
      if (media == null) {
        // A backend with no separate media stage: keep what is shown.
        _notify();
        return;
      }
      if (media.offerId != _recordId || media.ownerId != ownerId) {
        throw StateError('Resolved media does not belong to this record.');
      }
      _mediaItems = media.items;
      _mediaIsAuthoritative = true;
      _notify();
    } on OfferMediaException catch (error) {
      if (!_accepts(generation)) return;
      _isLoading = false;
      if (error.isAccessDenied) {
        // Proven gone for this account. The service has already removed this
        // device's copy; stop presenting it.
        _mediaItems = const <OfferMediaRef>[];
        _accessRevoked = true;
      } else {
        _loadFailed = true;
      }
      _notify();
    } catch (_) {
      if (!_accepts(generation)) return;
      _isLoading = false;
      _loadFailed = true;
      _notify();
    }
  }

  /// Signs the record's media again — for a private video whose link expired
  /// — and returns [mediaObjectId]'s new link, or null when there is none.
  /// Only a link from a resolution that just succeeded is returned.
  Future<String?> refreshSignedUrl(String mediaObjectId) async {
    await load();
    if (_loadFailed || _accessRevoked || !_mediaIsAuthoritative) return null;
    for (final item in _mediaItems) {
      if (item.mediaObjectId == mediaObjectId && item.hasSignedUrl) {
        return item.signedUrl;
      }
    }
    return null;
  }

  /// Retry is only meaningful for a transport problem.
  Future<void> retry() => _accessRevoked ? Future.value() : load();

  bool _accepts(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) _onChanged?.call();
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _onChanged = null;
  }
}
