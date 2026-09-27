import 'package:flutter/foundation.dart';

/// Signed Offer-media URLs, held in memory only and only until shortly
/// before they expire.
///
/// A signed URL is transport, not identity: it is never written to disk,
/// never used as a cache key and never logged. Holding the last one per item
/// lets a reopened Offer (or a video tapped to play) reuse a still-valid URL
/// instead of waiting for a new one, and an entry close to expiry is treated
/// as absent so nothing is ever handed out that is about to stop working.
///
/// Keys are account-scoped `offerMediaCacheKey`s, and the whole cache is
/// cleared when the signed-in account changes.
class OfferMediaUrlCache {
  OfferMediaUrlCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final OfferMediaUrlCache instance = OfferMediaUrlCache();

  /// An entry this close to its expiry is no longer handed out.
  static const Duration safetyMargin = Duration(seconds: 60);

  final DateTime Function() _now;
  final Map<String, OfferMediaUrlEntry> _entries = {};

  void put(
    String cacheKey,
    String url,
    DateTime expiresAt, {
    bool isVideo = false,
    int? durationMs,
  }) {
    if (cacheKey.isEmpty || url.isEmpty) return;
    _entries[cacheKey] = OfferMediaUrlEntry(
      url: url,
      expiresAt: expiresAt,
      isVideo: isVideo,
      durationMs: durationMs,
    );
  }

  /// The URL for [cacheKey] while it is safely valid; null otherwise.
  OfferMediaUrlEntry? get(String? cacheKey) {
    if (cacheKey == null) return null;
    final entry = _entries[cacheKey];
    if (entry == null) return null;
    if (!_now().isBefore(entry.expiresAt.subtract(safetyMargin))) {
      _entries.remove(cacheKey);
      return null;
    }
    return entry;
  }

  /// Forgets one URL, e.g. after R2 refused it.
  void invalidate(String? cacheKey) {
    if (cacheKey != null) _entries.remove(cacheKey);
  }

  void clear() => _entries.clear();

  @visibleForTesting
  int get length => _entries.length;
}

@immutable
class OfferMediaUrlEntry {
  const OfferMediaUrlEntry({
    required this.url,
    required this.expiresAt,
    this.isVideo = false,
    this.durationMs,
  });

  final String url;
  final DateTime expiresAt;
  final bool isVideo;
  final int? durationMs;
}
