import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:flutter/material.dart';

class ProfileFeatureScaffold extends StatelessWidget {
  const ProfileFeatureScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.statusTitle,
    required this.statusDescription,
    this.children = const [],
  });

  final String title;
  final IconData icon;
  final String statusTitle;
  final String statusDescription;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(title, style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            ProfileStatusCard(
              icon: icon,
              title: statusTitle,
              description: statusDescription,
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ProfileStatusCard extends StatelessWidget {
  const ProfileStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary, size: 30),
            const SizedBox(height: 16),
            Text(title, style: texts.titleLarge),
            const SizedBox(height: 8),
            Text(
              description,
              style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
