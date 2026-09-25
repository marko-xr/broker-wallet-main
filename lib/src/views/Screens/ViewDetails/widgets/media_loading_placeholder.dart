import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// The single loading treatment for a detail screen's media area.
///
/// Loading an Offer's photo is one continuous operation from the user's point
/// of view, but it has two distinct stages underneath: resolving a short-lived
/// signed URL, then fetching the bytes behind it. Each stage used to draw its
/// own `CircularProgressIndicator` — a 28px one in the header while the URL
/// resolved, then a 24px one inside the gallery while the bytes arrived — so a
/// first open showed two different spinners in the same box, one after the
/// other.
///
/// Using this one widget for both stages makes the hand-over invisible: the
/// same surface stays on screen from the moment the screen opens until the
/// photo fades in over it. A shimmering block also reads as "a picture is
/// coming here", which a spinner does not.
///
/// It draws only from [ColorScheme] tokens, and it honours the platform's
/// reduce-motion setting by falling back to a still surface.
class MediaLoadingPlaceholder extends StatefulWidget {
  const MediaLoadingPlaceholder({super.key});

  @override
  State<MediaLoadingPlaceholder> createState() =>
      _MediaLoadingPlaceholderState();
}

class _MediaLoadingPlaceholderState extends State<MediaLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 1400);

  /// Shared by every instance so two of them are always in phase.
  ///
  /// The header's surface and the gallery's surface are two separate mounts of
  /// this widget, and the gallery replaces the header the moment media
  /// resolves. Driving the sweep from a per-instance controller would restart
  /// it at that moment — a visible stutter at exactly the hand-over this
  /// widget exists to hide. Reading the phase from one clock means the
  /// replacement picks up mid-sweep, exactly where the previous one was.
  static final Stopwatch _clock = Stopwatch()..start();

  /// Only schedules frames; the phase itself comes from [_clock].
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _period,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState so a change to the platform's
    // animation setting is honoured while this widget is alive.
    _applyMotionPreference(
      MediaQuery.maybeOf(context)?.disableAnimations ?? false,
    );
  }

  /// Starts or stops the frame pump to match the accessibility setting.
  ///
  /// A running [AnimationController] schedules a frame callback every vsync
  /// whether or not anything listens to it, so leaving it running under
  /// reduce motion would keep waking the engine for an animation nobody is
  /// shown.
  void _applyMotionPreference(bool reduceMotion) {
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      if (_sweep.isAnimating) _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = colors.surfaceContainerHighest;
    // Derived from the same tokens rather than introduced as a new colour, so
    // the sweep stays correct in both themes.
    final highlight = Color.alphaBlend(
      colors.surface.withValues(alpha: 0.55),
      base,
    );
    final reduceMotion = _reduceMotion;

    final mark = Center(
      child: Icon(
        Icons.image_outlined,
        size: 44,
        color: colors.onSurfaceVariant.withValues(alpha: 0.28),
      ),
    );

    // The screen reader still hears a loading state even though nothing spins.
    return Semantics(
      label: AppLocalizations.of(context).translate('loading'),
      liveRegion: true,
      child: reduceMotion
          ? ColoredBox(color: base, child: mark)
          : AnimatedBuilder(
              animation: _sweep,
              builder: (context, child) {
                // Slides a soft highlight band from one edge to the other.
                final phase =
                    (_clock.elapsedMilliseconds % _period.inMilliseconds) /
                        _period.inMilliseconds;
                final offset = -1.5 + 3.0 * phase;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(offset - 0.6, -0.4),
                      end: Alignment(offset + 0.6, 0.4),
                      colors: [base, highlight, base],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: child,
                );
              },
              child: SizedBox.expand(child: mark),
            ),
    );
  }
}
