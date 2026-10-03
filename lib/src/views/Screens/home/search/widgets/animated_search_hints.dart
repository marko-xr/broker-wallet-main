import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The search field's rotating hint: one suggestion at a time, swapped with a
/// short fade and a small rise.
///
/// A hint is only ever laid out at the START edge (the left in English, the
/// right in Arabic). That is not a detail: while one hint is replaced by
/// another, both are on screen at once, in a [Stack]. [AnimatedSwitcher]'s
/// default stack CENTRES its children, so the shorter of two hints used to sit
/// in the middle of the longer one's width for the length of the fade — it slid
/// toward the centre — and then snapped back to the start once the old hint was
/// gone and the stack shrank. Aligning the stack to the start leaves nothing to
/// move: a hint never changes its horizontal position, whatever its length.
class AnimatedSearchHints extends StatefulWidget {
  final List<String> hints;

  /// How long each hint stays.
  final Duration duration;
  final TextStyle? style;

  const AnimatedSearchHints({
    super.key,
    required this.hints,
    this.duration = const Duration(milliseconds: 3000),
    this.style,
  });

  /// How long one hint takes to give way to the next.
  static const Duration transitionDuration = Duration(milliseconds: 350);

  /// The layout [AnimatedSwitcher] uses here: every hint, the leaving one and
  /// the arriving one, anchored to the start edge and centred vertically.
  static Widget startAlignedLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: <Widget>[
        ...previousChildren,
        if (currentChild != null) currentChild,
      ],
    );
  }

  @override
  State<AnimatedSearchHints> createState() => _AnimatedSearchHintsState();
}

class _AnimatedSearchHintsState extends State<AnimatedSearchHints> {
  Timer? _timer;
  int _currentIndex = 0;

  // The Search tab stays mounted while another tab is in front, and its
  // animations are paused then (TickerMode) — but a Timer is not. A hint swapped
  // while paused would pile up half-finished transitions that all play at once
  // when the tab comes back, so nothing is swapped while it is hidden.
  bool _tickersEnabled = true;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.hints.length < 2) return;
    _timer = Timer.periodic(widget.duration, (_) => _showNext());
  }

  void _showNext() {
    if (!mounted || !_tickersEnabled || widget.hints.length < 2) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.hints.length;
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedSearchHints oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent builds a new list on every rebuild, so only a change in what
    // the list SAYS counts. A rebuild that changes nothing must not restart the
    // rotation or swap the hint on screen.
    if (!listEquals(oldWidget.hints, widget.hints)) {
      if (_currentIndex >= widget.hints.length) _currentIndex = 0;
      _startTimer();
    } else if (oldWidget.duration != widget.duration) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hints.isEmpty) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: AnimatedSearchHints.transitionDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: AnimatedSearchHints.startAlignedLayout,
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
