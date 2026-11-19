import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// The one "Delete …?" confirmation used by every list and details screen,
/// so the dialog looks and behaves the same everywhere.
///
/// Returns true only when the user taps Delete. Cancel, the barrier and Back
/// all return false.
Future<bool> showDeleteConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required IconData itemIcon,
  required String itemLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteConfirmationDialog(
      title: title,
      message: message,
      itemIcon: itemIcon,
      itemLabel: itemLabel,
    ),
  );
  return confirmed == true;
}

class DeleteConfirmationDialog extends StatelessWidget {
  const DeleteConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.itemIcon,
    required this.itemLabel,
  });

  final String title;
  final String message;
  final IconData itemIcon;
  final String itemLabel;

  /// Keys of the two buttons, for tests and accessibility tools.
  static const Key cancelKey = ValueKey('delete-confirm-cancel');
  static const Key deleteKey = ValueKey('delete-confirm-delete');

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const buttonSize = Size.fromHeight(48);
    final buttonText = texts.labelLarge?.copyWith(fontWeight: FontWeight.w600);

    // Material 3 confirmation: the icon, title and message centred; the record
    // in a calm chip; two equal buttons, the safe one first. No LayoutBuilder
    // anywhere: AlertDialog sizes itself with IntrinsicWidth.
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child:
            Icon(Icons.delete_outline_rounded, color: colors.error, size: 28),
      ),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: texts.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: texts.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(itemIcon, size: 20, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    itemLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: texts.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: cancelKey,
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: buttonSize,
                  shape: buttonShape,
                  foregroundColor: colors.onSurface,
                  side: BorderSide(color: colors.outlineVariant),
                  textStyle: buttonText,
                ),
                child:
                    Text(loc.translate('cancel'), textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: deleteKey,
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: buttonSize,
                  shape: buttonShape,
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                  textStyle: buttonText,
                ),
                child:
                    Text(loc.translate('delete'), textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
