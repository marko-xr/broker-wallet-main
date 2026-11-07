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
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
      final mapped = heldNow(cacheKey);
      if (mapped != null) return mapped;
      final store = cache();
      if (!store.canRead(cacheKey)) return null;

      var file = await store.cached(cacheKey);
      file ??= await _previousCache(cacheKey);
      file ??= await store.get(
        cacheKey,
        signedUrl: () async => _linkFor(cacheKey, signedUrl),
      );
      if (file == null || !store.canRead(cacheKey)) return null;

      await OfflineMediaService.instance
          .mapMediaIdToLocalFile(cacheKey, file.path);
      return store.canRead(cacheKey) ? file : null;
    } catch (_) {
      return null;
    }
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
