import 'package:flutter/material.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// A reusable widget for save and cancel buttons used in add/edit screens
///
/// This widget provides a consistent layout for action buttons at the bottom
/// of forms with proper spacing, styling, and loading states.
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

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: isLoading ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: isEnabled
                    ? colors.primary
                    : Color.fromARGB((0.3 * 255).round(), colors.primary.red,
                        colors.primary.green, colors.primary.blue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      saveButtonText ??
                          (isEditMode
                              ? localization.translate('update')
                              : localization.translate('save')),
                      style: AppTextStyles.buttonText
                          .copyWith(color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: OutlinedButton(
              onPressed: isLoading ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Color.fromARGB(
                    (0.5 * 255).round(),
                    colors.primary.red,
                    colors.primary.green,
                    colors.primary.blue),
                side: BorderSide(
                    color: Color.fromARGB(
                        (0.5 * 255).round(),
                        colors.primary.red,
                        colors.primary.green,
                        colors.primary.blue),
                    width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text(
                cancelButtonText ?? localization.translate('cancel'),
                style: AppTextStyles.buttonText.copyWith(
                    color: Color.fromARGB(
                        (0.5 * 255).round(),
                        colors.primary.red,
                        colors.primary.green,
                        colors.primary.blue)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
