import 'package:flutter/material.dart';

import 'package:broker_wallet/src/views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_debug_preview_sheet.dart';

/// The frame every Subscription & Billing screen shares: the back arrow, a
/// centred title, a safe-area scrolling body with the standard gutter, and an
/// optional pinned [bottom] bar (for a screen's one primary action).
///
/// Keeping the frame in one place is what makes the sub-screens feel like one
/// calm area instead of separate pages: same spacing, same back behaviour, and
/// the debug-only preview button in the same corner everywhere.
class PlusScreenScaffold extends StatelessWidget {
  const PlusScreenScaffold({
    super.key,
    required this.title,
    required this.children,
    this.bottom,
    this.showDebugButton = true,
  });

  final String title;
  final List<Widget> children;

  /// Pinned under the scrolling content, above the system navigation area.
  final Widget? bottom;

  /// The debug preview button renders nothing outside debug builds.
  final bool showDebugButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrowButton(),
        // Scales down rather than ellipsizing, so a long title ("Manage payment
        // methods", or its Arabic) stays whole on a narrow phone.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        actions: showDebugButton ? const [PlusDebugButton()] : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: children,
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}

/// A pinned bar for a screen's single primary action, matching the one the
/// paywall uses.
class PlusBottomBar extends StatelessWidget {
  const PlusBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: colors.outline.withValues(alpha: 0.18)),
        ),
      ),
      child: child,
    );
  }
}
