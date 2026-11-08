/// Where an Offer or Owner detail image comes from (tracker §7AZ, M1c).
///
/// For an account-scoped key (`offer-media:<account>:<mediaId>`, shared by
/// Offer and Owner media), in this order:
///  1. the file this device maps for the key in the existing `url_mapping`
///     box — an adopted original, or a copy an earlier open recorded;
///  2. the private image cache's copy ([PrivateMediaCache]);
///  3. the image cache in use before M1c, read only and with no network, so
///     what it already holds is shown rather than downloaded again;
///  4. one download through the private cache, with the link already in hand.
/// Every step needs the current application session, and the key must name
/// its account; holding the bytes is never permission on its own. Whatever
/// was found is recorded in `url_mapping` (a file path, never a link), so the
/// next open — cold or offline — paints at once. No link is ever requested
/// here: a miss with no link in hand waits for the screen's own media
/// resolution to supply one.
///
/// An image shown from the previous cache (step 3, or a mapping that names
/// its entry) is then copied into the private cache in the background, once
/// per item and with no network (tracker §7AZ, M1d-1, D-M1d-1..6) — only when
/// the key is exactly `offer-media:<session account>:<media id>` and the
/// media id is trusted: named by that account's media catalogue, or resolved
/// by the Worker in this run as an image. The display never waits for it;
/// the previous cache's entry, `url_mapping` and the catalogue are left as
/// they are, so what is shown does not change (the mapping switch is M1d-2).
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/private_media_cache.dart';

abstract final class PrivateMediaImages {
  /// The private cache in use; replaced in tests.
  @visibleForTesting
  static PrivateMediaCache Function() cache = _appCache;

  static PrivateMediaCache _appCache() => PrivateMediaCache.instance;

  /// Replaces [load] in widget tests, whose fake-async zone cannot run the
  /// cache's real file work.
  @visibleForTesting
  static Future<File?> Function(String cacheKey, String? signedUrl)? debugLoad;

  /// The file already mapped for [cacheKey], for the first frame: only when
  /// the key is the current session's account's and the file exists.
  static File? heldNow(String cacheKey) {
    if (!cache().canRead(cacheKey)) return null;
    final path =
        OfflineMediaService.instance.getLocalFilePathForMediaId(cacheKey);
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// The image's file, by the order above; null when it cannot be had now
  /// (no session for its account, offline with no copy, no link, a failed
  /// fetch). Never throws, and never removes anything.
  static Future<File?> load(String cacheKey, {String? signedUrl}) async {
    final override = debugLoad;
    if (override != null) return override(cacheKey, signedUrl);
    try {
      // The session this image is shown in; a copy is made only for it.
      final origin = cache().scopeFor(cacheKey);
      final mapped = heldNow(cacheKey);
      if (mapped != null) {
        _copyLater(cacheKey, mapped, origin, fromMapping: true);
        return mapped;
      }
      final store = cache();
      if (!store.canRead(cacheKey)) return null;

      var file = await store.cached(cacheKey);
      File? previous;
      if (file == null) file = previous = await _previousCache(cacheKey);
      file ??= await store.get(
        cacheKey,
        signedUrl: () async => _linkFor(cacheKey, signedUrl),
      );
      if (file == null || !store.canRead(cacheKey)) return null;

      await OfflineMediaService.instance
          .mapMediaIdToLocalFile(cacheKey, file.path);
      if (!store.canRead(cacheKey)) return null;
      if (previous != null) {
        _copyLater(cacheKey, previous, origin, fromMapping: false);
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Copies running now, by session and key.
  static final Map<String, Future<void>> _copies = {};

  /// Items settled for good in this run, by session and key: copied, already
  /// held, not from the previous cache, or unusable there. Anything else is
  /// tried again the next time the image is shown.
  static final Set<String> _settled = {};

  static const Set<String> _settledOutcomes = {
    'adopted',
    'alreadyHeld',
    'notPrevious',
    'unusableSource',
  };

  /// Reports how each copy ended, by key; for tests and measurement only.
  @visibleForTesting
  static void Function(String cacheKey, String outcome)? debugOnMigration;

  /// Completes once no copy is running.
  @visibleForTesting
  static Future<void> debugMigrationsSettled() async {
    while (_copies.isNotEmpty) {
      await Future.wait(_copies.values.toList());
    }
  }

  /// Forgets what this run settled, as a restart would.
  @visibleForTesting
  static void debugForgetMigrations() => _settled.clear();

  /// Starts the copy of [shown] into the private cache, unless it is settled
  /// or already running. Never waits and never throws.
  static void _copyLater(
    String cacheKey,
    File shown,
    PrivateMediaScope? origin, {
    required bool fromMapping,
  }) {
    if (origin == null) return;
    final id = '${origin.session}\n$cacheKey';
    if (_settled.contains(id) || _copies.containsKey(id)) return;
    _copies[id] = () async {
      var outcome = 'failed';
      try {
        outcome = await _copy(cacheKey, shown, origin, fromMapping);
      } catch (_) {
        // Nothing to undo: the shown file is untouched.
      } finally {
        _copies.remove(id);
      }
      if (_settledOutcomes.contains(outcome)) _settled.add(id);
      debugOnMigration?.call(cacheKey, outcome);
    }();
  }

  static Future<String> _copy(
    String cacheKey,
    File shown,
    PrivateMediaScope origin,
    bool fromMapping,
  ) async {
    final store = cache();
    if (store.scopeFor(cacheKey) != origin) return 'notAllowed';
    if (!_trusted(cacheKey, origin)) return 'untrusted';
    if (await store.cached(cacheKey) != null) return 'alreadyHeld';
    if (store.scopeFor(cacheKey) != origin) return 'notAllowed';
    var source = shown;
    if (fromMapping) {
      // A mapping may name an adopted original or a private copy: only the
      // previous cache's own entry for this exact key is copied.
      final previous = await _previousCache(cacheKey);
      if (previous == null || previous.path != shown.path) {
        return 'notPrevious';
      }
      if (store.scopeFor(cacheKey) != origin) return 'notAllowed';
      source = previous;
    }
    return (await store.adopt(cacheKey, source, origin: origin)).name;
  }

  /// Whether [cacheKey] is exactly the current account's key of a media id
  /// that account's own records name — never the key, a file name, a link
  /// or an image format alone.
  static bool _trusted(String cacheKey, PrivateMediaScope origin) {
    final prefix = '$offerMediaCacheKeyPrefix${origin.account}:';
    if (!cacheKey.startsWith(prefix)) return false;
    final mediaId = cacheKey.substring(prefix.length);
    // Rejects a still frame's `:poster` key and anything else derived.
    if (mediaId.isEmpty || mediaId.contains(':') || mediaId.trim() != mediaId) {
      return false;
    }
    if (offerMediaCacheKey(ownerId: origin.account, mediaObjectId: mediaId) !=
        cacheKey) {
      return false;
    }
    // This run's Worker answer for the account, which also says what it is.
    final resolved = OfferMediaUrlCache.instance.get(cacheKey);
    if (resolved != null) return !resolved.isVideo;
    return OfflineMediaService.instance
        .catalogueNamesMedia(ownerId: origin.account, mediaObjectId: mediaId);
  }

  /// A link valid in memory for this item, else the one the screen holds.
  static String? _linkFor(String cacheKey, String? inHand) {
    final held = OfferMediaUrlCache.instance.get(cacheKey);
    if (held != null) return held.url;
    final link = inHand?.trim();
    return link == null || link.isEmpty ? null : link;
  }

  static Future<File?> _previousCache(String cacheKey) async {
    try {
      final path =
          await OfflineMediaService.instance.heldInSharedCache(cacheKey);
      if (path == null) return null;
      final file = File(path);
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }
}

/// The full-screen viewer's image for a private item not mapped yet: loaded
/// through [PrivateMediaImages.load]. Keyed by identity and link (both in
/// memory only), so a new link retries a failed load.
@immutable
class PrivateMediaImageProvider
    extends ImageProvider<PrivateMediaImageProvider> {
  const PrivateMediaImageProvider(this.cacheKey, {this.signedUrl});

  final String cacheKey;
  final String? signedUrl;

  @override
  Future<PrivateMediaImageProvider> obtainKey(
          ImageConfiguration configuration) =>
      SynchronousFuture<PrivateMediaImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
          PrivateMediaImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _codec(key, decode),
        scale: 1.0,
        debugLabel: 'private-media',
      );

  static Future<ui.Codec> _codec(
      PrivateMediaImageProvider key, ImageDecoderCallback decode) async {
    final file =
        await PrivateMediaImages.load(key.cacheKey, signedUrl: key.signedUrl);
    if (file == null) throw const PrivateMediaUnavailable('unavailable');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const PrivateMediaUnavailable('empty');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is PrivateMediaImageProvider &&
      other.cacheKey == cacheKey &&
      other.signedUrl == signedUrl;

  @override
  int get hashCode => Object.hash(cacheKey, signedUrl);

  @override
  String toString() => 'PrivateMediaImageProvider($cacheKey)';
}
