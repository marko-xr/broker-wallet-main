import 'package:flutter/material.dart';

/// The card at the top of every toolbox screen.
///
/// One widget for all the tools so they cannot drift apart: the same height,
/// radius, shadow, icon box and text sizes. A tool only supplies its icon, its
/// two lines of text and its colors. The height is fixed (and follows the
/// system text size), so a long line is cut with an ellipsis instead of making
/// one tool's card taller than another's.
class ToolHeaderCard extends StatelessWidget {
  const ToolHeaderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  /// The card's height at the normal text size.
  static const double baseHeight = 100;

  final IconData icon;
  final String title;
  final String subtitle;

  /// Start and end colors of the diagonal gradient.
  final List<Color> gradient;

  /// Outer spacing. Pass [EdgeInsets.zero] inside a list that already pads.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
        .clamp(1.0, 1.6)
        .toDouble();
    return Container(
      height: baseHeight * textScale,
      margin: margin,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
