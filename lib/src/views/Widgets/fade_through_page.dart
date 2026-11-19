import 'package:flutter/material.dart';

/// A GoRouter page that opens with a Material "fade through": the screen
/// behind is covered first (the first 35% of the motion), then this screen
/// fades in while growing slightly (92% → 100%). The two screens are never
/// seen at the same time. Closing plays it in reverse.
class FadeThroughPage<T> extends Page<T> {
  const FadeThroughPage({super.key, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) =>
      _FadeThroughRoute<T>(page: this);
}

class _FadeThroughRoute<T> extends PageRoute<T> {
  _FadeThroughRoute({required FadeThroughPage<T> page}) : super(settings: page);

  FadeThroughPage<T> get _page => settings as FadeThroughPage<T>;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _FadeThrough(animation: animation, child: child);
}

class _FadeThrough extends StatelessWidget {
  const _FadeThrough({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  // The screen behind fades away first; this screen comes in after it.
  static const _coverIn = Interval(0, 0.35, curve: Curves.easeOut);
  static const _contentIn = Interval(0.35, 1, curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: child),
      // The tree keeps the same shape at every value, so the screen is never
      // rebuilt from scratch when the motion ends.
      builder: (context, page) {
        final t = animation.value;
        final content = _contentIn.transform(t);
        return ColoredBox(
          color: surface.withValues(alpha: _coverIn.transform(t)),
          child: Opacity(
            opacity: content,
            child: Transform.scale(
              scale: 0.92 + 0.08 * content,
              child: page,
            ),
          ),
        );
      },
    );
  }
}
