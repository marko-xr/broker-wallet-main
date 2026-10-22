import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Parsing and formatting for the fixed-prefix UAE phone field.
///
/// The field shows only the 9-digit national significant number
/// (`5X XXX XXXX`) beside a fixed `+971`. The rest of the app still exchanges
/// the established local trunk form `05XXXXXXXX`, which
/// [UaePhoneInput.toLocalTrunk] produces, so authentication, OTP, profile
/// verification and entity saving keep receiving the formats they expect.
class UaePhoneInput {
  UaePhoneInput._();

  /// Digits of the national significant number, without the trunk zero.
  static const int nationalLength = 9;

  /// Replaces Arabic-Indic (U+0660..0669) and Eastern Arabic-Indic
  /// (U+06F0..06F9) digits with ASCII digits.
  static String toAsciiDigits(String input) {
    final out = StringBuffer();
    for (final unit in input.runes) {
      if (unit >= 0x0660 && unit <= 0x0669) {
        out.writeCharCode(0x30 + unit - 0x0660);
      } else if (unit >= 0x06F0 && unit <= 0x06F9) {
        out.writeCharCode(0x30 + unit - 0x06F0);
      } else {
        out.writeCharCode(unit);
      }
    }
    return out.toString();
  }

  static String _onlyDigits(String input) =>
      toAsciiDigits(input).replaceAll(RegExp(r'[^0-9]'), '');

  /// National digits of a UAE number written in any common form:
  /// `501234567`, `0501234567`, `+971501234567`, `971501234567`,
  /// `00971501234567`, `+9710501234567`, with spaces, hyphens or non-ASCII
  /// digits. Returns null when the text is explicitly another country's number
  /// (an unsupported prefix), so the caller can refuse it instead of mangling
  /// it. The result is not length-limited.
  static String? nationalDigits(String raw) {
    final cleaned = toAsciiDigits(raw).replaceAll(RegExp(r'[^0-9+]'), '');
    var digits = cleaned.replaceAll('+', '');
    final international = cleaned.contains('+') || digits.startsWith('00');
    if (international) {
      if (digits.startsWith('00')) digits = digits.substring(2);
      if (!digits.startsWith('971')) return null;
      digits = digits.substring(3);
    } else if (digits.length >= 3 && digits.startsWith('971')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  /// `5X XXX XXXX` grouping of [national] digits (spaces after 2 and 5).
  static String formatNational(String national) {
    final out = StringBuffer();
    for (var i = 0; i < national.length; i++) {
      if (i == 2 || i == 5) out.write(' ');
      out.write(national[i]);
    }
    return out.toString();
  }

  /// The text the field should display for a value held by the app.
  static String displayFor(String value) {
    if (value.trim().isEmpty) return '';
    final national = nationalDigits(value) ?? _onlyDigits(value);
    return formatNational(national);
  }

  /// The value handed back to the app: `05XXXXXXXX` (or its partial prefix),
  /// or an empty string when nothing has been entered.
  static String toLocalTrunk(String displayText) {
    final national = _onlyDigits(displayText);
    return national.isEmpty ? '' : '0$national';
  }
}

/// Keeps the editable text as a grouped national number and accepts pasted
/// UAE numbers in any common format.
///
/// A pasted full number is normalized rather than rejected for its `+`,
/// leading `00`, `971` or trunk zero. Input that would exceed the national
/// length, or an explicit non-UAE prefix, is refused whole: nothing is ever
/// truncated into a different valid-looking number.
class UaeNationalPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final oldText = oldValue.text;
    final caret = newValue.selection.isValid
        ? math.min(math.max(newValue.selection.extentOffset, 0), text.length)
        : text.length;

    // Split the new text into the untouched head, the inserted run and the
    // untouched tail, so a paste into the middle is normalized on its own.
    var head = '';
    var inserted = text;
    var tail = '';
    final candidateTail = text.substring(caret);
    if (oldText.endsWith(candidateTail)) {
      final maxHead = math.min(caret, oldText.length - candidateTail.length);
      var p = 0;
      while (p < maxHead && oldText[p] == text[p]) {
        p++;
      }
      head = text.substring(0, p);
      inserted = text.substring(p, caret);
      tail = candidateTail;
    }

    final headDigits = UaePhoneInput._onlyDigits(head);
    final tailDigits = UaePhoneInput._onlyDigits(tail);

    String insertedDigits;
    if (inserted.isEmpty) {
      insertedDigits = '';
    } else if (headDigits.isEmpty || inserted.contains('+')) {
      final national = UaePhoneInput.nationalDigits(inserted);
      if (national == null) return oldValue;
      insertedDigits = national;
    } else {
      insertedDigits = UaePhoneInput._onlyDigits(inserted);
    }

    final total = '$headDigits$insertedDigits$tailDigits';
    final oldCount = UaePhoneInput._onlyDigits(oldText).length;
    if (total.length > math.max(UaePhoneInput.nationalLength, oldCount)) {
      return oldValue;
    }

    final formatted = UaePhoneInput.formatNational(total);
    final digitsBeforeCaret = headDigits.length + insertedDigits.length;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _offsetAfterDigits(formatted, digitsBeforeCaret),
      ),
      composing: TextRange.empty,
    );
  }

  static int _offsetAfterDigits(String formatted, int digits) {
    if (digits <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (formatted[i] != ' ') {
        seen++;
        if (seen == digits) return i + 1;
      }
    }
    return formatted.length;
  }
}
