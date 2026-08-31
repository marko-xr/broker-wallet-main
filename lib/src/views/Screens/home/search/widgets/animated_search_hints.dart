import 'package:flutter/material.dart';
import 'dart:async';

class AnimatedSearchHints extends StatefulWidget {
  final List<String> hints;
  final Duration duration;
  final TextStyle? style;

  const AnimatedSearchHints({
    super.key,
    required this.hints,
    this.duration = const Duration(milliseconds: 3000),
    this.style,
  });

  @override
  State<AnimatedSearchHints> createState() => _AnimatedSearchHintsState();
}

class _AnimatedSearchHintsState extends State<AnimatedSearchHints>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.hints.isNotEmpty) _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(widget.duration, (_) {
      if (!mounted || widget.hints.isEmpty) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.hints.length;
      });
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedSearchHints oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset index if hints list changes
    if (oldWidget.hints != widget.hints) {
      _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    if (mounted) {
      _timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hints.isEmpty) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.4),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeInOut)),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Text(
        widget.hints[_currentIndex],
        key: ValueKey<int>(_currentIndex),
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
