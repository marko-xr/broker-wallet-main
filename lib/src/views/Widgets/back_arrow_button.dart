import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BackArrowButton extends StatelessWidget {
  final Color? iconColor;
  final Color? backgroundColor;
  final double? iconSize;
  final VoidCallback? onPressed;
  final bool showBackground;
  final EdgeInsets? padding;

  const BackArrowButton({
    super.key,
    this.iconColor,
    this.backgroundColor,
    this.iconSize,
    this.onPressed,
    this.showBackground = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    // Use the provided colors or fall back to theme colors
    final effectiveIconColor = iconColor ?? colors.primary;
    final effectiveBackgroundColor = backgroundColor ?? colors.surface;

    Widget button = IconButton(
      icon: Icon(
        isRTL ? Icons.arrow_back_ios_new : Icons.arrow_back_ios_new,
        color: effectiveIconColor,
        size: iconSize ?? 20,
      ),
      onPressed: onPressed ??
          () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/welcome');
            }
          },
      splashRadius: 24,
      padding: EdgeInsets.zero,
    );

    if (showBackground) {
      button = Container(
        decoration: BoxDecoration(
          color: effectiveBackgroundColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color.fromARGB((0.06 * 255).round(), colors.shadow.red,
                  colors.shadow.green, colors.shadow.blue),
              blurRadius: 3,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: button,
      );
    }

    return Padding(
      padding: padding ??
          const EdgeInsetsDirectional.only(
            start: 16,
            top: 6,
            bottom: 6,
          ),
      child: button,
    );
  }
}
