import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/widgets/brand_splash/brand_logo_data.dart';

enum BrandSplashStage {
  waiting,
  destination,
  showRetry,
}

/// Observes a route match without rebuilding the launch overlay from inside
/// the Router's own build (its initial match can notify synchronously).
class BrandSplashRouteBuilder extends StatefulWidget {
  const BrandSplashRouteBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    required this.child,
  });

  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  State<BrandSplashRouteBuilder> createState() =>
      _BrandSplashRouteBuilderState();
}

class _BrandSplashRouteBuilderState extends State<BrandSplashRouteBuilder> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onRouteChanged);
  }

  @override
  void didUpdateWidget(BrandSplashRouteBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable == widget.listenable) return;
    oldWidget.listenable.removeListener(_onRouteChanged);
    widget.listenable.addListener(_onRouteChanged);
  }

  void _onRouteChanged() {
    if (_scheduled) return;
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    _scheduled = true;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}

class _SplashColors {
  static const background = AppColors.white;
  // The same primary colour and alpha used in the native outline PNGs.
  static const blueprint = Color(0x6B02957D);
  static const glow = Color(0x1402957D);
  static const title = Color(kBrandLogoStrapColor);
  static const tagline = AppColors.textSecondary;
  static const sheen = Color(0x6BFFFFFF);
  static const ring = Color(0x8002957D);
}

/// One continuous app opening.
///
/// Sits above the whole app. Its first frame is identical to the native
/// launch screen (flat background plus the logo outline), so the hand-off
/// from Android / iOS is invisible. It then fills the logo in, raises the
/// app name, and when [stage] is destination opens a circle from the wallet clasp
/// to reveal [child].
///
/// The gate is purely visual. It never decides where the user goes and never
/// shortens or skips any startup or session check: [child] keeps running
/// underneath, fully covered and non-interactive, until the gate opens.
class BrandSplashGate extends StatefulWidget {
  const BrandSplashGate({
    super.key,
    required this.stage,
    required this.title,
    required this.child,
    this.tagline,
  });

  final BrandSplashStage stage;
  final String title;
  final String? tagline;
  final Widget child;

  /// Side of the square the logo is drawn in, in logical pixels.
  ///
  /// Must match the native launch images: the artwork is 812 px wide in the
  /// 4x source PNGs, and 812 / 4 = 203.
  static const double logoBoxSize = 203;

  @override
  State<BrandSplashGate> createState() => _BrandSplashGateState();
}

class _BrandSplashGateState extends State<BrandSplashGate>
    with TickerProviderStateMixin {
  static const Duration _introDuration = Duration(milliseconds: 1500);
  static const Duration _exitDuration = Duration(milliseconds: 440);
  static const Duration _slowAfter = Duration(milliseconds: 2500);

  late final AnimationController _intro;
  late final AnimationController _exit;
  late final AnimationController _hint;
  late final AnimationController _wait;

  Timer? _slowTimer;
  TextPainter? _titlePainter;
  TextPainter? _taglinePainter;

  bool _reduceMotion = false;
  bool _syncScheduled = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: _introDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _scheduleSync();
      });
    _exit = AnimationController(vsync: this, duration: _exitDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dismiss();
      });
    _hint = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _wait = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(BrandSplashGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_done || oldWidget.stage == widget.stage) return;
    if (widget.stage == BrandSplashStage.waiting) _exit.reset();
    _scheduleSync();
  }

  // The router builds its accepted configuration in the same frame as the
  // overlay. Start the reveal after that frame, with no guessed frame count.
  void _scheduleSync() {
    if (_syncScheduled || _done) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted && !_done) _sync();
    });
  }

  void _sync() {
    if (widget.stage == BrandSplashStage.showRetry) {
      _dismiss();
      return;
    }
    if (_reduceMotion) {
      _intro.value = 1;
      _stopHint();
    } else if (!_intro.isCompleted && !_intro.isAnimating) {
      _intro.forward();
    }

    if (widget.stage == BrandSplashStage.destination) {
      _stopHint();
      if (_reduceMotion) {
        _dismiss();
      } else if (_intro.isCompleted && !_exit.isAnimating) {
        _exit.forward();
      }
    } else if (!_reduceMotion && _intro.isCompleted && _hint.isDismissed) {
      _slowTimer ??= Timer(_slowAfter, () {
        if (!mounted ||
            _done ||
            _reduceMotion ||
            widget.stage != BrandSplashStage.waiting) return;
        _hint.forward();
        _wait.repeat();
      });
    }
  }

  void _stopHint() {
    _slowTimer?.cancel();
    _slowTimer = null;
    _wait.stop();
    if (!_hint.isDismissed) _hint.reset();
  }

  void _dismiss() {
    if (_done) return;
    _stopHint();
    _intro.stop();
    _exit.stop();
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _intro.dispose();
    _exit.dispose();
    _hint.dispose();
    _wait.dispose();
    _titlePainter?.dispose();
    _taglinePainter?.dispose();
    super.dispose();
  }

  TextPainter _layout(
    String text,
    TextStyle style,
    TextDirection direction,
    double maxWidth,
    TextScaler textScaler,
  ) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textAlign: TextAlign.center,
      textScaler: textScaler,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
  }

  Widget _buildOverlay(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final TextDirection direction =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);

    // letterSpacing stays at 0: spacing breaks Arabic letter joins.
    final TextStyle titleStyle =
        (textTheme.titleLarge ?? const TextStyle()).copyWith(
      height: 1.4,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: _SplashColors.title,
    );
    final TextStyle taglineStyle =
        (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      height: 1.4,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: _SplashColors.tagline,
    );

    _titlePainter?.dispose();
    _taglinePainter?.dispose();
    _titlePainter = _layout(
        widget.title, titleStyle, direction, size.width - 32, textScaler);
    final String? tagline = widget.tagline;
    _taglinePainter = (tagline == null || tagline.isEmpty)
        ? null
        : _layout(
            tagline, taglineStyle, direction, size.width - 32, textScaler);

    final logoBox = math.min(
      BrandSplashGate.logoBoxSize,
      math.max(0.0, math.min(size.width - 32, size.height - 32)),
    );
    final viewPadding = MediaQuery.viewPaddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Semantics(
        container: true,
        label: [widget.title, if (tagline != null) tagline].join('\n'),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SplashPainter(
              intro: _intro,
              exit: _exit,
              hint: _hint,
              wait: _wait,
              title: _titlePainter!,
              tagline: _taglinePainter,
              logoBox: logoBox,
              centerY: size.height / 2,
              safeBottom: viewPadding.bottom,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final covered = !_done && widget.stage != BrandSplashStage.showRetry;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ExcludeSemantics(
          excluding: covered,
          child: ExcludeFocus(
            excluding: covered,
            child: IgnorePointer(ignoring: covered, child: widget.child),
          ),
        ),
        if (covered) Positioned.fill(child: _buildOverlay(context)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

const Cubic _easeDraw = Cubic(0.4, 0, 0.2, 1);
const Cubic _easeEnter = Cubic(0.2, 0, 0, 1);
const Cubic _easePop = Cubic(0.34, 1.4, 0.64, 1);
const Cubic _easeIris = Cubic(0.5, 0, 0.2, 1);

/// Progress of [t] through the window [a]..[b], clamped to 0..1.
double _p(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

Color _fade(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity);

/// Parses the path grammar used by the master icon: absolute M, L, C and Z.
Path _parseSvgPath(String data) {
  final Path path = Path();
  final RegExp token = RegExp(r'[MLCZ]|-?\d*\.?\d+');
  final List<double> n = <double>[];
  String command = '';
  for (final RegExpMatch match in token.allMatches(data)) {
    final String s = match.group(0)!;
    if (s == 'M' || s == 'L' || s == 'C') {
      command = s;
      n.clear();
      continue;
    }
    if (s == 'Z') {
      path.close();
      n.clear();
      continue;
    }
    n.add(double.parse(s));
    if (command == 'M' && n.length == 2) {
      path.moveTo(n[0], n[1]);
      n.clear();
      command = 'L';
    } else if (command == 'L' && n.length == 2) {
      path.lineTo(n[0], n[1]);
      n.clear();
    } else if (command == 'C' && n.length == 6) {
      path.cubicTo(n[0], n[1], n[2], n[3], n[4], n[5]);
      n.clear();
    }
  }
  return path;
}

ui.Gradient _logoGradient(List<double> line) {
  return ui.Gradient.linear(
    Offset(line[0], line[1]),
    Offset(line[2], line[3]),
    const <Color>[
      Color(kBrandLogoGradientStartColor),
      Color(kBrandLogoGradientEndColor),
    ],
  );
}

/// The logo shapes, parsed once.
class _LogoArt {
  _LogoArt._();

  static final List<Path> paths =
      kBrandLogoPaths.map(_parseSvgPath).toList(growable: false);
  static final ui.Gradient roofGradient =
      _logoGradient(kBrandLogoRoofGradientLine);
  static final ui.Gradient walletGradient =
      _logoGradient(kBrandLogoWalletGradientLine);

  /// Area that contains every shape, in logo units.
  static const Rect bounds = Rect.fromLTRB(140, 190, 885, 835);

  /// Lowest point of the artwork as a fraction of the box height.
  static const double bottom = 817 / 1024;

  static const Offset ridge = Offset(510, 205);
  static const Offset innerRidge = Offset(528, 300);
  static const Offset button = Offset(592.3, 675.1);
  static const List<Offset> paneCenters = <Offset>[
    Offset(485.3, 446.3),
    Offset(537.9, 446.5),
    Offset(485.2, 497.5),
    Offset(537.7, 497.4),
  ];
}

class _SplashPainter extends CustomPainter {
  _SplashPainter({
    required this.intro,
    required this.exit,
    required this.hint,
    required this.wait,
    required this.title,
    required this.tagline,
    required this.logoBox,
    required this.centerY,
    required this.safeBottom,
  }) : super(repaint: Listenable.merge(<Listenable>[intro, exit, hint, wait]));

  final Animation<double> intro;
  final Animation<double> exit;
  final Animation<double> hint;
  final Animation<double> wait;
  final TextPainter title;
  final TextPainter? tagline;
  final double logoBox;
  final double centerY;
  final double safeBottom;

  static const double _introMs = 1500;
  static const double _lift = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = intro.value * _introMs;
    final double e = exit.value;
    if (e >= 1) return;

    final double scale = logoBox / kBrandLogoViewBox;
    final textHeight = title.height + 4 + (tagline?.height ?? 0);
    final textTop = centerY + logoBox * (_LogoArt.bottom - 0.5) + 20;
    final compactLift = math.max(
      _lift,
      textTop + textHeight + 28 + safeBottom - size.height,
    );
    final double lift = compactLift * _easeEnter.transform(_p(t, 1050, 1500));
    final double left = size.width / 2 - logoBox / 2;
    final double restTop = centerY - logoBox / 2;
    final Offset origin = Offset(left, restTop - lift);
    final Offset finalOrigin = Offset(left, restTop - compactLift);

    // The circle that opens from the wallet clasp.
    final Offset irisCenter = finalOrigin + _LogoArt.button * scale;
    double irisRadius = 0;
    if (e > 0) {
      double far = 0;
      for (final Offset corner in <Offset>[
        Offset.zero,
        Offset(size.width, 0),
        Offset(0, size.height),
        Offset(size.width, size.height),
      ]) {
        far = math.max(far, (corner - irisCenter).distance);
      }
      irisRadius = (far + 2) * _easeIris.transform(e);
    }

    canvas.save();
    if (e > 0) {
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addOval(Rect.fromCircle(center: irisCenter, radius: irisRadius)),
      );
    }

    canvas.drawRect(
        Offset.zero & size, Paint()..color = _SplashColors.background);
    _paintGlow(canvas, Offset(size.width / 2, centerY - lift), t);

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    _paintLogo(canvas, t);
    canvas.restore();

    _paintText(
      canvas,
      size,
      t,
      finalOrigin.dy + logoBox * _LogoArt.bottom + 20,
    );
    canvas.restore();

    if (e > 0) {
      canvas.drawCircle(
        irisCenter,
        irisRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _fade(_SplashColors.ring, 1 - e),
      );
    }
  }

  void _paintGlow(Canvas canvas, Offset center, double t) {
    final double g = _easeDraw.transform(_p(t, 0, 700));
    if (g <= 0) return;
    const double radius = 180;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[_fade(_SplashColors.glow, g), _fade(_SplashColors.glow, 0)],
        ),
    );
  }

  Paint _fill(Color master, {ui.Gradient? gradient}) {
    final Paint paint = Paint()..isAntiAlias = true;
    if (gradient != null) {
      paint.shader = gradient;
    } else {
      paint.color = master;
    }
    return paint;
  }

  void _paintLogo(Canvas canvas, double t) {
    final List<Path> paths = _LogoArt.paths;

    // 1. Outline. This is what the native launch screen shows.
    final double outline = 1 - _p(t, 950, 1200);
    if (outline > 0) {
      final Paint line = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeJoin = StrokeJoin.round
        ..color = _fade(_SplashColors.blueprint, outline);
      for (final Path path in paths) {
        canvas.drawPath(path, line);
      }
    }

    // 2. The real shapes, with one light sweep once they are complete.
    final double sweep = _p(t, 1080, 1480);
    final bool sweeping = sweep > 0 && sweep < 1;
    if (sweeping) canvas.saveLayer(_LogoArt.bounds, Paint());
    _paintInk(canvas, t);
    if (sweeping) {
      final Color clear = _fade(_SplashColors.sheen, 0);
      canvas.save();
      canvas.translate(-100 + 1350 * _easeDraw.transform(sweep), 0);
      canvas.skew(-0.3443, 0);
      canvas.drawRect(
        const Rect.fromLTWH(0, 150, 240, 720),
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = ui.Gradient.linear(
            Offset.zero,
            const Offset(240, 0),
            <Color>[clear, _SplashColors.sheen, clear],
            const <double>[0, 0.5, 1],
          ),
      );
      canvas.restore();
      canvas.restore();
    }

    // 3. Clasp button, on top.
    final double pop = _p(t, 820, 1000);
    if (pop > 0) {
      final Paint paint = Paint()
        ..isAntiAlias = true
        ..color = AppColors.white;
      _scaledAbout(canvas, _LogoArt.button, _easePop.transform(pop), () {
        canvas.drawPath(paths[kBrandLogoButton], paint);
      });
    }
  }

  void _paintInk(Canvas canvas, double t) {
    final List<Path> paths = _LogoArt.paths;

    // Window panes: one after another.
    for (int i = 0; i < 4; i++) {
      final double start = 860 + i * 45.0;
      final double pp = _p(t, start, start + 165);
      if (pp <= 0) continue;
      final Paint paint = _fill(const Color(kBrandLogoPaneColor));
      paint.color = _fade(paint.color, math.min(1, pp / 0.6));
      _scaledAbout(
        canvas,
        _LogoArt.paneCenters[i],
        0.6 + 0.4 * _easeEnter.transform(pp),
        () => canvas.drawPath(paths[i], paint),
      );
    }

    // Inner roof lines: revealed outward from the ridge.
    final double eaves = _easeDraw.transform(_p(t, 90, 540));
    if (eaves > 0) {
      canvas.save();
      canvas.clipPath(
        Path()
          ..addOval(
            Rect.fromCircle(center: _LogoArt.innerRidge, radius: 500 * eaves),
          ),
      );
      canvas.drawPath(
        paths[kBrandLogoEaveRight],
        _fill(const Color(kBrandLogoEaveRightColor)),
      );
      canvas.drawPath(
        paths[kBrandLogoEaveLeft],
        _fill(const Color(kBrandLogoEaveLeftColor)),
      );
      canvas.restore();
    }

    // Clasp strap: wipes in from the right.
    final double strap = _easeDraw.transform(_p(t, 640, 900));
    if (strap > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(770 - 232 * strap, 590, 770, 740));
      canvas.drawPath(
        paths[kBrandLogoStrap],
        _fill(const Color(kBrandLogoStrapColor)),
      );
      canvas.restore();
    }

    // Roof and chimney: revealed outward from the ridge.
    final double roof = _easeDraw.transform(_p(t, 0, 460));
    if (roof > 0) {
      canvas.save();
      canvas.clipPath(
        Path()
          ..addOval(
              Rect.fromCircle(center: _LogoArt.ridge, radius: 520 * roof)),
      );
      canvas.drawPath(
        paths[kBrandLogoRoof],
        _fill(AppColors.primary, gradient: _LogoArt.roofGradient),
      );
      canvas.restore();
    }

    // Wallet body: wipes in from the left.
    final double wallet = _easeDraw.transform(_p(t, 330, 760));
    if (wallet > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(262, 500, 486 * wallet, 340));
      canvas.drawPath(
        paths[kBrandLogoWallet],
        _fill(AppColors.primary, gradient: _LogoArt.walletGradient),
      );
      canvas.restore();
    }
  }

  void _scaledAbout(
    Canvas canvas,
    Offset center,
    double scale,
    VoidCallback draw,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    draw();
    canvas.restore();
  }

  void _paintText(Canvas canvas, Size size, double t, double top) {
    // App name: rises into place behind a straight edge.
    final double rise = _easeEnter.transform(_p(t, 1120, 1480));
    if (rise > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, top, size.width, title.height));
      title.paint(
        canvas,
        Offset(
          (size.width - title.width) / 2,
          top + (1 - rise) * title.height,
        ),
      );
      canvas.restore();
    }

    double below = top + title.height + 4;

    final TextPainter? line = tagline;
    if (line != null) {
      final double show = _easeEnter.transform(_p(t, 1240, 1500));
      if (show > 0) {
        final Offset at = Offset(
          (size.width - line.width) / 2,
          below + 6 * (1 - show),
        );
        _withOpacity(canvas, (at & line.size).inflate(4), show, () {
          line.paint(canvas, at);
        });
      }
      below += line.height;
    }

    // Shown only when startup is slow: a small indeterminate bar.
    final double shown = hint.value;
    if (shown > 0) {
      const double width = 40;
      const double height = 3;
      const double segment = 16;
      final Rect track = Rect.fromLTWH(
        (size.width - width) / 2,
        below + 22,
        width,
        height,
      );
      final RRect pill =
          RRect.fromRectAndRadius(track, const Radius.circular(height / 2));
      canvas.drawRRect(
          pill, Paint()..color = _fade(_SplashColors.title, 0.18 * shown));
      canvas.save();
      canvas.clipRRect(pill);
      final double x = track.left - segment + (width + segment) * wait.value;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, track.top, segment, height),
          const Radius.circular(height / 2),
        ),
        Paint()..color = _fade(_SplashColors.title, 0.8 * shown),
      );
      canvas.restore();
    }
  }

  void _withOpacity(
    Canvas canvas,
    Rect bounds,
    double opacity,
    VoidCallback draw,
  ) {
    if (opacity >= 1) {
      draw();
      return;
    }
    canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    draw();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplashPainter oldDelegate) => true;
}
