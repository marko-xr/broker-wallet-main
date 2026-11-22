import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';

import '../../services/sms_user_consent_retriever.dart';

/// Broker Wallet's one shared six-digit code input (Pinput).
///
/// Presentation and input only. It never verifies, stores or logs a code:
/// each flow keeps its own state, single-flight rules and server-side
/// verification, and decides what happens on [onCompleted].
///
/// * Six equal cells that fit the available width (no overflow on narrow
///   screens or with large text) and grow with the text scale up to 1.6×.
/// * Neutral borders at rest; Broker Wallet green (the theme's primary) for
///   focus; distinct filled, error, disabled and verifying looks; short fades
///   only.
/// * Digits only, entered left to right in Arabic too; a pasted message keeps
///   just its digits; numeric keyboard; `oneTimeCode` autofill hint (iOS
///   keyboard suggestion, Android autofill services).
/// * Android SMS User Consent autofill when [smsAutofill] is on (no
///   permission, no app hash), accepted only while the field is enabled and
///   not verifying.
/// * [onCompleted] fires once per completed code. A code that only arrives
///   while the field is disabled or verifying never fires it.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    required this.semanticLabel,
    this.focusNode,
    this.enabled = true,
    this.verifying = false,
    this.hasError = false,
    this.errorText,
    this.autofocus = false,
    this.closeKeyboardWhenCompleted = true,
    this.smsAutofill = false,
    this.smsRetriever,
    this.onChanged,
    this.onCompleted,
  });

  /// Codes are six digits in every Broker Wallet flow.
  static const int length = 6;

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// Read by screen readers for the whole field, e.g. "Enter OTP".
  final String semanticLabel;

  final bool enabled;

  /// The flow is checking the code: input is locked and shown as such.
  final bool verifying;

  /// Error look without a message (the flow shows the message elsewhere).
  final bool hasError;

  /// Error look with this message under the cells, announced politely.
  final String? errorText;

  final bool autofocus;
  final bool closeKeyboardWhenCompleted;

  /// Listen for the code with Android's SMS User Consent while mounted.
  final bool smsAutofill;

  /// Replaces the platform retriever when [smsAutofill] is on (tests).
  final SmsRetriever? smsRetriever;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  SmsRetriever? _retriever;
  String? _lastCompleted;

  bool get _accepting => mounted && widget.enabled && !widget.verifying;

  /// The field's own focus node when the caller gives none.
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  double? _keyboardInset;
  bool _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    if (widget.smsAutofill) {
      final inner = widget.smsRetriever ??
          (SmsUserConsentRetriever.isSupported
              ? SmsUserConsentRetriever()
              : null);
      if (inner != null) {
        _retriever = GatedSmsRetriever(inner, isOpen: () => _accepting);
      }
    }
    widget.controller.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The keyboard opening (or resizing) shrinks the visible area: bring the
    // focused field back into view.
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (_keyboardInset != null && inset != _keyboardInset) _reveal();
    _keyboardInset = inset;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) _reveal();
  }

  /// Scrolls every enclosing scrollable so the whole field, with its error
  /// line, is visible — not only the cursor, which Flutter alone would show.
  /// Small phones with the keyboard open and large text otherwise show half
  /// a row of cells.
  void _reveal() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !_focus.hasFocus) return;
      // Immediate: Flutter's own cursor reveal runs in the same frame and
      // would cancel a running scroll animation.
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// Once the code is no longer complete, the next completion counts again.
  void _onText() {
    if (widget.controller.text.length < OtpCodeField.length) {
      _lastCompleted = null;
    }
    // Flutter scrolls only the cursor into view while typing; keep the whole
    // row visible instead.
    if (_focus.hasFocus) _reveal();
  }

  void _handleCompleted(String value) {
    if (!_accepting) return;
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return;
    if (_lastCompleted == value) return;
    _lastCompleted = value;
    widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final showError = widget.hasError || widget.errorText != null;
    final inputEnabled = widget.enabled && !widget.verifying;
    // The system's reduce-motion setting turns the cursor blink and fades off.
    final calm = MediaQuery.disableAnimationsOf(context);

    // Natural size; a narrower place scales the whole row down (FittedBox)
    // so the six cells stay equal and never overflow. No LayoutBuilder:
    // dialogs measure their content's intrinsic width.
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    // A little less space between cells on narrow phones keeps the cells
    // themselves larger.
    final gap = MediaQuery.sizeOf(context).width < 360 ? 6.0 : 8.0;
    const cellWidth = 46.0;
    const fontSize = 22.0;
    final cellHeight = 56.0 + fontSize * (textScale - 1);
    final radius = BorderRadius.circular(14);

    final digits = (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: colors.onSurface,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    BoxDecoration box({
      required Color border,
      double width = 1,
      Color? fill,
      List<BoxShadow>? shadow,
    }) =>
        BoxDecoration(
          color: fill ?? colors.surface,
          borderRadius: radius,
          border: Border.all(color: border, width: width),
          boxShadow: shadow,
        );

    final neutral = colors.outline.withValues(alpha: dark ? 0.55 : 0.35);
    final base = PinTheme(
      width: cellWidth,
      height: cellHeight,
      textStyle: digits,
      decoration: box(border: neutral),
    );
    final focused = base.copyWith(
      decoration: box(
        border: colors.primary,
        width: 1.8,
        shadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: dark ? 0.28 : 0.16),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
    final filled = base.copyWith(
      decoration: box(
        border: colors.primary.withValues(alpha: 0.55),
        width: 1.2,
        fill: Color.alphaBlend(
          colors.primary.withValues(alpha: dark ? 0.12 : 0.05),
          colors.surface,
        ),
      ),
    );
    final error = base.copyWith(
      decoration: box(
        border: colors.error,
        width: 1.6,
        fill: Color.alphaBlend(
          colors.error.withValues(alpha: dark ? 0.14 : 0.05),
          colors.surface,
        ),
      ),
    );
    final disabled = base.copyWith(
      textStyle: digits.copyWith(
        color:
            colors.onSurface.withValues(alpha: widget.verifying ? 0.6 : 0.38),
      ),
      decoration: box(
        border: widget.verifying
            ? colors.primary.withValues(alpha: 0.35)
            : colors.outline.withValues(alpha: 0.2),
        fill: Color.alphaBlend(
          colors.onSurface.withValues(alpha: dark ? 0.06 : 0.04),
          colors.surface,
        ),
      ),
    );

    final field = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Directionality(
        // Codes are read and typed left to right, in Arabic too.
        textDirection: TextDirection.ltr,
        child: AnimatedOpacity(
          opacity: widget.verifying ? 0.75 : 1,
          duration: calm ? Duration.zero : const Duration(milliseconds: 180),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Pinput(
              length: OtpCodeField.length,
              controller: widget.controller,
              focusNode: _focus,
              enabled: inputEnabled,
              autofocus: widget.autofocus,
              smsRetriever: _retriever,
              defaultPinTheme: base,
              focusedPinTheme: focused,
              submittedPinTheme: filled,
              followingPinTheme: base,
              disabledPinTheme: disabled,
              errorPinTheme: error,
              forceErrorState: showError,
              separatorBuilder: (_) => SizedBox(width: gap),
              mainAxisAlignment: MainAxisAlignment.center,
              pinAnimationType:
                  calm ? PinAnimationType.none : PinAnimationType.fade,
              animationDuration:
                  calm ? Duration.zero : const Duration(milliseconds: 160),
              animationCurve: Curves.easeOut,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofillHints: const [AutofillHints.oneTimeCode],
              enableSuggestions: false,
              closeKeyboardWhenCompleted: widget.closeKeyboardWhenCompleted,
              showCursor: true,
              isCursorAnimationEnabled: !calm,
              cursor: Container(
                width: 2,
                height: fontSize + 4,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              onChanged: widget.onChanged,
              onCompleted: _handleCompleted,
              onSubmitted: _handleCompleted,
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: widget.semanticLabel,
          enabled: inputEnabled,
          child: field,
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                widget.errorText!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          ),
      ],
    );
  }
}

/// Margins for the dialogs that hold an [OtpCodeField] (Add Phone, Change
/// Phone).
///
/// Flutter's dialog keeps 40 dp on each side and 24 dp inside, which on a
/// narrow phone leaves the six cells very small. Narrower phones get narrower
/// margins instead, so the cells stay readable:
///  * under 390 dp wide: 24 dp outer margins;
///  * under 360 dp wide: 16 dp outer margins and 16 dp inner padding.
/// 390 dp and wider keep Flutter's defaults (null = unchanged).
abstract final class OtpDialogSpacing {
  static double _width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static EdgeInsets? insetPadding(BuildContext context) {
    final width = _width(context);
    if (width >= 390) return null;
    return EdgeInsets.symmetric(
        horizontal: width < 360 ? 16 : 24, vertical: 24);
  }

  static EdgeInsets? titlePadding(BuildContext context) =>
      _width(context) < 360 ? const EdgeInsets.fromLTRB(16, 24, 16, 0) : null;

  static EdgeInsets? contentPadding(BuildContext context) =>
      _width(context) < 360 ? const EdgeInsets.fromLTRB(16, 16, 16, 24) : null;

  static EdgeInsets? actionsPadding(BuildContext context) =>
      _width(context) < 360 ? const EdgeInsets.fromLTRB(16, 0, 16, 24) : null;
}
