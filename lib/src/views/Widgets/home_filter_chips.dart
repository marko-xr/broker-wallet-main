import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_filter_chips.dart';

/// The Home filters: Search's compact chips, with a selection that never makes
/// the row jump.
///
/// In Search's row a chosen chip gets its check mark in a single frame and its
/// label changes weight, so the chip is wider at once and every chip after it
/// jumps sideways; moving the choice from one chip to another does that twice.
/// Here the room for the check mark opens and closes over the same [transition]
/// as the colours, and the label keeps one weight, so a chip's width, and with it
/// where its neighbours are, glides in both directions.
///
/// Everything else is Search's [FilterChips]: the height, the touch target, the
/// padding, the label, the colours and shadows, and the spacing between chips,
/// which follows the reading direction. The row starts at the reading edge.
class HomeFilterChips extends StatelessWidget {
  final List<FilterModel> filters;
  final void Function(int) onToggle;

  const HomeFilterChips({
    super.key,
    required this.filters,
    required this.onToggle,
  });

  /// How long a chip takes to change between chosen and not chosen. Its colours
  /// and the room for its check mark move together.
  static const Duration transition = Duration(milliseconds: 200);

  /// The pace of that change.
  static const Curve curve = Curves.easeInOut;

  // The same numbers Search's chips have.
  static const double _horizontalPadding = 16;
  static const double _verticalPadding = 8;
  static const double _borderWidth = 1;
  static const double _checkSize = 16;
  static const double _checkGap = 6;

  /// The room a chip makes for its check mark when it is chosen: the check and
  /// the gap before it.
  static const double checkRoom = _checkGap + _checkSize;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final touchHeight = FilterChips.rowHeightOf(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          for (var index = 0; index < filters.length; index++)
            Padding(
              // A chip keeps its own animation however the row changes.
              key: ValueKey<String>(
                  filters[index].labelKey ?? filters[index].label),
              // Direction-aware spacing (mirrors in RTL)
              padding: const EdgeInsetsDirectional.only(
                end: AppControlSizes.chipSpacing,
              ),
              child: _Chip(
                label: filters[index].labelKey != null
                    ? localization.translate(filters[index].labelKey!)
                    : filters[index].label,
                selected: filters[index].selected,
                onTap: () => onToggle(index),
                touchHeight: touchHeight,
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.touchHeight,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double touchHeight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppControlSizes.chipRadius);

    return GestureDetector(
      // The taller area around the chip answers to a tap too. The chip's own
      // InkWell, being nearer, takes the taps that land on the chip.
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: SizedBox(
        height: touchHeight,
        child: Center(
          child: Semantics(
            button: true,
            selected: selected,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: AnimatedContainer(
                  duration: HomeFilterChips.transition,
                  curve: HomeFilterChips.curve,
                  // At least the compact height; the label and its padding decide
                  // when a large font needs more. No alignment here: an aligned
                  // Container grows to fill the room it is given, which is the
                  // whole touch target, not the chip.
                  constraints: const BoxConstraints(
                    minHeight: AppControlSizes.compactChipHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: HomeFilterChips._horizontalPadding,
                    vertical: HomeFilterChips._verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : colors.surface,
                    borderRadius: radius,
                    border: Border.all(
                      color: selected
                          ? colors.primary
                          : colors.outline.withValues(alpha: 0.2),
                      width: HomeFilterChips._borderWidth,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: colors.shadow.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: HomeFilterChips.transition,
                        curve: HomeFilterChips.curve,
                        style: TextStyle(
                          color: selected ? colors.onPrimary : colors.onSurface,
                          // One weight for both states: a weight change makes
                          // the label wider, and that is a second jump.
                          fontWeight: FontWeight.w500,
                          fontSize: FilterChips.labelFontSize,
                          // A fixed line box: the chip's height must not depend
                          // on the font's own metrics.
                          height: FilterChips.labelLineHeight,
                        ),
                        child: Text(label, maxLines: 1, softWrap: false),
                      ),
                      _CheckMark(visible: selected, color: colors.onPrimary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The check mark of a chosen chip, and the room it takes.
///
/// The room opens and closes with the animation (its width is the check's width
/// times how far along the animation is) instead of appearing in one frame, so
/// the chips beside it are carried along smoothly. While it is closed nothing is
/// drawn and nothing takes room.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.visible, required this.color});

  final bool visible;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visible ? 1 : 0),
      duration: HomeFilterChips.transition,
      curve: HomeFilterChips.curve,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: HomeFilterChips._checkGap),
          Icon(
            Icons.check_rounded,
            size: HomeFilterChips._checkSize,
            color: color,
          ),
        ],
      ),
      builder: (context, progress, check) {
        if (progress <= 0) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: progress,
            heightFactor: 1,
            child: Opacity(
              opacity: progress > 1 ? 1.0 : progress,
              child: check,
            ),
          ),
        );
      },
    );
  }
}
