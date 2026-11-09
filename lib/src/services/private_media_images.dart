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
/// by the Worker in this run as an image. The display never waits for it,
/// and the previous cache's entry and the catalogue are left as they are.
///
/// Once the copy is verified, the key's `url_mapping` entry is switched to it
/// (tracker §7AZ, M1d-2, D-M1d-3): by compare-and-set, only from the exact
/// value captured when the image was shown — the previous cache's file, or a
/// copy that is gone — only while the session that showed it is current, and
/// only when the copy's bytes equal that file's (SHA-256 and size). The
/// replaced path is kept as the key's fallback, so if the private copy is
/// later evicted the previous cache's file is shown again (and re-copied):
/// a switch never hides bytes this device holds.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
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
  /// the key is the current session's account's and the file exists — or,
  /// when the private copy the mapping was switched to is gone, the previous
  /// cache's file it replaced (M1d-2).
  static File? heldNow(String cacheKey) {
    if (!cache().canRead(cacheKey)) return null;
    final path =
        OfflineMediaService.instance.usableLocalPathForMediaId(cacheKey);
    return path == null ? null : File(path);
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
        // Shown from the fallback: the private copy is gone, so it is copied
        // again even if this run already settled it.
        final fallback = mapped.path !=
            OfflineMediaService.instance.getLocalFilePathForMediaId(cacheKey);
        _copyLater(cacheKey, mapped, origin,
            fromMapping: true, again: fallback);
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

  /// Reports how each mapping switch ended (`switched`, `changed`, `differs`,
  /// `notAllowed`, `missing`, `notPrevious`, `failed`); tests only.
  @visibleForTesting
  static void Function(String cacheKey, String outcome)? debugOnMapping;

  /// Runs right before the session check and compare-and-set; tests only.
  @visibleForTesting
  static Future<void> Function(String cacheKey, File copy)?
      debugBeforeMappingSwitch;

  /// The compare-and-set itself; replaced in tests to make the write fail.
  @visibleForTesting
  static Future<bool> Function(
          String cacheKey, String expected, String copy, String previous)
      switchMapping = defaultSwitchMapping;

  @visibleForTesting
  static Future<bool> defaultSwitchMapping(
          String cacheKey, String expected, String copy, String previous) =>
      OfflineMediaService.instance.replaceMediaIdMapping(cacheKey,
          expected: expected, replacement: copy, previous: previous);

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
  /// (and not to be done [again]) or already running. Never waits and never
  /// throws. The mapping is captured now, when the image is shown: the switch
  /// only ever replaces exactly this value.
  static void _copyLater(
    String cacheKey,
    File shown,
    PrivateMediaScope? origin, {
    required bool fromMapping,
    bool again = false,
  }) {
    if (origin == null) return;
    final id = '${origin.session}\n$cacheKey';
    if ((_settled.contains(id) && !again) || _copies.containsKey(id)) return;
    final captured =
        OfflineMediaService.instance.getLocalFilePathForMediaId(cacheKey);
    _copies[id] = () async {
      var outcome = 'failed';
      try {
        outcome = await _copy(cacheKey, shown, origin, fromMapping, captured);
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
    String? captured,
  ) async {
    final store = cache();
    if (store.scopeFor(cacheKey) != origin) return 'notAllowed';
    if (!_trusted(cacheKey, origin)) return 'untrusted';
    var copy = await store.cached(cacheKey);
    if (store.scopeFor(cacheKey) != origin) return 'notAllowed';
    final held = copy != null;
    // Already the mapped file: nothing to copy or switch.
    if (copy != null && copy.path == captured) return 'alreadyHeld';
    var source = shown;
    if (fromMapping) {
      // A mapping may name an adopted original or a private copy: only the
      // previous cache's own entry for this exact key is copied — when it is
      // what was shown, or what was shown is gone (a damaged private copy
      // the lookup above just dropped).
      final previous = await _previousCache(cacheKey);
      final isPrevious = previous != null &&
          (previous.path == shown.path || !await shown.exists());
      if (!isPrevious) return held ? 'alreadyHeld' : 'notPrevious';
      if (store.scopeFor(cacheKey) != origin) return 'notAllowed';
      source = previous;
    }
    var outcome = PrivateMediaAdoption.alreadyHeld;
    if (copy == null) {
      (outcome, copy) = await store.adoptCopy(cacheKey, source, origin: origin);
      if (copy == null) return outcome.name;
    }
    // Computed first: a null-aware call would skip evaluating its arguments.
    final switched = await _switch(cacheKey, origin, captured, source, copy);
    debugOnMapping?.call(cacheKey, switched);
    return outcome.name;
  }

  /// Points [cacheKey]'s mapping at [copy] instead of [captured], keeping
  /// [source] as its fallback (M1d-2). Only from the previous cache's file
  /// that was shown, or from a copy that is gone; only when [copy] holds
  /// exactly [source]'s bytes; only while [origin] is current, checked with
  /// no wait before the compare-and-set. Anything else leaves the mapping as
  /// it is. Deletes nothing.
  static Future<String> _switch(
    String cacheKey,
    PrivateMediaScope origin,
    String? captured,
    File source,
    File copy,
  ) async {
    try {
      if (captured == null ||
          (captured != source.path && File(captured).existsSync())) {
        return 'notPrevious';
      }
      if (!await _sameBytes(source, copy)) return 'differs';
      await debugBeforeMappingSwitch?.call(cacheKey, copy);
      if (cache().scopeFor(cacheKey) != origin) return 'notAllowed';
      if (!copy.existsSync()) return 'missing';
      final switched =
          await switchMapping(cacheKey, captured, copy.path, source.path);
      return switched ? 'switched' : 'changed';
    } catch (_) {
      return 'failed';
    }
  }

  static Future<bool> _sameBytes(File a, File b) async {
    if (!await a.exists() || !await b.exists()) return false;
    if (await a.length() != await b.length()) return false;
    final digests = await Future.wait(
        [sha256.bind(a.openRead()).first, sha256.bind(b.openRead()).first]);
    return digests[0] == digests[1];
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
