// phone_input_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneInputService {
  static const int UAE_PHONE_LENGTH = 10; // local digits without leading 0
  static const String UAE_COUNTRY_CODE = '+971';

  static const List<String> UAE_MOBILE_PREFIXES = [
    '50',
    '52',
    '54',
    '55',
    '56',
    '58'
  ];

  // ---------- Validation / Basic helpers ----------

  /// Return only digits from the input (no plus).
  static String getCleanPhoneNumber(String formattedPhone) =>
      formattedPhone.replaceAll(RegExp(r'[^\d]'), '');

  /// Return digits+plus cleaned (keeps pluses if present then normalized outside).
  static String _keepDigitsAndPlus(String input) =>
      input.replaceAll(RegExp(r'[^\d+]'), '');

  /// Normalize input to an international string with + at start when possible.
  /// Tries UAE rules first, then falls back to adding + before digits.
  static String normalizeToInternational(String input) {
    if (input.isEmpty) return '';

    // Remove all non-digit and '+' chars
    var cleanedWithPlus = _keepDigitsAndPlus(input);

    // Remove all plus signs then re-add a single one at the start when appropriate
    final digitsOnly = cleanedWithPlus.replaceAll('+', '');

    // If digitsOnly is empty return empty
    if (digitsOnly.isEmpty) return '';

    // Handle common UAE cases:
    // - If user typed 05xxxxxxxx (10 digits) -> +9715xxxxxxxx (drop leading 0)
    // - If user typed 9715xxxxxxxx -> +9715xxxxxxxx
    // - If user typed +971... -> ensure single leading +
    if (digitsOnly.length == UAE_PHONE_LENGTH && digitsOnly.startsWith('0')) {
      // local format: 0XXXXXXXXX (10 digits) -> +971 + drop 0
      return '$UAE_COUNTRY_CODE${digitsOnly.substring(1)}';
    }

    if (digitsOnly.length == 12 && digitsOnly.startsWith('971')) {
      return '+$digitsOnly';
    }

    // If original had a plus anywhere, treat as international and prefix + to digits
    if (cleanedWithPlus.contains('+')) {
      return '+$digitsOnly';
    }

    // Generic fallback: if length looks like country-code + rest (>=8), prefix +
    // We'll prefix + by default to give consistent display & dialing behaviour
    return '+$digitsOnly';
  }

  // ---------- Display / Dialing helpers ----------

  /// Format number for display in UI.
  /// Ensures + is at start, applies UAE pretty grouping if detected.
  /// Prepends an LRM (left-to-right mark) so the phone renders correctly in RTL locales.
  static String formatForDisplay(String phone) {
    if (phone.isEmpty) return '';

    final intl = normalizeToInternational(phone);

    String formatted;

    // If UAE
    if (intl.startsWith(UAE_COUNTRY_CODE)) {
      final rest = intl.substring(UAE_COUNTRY_CODE.length); // digits after +971
      if (rest.isEmpty)
        formatted = UAE_COUNTRY_CODE;
      else if (rest.length >= 9) {
        final p1 = rest.substring(0, 2);
        final p2 = rest.substring(2, 5);
        final p3 = rest.substring(5);
        formatted = '$UAE_COUNTRY_CODE $p1 $p2 $p3'.trim();
      } else {
        formatted = '$UAE_COUNTRY_CODE ${_groupDigits(rest)}'.trim();
      }
    } else {
      // Generic: split into country code (1-3 digits) + rest grouped
      final m = RegExp(r'^\+(\d{1,3})(\d*)$').firstMatch(intl);
      if (m != null) {
        final cc = m.group(1)!;
        final rest = m.group(2) ?? '';
        formatted = rest.isEmpty ? '+$cc' : '+$cc ${_groupDigits(rest)}';
      } else {
        // Fallback (should not happen)
        formatted = intl;
      }
    }

    // Prepend Left-to-Right Mark so this piece renders LTR even inside RTL paragraphs.
    // Using '\u200E' is safe and invisible.
    return '\u200E$formatted';
  }

  /// Format number for dialing URIs (tel: and whatsapp) — returns +<digits> with NO spaces
  static String formatForDial(String phone) {
    if (phone.isEmpty) return '';
    final intl = normalizeToInternational(phone);
    return intl.replaceAll(RegExp(r'\s+'), '');
  }

  // ---------- Your existing validation & formatting preserved/improved ----------

  static bool isValidUAEPhoneNumber(String phone) {
    final digitsOnly = getCleanPhoneNumber(phone);
    if (digitsOnly.length != UAE_PHONE_LENGTH) return false;
    if (!digitsOnly.startsWith('0')) return false;
    if (digitsOnly.length < 3) return false;
    final prefix = digitsOnly.substring(1, 3);
    return UAE_MOBILE_PREFIXES.contains(prefix);
  }

  /// Formats as: 0XX XXX XXXX (spaces at positions 3 and 6) for the local 10-digit input
  static String formatPhoneNumber(String phone) {
    final digitsOnly = getCleanPhoneNumber(phone);
    if (digitsOnly.isEmpty) return '';

    final buf = StringBuffer();
    for (int i = 0; i < digitsOnly.length && i < UAE_PHONE_LENGTH; i++) {
      if (i == 3 || i == 6) buf.write(' ');
      buf.write(digitsOnly[i]);
    }
    return buf.toString();
  }

  /// Original toInternationalFormat improved: always returns +... if it can convert
  static String toInternationalFormat(String phone) {
    return normalizeToInternational(phone);
  }

  static String? getValidationError(String phone, String Function(String) t) {
    final clean = getCleanPhoneNumber(phone);
    if (clean.isEmpty) return null;
    if (clean.length < 10) return t('phoneNumberTooShort');
    if (clean.length > 10 && !(clean.length == 12 && clean.startsWith('971'))) {
      // allow 12-digit 971... international local digits
      return t('phoneNumberTooLong');
    }
    if (!clean.startsWith('05')) return t('phoneNumberMustStartWith05');
    final prefix = clean.substring(1, 3);
    if (!UAE_MOBILE_PREFIXES.contains(prefix))
      return t('invalidUAEPhoneNumber');
    return null;
  }

  // ---------- Utility grouping ----------

  /// Helper - group digits into chunks of up to 3 separated by single spaces
  static String _groupDigits(String digits) {
    if (digits.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i += 3) {
      if (i != 0) buffer.write(' ');
      final end = (i + 3 < digits.length) ? i + 3 : digits.length;
      buffer.write(digits.substring(i, end));
    }
    return buffer.toString();
  }
}

/// Caret-preserving UAE phone formatter (unchanged logic — kept for textfields)
class UAEPhoneInputFormatter extends TextInputFormatter {
  int _digitsBeforeOffset(String text, int offset) {
    if (offset <= 0) return 0;
    final left = text.characters.take(offset).toString();
    return RegExp(r'\d').allMatches(left).length;
  }

  int _formattedOffsetForDigits(String formatted, int digitsCount) {
    if (digitsCount <= 0) return 0;
    int seen = 0;
    for (int i = 0; i < formatted.length; i++) {
      final ch = formatted[i];
      if (RegExp(r'\d').hasMatch(ch)) {
        seen++;
        if (seen == digitsCount) {
          return i + 1;
        }
      }
    }
    return formatted.length;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newDigits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    final limited = newDigits.length > PhoneInputService.UAE_PHONE_LENGTH
        ? newDigits.substring(0, PhoneInputService.UAE_PHONE_LENGTH)
        : newDigits;

    final digitsBeforeCaret =
        _digitsBeforeOffset(newValue.text, newValue.selection.extentOffset);

    final formatted = PhoneInputService.formatPhoneNumber(limited);

    final targetOffset =
        _formattedOffsetForDigits(formatted, digitsBeforeCaret);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: targetOffset),
      composing: TextRange.empty,
    );
  }
}
