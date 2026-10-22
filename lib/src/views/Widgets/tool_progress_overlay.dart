import 'package:flutter/material.dart';

/// The one progress indicator of a toolbox screen while it makes or saves a
/// document: a lightly dimmed screen that takes the taps, and a small centered
/// box with one short line and a spinner below it.
///
/// It is the only indicator on screen. The button that started the work keeps
/// its label and look, and no card or spinner is added elsewhere. There is no
/// percentage, no stage text and no button: the libraries report no progress,
/// and one tap should read as one operation. The box has the same size for the
/// whole operation.
class ToolProgressOverlay extends StatelessWidget {
  const ToolProgressOverlay({
    super.key,
    required this.message,
    this.accent,
  });

  final String message;

  /// The tool's color for the spinner; the theme's primary if null.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = accent ?? colors.primary;
    return Stack(
      fit: StackFit.expand,
      children: [
        ModalBarrier(
          dismissible: false,
          color: colors.scrim.withValues(alpha: 0.24),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
