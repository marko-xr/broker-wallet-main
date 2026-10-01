import 'package:flutter/material.dart';

import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Shared layout for a screen whose whole job is to report an outcome:
/// purchase success, pending, cancelled, failure, and the restore results.
///
/// The message scrolls (large text, long Arabic) while [actions] stay pinned
/// to the bottom, so the primary action is always reachable.
class PlusResultView extends StatelessWidget {
  const PlusResultView({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    required this.actions,
    this.extra,
    this.popIn = false,
  });

  final IconData icon;
  final PlusTone tone;
  final String title;
  final String body;
  final List<Widget> actions;

  /// Optional extra content under the message (for example a notice card).
  final Widget? extra;

  /// Scales the icon in once. Used for success only, and skipped entirely
  /// when the user has turned animations off.
  final bool popIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final animate = popIn && !MediaQuery.disableAnimationsOf(context);

    final badge = PlusIconBadge(icon: icon, tone: tone, size: 96);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (animate)
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.7, end: 1),
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: badge,
                    )
                  else
                    badge,
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.8),
                      height: 1.45,
                    ),
                  ),
                  if (extra != null) ...[
                    const SizedBox(height: 20),
                    extra!,
                  ],
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                actions[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
