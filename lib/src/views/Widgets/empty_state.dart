// lib/src/widgets/empty_state.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class EmptyState extends StatelessWidget {
  final String asset;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.asset,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(asset, width: 120, height: 120),
          const SizedBox(height: 24),
          Text(
            title,
            style: textTheme.headlineSmall, // was typography.heading
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: textTheme.bodyMedium, // was typography.bodyText2
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
