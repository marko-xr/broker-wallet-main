import 'dart:async';

import 'package:flutter/material.dart';

/// Builds [child] once the route this widget is in has finished sliding in, and
/// shows [placeholder] until then.
///
/// A heavy native view (the Google map) that is created while its page is still
/// animating makes the animation stutter: the phone's main thread is busy
/// building the view just when the animation needs it for the next frame. So the
/// page slides in with [placeholder], at full smoothness, and the view is made
/// the moment the page is in place, where a short pause is not seen.
///
/// [maxWait] bounds the wait, so [child] always appears even when the route's
/// animation never reports that it finished. A widget that is not in a route, or
/// is in one that opened without a transition, builds [child] at once.
///
/// It draws nothing of its own and reads nothing: its inputs are plain widgets.
class AfterRouteTransition extends StatefulWidget {
  const AfterRouteTransition({
    super.key,
    required this.child,
    this.placeholder = const SizedBox.shrink(),
    this.maxWait = const Duration(milliseconds: 1200),
  });

  /// What to show once the route is in place.
  final Widget child;

  /// What to show while the route slides in.
  final Widget placeholder;

  /// The longest to wait for the route to be in place.
  final Duration maxWait;

  @override
  State<AfterRouteTransition> createState() => _AfterRouteTransitionState();
}

class _AfterRouteTransitionState extends State<AfterRouteTransition> {
  Animation<double>? _watching;
  Timer? _giveUp;
  bool _looked = false;
  bool _arrived = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrived) return;

    final animation = ModalRoute.of(context)?.animation;
    // The route's other changes (a page pushed over it) call this again.
    if (_looked && identical(animation, _watching)) return;
    _looked = true;

    _watching?.removeStatusListener(_onStatus);
    _watching = animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _arrived = true;
      return;
    }
    animation.addStatusListener(_onStatus);
    _giveUp ??= Timer(widget.maxWait, _arrive);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _arrive();
  }

  void _arrive() {
    if (_arrived || !mounted) return;
    _stopWaiting();
    setState(() => _arrived = true);
  }

  void _stopWaiting() {
    _watching?.removeStatusListener(_onStatus);
    _giveUp?.cancel();
    _giveUp = null;
  }

  @override
  void dispose() {
    _stopWaiting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _arrived ? widget.child : widget.placeholder;
  }
}

/// A plain sheet of [color] laid over the map while it opens, that fades away
/// once the map exists.
///
/// A native map draws its first frames before there is anything to see in them
/// (an empty or dark sheet, then the tiles). Seen straight away, that is a flash
/// on a page that was calm a moment ago. The sheet is the page's own colour, so
/// until the map is ready the page looks as it always did, and then it lets the
/// map through over [duration] instead of the map appearing all at once.
///
/// It takes no touches: the map and the controls over it work throughout.
/// [maxWait] bounds how long it can stay, so a map that never reports it exists
/// is never hidden for good.
class MapRevealCover extends StatefulWidget {
  const MapRevealCover({
    super.key,
    required this.revealed,
    required this.color,
    this.duration = const Duration(milliseconds: 300),
    this.maxWait = const Duration(seconds: 4),
  });

  /// Whether the map is ready to be seen.
  final bool revealed;

  /// The page's own colour, so the sheet cannot be told from the page.
  final Color color;

  /// How long the sheet takes to fade away.
  final Duration duration;

  /// The longest the sheet stays when [revealed] never turns true.
  final Duration maxWait;

  @override
  State<MapRevealCover> createState() => _MapRevealCoverState();
}

class _MapRevealCoverState extends State<MapRevealCover> {
  Timer? _giveUp;

  /// The sheet is (still) laid over the map.
  bool _covering = true;

  /// The sheet has faded away completely and is not built any more.
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    if (widget.revealed) {
      _covering = false;
      _gone = true;
    } else {
      _giveUp = Timer(widget.maxWait, _giveUpWaiting);
    }
  }

  @override
  void didUpdateWidget(covariant MapRevealCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed && _covering) {
      _stopWaiting();
      _covering = false;
    }
  }

  void _giveUpWaiting() {
    _giveUp = null;
    if (_covering && mounted) setState(() => _covering = false);
  }

  void _stopWaiting() {
    _giveUp?.cancel();
    _giveUp = null;
  }

  @override
  void dispose() {
    _stopWaiting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _covering ? 1 : 0,
        duration: widget.duration,
        curve: Curves.easeOut,
        onEnd: () {
          if (!_covering && mounted) setState(() => _gone = true);
        },
        child: SizedBox.expand(child: ColoredBox(color: widget.color)),
      ),
    );
  }
}
