import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:flutter/material.dart';

class RtlAwareTextField extends StatelessWidget {
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int minLines;
  final bool expands;
  final bool autofocus;
  final bool obscureText;
  final bool readOnly;
  final bool forceLTR; // for phone/email/url in Arabic
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator; // for TextFormField-like usage
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;

  const RtlAwareTextField({
    super.key,
    this.controller,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines = 1,
    this.expands = false,
    this.autofocus = false,
    this.obscureText = false,
    this.readOnly = false,
    this.forceLTR = false,
    this.decoration,
    this.onChanged,
    this.validator,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final isRTL = context.isRTL;
    final align = (isRTL && !forceLTR) ? TextAlign.right : TextAlign.left;

    final field = TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      autofocus: autofocus,
      obscureText: obscureText,
      readOnly: readOnly,
      textAlign: align,
      textCapitalization: textCapitalization,
      textAlignVertical: TextAlignVertical.top,
      decoration: (decoration ?? const InputDecoration())
          .copyWith(alignLabelWithHint: true),
      onChanged: onChanged,
      validator: validator,
      focusNode: focusNode,
    );

    if (forceLTR && isRTL) {
      // e.g., Arabic UI but email/phone should stay LTR
      return ForceDirectionality(direction: TextDirection.ltr, child: field);
    }
    return field;
  }
}

class RtlAwareDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration? decoration;
  final Widget? hint;
  final FormFieldValidator<T>? validator;
  final bool isExpanded;

  const RtlAwareDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.decoration,
    this.hint,
    this.validator,
    this.isExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final isRTL = context.isRTL;
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: isExpanded,
      decoration: (decoration ?? const InputDecoration())
          .copyWith(alignLabelWithHint: true, isDense: true),
      icon: const Icon(Icons.arrow_drop_down),
      alignment: isRTL ? Alignment.centerRight : Alignment.centerLeft,
      validator: validator,
      hint: hint,
    );
  }
}
