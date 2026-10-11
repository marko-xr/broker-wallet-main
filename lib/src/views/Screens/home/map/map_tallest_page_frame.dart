import 'package:flutter/material.dart';

/// The frame a [PageView] of cards sits in, exactly as tall as its tallest card.
///
/// A [PageView] takes its height from its parent, and a hard-coded height is a
/// bet that no card ever needs more: an Arabic title, a font whose lines are
/// taller than Latin ones, or a larger text size in the phone's settings each
/// make a card taller than the bet, and Flutter paints "BOTTOM OVERFLOWED BY n
/// PIXELS" over it. This frame never bets: the page view fills whatever height
/// the cards themselves ask for.
///
/// [measure] is one stand-in for every card, built the way the real card is, so
/// the two cannot disagree about their height. The stand-ins are laid out but
/// never drawn, never touched, never focused and never read out; they only give
/// this widget its size, so the height is the same on every page (swiping never
/// resizes the frame). [minHeight] is the floor, kept so a card that always
/// fitted looks as it always did.
///
/// The widget holds no state and reads nothing: its inputs are plain widgets.
class TallestPageFrame extends StatelessWidget {
  const TallestPageFrame({
    super.key,
    required this.minHeight,
    required this.measure,
    required this.child,
  });

  /// The least height the frame has, whatever the cards need.
  final double minHeight;

  /// One stand-in for each card; the tallest one sets the frame's height.
  final List<Widget> measure;

  /// The page view; it is given the frame's whole size.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Full width as the page view always had; at least [minHeight] tall.
      constraints: BoxConstraints(
        minWidth: double.infinity,
        minHeight: minHeight,
      ),
      child: Stack(
        children: [
          // A stack is as big as its biggest unpositioned child, which is what
          // makes it the tallest card's height.
          for (final card in measure)
            ExcludeFocus(
              child: Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: card,
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
