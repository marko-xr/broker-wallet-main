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

  static const Color _danger = Color(0xFFC81E1E);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    // No LayoutBuilder in here: AlertDialog sizes itself with IntrinsicWidth,
    // which a LayoutBuilder cannot answer. The actions bar stacks the buttons
    // by itself when they do not fit side by side.
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _danger, size: 28),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              title,
              style: texts.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: texts.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE6E6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFCCCC)),
            ),
            child: Row(
              children: [
                Icon(itemIcon, size: 18, color: _danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    itemLabel,
                    style: texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.surface,
            foregroundColor: colors.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: colors.outline.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.close_rounded,
                size: 18,
                color: colors.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  loc.translate('cancel'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: colors.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: _danger,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            shadowColor: _danger.withValues(alpha: 0.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.delete_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  loc.translate('delete'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
