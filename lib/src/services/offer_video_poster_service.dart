import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_diagnostics.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';

/// Still frames for ready private Offer videos that this device holds none
/// of.
///
/// The device that uploads a video makes its still frame when the file is
/// picked. No other device has it — nor this one after a reinstall — because
/// the server keeps only the video (device evidence, 2026-09-26: after a
/// reinstall every saved video showed a black tile). This makes the frame on
/// demand from the video itself, through its private signed link: Android's
/// `MediaMetadataRetriever` reads only the byte ranges it needs (the index
/// and the first frame), not the whole video.
///
/// The frame is kept on this device under the video's stable, account-scoped
/// identity ([offerMediaPosterKey]), exactly where the uploader's own frame
/// is kept, so every later open and every restart draws it at once, and the
/// account-deletion sweep removes it with the account's other files. The link
/// is used for that single read and never stored or logged.
class OfferVideoPosterService {
  OfferVideoPosterService._();

  static final OfferVideoPosterService instance = OfferVideoPosterService._();

  /// Makes a JPEG still frame of the video at [signedUrl] at [targetPath].
  /// Returns the written path, or null. Replaceable in tests.
  @visibleForTesting
  static Future<String?> Function(String signedUrl, String targetPath)
      generate = _generateFromVideo;

  @visibleForTesting
  static Future<Directory> Function() temporaryDirectory =
      getTemporaryDirectory;

  /// The signed-in account. Replaceable in tests.
  @visibleForTesting
  static String? Function() currentOwnerId = _supabaseUserId;

  /// A failed attempt is not repeated for this long (offline, or a link that
  /// expired): the next open after it tries again.
  static const Duration _retryAfter = Duration(minutes: 2);

  final Map<String, Future<String?>> _inFlight = {};
  final Map<String, DateTime> _failedAt = {};
  Future<void> _tail = Future<void>.value();

  static String? _supabaseUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _generateFromVideo(
    String signedUrl,
    String targetPath,
  ) =>
      VideoThumbnail.thumbnailFile(
        video: signedUrl,
        thumbnailPath: targetPath,
        imageFormat: ImageFormat.JPEG,
        // The same size and quality as a frame made when the video is picked.
        maxWidth: 1280,
        quality: 85,
      );

  /// The still frame this device already holds for [cacheKey], or null.
  String? localPoster(String? cacheKey) {
    if (cacheKey == null || cacheKey.isEmpty) return null;
    final path = OfflineMediaService.instance
        .getLocalFilePathForMediaId(offerMediaPosterKey(cacheKey));
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  /// The still frame for the ready video [cacheKey], made from [signedUrl]
  /// when this device has none. Null when there is none and none can be made
  /// now. Only the signed-in account's own media is ever read; one frame is
  /// made at a time, and a video asked for twice is read once.
  Future<String?> ensure({
    required String? cacheKey,
    required String? signedUrl,
  }) {
    final key = cacheKey;
    if (key == null || !_ownedByCurrentAccount(key)) {
      return Future<String?>.value();
    }
    final existing = localPoster(key);
    if (existing != null) return Future<String?>.value(existing);
    final url = signedUrl?.trim() ?? '';
    if (url.isEmpty) return Future<String?>.value();
    final failed = _failedAt[key];
    if (failed != null && DateTime.now().difference(failed) < _retryAfter) {
      return Future<String?>.value();
    }
    final running = _inFlight[key];
    if (running != null) return running;
    final job = _serialized(() => _make(key, url));
    _inFlight[key] = job;
    return job.whenComplete(() => _inFlight.remove(key));
  }

  bool _ownedByCurrentAccount(String cacheKey) {
    if (!cacheKey.startsWith(offerMediaCacheKeyPrefix)) return false;
    final parts =
        cacheKey.substring(offerMediaCacheKeyPrefix.length).split(':');
    final owner = currentOwnerId();
    return parts.length == 2 && owner != null && parts.first == owner;
  }

  Future<String?> _serialized(Future<String?> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String?> _make(String cacheKey, String signedUrl) async {
    // Another caller may have made it, or the account changed, while this
    // waited its turn.
    final existing = localPoster(cacheKey);
    if (existing != null) return existing;
    if (!_ownedByCurrentAccount(cacheKey)) return null;

    final id = cacheKey.split(':').last;
    final clock = Stopwatch()..start();
    String? target;
    try {
      final directory = await temporaryDirectory();
      target = '${directory.path}/offer-poster-${const Uuid().v4()}.jpg';
      final written = await generate(signedUrl, target);
      final file = written == null ? null : File(written);
      if (file == null || !await file.exists() || await file.length() == 0) {
        throw const FileSystemException('no frame');
      }
      if (!_ownedByCurrentAccount(cacheKey)) return null;
      await OfflineMediaService.instance.adoptLocalFileForMediaId(
        offerMediaPosterKey(cacheKey),
        file.path,
        directoryName: OfflineMediaService.offerMediaDirectoryName,
      );
      final adopted = localPoster(cacheKey);
      OfferMediaDiagnostics.log('poster-made', id: id, fields: {
        'elapsedMs': clock.elapsedMilliseconds,
        'kept': adopted != null,
      });
      _failedAt.remove(cacheKey);
      return adopted;
    } catch (error) {
      _failedAt[cacheKey] = DateTime.now();
      OfferMediaDiagnostics.log('poster-failed', id: id, fields: {
        'elapsedMs': clock.elapsedMilliseconds,
        'cause': OfferMediaDiagnostics.categorize(error),
      });
      return null;
    } finally {
      // The adopted copy is the one kept; the temporary frame goes.
      if (target != null) {
        try {
          final temporary = File(target);
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {}
      }
    }
  }

  @visibleForTesting
  void reset() {
    _inFlight.clear();
    _failedAt.clear();
    _tail = Future<void>.value();
  }
}
