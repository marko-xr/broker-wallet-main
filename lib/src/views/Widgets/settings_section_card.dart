// lib/src/Views/Widgets/settings_section_card.dart
import 'package:flutter/material.dart';

/// Groups the [SettingsTile] rows of one Profile/Settings category into a
/// single rounded card, matching the Intlaq-style grouped list layout while
/// keeping Broker Wallet's own colors, radius and elevation language.
///
/// This widget owns the card's background, border radius and clipping, and
/// draws a subtle theme-aware divider between rows (never after the last
/// row). Each child should be a [SettingsTile] built with `grouped: true`
/// so it renders as a flat row instead of its own standalone card.
class SettingsSectionCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsSectionCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor;

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 20, end: 20),
            child: Divider(height: 1, thickness: 0.1, color: dividerColor),
          ),
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: colors.surface,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}
