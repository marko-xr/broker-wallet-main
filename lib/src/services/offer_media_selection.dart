import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

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

/// What survived screening, and why anything else did not.
class OfferMediaSelectionResult {
  const OfferMediaSelectionResult({
    required this.accepted,
    required this.rejections,
    required this.trimmedByLimit,
  });

  final List<File> accepted;

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
/// Purely local and cheap: only each file's first 64 bytes are read, plus one
/// player probe per video. The Media Worker independently re-checks every rule
/// it can; this only spares the user a doomed upload.
Future<OfferMediaSelectionResult> screenOfferMediaSelection({
  required List<File> candidates,
  required int itemsAlreadyOnOffer,
}) async {
  final remaining = OfferMediaPolicy.remainingSlots(itemsAlreadyOnOffer);
  final accepted = <File>[];
  final rejections = <OfferMediaRejection>[];
  var trimmedByLimit = false;

  void reject(OfferMediaRejection rejection) {
    if (!rejections.contains(rejection)) rejections.add(rejection);
  }

  for (final file in candidates) {
    if (accepted.length >= remaining) {
      trimmedByLimit = true;
      continue;
    }

    final check = await OfferMediaPolicy.check(file);
    if (!check.isAccepted) {
      reject(check.rejection!);
      continue;
    }

    if (check.kind == OfferMediaKind.video) {
      final duration = await VideoDurationProbe.read(file);
      if (duration == null) {
        reject(OfferMediaRejection.unsupportedType);
        continue;
      }
      if (duration > OfferMediaPolicy.maxVideoDuration) {
        reject(OfferMediaRejection.videoTooLong);
        continue;
      }
    }

    accepted.add(file);
  }

  return OfferMediaSelectionResult(
    accepted: accepted,
    rejections: rejections,
    trimmedByLimit: trimmedByLimit,
  );
}
