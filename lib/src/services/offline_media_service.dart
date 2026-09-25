import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';

/// What a local Offer-media cleanup actually managed to remove.
///
/// Cleanup is best effort — it runs inside account deletion, which must never
/// be blocked by a file that will not delete — but "best effort" must not mean
/// "assumed to have worked". Private image bytes are at stake, so the caller
/// is told when something was left behind rather than being allowed to report
/// a success that did not happen.
class OfferMediaCleanupReport {
  const OfferMediaCleanupReport({
    required this.catalogueEntriesRemoved,
    required this.cacheEntriesRemoved,
    required this.originalsRemoved,
    required this.failures,
    required this.sweepCompleted,
  });

  const OfferMediaCleanupReport.empty()
      : catalogueEntriesRemoved = 0,
        cacheEntriesRemoved = 0,
        originalsRemoved = 0,
        failures = 0,
        sweepCompleted = true;

  final int catalogueEntriesRemoved;
  final int cacheEntriesRemoved;
  final int originalsRemoved;

  /// Individual removals that failed.
  final int failures;

  /// Whether the app-owned directory could be enumerated to the end.
  ///
  /// False means orphaned originals — the ones no catalogue names — may still
  /// be on the device, so [isComplete] cannot be claimed.
  final bool sweepCompleted;

  /// Only true when nothing was left behind, as far as this run could tell.
  bool get isComplete => failures == 0 && sweepCompleted;

  OfferMediaCleanupReport withSweepFailed() => OfferMediaCleanupReport(
        catalogueEntriesRemoved: catalogueEntriesRemoved,
        cacheEntriesRemoved: cacheEntriesRemoved,
        originalsRemoved: originalsRemoved,
        failures: failures,
        sweepCompleted: false,
      );

  OfferMediaCleanupReport merge(OfferMediaCleanupReport other) =>
      OfferMediaCleanupReport(
        catalogueEntriesRemoved:
            catalogueEntriesRemoved + other.catalogueEntriesRemoved,
        cacheEntriesRemoved: cacheEntriesRemoved + other.cacheEntriesRemoved,
        originalsRemoved: originalsRemoved + other.originalsRemoved,
        failures: failures + other.failures,
        sweepCompleted: sweepCompleted && other.sweepCompleted,
      );

  @override
  String toString() => 'OfferMediaCleanupReport('
      'catalogues: $catalogueEntriesRemoved, '
      'cacheEntries: $cacheEntriesRemoved, '
      'originals: $originalsRemoved, '
      'failures: $failures, '
      'sweepCompleted: $sweepCompleted)';
}

/// Service to handle offline media loading for images and videos
/// Maps Firebase Storage URLs to local file paths when offline
class OfflineMediaService {
  static const String _localMediaBoxName = 'local_media';
  static const String _urlMappingBoxName = 'url_mapping';

  static OfflineMediaService? _instance;
  static OfflineMediaService get instance =>
      _instance ??= OfflineMediaService._();
  OfflineMediaService._();

  late Box _localMediaBox;
  late Box _urlMappingBox;
  bool _isInitialized = false;

  /// Initialize the offline media service
  Future<void> initialize() async {
    try {
      _localMediaBox = await Hive.openBox(_localMediaBoxName);
      _urlMappingBox = await Hive.openBox(_urlMappingBoxName);
      _isInitialized = true;
      // ✅ OfflineMediaService initialized (log removed)
    } catch (e) {
      // ⚠️ OfflineMediaService init failed: $e (log removed)
    }
  }

  /// Map Firebase URL to local file path
  Future<void> mapUrlToLocalFile(String firebaseUrl, String localPath) async {
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }

    try {
      await _urlMappingBox.put(firebaseUrl, localPath);
      // 📁 Mapped URL to local file: $firebaseUrl -> $localPath (log removed)
    } catch (e) {
      // ⚠️ Failed to map URL: $e (log removed)
    }
  }

  /// Prefix under which a stable media identity is mapped to a local file.
  ///
  /// [_urlMappingBox] is keyed by URL, which can never hit for a Cloudflare R2
  /// signed URL because the signature and expiry query parameters rotate on
  /// every resolution. A canonical `profile_media_id` does not rotate, so it is
  /// stored under its own namespaced key in the same box.
  static const String _mediaIdKeyPrefix = 'mediaId::';

  static String _mediaIdKey(String mediaId) => '$_mediaIdKeyPrefix$mediaId';

  /// Prefix under which an Offer's ordered media identity is remembered.
  ///
  /// Offer media ids only ever existed in memory, obtained from a
  /// `/offer-media` call. That made a cold open structurally incapable of
  /// drawing anything from disk: with no id there is no cache key, and with no
  /// cache key the only way to reach the bytes is a freshly signed URL — two
  /// serialised network round trips before the first pixel. Remembering the
  /// ids (which are durable) turns that into a synchronous local lookup.
  ///
  /// The key carries the authenticated owner id, so one account can never read
  /// back another account's Offer media list on a shared device.
  static const String _offerMediaCatalogPrefix = 'offerMediaCatalog::';

  static String _offerMediaCatalogKey(String ownerId, String offerId) =>
      '$_offerMediaCatalogPrefix$ownerId::$offerId';

  /// Ceiling on any single shared-image-cache call made from this service.
  ///
  /// These are best-effort maintenance operations that run inside account
  /// deletion and inside background warm-up. The cache manager reaches the
  /// platform for its own storage directory, so a call can fail in ways that
  /// never complete; bounding it guarantees a stalled cache can never stall a
  /// sign-out or leave a warm-up future pending forever.
  static const Duration _cacheCallTimeout = Duration(seconds: 5);

  /// Removes the shared image cache's copy of a stable identity's bytes.
  ///
  /// Overridable because `DefaultCacheManager` resolves its own storage
  /// through path_provider: merely constructing it under `flutter test`
  /// raises an asynchronous platform error that no caller can catch. Tests
  /// substitute a no-op so catalogue cleanup can be exercised on its own.
  @visibleForTesting
  static Future<void> Function(String cacheKey) removeCachedBytes =
      _removeBytesFromSharedCache;

  static Future<void> _removeBytesFromSharedCache(String cacheKey) =>
      DefaultCacheManager().removeFile(cacheKey).timeout(_cacheCallTimeout);

  /// The media object ids last confirmed for [offerId], in display order.
  ///
  /// Synchronous by design: it is read while building the first frame of Offer
  /// Details. Returns an empty list when nothing is remembered, which simply
  /// means the screen waits for the network exactly as it did before.
  List<String> readOfferMediaCatalog({
    required String? ownerId,
    required String? offerId,
  }) {
    final owner = ownerId?.trim();
    final offer = offerId?.trim();
    if (!_isInitialized ||
        owner == null ||
        owner.isEmpty ||
        offer == null ||
        offer.isEmpty) {
      return const <String>[];
    }

    try {
      final stored = _localMediaBox.get(_offerMediaCatalogKey(owner, offer));
      if (stored is! Map) return const <String>[];
      final ids = stored['ids'];
      if (ids is! List) return const <String>[];
      return <String>[
        for (final id in ids)
          if (id is String && id.trim().isNotEmpty) id.trim(),
      ];
    } catch (e) {
      return const <String>[];
    }
  }

  /// Replaces the remembered media identity for [offerId] wholesale.
  ///
  /// Always a replacement, never a merge: an authoritative `/offer-media`
  /// response is the complete current media set, so an empty response must
  /// clear the catalogue rather than leave a removed item addressable.
  Future<void> writeOfferMediaCatalog({
    required String? ownerId,
    required String? offerId,
    required List<String> mediaObjectIds,
  }) async {
    final owner = ownerId?.trim();
    final offer = offerId?.trim();
    if (owner == null || owner.isEmpty || offer == null || offer.isEmpty) {
      return;
    }
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }

    try {
      await _localMediaBox.put(_offerMediaCatalogKey(owner, offer), {
        'version': 1,
        'ids': <String>[
          for (final id in mediaObjectIds)
            if (id.trim().isNotEmpty) id.trim(),
        ],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      // Best effort: a missing catalogue only costs the previous behaviour.
    }
  }

  /// Replaces the remembered media identity for an Offer and removes what
  /// the new set no longer contains.
  ///
  /// An authoritative `/offer-media` response is the complete current media
  /// set, so an id it no longer lists has been removed server side. This is
  /// the only removal signal the current architecture provides — there is no
  /// client-side delete path — and applying it here is what stops a removed
  /// photo's bytes, its identity mapping and its adopted original lingering
  /// on the device and being redisplayed.
  ///
  /// Returns what the removal of the dropped ids managed to clean up.
  Future<OfferMediaCleanupReport> reconcileOfferMediaCatalog({
    required String? ownerId,
    required String? offerId,
    required List<String> mediaObjectIds,
  }) async {
    final owner = ownerId?.trim();
    final offer = offerId?.trim();
    if (owner == null || owner.isEmpty || offer == null || offer.isEmpty) {
      return const OfferMediaCleanupReport.empty();
    }

    final current = mediaObjectIds.toSet();
    final dropped = readOfferMediaCatalog(ownerId: owner, offerId: offer)
        .where((id) => !current.contains(id))
        .toList(growable: false);

    await writeOfferMediaCatalog(
      ownerId: owner,
      offerId: offer,
      mediaObjectIds: mediaObjectIds,
    );

    if (dropped.isEmpty) return const OfferMediaCleanupReport.empty();
    return forgetOfferMediaItems(ownerId: owner, mediaObjectIds: dropped);
  }

  /// Ensures this device holds the bytes for [cacheKey] and remembers where.
  ///
  /// Downloads through the same [DefaultCacheManager] the display widget reads
  /// from, keyed by the stable identity rather than the rotating signed URL,
  /// then records the resulting path so the *next* open can paint from it
  /// synchronously — before any URL exists. Returns the local path, or null
  /// when the bytes could not be obtained.
  Future<String?> ensureMediaIdCached({
    required String? cacheKey,
    required String? url,
  }) async {
    final key = cacheKey?.trim();
    if (key == null || key.isEmpty) return null;

    final existing = getLocalFilePathForMediaId(key);
    if (existing != null && File(existing).existsSync()) return existing;

    final source = url?.trim();
    final path = await fetchCachedBytes(
      key,
      source != null && source.isNotEmpty && _isValidNetworkUrl(source)
          ? source
          : null,
    );
    if (path == null || !File(path).existsSync()) return null;

    await mapMediaIdToLocalFile(key, path);
    return path;
  }

  /// Returns the shared image cache's file for a stable identity, fetching it
  /// from [url] if the cache does not hold it yet.
  ///
  /// Overridable for the same reason as [removeCachedBytes]: constructing
  /// `DefaultCacheManager` reaches path_provider, which does not exist under
  /// `flutter test`.
  @visibleForTesting
  static Future<String?> Function(String cacheKey, String? url)
      fetchCachedBytes = _fetchBytesFromSharedCache;

  static Future<String?> _fetchBytesFromSharedCache(
    String cacheKey,
    String? url,
  ) async {
    try {
      final held = await DefaultCacheManager()
          .getFileFromCache(cacheKey)
          .timeout(_cacheCallTimeout);
      final heldPath = held?.file.path;
      if (heldPath != null && File(heldPath).existsSync()) return heldPath;
    } catch (e) {
      // Fall through and try to fetch it.
    }

    if (url == null) return null;
    try {
      final file = await DefaultCacheManager()
          .getSingleFile(url, key: cacheKey)
          .timeout(_cacheCallTimeout);
      return file.existsSync() ? file.path : null;
    } catch (e) {
      // Offline, or an expired signature: the display path still renders from
      // the network when it can, and the next resolution retries this.
      return null;
    }
  }

  /// The app-owned directory holding adopted Offer originals.
  ///
  /// Files here are named after the sanitized account-scoped cache key, so the
  /// account owning each one is readable from its name alone. That is what
  /// makes an ownership-scoped sweep possible without a catalogue.
  static const String offerMediaDirectoryName = 'offer_media';

  /// Where app-owned media directories are created.
  ///
  /// Overridable for the same reason as [removeCachedBytes]: path_provider
  /// has no implementation under `flutter test`, and cleanup that deletes
  /// files must be exercised against a temporary directory rather than
  /// asserted from source.
  @visibleForTesting
  static Future<Directory> Function() resolveDocumentsDirectory =
      getApplicationDocumentsDirectory;

  static final RegExp _unsafeFileSegment = RegExp(r'[^A-Za-z0-9_-]');

  /// The file-name form of a cache key, matching [adoptLocalFileForMediaId].
  static String _safeFileSegment(String value) =>
      value.replaceAll(_unsafeFileSegment, '_');

  /// The file-name prefix every adopted original of [ownerId] starts with.
  ///
  /// Returns null when [ownerId] is missing or sanitizes to nothing, which
  /// deliberately disables the sweep rather than letting it match every file.
  static String? _offerOriginalPrefixFor(String? ownerId) {
    final owner = ownerId?.trim();
    if (owner == null || owner.isEmpty) return null;
    final safeOwner = _safeFileSegment(owner);
    if (safeOwner.replaceAll('_', '').isEmpty) return null;
    return '${_safeFileSegment('offer-media')}_${safeOwner}_';
  }

  /// Listeners that drop in-memory copies of bytes this service just removed.
  ///
  /// Deleting a file and its cache entry is not enough on its own: a decoded
  /// image or a retained `ImageProvider` can still redisplay bytes that are
  /// gone from disk. The presentation layer registers here so removal reaches
  /// memory too, without this service having to know about widgets.
  static final List<void Function(String cacheKey)> _forgetListeners =
      <void Function(String cacheKey)>[];

  static void addCacheKeyForgetListener(void Function(String cacheKey) l) {
    if (!_forgetListeners.contains(l)) _forgetListeners.add(l);
  }

  static void removeCacheKeyForgetListener(void Function(String cacheKey) l) {
    _forgetListeners.remove(l);
  }

  static void _notifyForgotten(String cacheKey) {
    for (final listener in List.of(_forgetListeners)) {
      try {
        listener(cacheKey);
      } catch (e) {
        // A presentation cache that cannot forget must not stop the rest.
      }
    }
  }

  /// Removes everything held for [mediaObjectIds] of [ownerId] and nothing
  /// else: the cached bytes, the identity mapping, the adopted original, and
  /// any in-memory copy.
  ///
  /// Used when an authoritative response drops media that used to exist, and
  /// when access to an Offer is proven revoked. Idempotent.
  Future<OfferMediaCleanupReport> forgetOfferMediaItems({
    required String? ownerId,
    required Iterable<String> mediaObjectIds,
  }) async {
    final owner = ownerId?.trim();
    if (owner == null || owner.isEmpty) {
      return const OfferMediaCleanupReport.empty();
    }
    if (!_isInitialized) await initialize();

    var report = const OfferMediaCleanupReport.empty();
    for (final id in mediaObjectIds) {
      final cacheKey = offerMediaCacheKey(ownerId: owner, mediaObjectId: id);
      if (cacheKey == null) continue;
      report = report.merge(await _removeArtifactsFor(cacheKey));
    }
    return report;
  }

  /// Removes every trace of one cache key. Never throws.
  Future<OfferMediaCleanupReport> _removeArtifactsFor(String cacheKey) async {
    var originalsRemoved = 0;
    var cacheEntriesRemoved = 0;
    var failures = 0;

    final mappedPath = getLocalFilePathForMediaId(cacheKey);
    if (mappedPath != null &&
        mappedPath.isNotEmpty &&
        _isInsideOfferMediaDirectory(mappedPath)) {
      try {
        final file = File(mappedPath);
        if (await file.exists()) {
          await file.delete();
          originalsRemoved += 1;
        }
      } catch (e) {
        failures += 1;
      }
    }

    try {
      await removeCachedBytes(cacheKey);
      cacheEntriesRemoved += 1;
    } catch (e) {
      failures += 1;
    }

    if (_isInitialized) {
      try {
        await _urlMappingBox.delete(_mediaIdKey(cacheKey));
      } catch (e) {
        failures += 1;
      }
    }

    _notifyForgotten(cacheKey);

    return OfferMediaCleanupReport(
      catalogueEntriesRemoved: 0,
      cacheEntriesRemoved: cacheEntriesRemoved,
      originalsRemoved: originalsRemoved,
      failures: failures,
      sweepCompleted: true,
    );
  }

  /// Whether [path] names a file this service itself adopted.
  ///
  /// A mapped path can point anywhere — [adoptLocalFileForMediaId] falls back
  /// to the picked file when its copy fails — so deletion is confined to the
  /// app-owned directory. A path outside it is left alone.
  bool _isInsideOfferMediaDirectory(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/$offerMediaDirectoryName/');
  }

  /// Removes the remembered Offer-media catalogue, the cached bytes behind it,
  /// the adopted originals, and any in-memory copy.
  ///
  /// With [ownerId] given, only that account is touched — the case after a
  /// different account has already signed in, and the case account deletion
  /// always takes. Without it, everything is removed.
  ///
  /// A catalogue is not a complete inventory: an upload adopted before the
  /// Offer was ever viewed, a catalogue write that failed, and media dropped
  /// by a later response all leave originals that no catalogue names. So the
  /// app-owned directory is also swept by file-name ownership prefix, which is
  /// what stops private originals surviving an account deletion.
  ///
  /// Best effort and idempotent. The returned report states what was removed
  /// and whether anything was left behind; it never claims a success it cannot
  /// support.
  Future<OfferMediaCleanupReport> forgetOfferMedia({String? ownerId}) async {
    if (!_isInitialized) await initialize();

    final owner = ownerId?.trim();
    final scoped = owner != null && owner.isNotEmpty;
    final cacheKeys = <String>{};
    final catalogKeys = <String>[];
    var catalogueEntriesRemoved = 0;
    var failures = 0;

    if (_isInitialized) {
      try {
        for (final key in _localMediaBox.keys) {
          if (key is! String || !key.startsWith(_offerMediaCatalogPrefix)) {
            continue;
          }
          final entryOwner =
              key.substring(_offerMediaCatalogPrefix.length).split('::').first;
          if (scoped && entryOwner != owner) continue;
          catalogKeys.add(key);

          final stored = _localMediaBox.get(key);
          final ids = stored is Map ? stored['ids'] : null;
          if (ids is! List) continue;
          for (final id in ids) {
            if (id is! String || id.trim().isEmpty) continue;
            final cacheKey = offerMediaCacheKey(
              ownerId: entryOwner,
              mediaObjectId: id,
            );
            if (cacheKey != null) cacheKeys.add(cacheKey);
          }
        }
      } catch (e) {
        failures += 1;
      }

      for (final key in catalogKeys) {
        try {
          await _localMediaBox.delete(key);
          catalogueEntriesRemoved += 1;
        } catch (e) {
          failures += 1;
        }
      }
    } else {
      // Without Hive there is no catalogue to consult. The directory sweep
      // below still runs, which is exactly why it does not depend on one.
      failures += 1;
    }

    var report = OfferMediaCleanupReport(
      catalogueEntriesRemoved: catalogueEntriesRemoved,
      cacheEntriesRemoved: 0,
      originalsRemoved: 0,
      failures: failures,
      sweepCompleted: true,
    );

    for (final cacheKey in cacheKeys) {
      report = report.merge(await _removeArtifactsFor(cacheKey));
    }

    return report.merge(await _sweepOfferOriginals(scoped ? owner : null));
  }

  /// Deletes adopted originals in the app-owned directory that belong to
  /// [ownerId], including any that no catalogue names.
  ///
  /// With [ownerId] null the whole directory goes. With an owner, only files
  /// whose name carries that account's prefix are touched, so another
  /// account's originals on the same device are never removed. Symbolic links
  /// are not followed, and nothing outside the directory is visited.
  Future<OfferMediaCleanupReport> _sweepOfferOriginals(String? ownerId) async {
    Directory directory;
    try {
      final appDir = await resolveDocumentsDirectory();
      directory = Directory('${appDir.path}/$offerMediaDirectoryName');
      if (!await directory.exists()) {
        return const OfferMediaCleanupReport.empty();
      }
    } catch (e) {
      // The directory could not even be located, so nothing can be claimed.
      return const OfferMediaCleanupReport.empty().withSweepFailed();
    }

    if (ownerId == null) {
      try {
        await directory.delete(recursive: true);
        return const OfferMediaCleanupReport.empty();
      } catch (e) {
        return const OfferMediaCleanupReport.empty().withSweepFailed();
      }
    }

    final prefix = _offerOriginalPrefixFor(ownerId);
    if (prefix == null) {
      // An unusable owner id must never be allowed to match every file.
      return const OfferMediaCleanupReport.empty().withSweepFailed();
    }

    var removed = 0;
    var failures = 0;
    try {
      final entries = await directory.list(followLinks: false).toList();
      for (final entry in entries) {
        // Only real files: a Link is never followed and never deleted.
        if (entry is! File) continue;
        final name = entry.path.split(RegExp(r'[\\/]')).last;
        if (!name.startsWith(prefix)) continue;
        try {
          if (await entry.exists()) {
            await entry.delete();
            removed += 1;
          }
        } catch (e) {
          failures += 1;
        }
      }
    } catch (e) {
      return OfferMediaCleanupReport(
        catalogueEntriesRemoved: 0,
        cacheEntriesRemoved: 0,
        originalsRemoved: removed,
        failures: failures,
        sweepCompleted: false,
      );
    }

    return OfferMediaCleanupReport(
      catalogueEntriesRemoved: 0,
      cacheEntriesRemoved: 0,
      originalsRemoved: removed,
      failures: failures,
      sweepCompleted: true,
    );
  }

  /// Map a stable media identity (Supabase `profile_media_id`) to local bytes.
  Future<void> mapMediaIdToLocalFile(String mediaId, String localPath) async {
    if (mediaId.isEmpty || localPath.isEmpty) return;
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }

    try {
      await _urlMappingBox.put(_mediaIdKey(mediaId), localPath);
    } catch (e) {
      // Best effort: a missing mapping only costs a network fetch.
    }
  }

  /// Binds a freshly confirmed media identity to the image the user just
  /// picked, so the authoritative image renders from the same bytes the
  /// optimistic preview was already showing — no download, no blank frame.
  ///
  /// The picked file normally lives in the image picker's cache directory,
  /// which the OS may purge. It is copied into an app-owned directory first so
  /// the mapping survives. If the copy fails, the picked file is mapped
  /// directly: that still makes the transition seamless now, and
  /// [warmMediaIdMapping] re-heals the mapping from the network cache if the
  /// file later disappears.
  ///
  /// Uses its own directory rather than `local_media`, so a future
  /// [cleanupOldFiles] run can never delete the current avatar.
  Future<void> adoptLocalFileForMediaId(
    String mediaId,
    String sourcePath, {
    String directoryName = 'profile_media',
  }) async {
    if (mediaId.isEmpty || sourcePath.isEmpty) return;

    var mappedPath = sourcePath;
    try {
      final source = File(sourcePath);
      if (await source.exists()) {
        final appDir = await resolveDocumentsDirectory();
        final profileDir = Directory('${appDir.path}/$directoryName');
        if (!await profileDir.exists()) {
          await profileDir.create(recursive: true);
        }

        final safeId = mediaId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
        final dot = sourcePath.lastIndexOf('.');
        final extension =
            dot > sourcePath.lastIndexOf('/') ? sourcePath.substring(dot) : '';
        final copy = await source.copy('${profileDir.path}/$safeId$extension');
        mappedPath = copy.path;
      }
    } catch (e) {
      // Fall back to the picked file; see above.
    }

    await mapMediaIdToLocalFile(mediaId, mappedPath);
  }

  /// Records where the image cache stored the bytes for [mediaId].
  ///
  /// Without this, a cold start still shows a placeholder until a fresh signed
  /// URL resolves, because `CachedNetworkImage` needs a URL before it will
  /// consult its cache. Persisting the file path against the stable media
  /// identity means the next cold start resolves it synchronously and paints
  /// the real image with no URL and no network at all.
  ///
  /// Returns the local path when one is available.
  Future<String?> warmMediaIdMapping(String? mediaId) async {
    if (mediaId == null || mediaId.isEmpty) return null;

    final existing = getLocalFilePathForMediaId(mediaId);
    if (existing != null && File(existing).existsSync()) return existing;

    try {
      final cached = await DefaultCacheManager().getFileFromCache(mediaId);
      final path = cached?.file.path;
      if (path == null || !File(path).existsSync()) return null;
      await mapMediaIdToLocalFile(mediaId, path);
      return path;
    } catch (e) {
      return null;
    }
  }

  /// Removes locally held profile avatars after an account is deleted.
  ///
  /// With [mediaIds] null, every `mediaId::` mapping, the image-cache entry
  /// keyed by each of those ids, and the app-owned `profile_media` directory
  /// are removed. These are re-downloadable presentation caches that are not
  /// partitioned by account, so clearing all of them costs another account on
  /// this device at most one avatar download. With [mediaIds] given, only those
  /// identities are removed — used when a different account is already signed
  /// in. Best effort throughout.
  Future<void> forgetProfileMedia({Iterable<String>? mediaIds}) async {
    if (!_isInitialized) {
      await initialize();
    }

    final targets = <String>{
      ...?mediaIds?.where((id) => id.isNotEmpty),
    };
    if (_isInitialized && mediaIds == null) {
      try {
        for (final key in _urlMappingBox.keys) {
          if (key is String && key.startsWith(_mediaIdKeyPrefix)) {
            targets.add(key.substring(_mediaIdKeyPrefix.length));
          }
        }
      } catch (e) {
        // Fall through with whatever was collected.
      }
    }

    for (final mediaId in targets) {
      final mappedPath = getLocalFilePathForMediaId(mediaId);
      if (mappedPath != null && mediaIds != null) {
        try {
          final file = File(mappedPath);
          if (mappedPath.contains('/profile_media/') && await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          // Best effort.
        }
      }
      try {
        await DefaultCacheManager().removeFile(mediaId);
      } catch (e) {
        // Best effort.
      }
      if (_isInitialized) {
        try {
          await _urlMappingBox.delete(_mediaIdKey(mediaId));
        } catch (e) {
          // Best effort.
        }
      }
    }

    if (mediaIds == null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final profileDir = Directory('${appDir.path}/profile_media');
        if (await profileDir.exists()) {
          await profileDir.delete(recursive: true);
        }
      } catch (e) {
        // Best effort.
      }
    }
  }

  /// Local file already held for a stable media identity, if any.
  String? getLocalFilePathForMediaId(String? mediaId) {
    if (mediaId == null || mediaId.isEmpty) return null;
    if (!_isInitialized) return null;

    try {
      return _urlMappingBox.get(_mediaIdKey(mediaId)) as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get local file path for Firebase URL
  String? getLocalFilePath(String firebaseUrl) {
    if (!_isInitialized) return null;

    try {
      return _urlMappingBox.get(firebaseUrl);
    } catch (e) {
      return null;
    }
  }

  /// Check if local file exists for given Firebase URL
  Future<bool> hasLocalFile(String firebaseUrl) async {
    final localPath = getLocalFilePath(firebaseUrl);
    if (localPath == null) return false;

    final file = File(localPath);
    return await file.exists();
  }

  /// Get ImageProvider that checks local files first
  ImageProvider getImageProvider(String imageUrl) {
    // Handle local:// URLs first
    if (imageUrl.startsWith('local://')) {
      final localPath = getLocalFilePath(imageUrl);
      if (localPath != null) {
        final file = File(localPath);
        if (file.existsSync()) {
          // 📱 Using local image: $localPath (log removed)
          return FileImage(file);
        }
      }
      // For local:// URLs that don't have a local file, return a broken image provider
      // instead of trying to use CachedNetworkImageProvider which doesn't support local:// scheme
      return const AssetImage('assets/icons/placeholder.png');
    }

    // Check if we have a local file for this URL (Firebase URLs)
    final localPath = getLocalFilePath(imageUrl);
    if (localPath != null) {
      final file = File(localPath);
      if (file.existsSync()) {
        // 📱 Using local image: $localPath (log removed)
        return FileImage(file);
      }
    }

    // Only use CachedNetworkImageProvider for valid network URLs
    if (!_isValidNetworkUrl(imageUrl)) {
      // For invalid URLs, return a placeholder
      return const AssetImage('assets/icons/placeholder.png');
    }

    // Fallback to network image
    return CachedNetworkImageProvider(
      imageUrl,
      cacheKey: imageUrl,
      maxWidth: 800,
      maxHeight: 600,
    );
  }

  /// Helper method to validate if URL is suitable for CachedNetworkImage
  bool _isValidNetworkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  /// Get file for video player that checks local files first
  Future<File?> getVideoFile(String videoUrl) async {
    // Handle local:// URLs first
    if (videoUrl.startsWith('local://')) {
      final localPath = getLocalFilePath(videoUrl);
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          // 📱 Using local video: $localPath (log removed)
          return file;
        }
      }
    }

    // Check if we have a local file for this URL (Firebase URLs)
    final localPath = getLocalFilePath(videoUrl);
    if (localPath != null) {
      final file = File(localPath);
      if (await file.exists()) {
        return file;
      }
    }

    // No local file available
    return null;
  }

  /// Store local media data when saving with FastMediaUploadService
  Future<void> storeLocalMediaData(
      String documentId, Map<String, dynamic> data) async {
    if (!_isInitialized) return;

    try {
      await _localMediaBox.put(documentId, data);
      // 📦 Stored local media data for: $documentId (log removed)
    } catch (e) {
      // ⚠️ Failed to store local media data: $e (log removed)
    }
  }

  /// Get local media data for document
  Map<String, dynamic>? getLocalMediaData(String documentId) {
    if (!_isInitialized) return null;

    try {
      final data = _localMediaBox.get(documentId);
      return data != null ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      // ⚠️ Failed to get local media data: $e (log removed)
      return null;
    }
  }

  /// Clean up old local files to save space
  Future<void> cleanupOldFiles({int maxAgeInDays = 30}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final localMediaDir = Directory('${appDir.path}/local_media');

      if (!await localMediaDir.exists()) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: maxAgeInDays));
      final entities = await localMediaDir.list(recursive: true).toList();

      for (final entity in entities) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
            // 🗑️ Cleaned up old file: ${entity.path} (log removed)
          }
        }
      }
    } catch (e) {
      // ⚠️ Cleanup failed: $e (log removed)
    }
  }

  /// Check if device is currently offline
  bool get isOfflineMode {
    // This is a simple check - in a real app you'd want to ping a server
    // For now, we'll assume offline if we can't reach Firebase
    return !_canReachFirebase();
  }

  bool _canReachFirebase() {
    // Simplified check - you could implement actual connectivity check here
    // For now, return false to enable offline mode for testing
    return false; // TODO: Implement proper connectivity check
  }

  /// Create offline-aware widget for images
  /// [cacheKey] gives an image a stable cache identity that is independent of
  /// its URL. Profile images pass their canonical `profile_media_id`, so a
  /// re-signed R2 URL resolves to the same cache entry instead of missing and
  /// re-downloading bytes the device already holds. Omitting it keeps the
  /// previous URL-keyed behavior, which is correct for the stable Firebase
  /// Storage URLs used by property and search imagery.
  Widget buildOfflineAwareImage({
    required String imageUrl,
    String? cacheKey,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    // Stable-identity local bytes win over everything: they are already on
    // disk, so they render on the first frame with no network and no
    // placeholder, even before a refreshed signed URL has been resolved.
    final mediaIdPath = getLocalFilePathForMediaId(cacheKey);
    if (mediaIdPath != null) {
      final mediaIdFile = File(mediaIdPath);
      if (mediaIdFile.existsSync()) {
        return Image.file(
          mediaIdFile,
          fit: fit,
          width: width,
          height: height,
          // Keeps the previous frame on screen while a different file decodes
          // — e.g. an optimistic preview handing over to its adopted copy.
          gaplessPlayback: true,
          // Reading and decoding a local file is still asynchronous, and after
          // a process restart the in-memory image cache is empty, so thereは
          // a short interval with nothing to paint. Holding the caller's
          // loading surface over it avoids an empty media area. This does not
          // make the image appear on the first frame; it only stops the gap
          // from being blank.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return placeholder ?? _buildDefaultPlaceholder();
          },
          errorBuilder: (context, error, stackTrace) {
            return errorWidget ?? _buildDefaultErrorWidget();
          },
        );
      }
    }

    // ALWAYS check for local file first (for both local:// and Firebase URLs)
    // This prevents loading indicators when switching from local:// to Firebase URLs
    final localPath = getLocalFilePath(imageUrl);
    if (localPath != null) {
      final file = File(localPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) {
            return errorWidget ?? _buildDefaultErrorWidget();
          },
        );
      }
    }

    // Handle local:// URLs - if no local file exists, show placeholder immediately
    if (imageUrl.startsWith('local://')) {
      return placeholder ?? _buildDefaultPlaceholder();
    }

    // A caller may hold a stable cache identity but no URL yet — a profile
    // image whose signed URL has not been resolved for this session. With no
    // local bytes for that identity there is nothing to draw yet.
    if (imageUrl.isEmpty) {
      return placeholder ?? _buildDefaultPlaceholder();
    }

    // For Firebase URLs, use CachedNetworkImage with preloading strategy
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheKey: cacheKey,
      fit: fit,
      width: width,
      height: height,
      placeholder: (context, url) {
        if (placeholder != null) {
          return placeholder;
        }

        // For profile images that were previously saved locally,
        // avoid showing loading placeholders to prevent flicker
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(
              Icons.person,
              size: (width != null && height != null)
                  ? (width * height < 2500 ? 24 : 48)
                  : 32,
              color: Colors.grey[400],
            ),
          ),
        );
      },
      errorWidget: (context, url, error) {
        // Check if it's a network error and show appropriate fallback
        final errorString = error.toString().toLowerCase();
        if (errorString.contains('socketexception') ||
            errorString.contains('failed host lookup') ||
            errorString.contains('firebasestorage')) {
          return _buildOfflineIndicator();
        }
        return errorWidget ?? _buildDefaultErrorWidget();
      },
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 50),
    );
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Icon(
          Icons.person,
          size: 32,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildDefaultErrorWidget() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(
          Icons.broken_image,
          size: 48,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildOfflineIndicator() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              'Offline Mode',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Image unavailable',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
