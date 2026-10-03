import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';

/// Hands a share to `share_plus`, the plugin the app already ships.
///
/// It translates the app's own [ShareRequest] into the plugin's parameters and
/// the plugin's result back into a [ShareOutcome]:
///
///  * files are passed as real paths with the type they were prepared as, so
///    the receiving app gets the file itself, never a link;
///  * an iPad or Mac needs the rectangle the sheet comes from, so the origin is
///    always passed on when there is one (an iPhone and Android ignore it);
///  * the sheet being closed without a choice is reported as
///    [ShareOutcome.dismissed], which is not an error.
class SharePlusSink implements ShareSink {
  const SharePlusSink(
      {Future<ShareResult> Function(ShareParams params)? invoke})
      : _invoke = invoke;

  final Future<ShareResult> Function(ShareParams params)? _invoke;

  @override
  Future<ShareOutcome> send(ShareRequest request) async {
    final text = _nonEmpty(request.text);
    final params = ShareParams(
      text: text,
      subject: _nonEmpty(request.subject),
      files: request.files.isEmpty
          ? null
          : <XFile>[
              for (final file in request.files)
                XFile(file.path, mimeType: file.mimeType),
            ],
      sharePositionOrigin: _rect(request.origin),
    );
    final invoke = _invoke ?? SharePlus.instance.share;
    final result = await invoke(params);
    switch (result.status) {
      case ShareResultStatus.success:
        return ShareOutcome.shared;
      case ShareResultStatus.dismissed:
        return ShareOutcome.dismissed;
      case ShareResultStatus.unavailable:
        return ShareOutcome.unknown;
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : value;
  }

  static Rect? _rect(ShareOrigin? origin) {
    if (origin == null || origin.isEmpty) return null;
    return Rect.fromLTWH(origin.left, origin.top, origin.width, origin.height);
  }
}
