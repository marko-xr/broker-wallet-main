import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';

/// Instagram-style favorite button with optimistic updates and smooth animations
class OptimizedFavoriteButton extends StatefulWidget {
  final bool isFavorite;
  final bool isLoading;
  final VoidCallback? onToggle;
  final double size;
  final Color? activeColor;
  final Color? inactiveColor;
  final bool showBackground;
  final EdgeInsets? padding;

  const OptimizedFavoriteButton({
    super.key,
    required this.isFavorite,
    this.isLoading = false,
    this.onToggle,
    this.size = 24.0,
    this.activeColor,
    this.inactiveColor,
    this.showBackground = false,
    this.padding,
  });

  @override
  State<OptimizedFavoriteButton> createState() =>
      _OptimizedFavoriteButtonState();
}

class _OptimizedFavoriteButtonState extends State<OptimizedFavoriteButton>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _isAnimating = false;
  DateTime? _lastTapTime;
  static const Duration _debounceTime = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.7,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.onToggle == null || _isAnimating) return;

    // Debounce rapid taps
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!) < _debounceTime) {
      return;
    }
    _lastTapTime = now;

    // Haptic feedback
    HapticFeedback.lightImpact();

    // Start animation
    setState(() {
      _isAnimating = true;
    });

    // Instagram-style animation sequence
    await _animateToggle();

    // Call the toggle callback
    widget.onToggle?.call();

    // Reset animation state
    if (mounted) {
      setState(() {
        _isAnimating = false;
      });
    }
  }

  Future<void> _animateToggle() async {
    if (widget.isFavorite) {
      // Unlike animation: quick scale down
      await _scaleController.forward();
      await _scaleController.reverse();
    } else {
      // Like animation: scale down, then bounce up
      await _scaleController.forward();
      await _scaleController.reverse();

      // Bounce effect for "like"
      await _scaleController.animateTo(0.3);
      await _scaleController.animateTo(1.1);
      await _scaleController.animateTo(1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeColor = widget.activeColor ?? colors.primary;
    final inactiveColor = widget.inactiveColor ?? colors.onSurface;

    Widget iconWidget = AnimatedBuilder(
      animation: Listenable.merge([_scaleController, _fadeController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: SvgPicture.asset(
                widget.isFavorite
                    ? SvgIcon.markedFavorite
                    : SvgIcon.unmarkedFavorite,
                key: ValueKey(widget.isFavorite),
                width: widget.size,
                height: widget.size,
                colorFilter: ColorFilter.mode(
                  widget.isFavorite ? activeColor : inactiveColor,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        );
      },
    );

    // Add background if requested
    if (widget.showBackground) {
      iconWidget = Container(
        padding: widget.padding ?? const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.15),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: iconWidget,
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: widget.padding,
          child: iconWidget,
        ),
      ),
    );
  }
}

/// Selector widget for isolating favorite button rebuilds
class FavoriteButtonSelector<T> extends StatelessWidget {
  final T Function() selector;
  final Widget Function(BuildContext, T, Widget?) builder;
  final Widget? child;

  const FavoriteButtonSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: _SelectorNotifier(selector),
      builder: builder,
      child: child,
    );
  }
}

class _SelectorNotifier<T> extends ValueNotifier<T> {
  final T Function() _selector;

  _SelectorNotifier(this._selector) : super(_selector());

  void update() {
    value = _selector();
  }
}
