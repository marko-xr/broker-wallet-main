// lib/src/Views/Widgets/settings_section_header.dart
import 'package:flutter/material.dart';

/// Section title used to group related [SettingsTile] rows on the Profile
/// screen (e.g. "General Settings", "Account & Billing"). Kept as its own
/// small widget so every category heading stays visually consistent.
class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final texts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: texts.titleLarge,
        textAlign: TextAlign.start,
      ),
    );
  }
}
