import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'package:broker_wallet/src/services/offer_media_policy.dart';

/// Reads a video's real duration by opening it with the same player that will
/// later play it back. Replaceable in tests, which have no platform player.
abstract final class VideoDurationProbe {
  @visibleForTesting
  static Future<Duration?> Function(File file) read = _readWithPlayer;

  static Future<Duration?> _readWithPlayer(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize().timeout(const Duration(seconds: 15));
      final duration = controller.value.duration;
      return duration > Duration.zero ? duration : null;
    } catch (_) {
      // Unreadable by the platform player: it could not be played back in the
      // app either, so it is refused rather than uploaded blindly.
      return null;
    } finally {
      await controller.dispose();
    }
  }
}

/// Converts a HEIC/HEIF photo to JPEG on the device, with the image
/// compression capability the app already ships, so no Offer photo ever
/// depends on a platform being able to decode HEIF for display. Replaceable
/// in tests, which have no platform codec.
abstract final class HeifToJpegConverter {
  @visibleForTesting
  static Future<File?> Function(File source) convert = _convert;

  static Future<File?> _convert(File source) async {
    try {
      final directory = await getTemporaryDirectory();
      final target = '${directory.path}/offer-heif-${const Uuid().v4()}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        source.path,
        target,
        format: CompressFormat.jpeg,
        quality: 90,
        // The same scale the picker already gives camera and gallery photos.
        minWidth: 1920,
        minHeight: 1920,
      );
      if (result == null) return null;
      final file = File(result.path);
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }
}

/// Makes a still frame of a video on the device, so the video can be shown
/// the moment it is picked. Replaceable in tests.
abstract final class VideoPosterGenerator {
  @visibleForTesting
  static Future<String?> Function(File video) generate = _generate;

  static Future<String?> _generate(File video) async {
    try {
      final directory = await getTemporaryDirectory();
      return await VideoThumbnail.thumbnailFile(
        video: video.path,
        // A file of its own (a path ending in .jpg is taken as the file):
        // named after the video, two picks of one video would share it.
        thumbnailPath:
            '${directory.path}/offer-poster-${const Uuid().v4()}.jpg',
        imageFormat: ImageFormat.JPEG,
        // Drawn full-width in Offer Details and full screen (about 1080
        // physical pixels on the test phone): a 480-pixel frame there was
        // visibly blurred. Still one small JPEG per video.
        maxWidth: 1280,
        quality: 85,
      );
    } catch (_) {
      // A video without a preview still uploads and plays.
      return null;
    }
  }
}

/// What survived screening, and why anything else did not.
class OfferMediaSelectionResult {
  const OfferMediaSelectionResult({
    required this.accepted,
    required this.rejections,
    required this.trimmedByLimit,
  });

  /// Each accepted file, with the id it will keep for the rest of its life.
  final List<OfferMediaDraft> accepted;

  /// Distinct reasons, in the order they were first hit — one message each.
  final List<OfferMediaRejection> rejections;

  /// True when otherwise-valid files were dropped because the Offer's 10-item
  /// limit was reached, which reads differently from an outright refusal.
  final bool trimmedByLimit;

  bool get hasRejections => rejections.isNotEmpty || trimmedByLimit;
}

/// Screens freshly picked files against the Offer media rules before anything
/// is added to the form: the 10-item total, the per-kind size limits, the
/// supported containers (by bytes, not by name) and the 3-minute video length.
///
/// HEIC/HEIF photos are converted to JPEG here. Each accepted file gets its
/// `mediaObjectId` now, once: from this moment it is the item's identity.
///
/// Local and cheap: only each file's first 64 bytes are read, plus one player
/// probe and one still frame per video. The Media Worker independently
/// re-checks every rule it can; this only spares the user a doomed upload.
Future<OfferMediaSelectionResult> screenOfferMediaSelection({
  required List<File> candidates,
  required int itemsAlreadyOnOffer,
  String Function()? newMediaObjectId,
}) async {
  final remaining = OfferMediaPolicy.remainingSlots(itemsAlreadyOnOffer);
  final makeId = newMediaObjectId ?? () => const Uuid().v4();
  final accepted = <OfferMediaDraft>[];
  final rejections = <OfferMediaRejection>[];
  var trimmedByLimit = false;

  void reject(OfferMediaRejection rejection) {
    if (!rejections.contains(rejection)) rejections.add(rejection);
  }

  for (final picked in candidates) {
    if (accepted.length >= remaining) {
      trimmedByLimit = true;
      continue;
    }

    var file = picked;
    final List<int> header;
    try {
      header = await OfferMediaPolicy.readHeader(file);
    } catch (_) {
      reject(OfferMediaRejection.unsupportedType);
      continue;
    }
    if (HeifSignatureDetector.isHeif(header, path: file.path)) {
      final converted = await HeifToJpegConverter.convert(file);
      if (converted == null) {
        reject(OfferMediaRejection.unsupportedType);
        continue;
      }
      file = converted;
    }

    final check = await OfferMediaPolicy.check(file);
    if (!check.isAccepted) {
      reject(check.rejection!);
      continue;
    }

    int? durationMs;
    String? posterPath;
    if (check.kind == OfferMediaKind.video) {
      final duration = await VideoDurationProbe.read(file);
      if (duration == null) {
        reject(OfferMediaRejection.unsupportedType);
        continue;
      }
      if (duration > OfferMediaPolicy.maxVideoDurationAccepted) {
        reject(OfferMediaRejection.videoTooLong);
        continue;
      }
      durationMs = duration.inMilliseconds;
      posterPath = await VideoPosterGenerator.generate(file);
    }

    accepted.add(OfferMediaDraft(
      mediaObjectId: makeId(),
      path: file.path,
      kind: check.kind!,
      contentType: check.contentType!,
      byteLength: check.length!,
      posterPath: posterPath,
      displayName: picked.path.replaceAll('\\', '/').split('/').last,
      durationMs: durationMs,
    ));
  }

  return OfferMediaSelectionResult(
    accepted: accepted,
    rejections: rejections,
    trimmedByLimit: trimmedByLimit,
  );
}
