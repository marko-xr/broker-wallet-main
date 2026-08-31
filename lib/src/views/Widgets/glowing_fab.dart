// lib/src/Views/Widgets/glowing_fab.dart
import 'package:flutter/material.dart';

class GlowingFab extends StatelessWidget {
  final VoidCallback? onPressed;

  /// Use the same tag on screens that should share the FAB hero.
  final Object heroTag;

  /// Size controls the outer FAB diameter (Flutter default is 56).
  final double size;

  /// Normal resting elevation (we only zero it during the hero flight).
  final double elevation;

  /// Icon size inside the FAB.
  final double iconSize;

  const GlowingFab({
    super.key,
    this.onPressed,
    this.heroTag = 'mainFab',
    this.size = 56,
    this.iconSize = 22,
    this.elevation = 4,
  });

  /// Shuttle used ONLY while the hero is in flight (no glow, no shadow).
  static Widget _zeroGlowShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final Hero toHero = toHeroContext.widget as Hero;
    final FloatingActionButton targetFab = toHero.child as FloatingActionButton;

    return Theme(
      data: Theme.of(flightContext).copyWith(
        shadowColor: Colors.transparent, // no drop shadow color
        splashFactory: NoSplash.splashFactory, // no ripples mid-flight
        highlightColor: Colors.transparent,
      ),
      child: Material(
        type: MaterialType.transparency, // no surface/elevation
        child: FloatingActionButton(
          heroTag: null, // never nest heroes
          onPressed: null, // inert during flight
          backgroundColor: targetFab.backgroundColor,
          foregroundColor: targetFab.foregroundColor,
          shape: targetFab.shape ?? const CircleBorder(),
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          child: targetFab.child, // keep your icon as-is
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final double inner = size - 2; // inner ring size with border

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Stationary glow/gradient UNDER the FAB (does NOT fly).
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SizedBox(
              height: 40,
              child: Center(
                child: Container(
                  width: size + 16, // subtle wider glow than the FAB
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        primary.withValues(alpha: 0.0),
                        primary.withValues(alpha: 0.25),
                        primary.withValues(alpha: 0.5),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(40),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.5),
                        blurRadius: 24,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Only the FAB participates in the Hero animation.
        Hero(
          tag: heroTag,
          flightShuttleBuilder: _zeroGlowShuttle,
          // Keep the resting look at the endpoints while in flight.
          placeholderBuilder: (context, size, child) => child,
          child: FloatingActionButton(
            heroTag:
                null, // Disable the FAB's internal Hero to avoid duplicates.
            shape: const CircleBorder(),
            onPressed: onPressed,
            backgroundColor: primary,
            elevation: elevation, // <-- you keep the glow when idle
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: inner,
                  height: inner,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                ),
                Icon(Icons.add, color: Colors.white, size: iconSize),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
