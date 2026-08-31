import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

// Enforce LTR for phone/email/ID fields in Arabic UI (safe, minimal change).
class PhoneInputWidget extends StatefulWidget {
  final String countryCode;
  final String value;
  final ValueChanged<String> onChanged;
  final AppLocalizations localization;
  final String? phoneError; // Pass error from ViewModel (optional)
  final bool showError; // Control when to show error
  final bool validateInternally; // Whether to validate internally

  const PhoneInputWidget({
    Key? key,
    required this.countryCode,
    required this.value,
    required this.onChanged,
    required this.localization,
    this.phoneError,
    this.showError = false,
    this.validateInternally = true,
  }) : super(key: key);

  @override
  State<PhoneInputWidget> createState() => _PhoneInputWidgetState();
}

class _PhoneInputWidgetState extends State<PhoneInputWidget> {
  late TextEditingController _controller;
  String? _internalError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value.isNotEmpty
          ? PhoneInputService.formatPhoneNumber(widget.value)
          : '',
    );
    if (widget.validateInternally) {
      _validatePhone(widget.value);
    }
  }

  @override
  void didUpdateWidget(PhoneInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final formatted = widget.value.isNotEmpty
          ? PhoneInputService.formatPhoneNumber(widget.value)
          : '';
      if (_controller.text != formatted) {
        _controller.text = formatted;
      }
      if (widget.validateInternally) {
        _validatePhone(widget.value);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    final cleanPhone = PhoneInputService.getCleanPhoneNumber(value);
    if (widget.validateInternally) {
      _validatePhone(cleanPhone);
    }
    widget.onChanged(cleanPhone);
  }

  void _validatePhone(String phone) {
    if (!widget.validateInternally) return;
    setState(() {
      _internalError = PhoneInputService.getValidationError(
        phone,
        widget.localization.translate,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

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
            border:
                hasError ? Border.all(color: colors.error, width: 1.5) : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // UAE Flag
              SizedBox(
                width: 25,
                height: 25,
                child: SvgPicture.asset(
                  SvgIcon.flagArab,
                  width: 25,
                  height: 25,
                ),
              ),
              const SizedBox(width: 8),

              // Country Code
              Text(
                "(${widget.countryCode})",
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
                child: ForceDirectionality(
                  direction: TextDirection.ltr, // digits flow LTR
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [UAEPhoneInputFormatter()],
                    // IMPORTANT:
                    // In RTL screens we right-align the LTR field so the hint/caret
                    // sits next to the divider; in LTR screens we keep standard left align.
                    textAlign: isRTL ? TextAlign.end : TextAlign.start,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: widget.localization.translate('phoneHint'),
                      hintStyle: AppTextStyles.hintText.copyWith(height: 1.3),
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
              ),
            ],
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
