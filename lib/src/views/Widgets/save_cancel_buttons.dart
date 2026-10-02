import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Save and Cancel for the add/edit form screens: two pill buttons that FLOAT
/// above the page.
///
/// Nothing sits behind them — no panel, no dock, no shadow of their own. The
/// page colour shows around the buttons and the form's content can scroll under
/// the gaps. This component owns, once for every form:
///
///  * the buttons' size: both are [AppControlSizes.formActionHeight] tall in
///    every state — Save or Update, saving, "nothing to save yet" — see
///    [buttonHeightOf];
///  * the margins around the buttons ([margin] on every side);
///  * the bottom system inset ([SafeArea]) so they clear the navigation area;
///  * opaque buttons — a filled Cancel, and a Save whose "nothing to save yet"
///    tint is blended onto the page colour — so content scrolling underneath
///    never shows through them;
///  * [clearanceOf], the room a form's scroll view must keep at its end so the
///    last field can scroll completely above the buttons.
///
/// Place it at the bottom of the form's `Stack`, in a
/// `Positioned(bottom: 0, left: 0, right: 0)`, and leave it out while the
/// keyboard is open — the form scrolls above the keyboard instead, as the form
/// screens do. The buttons assume the page is painted with the theme's
/// `colorScheme.surface`, which every form screen uses for its `Scaffold`.
class SaveCancelButtons extends StatelessWidget {
  /// Whether the save operation is currently in progress
  final bool isLoading;

  /// Whether the save button should be enabled (has content)
  final bool isEnabled;

  /// Whether we're in edit mode (affects button text)
  final bool isEditMode;

  /// Callback for save button press
  final VoidCallback? onSave;

  /// Callback for cancel button press
  final VoidCallback? onCancel;

  /// Optional custom save button text
  final String? saveButtonText;

  /// Optional custom cancel button text
  final String? cancelButtonText;

  const SaveCancelButtons({
    super.key,
    required this.isLoading,
    required this.isEnabled,
    required this.isEditMode,
    required this.onSave,
    required this.onCancel,
    this.saveButtonText,
    this.cancelButtonText,
  });

  /// The margin around the buttons, on every side.
  static const double margin = 16;

  /// The gap between Save and Cancel.
  static const double buttonGap = 18;

  /// Space kept between a form's last field and the actions once the form is
  /// scrolled to its end.
  static const double contentGap = 16;

  // The progress indicator that replaces Save's label while saving.
  static const double _progressSize = 20;

  // The room a label keeps above and below it. Only a text scale large enough
  // that the label line plus this no longer fits the canonical height makes a
  // button taller.
  static const double _minLabelPadding = 8;

  // The tints the buttons have always had: 30% of the primary colour for a Save
  // with nothing to save yet, 50% for Cancel.
  static const int _nothingToSaveAlpha = 77;
  static const int _cancelAlpha = 128;

  /// Each button's height. It is [AppControlSizes.formActionHeight] for Save and
  /// Cancel alike, and does not change with the state (Save or Update, saving,
  /// nothing to save yet) or the language. It grows only when the text scale is
  /// so large that the label line, at the current scale and the theme's button
  /// line-height, plus [_minLabelPadding] above and below would no longer fit.
  static double buttonHeightOf(BuildContext context) {
    final fontSize = AppTextStyles.buttonText.fontSize ?? 14.0;
    final lineHeight = Theme.of(context).textTheme.labelLarge?.height ?? 1.43;
    final labelLine =
        MediaQuery.textScalerOf(context).scale(fontSize) * lineHeight;
    return math.max(
      AppControlSizes.formActionHeight,
      math.max(labelLine, _progressSize) + 2 * _minLabelPadding,
    );
  }

  /// The actions' height without the system inset: the margin above and below
  /// the buttons, and the buttons themselves ([buttonHeightOf]).
  static double heightOf(BuildContext context) =>
      2 * margin + buttonHeightOf(context);

  /// The bottom padding a form's scroll view needs so its last field can scroll
  /// completely above the floating actions: their height, the bottom system
  /// inset they clear, and [contentGap]. It follows the text scale and the
  /// inset, so no device-specific number is baked into a screen.
  ///
  /// Use it where the screen used to hard-code the room for a bottom panel.
  static double clearanceOf(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + heightOf(context) + contentGap;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final buttonHeight = buttonHeightOf(context);
    final cancelTint = colors.primary.withAlpha(_cancelAlpha);

    // Only the bottom inset, as the app's own SafeArea does (app.dart).
    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Padding(
        padding: const EdgeInsets.all(margin),
        // Both buttons take their height from the one shared value, so they are
        // the same height in every state and the form's clearance can use it.
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: buttonHeight,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEnabled
                        ? colors.primary
                        : Color.alphaBlend(
                            colors.primary.withAlpha(_nothingToSaveAlpha),
                            colors.surface),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: _progressSize,
                          width: _progressSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          saveButtonText ??
                              (isEditMode
                                  ? localization.translate('update')
                                  : localization.translate('save')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.buttonText
                              .copyWith(color: Colors.white),
                        ),
                ),
              ),
            ),
            const SizedBox(width: buttonGap),
            Expanded(
              child: SizedBox(
                height: buttonHeight,
                child: OutlinedButton(
                  onPressed: isLoading ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: colors.surface,
                    foregroundColor: cancelTint,
                    side: BorderSide(color: cancelTint, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    cancelButtonText ?? localization.translate('cancel'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.buttonText.copyWith(color: cancelTint),
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
