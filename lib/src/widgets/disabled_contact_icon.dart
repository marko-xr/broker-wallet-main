import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:flutter/material.dart';

class DisabledContactIcon extends StatelessWidget {
  const DisabledContactIcon.call({super.key, required this.size})
      : _isWhatsApp = false;

  const DisabledContactIcon.whatsApp({super.key, required this.size})
      : _isWhatsApp = true;

  final double size;
  final bool _isWhatsApp;

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    if (_isWhatsApp) {
      return Image.asset(
        AppImages.whatsAppDisable,
        width: size,
        height: size,
        color: color,
      );
    }

    // Match the slash direction in the disabled WhatsApp artwork.
    return Transform.flip(
      flipX: true,
      child: Icon(Icons.phone_disabled_rounded, size: size, color: color),
    );
  }
}
