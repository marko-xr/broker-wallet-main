import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:flutter/material.dart';

/// The Call/WhatsApp row shared by every list card, so their order,
/// styling, and disabled appearance can only drift out of sync in one
/// place instead of once per list screen that duplicates it.
class ContactActionsRow extends StatelessWidget {
  const ContactActionsRow({
    super.key,
    required this.hasPhone,
    required this.onCall,
    required this.onWhatsApp,
  });

  final bool hasPhone;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final activeColor = const Color(0xFF4CAF50);
    final mutedColor = colors.onSurfaceVariant.withValues(alpha: 0.5);
    final background = hasPhone
        ? const Color(0xFFE8F5E8)
        : colors.surfaceContainerHighest.withValues(alpha: 0.5);

    Widget pill({
      required VoidCallback? onTap,
      required Widget icon,
      required String label,
    }) {
      return Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: texts.bodyMedium?.copyWith(
                        color: hasPhone ? activeColor : mutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      pill(
        onTap: hasPhone ? onCall : null,
        // Material's phone_disabled slash runs the opposite diagonal from
        // the WhatsApp-disabled artwork below; flip it so both "disabled"
        // marks lean the same way.
        icon: hasPhone
            ? Icon(Icons.phone_rounded, color: activeColor, size: 20)
            : Transform.flip(
                flipX: true,
                child: Icon(Icons.phone_disabled_rounded,
                    color: mutedColor, size: 20),
              ),
        label: loc.translate('call'),
      ),
      const SizedBox(width: 12),
      pill(
        onTap: hasPhone ? onWhatsApp : null,
        icon: Image.asset(
          hasPhone ? AppImages.whatsapp : AppImages.whatsAppDisable,
          width: 20,
          height: 20,
          color: hasPhone ? null : mutedColor,
        ),
        label: loc.translate('whatsapp'),
      ),
    ]);
  }
}
