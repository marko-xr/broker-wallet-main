import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// The Search filters: one row of compact chips that float on the page.
///
/// Every chip is the same height — [AppControlSizes.compactChipHeight] — selected
/// or not, in English or Arabic, whether or not it carries the check mark. A
/// chip's visible size is not the size of what answers to a tap: each one is
/// handed a full [AppControlSizes.minTouchTarget] of height to be hit in, so
/// being compact does not make it hard to press.
class FilterChips extends StatelessWidget {
  final List<FilterModel> filters;
  final void Function(int) onToggle;

  const FilterChips({
    super.key,
    required this.filters,
    required this.onToggle,
  });

  /// The least height the row takes: the touch target.
  static const double rowHeight = AppControlSizes.minTouchTarget;

  /// The label's size and its line height, as a multiple of its size.
  static const double labelFontSize = 14;
  static const double labelLineHeight = 1.2;

  // A chip is its label line between this much padding and its border.
  static const double _chipVerticalPadding = 8;
  static const double _chipBorderWidth = 1;

  /// The height a chip needs for its label at the current text size, never less
  /// than [AppControlSizes.compactChipHeight].
  static double chipHeightOf(BuildContext context) {
    final line =
        MediaQuery.textScalerOf(context).scale(labelFontSize) * labelLineHeight;
    return math.max(
      AppControlSizes.compactChipHeight,
      line + 2 * (_chipVerticalPadding + _chipBorderWidth),
    );
  }

  /// The height the whole row takes: the touch target at normal text, and
  /// enough for the chips when a large font makes them taller.
  static double rowHeightOf(BuildContext context) =>
      math.max(rowHeight, chipHeightOf(context) + 8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final localization = AppLocalizations.of(context);
    final targetHeight = rowHeightOf(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: List.generate(filters.length, (index) {
          final filter = filters[index];
          final isSelected = filter.selected;
          final radius = BorderRadius.circular(AppControlSizes.chipRadius);

          return Padding(
            // Direction-aware spacing (mirrors in RTL)
            padding: const EdgeInsetsDirectional.only(
              end: AppControlSizes.chipSpacing,
            ),
            child: GestureDetector(
              // The taller area around the chip answers to a tap too. The chip's
              // own InkWell, being nearer, takes the taps that land on the chip.
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () => onToggle(index),
              child: SizedBox(
                height: targetHeight,
                child: Center(
                  child: Semantics(
                    button: true,
                    selected: isSelected,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onToggle(index),
                        borderRadius: radius,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          // At least the compact height; the label and its
                          // padding decide when a large font needs more. No
                          // alignment here: an aligned Container grows to fill
                          // the room it is given, which is the whole touch
                          // target, not the chip.
                          constraints: const BoxConstraints(
                            minHeight: AppControlSizes.compactChipHeight,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: _chipVerticalPadding,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primary
                                : theme.colorScheme.surface,
                            borderRadius: radius,
                            border: Border.all(
                              color: isSelected
                                  ? primary
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.2),
                              width: _chipBorderWidth,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: primary.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontSize: labelFontSize,
                                  // A fixed line box: the chip's height must
                                  // not depend on the font's own metrics.
                                  height: labelLineHeight,
                                ),
                                child: Text(
                                  filter.labelKey != null
                                      ? localization.translate(filter.labelKey!)
                                      : filter.label,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
