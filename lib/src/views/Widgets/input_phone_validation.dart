import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/utils/uae_phone_input.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Fixed-prefix UAE phone field.
///
/// Always paints `[ +971 | 5X XXX XXXX ]` left to right, in Arabic and English,
/// while the surrounding screen keeps its own direction. The field shows only
/// the 9-digit national number; [value] and [onChanged] keep the established
/// local trunk form (`05XXXXXXXX`), so callers are unaffected.
class PhoneInputWidget extends StatefulWidget {
  final String countryCode;
  final String value;
  final ValueChanged<String> onChanged;
  final AppLocalizations localization;
  final String? phoneError; // Pass error from ViewModel (optional)
  final bool showError; // Control when to show error
  final bool validateInternally; // Whether to validate internally

  /// Opt-in Login/Signup styling: one [AuthInputStyle] outline painted over the
  /// existing box and the auth hint color. Off by default, so every other
  /// screen keeps its current look.
  final bool outlined;

  const PhoneInputWidget({
    Key? key,
    required this.countryCode,
    required this.value,
    required this.onChanged,
    required this.localization,
    this.phoneError,
    this.showError = false,
    this.validateInternally = true,
    this.outlined = false,
  }) : super(key: key);

  @override
  State<PhoneInputWidget> createState() => _PhoneInputWidgetState();
}

class _PhoneInputWidgetState extends State<PhoneInputWidget> {
  late TextEditingController _controller;
  String? _internalError;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _controller = TextEditingController(
      text: UaePhoneInput.displayFor(widget.value),
    );
    if (widget.validateInternally) {
      _validatePhone(widget.value);
    }
  }

  @override
  void didUpdateWidget(PhoneInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final formatted = UaePhoneInput.displayFor(widget.value);
      if (_controller.text != formatted) {
        _controller.text = formatted;
      }
      if (widget.validateInternally) {
        _validatePhone(widget.value);
      }
    }
  }

  // Only repaints the outlined border; focus behaviour itself is untouched.
  void _onFocusChanged() {
    if (widget.outlined && mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    final localPhone = UaePhoneInput.toLocalTrunk(value);
    if (widget.validateInternally) {
      _validatePhone(localPhone);
    }
    widget.onChanged(localPhone);
  }

  void _validatePhone(String phone) {
    if (!widget.validateInternally) return;
    setState(() {
      _internalError = PhoneInputService.getValidationError(
        UaePhoneInput.toLocalTrunk(UaePhoneInput.displayFor(phone)),
        widget.localization.translate,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final countryDigits = widget.countryCode.replaceAll(RegExp(r'[^0-9]'), '');

    final errorToShow =
        widget.validateInternally ? _internalError : widget.phoneError;
    final hasError = widget.showError && errorToShow != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: !widget.outlined && hasError
                ? Border.all(color: colors.error, width: 1.5)
                : null,
          ),
          foregroundDecoration: widget.outlined
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AuthInputStyle.border(
                      colors,
                      focused: _focusNode.hasFocus,
                      hasError: hasError,
                    ),
                    width: AuthInputStyle.borderWidth,
                  ),
                )
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          // Only this row is forced LTR; the screen and its label keep the
          // app direction.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                // Country Code (fixed, not editable)
                Text(
                  '+$countryDigits',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: AppTextStyles.bodyText.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                    height: 1.25, // avoid clipping
                  ),
                  strutStyle:
                      const StrutStyle(height: 1.25, forceStrutHeight: true),
                ),
                const SizedBox(width: 8),

                // Divider
                Container(
                  width: 1.2,
                  height: 32,
                  color: colors.outline.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 12),

                // Phone Input
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [UaeNationalPhoneInputFormatter()],
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: widget.localization.translate('phoneHint'),
                      hintStyle: AppTextStyles.hintText.copyWith(
                        color: widget.outlined
                            ? AuthInputStyle.hint(colors)
                            : null,
                        height: 1.3,
                      ),
                      counterText: '',
                      isCollapsed: true, // tighter, relies on container height
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: AppTextStyles.bodyText.copyWith(height: 1.3),
                    strutStyle:
                        const StrutStyle(height: 1.3, forceStrutHeight: true),
                    onChanged: _onTextChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: colors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    errorToShow,
                    style: AppTextStyles.bodyText.copyWith(
                      color: colors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                    strutStyle:
                        const StrutStyle(height: 1.25, forceStrutHeight: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
