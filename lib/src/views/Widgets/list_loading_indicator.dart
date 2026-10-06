import 'dart:async';

import 'package:flutter/material.dart';

/// Shows [child] only once [delay] has passed, fading it in, and nothing
/// before that. A load that ends sooner never shows it at all, so a fast load
/// does not flash a loading state; one that ends just after [delay] is barely
/// noticed because the child is still fading in.
class DelayedReveal extends StatefulWidget {
  const DelayedReveal({
    super.key,
    required this.child,
    this.delay = defaultDelay,
  });

  /// How long a load may take before its loading state starts to appear.
  static const Duration defaultDelay = Duration(milliseconds: 400);

  final Widget child;
  final Duration delay;

  @override
  State<DelayedReveal> createState() => _DelayedRevealState();
}

class _DelayedRevealState extends State<DelayedReveal> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: widget.child,
    );
  }
}

/// What a list screen shows until its first list arrives: one progress
/// indicator, centered on the page, revealed by [DelayedReveal]. It replaces the
/// per-screen shimmer placeholders; a refresh or a delete never shows it (the
/// list stays on screen).
class ListLoadingIndicator extends StatelessWidget {
  const ListLoadingIndicator({super.key, this.delay = defaultDelay});

  /// How long a list may take before the indicator starts to appear.
  static const Duration defaultDelay = DelayedReveal.defaultDelay;

  final Duration delay;

  @override
  Widget build(BuildContext context) {
    // The room is kept from the first frame, so nothing moves when it appears.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: DelayedReveal(
        delay: delay,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
