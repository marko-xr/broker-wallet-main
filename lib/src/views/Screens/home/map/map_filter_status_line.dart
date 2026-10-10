import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/map_result_count.dart';
import 'package:flutter/material.dart';

/// What the map says under its filters, in one line over the map:
///
///     [ 12 results ]                                       [ ⟲ Reset ]
///
/// Both are small floating pills like the map's other controls, at the two
/// edges, so neither moves the other when its text changes. They follow the
/// reading direction: the count is at the start (on the right, in Arabic).
///
///  * The count is how many places the markers on the map stand for. The screen
///    gives it the number of the last draw that was published, so it is always
///    the same places as the markers; nothing is asked or counted again here.
///    It is null (and so not shown) while nothing has been drawn yet, or when
///    the places could not be loaded: it never says "0 results" for a map that
///    simply has not loaded.
///  * Reset is shown only while the filters differ from the default, and does
///    what the no-matches banner's action does: [onReset] puts the filters
///    back. It reads nothing and asks the device for nothing.
///
/// The widget holds no state and reads nothing: its inputs are plain values.
class MapFilterStatusLine extends StatelessWidget {
  const MapFilterStatusLine({
    super.key,
    required this.localization,
    required this.resultCount,
    required this.canReset,
    required this.onReset,
  });

  /// For tests: the count's pill and the Reset button.
  static const Key resultCountKey = ValueKey<String>('mapResultCount');
  static const Key resetKey = ValueKey<String>('mapResetFilters');

  /// How much room the line takes, the Reset's touch area included.
  static const double height = 40;

  final AppLocalizations localization;

  /// How many places the map shows now; null when that is not known (nothing
  /// drawn yet, or the load failed), and then no count is shown.
  final int? resultCount;

  /// Whether the filters differ from the default.
  final bool canReset;

  /// Puts the filters back to the default.
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final count = resultCount;
    if (count == null && !canReset) return const SizedBox.shrink();

    // Two slots, always: the count at the start and Reset at the end, whichever
    // of them is there.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (count != null)
          Flexible(child: IgnorePointer(child: _countPill(context, count)))
        else
          const SizedBox.shrink(),
        if (canReset)
          Flexible(child: _resetButton(context))
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _countPill(BuildContext context, int count) {
    final text = MapResultCount.text(
      count,
      languageCode: localization.locale.languageCode,
      translate: localization.translate,
    );
    // The count follows the markers, so it is announced when it changes.
    return _StatusPill(
      key: resultCountKey,
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _style(context),
        ),
      ),
    );
  }

  Widget _resetButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: localization.translate('mapResetFilters'),
      onTap: onReset,
      excludeSemantics: true,
      child: GestureDetector(
        key: resetKey,
        behavior: HitTestBehavior.opaque,
        onTap: onReset,
        // The pill is 32 high; the room around it makes the touch area 40.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _StatusPill(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restart_alt_rounded,
                    size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    localization.translate('mapReset'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _style(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static TextStyle _style(BuildContext context) => TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      );
}

/// A small pill with the surface and shadow the map's other floating controls
/// (the search bar, the buttons, the banner) have.
class _StatusPill extends StatelessWidget {
  const _StatusPill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
