import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';

/// The upload state of one Offer media item, drawn over its preview.
///
/// Distinguishes the phases the Offer media UI promises — waiting, uploading
/// (with progress), finishing on the server, retrying by itself, a failure
/// the user can retry and one they cannot — and never presents an item as
/// uploaded before the server has accepted it: a ready item draws nothing.
///
/// Two layouts. [compact] (a small grid tile) covers the tile with a scrim.
/// The full-size one (Offer Details' gallery, full screen) is a strip along
/// the bottom, so the preview itself stays fully visible — upload progress
/// is shown beside the media, not instead of it, and a pending video's play
/// button stays reachable.
///
/// Only Offer media uses it. Words are localized; the scrim and its text use
/// the same white-on-dark treatment as the tiles' existing overlays.
class OfferMediaUploadStatus extends StatelessWidget {
  const OfferMediaUploadStatus({
    super.key,
    required this.phase,
    this.progress,
    this.failureMessageKey,
    this.onRetry,
    this.onRemove,
    this.compact = false,
    this.bottomInset = 0,
  });

  final OfferMediaUploadPhase phase;
  final double? progress;
  final String? failureMessageKey;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  /// A small grid tile rather than a full gallery page.
  final bool compact;

  /// Space kept free below the full-size strip for controls the host draws
  /// along the bottom edge (a page indicator, a counter).
  final double bottomInset;

  static bool _canRetry(OfferMediaUploadPhase phase) =>
      phase == OfferMediaUploadPhase.retrying ||
      phase == OfferMediaUploadPhase.retryableFailure;

  static bool _canRemove(OfferMediaUploadPhase phase) =>
      _canRetry(phase) || phase == OfferMediaUploadPhase.permanentFailure;

  @override
  Widget build(BuildContext context) {
    if (phase == OfferMediaUploadPhase.ready) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final indicatorSize = compact ? 26.0 : 22.0;
    const iconSize = 22.0;

    Widget spinner(double? value) => SizedBox(
          width: indicatorSize,
          height: indicatorSize,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 3,
            color: Colors.white,
            backgroundColor: value == null ? null : Colors.white24,
          ),
        );

    final String label;
    final Widget indicator;
    switch (phase) {
      case OfferMediaUploadPhase.queued:
        label = loc.translate('offerMediaQueued');
        indicator =
            Icon(Icons.schedule_rounded, color: Colors.white, size: iconSize);
      case OfferMediaUploadPhase.uploading:
        final fraction = progress;
        final percent =
            fraction == null ? null : (fraction * 100).clamp(0, 100).round();
        label = percent == null
            ? loc.translate('uploading')
            : '${loc.translate('uploading')} $percent%';
        indicator = spinner(fraction);
      case OfferMediaUploadPhase.confirming:
        label = loc.translate('offerMediaFinishing');
        indicator = spinner(null);
      case OfferMediaUploadPhase.retrying:
        label = loc.translate('offerMediaRetrying');
        indicator =
            Icon(Icons.sync_rounded, color: Colors.white, size: iconSize);
      case OfferMediaUploadPhase.retryableFailure:
        label = loc.translate(failureMessageKey ?? 'uploadFailed');
        indicator =
            Icon(Icons.cloud_off_rounded, color: Colors.white, size: iconSize);
      case OfferMediaUploadPhase.permanentFailure:
        label = loc.translate(failureMessageKey ?? 'uploadFailed');
        indicator = Icon(
          Icons.error_outline_rounded,
          color: colors.errorContainer,
          size: iconSize,
        );
      case OfferMediaUploadPhase.ready:
        return const SizedBox.shrink();
    }

    final textStyle = (compact
            ? Theme.of(context).textTheme.labelSmall
            : Theme.of(context).textTheme.bodySmall)
        ?.copyWith(color: Colors.white);
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: Colors.white,
      visualDensity: VisualDensity.compact,
    );
    final actions = <Widget>[
      if (onRetry != null && _canRetry(phase))
        TextButton(
          onPressed: onRetry,
          style: buttonStyle,
          child: Text(loc.translate('retry')),
        ),
      if (onRemove != null && _canRemove(phase))
        TextButton(
          onPressed: onRemove,
          style: buttonStyle,
          child: Text(loc.translate('remove')),
        ),
    ];
    final text = ExcludeSemantics(
      child: Text(
        label,
        style: textStyle,
        textAlign: compact ? TextAlign.center : TextAlign.start,
        maxLines: compact ? 2 : 3,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (compact) {
      return Semantics(
        liveRegion: true,
        label: label,
        child: ColoredBox(
          color: colors.scrim.withValues(alpha: 0.45),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  indicator,
                  const SizedBox(height: 4),
                  text,
                  if (actions.isNotEmpty)
                    Wrap(alignment: WrapAlignment.center, children: actions),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      label: label,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.scrim.withValues(alpha: 0),
                colors.scrim.withValues(alpha: 0.7),
              ],
            ),
          ),
          child: Padding(
            padding:
                EdgeInsetsDirectional.fromSTEB(16, 24, 8, 12 + bottomInset),
            child: Row(
              children: [
                indicator,
                const SizedBox(width: 12),
                Expanded(child: text),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
