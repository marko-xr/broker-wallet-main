import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_sync.dart';

/// The one status line of a Toolkit tool's list: where its documents are kept.
///
/// It says what is true, in plain words: the documents are being restored from
/// the account, all of them are saved to the account, some wait for their upload,
/// or WHY the account cannot be used right now (no connection, the session needs
/// a new sign-in, the server does not offer the cloud copy yet, a limit). It is
/// shown only when the tool uses the account copy, and says nothing when there is
/// nothing to say. It is shaped like the screens' other notices.
class ToolkitCloudStatusLine extends StatelessWidget {
  const ToolkitCloudStatusLine({
    super.key,
    required this.summary,
    this.onRetry,
  });

  final ToolkitCloudSummary summary;

  /// Tries the documents that wait again now. The button is shown only where it
  /// can help (waiting, offline, something to look at).
  final VoidCallback? onRetry;

  /// The localized sentence for [summary], or null when there is nothing to say.
  static String? textFor(AppLocalizations loc, ToolkitCloudSummary summary) {
    final notice = summary.notice;
    if (notice == null) return null;
    switch (notice) {
      case ToolkitCloudNotice.restoring:
        return loc
            .translate('toolkitCloudRestoring')
            .replaceAll('{done}', '${summary.restoredCount}')
            .replaceAll('{total}', '${summary.restoreTotal}');
      case ToolkitCloudNotice.allSaved:
        return loc.translate('toolkitCloudAllSaved');
      case ToolkitCloudNotice.waiting:
        return loc
            .translate('toolkitCloudWaiting')
            .replaceAll('{count}', '${summary.waiting}');
      case ToolkitCloudNotice.offline:
        return loc.translate('toolkitCloudOffline');
      case ToolkitCloudNotice.signInAgain:
        return loc.translate('toolkitCloudSignIn');
      case ToolkitCloudNotice.serverNotReady:
        return loc.translate('toolkitCloudServerNotReady');
      case ToolkitCloudNotice.overLimit:
        return loc.translate('toolkitCloudOverLimit');
      case ToolkitCloudNotice.attention:
        return loc.translate('toolkitCloudAttention');
    }
  }

  static IconData _iconFor(ToolkitCloudNotice notice) {
    switch (notice) {
      case ToolkitCloudNotice.allSaved:
        return Icons.cloud_done_outlined;
      case ToolkitCloudNotice.restoring:
        return Icons.cloud_download_outlined;
      case ToolkitCloudNotice.waiting:
        return Icons.cloud_upload_outlined;
      case ToolkitCloudNotice.offline:
      case ToolkitCloudNotice.signInAgain:
      case ToolkitCloudNotice.serverNotReady:
      case ToolkitCloudNotice.overLimit:
      case ToolkitCloudNotice.attention:
        return Icons.cloud_off_outlined;
    }
  }

  static bool _canRetry(ToolkitCloudNotice notice) =>
      notice == ToolkitCloudNotice.waiting ||
      notice == ToolkitCloudNotice.offline ||
      notice == ToolkitCloudNotice.attention;

  @override
  Widget build(BuildContext context) {
    final notice = summary.notice;
    final loc = AppLocalizations.of(context);
    final text = textFor(loc, summary);
    if (notice == null || text == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final Color color;
    switch (notice) {
      case ToolkitCloudNotice.allSaved:
      case ToolkitCloudNotice.restoring:
        color = colors.primary;
      case ToolkitCloudNotice.waiting:
      case ToolkitCloudNotice.offline:
        color = colors.onSurface.withValues(alpha: 0.7);
      case ToolkitCloudNotice.signInAgain:
      case ToolkitCloudNotice.serverNotReady:
      case ToolkitCloudNotice.overLimit:
      case ToolkitCloudNotice.attention:
        color = colors.error;
    }
    final retry = onRetry;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(notice), size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
          if (retry != null && _canRetry(notice))
            InkWell(
              onTap: retry,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  loc.translate('toolkitCloudTryAgain'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
