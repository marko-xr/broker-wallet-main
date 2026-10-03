import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/services/share/share_flow_controller.dart';
import 'package:broker_wallet/src/services/share/share_live.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';
import 'package:broker_wallet/src/views/Widgets/selectable_chip.dart';

/// The space above and below the scrolling region of the dialog.
const double _regionGap = 20;

/// The least share of the dialog's height the scrolling region is always given.
///
/// The dialog's vertical budget is its available height. The buttons cost their
/// fixed height and the two gaps are fixed; the rows get what is left, and the
/// heading gets the rest of the budget but never so much that the rows would
/// fall below this share. A heading that needs more than it is given scrolls
/// inside its own space, so the three parts together can never be taller than
/// the dialog.
const double _minRowsShare = 0.3;

/// The one Share Options dialog every shareable record uses.
///
/// It answers "what am I about to share?": a row for each part the record
/// really has — never an empty one — with a short line saying what is in it, a
/// Select All box, and, for a record with photos and videos, a chip for each so
/// they can be chosen one by one. The Share button is off while nothing is
/// chosen, shows "Preparing files…" while photos and videos are fetched, and
/// cannot be pressed twice. If a file cannot be had, the dialog stays open with
/// the reason and the choices intact.
///
/// Closing the share sheet without choosing an app is not an error: the dialog
/// stays as it was. Choosing an app closes the dialog.
class ShareOptionsDialog extends StatefulWidget {
  const ShareOptionsDialog({
    super.key,
    required this.source,
    this.refreshLink,
    this.engine,
  });

  /// What the record offers for sharing.
  final ShareSource source;

  /// Gets a fresh link for a private photo or video whose link has expired,
  /// through the record's own authorized path.
  final LinkRefresher? refreshLink;

  /// The share machinery. Tests pass a fake; the app uses [ShareLive.engine].
  final ShareEngine? engine;

  static bool _isOpen = false;

  /// Opens the dialog, unless one is already open (a double tap on a Share icon).
  static Future<void> show(
    BuildContext context, {
    required ShareSource source,
    LinkRefresher? refreshLink,
  }) async {
    if (_isOpen) return;
    _isOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => ShareOptionsDialog(
          source: source,
          refreshLink: refreshLink,
        ),
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  State<ShareOptionsDialog> createState() => _ShareOptionsDialogState();
}

class _ShareOptionsDialogState extends State<ShareOptionsDialog> {
  ShareFlowController? _controller;

  /// The scrolling middle of the dialog. Held so that a failure that appears at
  /// its end can be brought into view.
  final ScrollController _scroll = ScrollController();

  /// The failure whose appearance was last brought into view.
  ShareFailure? _revealedFailure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= ShareFlowController(
      source: widget.source,
      labels: ShareLive.labelsFor(AppLocalizations.of(context)),
      engine: widget.engine ?? ShareLive.engine(),
      refreshLink: widget.refreshLink,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A failure appears at the end of the scrolling region. When the region is
  /// taller than the dialog, bring the end into view once, as it appears, so the
  /// reason and Retry are never out of sight.
  void _revealFailure(ShareFlowController controller) {
    final failure = controller.failure;
    if (identical(failure, _revealedFailure)) return;
    _revealedFailure = failure;
    if (failure == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _share(BuildContext buttonContext) async {
    final controller = _controller!;
    final origin = ShareLive.originOf(buttonContext);
    final result = await controller.share(origin: origin);
    if (!mounted) return;
    if (result == ShareFlowResult.shared) Navigator.of(context).pop();
  }

  void _close() {
    _controller?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.cancel();
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // No height of its own: the Dialog already keeps its child inside the
        // screen (less the system insets), whatever the device or text size, and
        // [_buildContent] scrolls whatever does not fit.
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              _revealFailure(controller);
              // The height the content really has: the Dialog's, less its own
              // padding. Everything below is budgeted inside it.
              return LayoutBuilder(
                builder: (context, constraints) => _buildContent(
                  context,
                  controller,
                  constraints.maxHeight,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ShareFlowController controller,
    double maxHeight,
  ) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final busy = controller.isBusy;

    // The vertical budget: [maxHeight] is all there is. The buttons and the two
    // gaps have fixed heights; the rows are guaranteed [_minRowsShare] of the
    // total; the heading may use everything else, and scrolls inside that if it
    // needs more (a very large font in a narrow dialog can wrap it into many
    // lines). With those three bounded the column cannot outgrow [maxHeight].
    final headingBudget = maxHeight.isFinite
        ? math.max(
            AppControlSizes.minTouchTarget,
            maxHeight -
                AppControlSizes.standardButtonHeight -
                2 * _regionGap -
                maxHeight * _minRowsShare,
          )
        : double.infinity;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: headingBudget),
          child: SingleChildScrollView(
            key: const ValueKey('share-header-scroll'),
            primary: false,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.share_rounded,
                      color: colors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.translate(controller.source.titleKey),
                        style: texts.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loc.translate('selectWhatToShare'),
                        style: texts.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: loc.translate('close'),
                  onPressed: _close,
                  icon:
                      Icon(Icons.close_rounded, color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: _regionGap),
        // Everything that can grow — the rows, the photo and video chips, the
        // hint and a failure — scrolls here, so a long list, a large font or a
        // short screen can never push the buttons off the dialog. Only the
        // heading above and the buttons below stay put.
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('share-body-scroll'),
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SelectAllRow(
                  key: const ValueKey('share-select-all'),
                  value: controller.allState,
                  enabled: !busy,
                  label: loc.translate('selectAll'),
                  onChanged: controller.toggleAll,
                ),
                const SizedBox(height: 16),
                for (final section in controller.sections)
                  _buildOption(context, controller, section),
                if (!controller.hasSelection && !busy) ...[
                  const SizedBox(height: 4),
                  Text(
                    loc.translate('shareSelectAtLeastOne'),
                    key: const ValueKey('share-empty-hint'),
                    style: texts.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
                if (controller.failure != null) ...[
                  const SizedBox(height: 12),
                  _buildFailure(context, controller),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: _regionGap),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: AppControlSizes.standardButtonHeight,
                child: OutlinedButton(
                  key: const ValueKey('share-cancel'),
                  onPressed: _close,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(
                        color: colors.outline.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    loc.translate('cancel'),
                    style: texts.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: AppControlSizes.standardButtonHeight,
                child: Builder(
                  builder: (buttonContext) => FilledButton(
                    key: const ValueKey('share-submit'),
                    onPressed: controller.canShare
                        ? () => _share(buttonContext)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: busy
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  loc.translate(controller.isPreparing
                                      ? 'preparingFiles'
                                      : 'sharing'),
                                  style: texts.bodyLarge,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.share_rounded, size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  loc.translate('share'),
                                  style: texts.bodyLarge,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFailure(BuildContext context, ShareFlowController controller) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final failure = controller.failure!;
    final canRetry = failure.kind == ShareFailureKind.network ||
        failure.kind == ShareFailureKind.generic;

    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('share-error'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        // The reason takes the whole width and Retry sits under it, at the end of
        // the block, so a large font cannot squeeze the sentence into a sliver
        // and Retry is always the last thing the scroll region ends on.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 20, color: colors.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.translate(failure.kind.messageKey),
                    style: texts.bodyMedium
                        ?.copyWith(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
            if (canRetry)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Builder(
                  builder: (buttonContext) => TextButton(
                    key: const ValueKey('share-retry'),
                    onPressed: controller.canShare
                        ? () => _share(buttonContext)
                        : null,
                    child: Text(loc.translate('retry')),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    ShareFlowController controller,
    ShareSection section,
  ) {
    final loc = AppLocalizations.of(context);
    final labels = controller.labels;
    final source = controller.source;
    final unavailable = controller.isUnavailable(section);

    String? detail;
    if (unavailable) {
      detail = loc.translate('shareItemUnavailable');
    } else if (section == ShareSection.media) {
      detail = loc
          .translate('shareMediaCount')
          .replaceAll('{selected}', '${controller.selectedMediaCount}')
          .replaceAll('{total}', '${controller.totalMediaCount}');
    } else {
      detail = source.sectionDetail(section, labels);
    }

    return Column(
      children: [
        _OptionTile(
          key: ValueKey('share-option-${section.name}'),
          icon: _iconOf(section),
          title: loc.translate(source.sectionTitleKey(section)),
          detail: detail,
          selected: controller.isSelected(section),
          enabled: !controller.isBusy && !unavailable,
          onTap: () => controller.toggleSection(section),
        ),
        if (section == ShareSection.media)
          _buildMediaChips(context, controller),
      ],
    );
  }

  Widget _buildMediaChips(
      BuildContext context, ShareFlowController controller) {
    final loc = AppLocalizations.of(context);
    final busy = controller.isBusy;
    var photos = 0;
    var videos = 0;

    final chips = <Widget>[];
    for (final item in controller.source.media) {
      final n = item.isVideo ? ++videos : ++photos;
      final base = loc
          .translate(item.isVideo ? 'shareMediaVideoN' : 'shareMediaPhotoN')
          .replaceAll('{n}', '$n');
      final unavailable = controller.isMediaUnavailable(item.key);
      final label = unavailable
          ? '$base · ${loc.translate('shareItemUnavailable')}'
          : base;
      final selected = controller.isMediaSelected(item.key);
      chips.add(Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: !busy && !unavailable,
        label: label,
        excludeSemantics: true,
        onTap:
            busy || unavailable ? null : () => controller.toggleMedia(item.key),
        child: SelectableChip(
          key: ValueKey('share-media-${item.key}'),
          label: label,
          isSelected: selected && !unavailable,
          isEnabled: !busy && !unavailable,
          onTap: () => controller.toggleMedia(item.key),
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4, end: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppControlSizes.chipSpacing,
            runSpacing: AppControlSizes.chipSpacing,
            children: chips,
          ),
          if (controller.totalMediaCount > 1)
            TextButton(
              key: const ValueKey('share-media-all'),
              onPressed: busy
                  ? null
                  : (controller.selectedMediaCount == controller.totalMediaCount
                      ? controller.clearMedia
                      : controller.selectAllMedia),
              child: Text(
                loc.translate(
                  controller.selectedMediaCount == controller.totalMediaCount
                      ? 'clear'
                      : 'selectAll',
                ),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconOf(ShareSection section) {
    switch (section) {
      case ShareSection.basicInfo:
        return Icons.info_rounded;
      case ShareSection.pricing:
        return Icons.payments_rounded;
      case ShareSection.propertyDetails:
        return Icons.home_rounded;
      case ShareSection.locationDetails:
        return Icons.location_city_rounded;
      case ShareSection.map:
        return Icons.map_rounded;
      case ShareSection.contact:
        return Icons.phone_rounded;
      case ShareSection.notes:
        return Icons.note_rounded;
      case ShareSection.media:
        return Icons.photo_library_rounded;
      case ShareSection.document:
        return Icons.picture_as_pdf_rounded;
    }
  }
}

class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({
    super.key,
    required this.value,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });

  final bool? value;
  final bool enabled;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      checked: value == true,
      mixed: value == null,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onChanged : null,
      child: InkWell(
        onTap: enabled ? onChanged : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Transform.scale(
                scale: 0.9,
                child: Checkbox(
                  tristate: true,
                  value: value,
                  onChanged: enabled ? (_) => onChanged() : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: texts.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        container: true,
        checked: selected,
        enabled: enabled,
        label: detail == null ? title : '$title, $detail',
        excludeSemantics: true,
        onTap: enabled ? onTap : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? colors.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? colors.primary.withValues(alpha: 0.3)
                      : colors.outline.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary.withValues(alpha: 0.15)
                          : colors.surfaceContainerHighest
                              .withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant
                              .withValues(alpha: enabled ? 1 : 0.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: texts.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: enabled
                                ? colors.onSurface
                                : colors.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: texts.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: selected,
                      onChanged: enabled ? (_) => onTap() : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
