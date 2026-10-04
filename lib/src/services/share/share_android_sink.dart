import 'package:flutter/services.dart';

import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';

/// The Android transport for a homogeneous batch of photos, or of videos.
///
/// Everything else (no file, one file, any other files) is passed straight to
/// the [system] sink, the share the app has always used. A batch of two or more
/// photos, or two or more videos, is handed to Broker Wallet's own small native
/// adapter instead: one `ACTION_SEND_MULTIPLE` request carrying every file as a
/// content URI in the order chosen, every URI also in the intent's `ClipData`
/// with a read grant, declared as the batch's real type (the common type its
/// files proved, or the wildcard of their one family), and no message. Its files
/// stay where they were prepared (nothing is copied again, which matters for
/// large videos) so a first batch is still there when a second is shared.
///
/// A mix of photos and videos never reaches it: the share flow hands them over as
/// separate batches. The native side is only the last step; it receives local
/// prepared files, never a link, and decides nothing about what is shared.
///
/// Android reports nothing back for a chooser that was started, so launching it
/// is the whole outcome: [ShareOutcome.unknown], which the flow treats as done.
class AndroidMediaBatchSink implements ShareSink {
  AndroidMediaBatchSink({required ShareSink system, MethodChannel? channel})
      : _system = system,
        _channel = channel ?? const MethodChannel(channelName);

  /// The channel the native adapter listens on. The same name is in
  /// `MultiMediaSharePlugin.kt`.
  static const String channelName =
      'com.example.broker_wallet/multi_media_share';

  /// The one method it answers.
  static const String shareMethod = 'shareMultipleMedia';

  final ShareSink _system;
  final MethodChannel _channel;

  /// Whether [request] goes to the native adapter rather than the system share.
  static bool takes(ShareRequest request) =>
      request.mediaBatch && request.files.length >= SharePayload.severalFiles;

  /// What the native adapter receives: the local files in the order they were
  /// chosen and the type each one proved to be. Only paths, never a link, and no
  /// message.
  static Map<String, Object?> arguments(ShareRequest request) {
    return <String, Object?>{
      'paths': <String>[for (final file in request.files) file.path],
      'mimeTypes': <String>[for (final file in request.files) file.mimeType],
    };
  }

  @override
  Future<ShareOutcome> send(ShareRequest request) async {
    if (!takes(request)) return _system.send(request);
    await _channel.invokeMethod<Object?>(shareMethod, arguments(request));
    return ShareOutcome.unknown;
  }
}
