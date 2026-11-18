import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DetailsMediaPlaceholder extends StatelessWidget {
  const DetailsMediaPlaceholder({super.key, required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Color.alphaBlend(
        colors.primary.withValues(alpha: 0.06),
        colors.surfaceContainerHighest,
      ),
      child: Center(
        child: SvgPicture.asset(
          asset,
          width: 56,
          height: 56,
          colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
