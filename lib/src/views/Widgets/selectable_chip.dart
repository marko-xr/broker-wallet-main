import 'package:flutter/material.dart';

import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/constants/constants.dart';

/// The rounded chip the forms use for quick-pick options: the area chips, the
/// city chips and the Owner property-type suggestions.
///
/// It has the three looks the area chips always had: selected (filled),
/// selectable (tinted outline) and unavailable (dimmed, ignoring taps).
///
/// Its size is the app's one chip size ([AppControlSizes.chipHorizontalPadding],
/// [AppControlSizes.chipVerticalPadding], [AppControlSizes.chipBorderWidth],
/// [AppControlSizes.chipRadius]) around ONE line of label. The label never wraps
/// — a very long name is ellipsized instead — and every line gets the same line
/// box whatever its script, so a chip's height never depends on its label: every
/// chip, in every state and language, is the same height, and only the width
/// follows the label.
class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isEnabled = true,
  });

  /// Horizontal padding between the chip's border and its label.
  static const double horizontalPadding = AppControlSizes.chipHorizontalPadding;

  static const double verticalPadding = AppControlSizes.chipVerticalPadding;

  static const double borderWidth = AppControlSizes.chipBorderWidth;

  /// The width a chip adds around its label: padding and border, both sides.
  /// A layout that has to predict a chip's width starts from this.
  static const double horizontalInset = 2 * (horizontalPadding + borderWidth);

  /// The label's style, before its colour. A layout that measures a chip's text
  /// must measure with this style, on one line ([labelMaxLines]).
  static final TextStyle textStyle =
      AppTextStyles.chipText.copyWith(fontWeight: FontWeight.w600);

  /// A chip's label is one line.
  static const int labelMaxLines = 1;

  final String label;
  final bool isSelected;

  /// A chip that is not enabled looks dimmed and ignores taps.
  final bool isEnabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: _chipDecoration(
          fill: isSelected
              ? primary
              : isEnabled
                  ? primary.withValues(alpha: 0.07)
                  : primary.withValues(alpha: 0.03),
          border: isSelected
              ? primary
              : isEnabled
                  ? primary
                  : primary.withValues(alpha: 0.3),
        ),
        child: _ChipLabel(
          label,
          color: isSelected
              ? Colors.white
              : isEnabled
                  ? primary
                  : primary.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// The filled chip that shows a choice already made, with a clear (×) button:
/// the selected city of the Request, Offer and Owner forms.
///
/// It is a selected [SelectableChip] with a × after the label — the same border,
/// corners, padding and one-line label — so it is exactly as tall as the chips
/// around it, including the area chips right below it. Only its width differs:
/// the label, then the × area.
///
/// The × is not just the 18 px icon. Its tap area is the icon plus the room
/// around it — [clearIconSize] plus the gap and the end padding wide, and the
/// chip's full inner height tall — so it is easy to hit without the chip growing.
class ClearableChip extends StatelessWidget {
  const ClearableChip({
    super.key,
    required this.label,
    required this.onClear,
    this.clearKey,
  });

  final String label;

  /// Called when the × is tapped.
  final VoidCallback onClear;

  /// Identifies the clear button, for tests.
  final Key? clearKey;

  static const double clearIconSize = 18;

  // The gap between the label and the ×.
  static const double _clearIconGap = 8;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: AppControlSizes.chipHorizontalPadding,
      ),
      decoration: _chipDecoration(fill: primary, border: primary),
      // Both cells are as tall as the label's cell, so the × can never make the
      // chip taller than its label does.
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppControlSizes.chipVerticalPadding,
              ),
              child: _ChipLabel(label, color: Colors.white),
            ),
            GestureDetector(
              key: clearKey,
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsetsDirectional.only(
                  start: _clearIconGap,
                  end: AppControlSizes.chipHorizontalPadding,
                ),
                child: Center(
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: clearIconSize,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame every chip shares: its fill, its border of one thickness and its
/// pill corners. The border is part of the chip's size in every state, selected
/// or not, so the fill and the border colour are all that ever differ.
BoxDecoration _chipDecoration({required Color fill, required Color border}) {
  return BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(AppControlSizes.chipRadius),
    border: Border.all(color: border, width: AppControlSizes.chipBorderWidth),
  );
}

/// A chip's label: [SelectableChip.textStyle] on one line, ellipsized rather
/// than wrapped, with every line forced to the line box of the style it inherits.
///
/// Without the forced line box, a line whose glyphs come from more than one font
/// (an Arabic name with a Latin digit, say) can be a pixel or two taller than a
/// line from one font, which would make that chip taller than its neighbours.
class _ChipLabel extends StatelessWidget {
  const _ChipLabel(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = SelectableChip.textStyle.copyWith(color: color);
    // The style the text really gets: its own over what it inherits.
    final effective = DefaultTextStyle.of(context).style.merge(style);

    return Text(
      label,
      maxLines: SelectableChip.labelMaxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
      strutStyle: StrutStyle.fromTextStyle(effective, forceStrutHeight: true),
    );
  }
}
