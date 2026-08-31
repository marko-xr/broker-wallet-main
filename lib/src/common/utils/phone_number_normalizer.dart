/// Canonical phone normalization used by every Supabase write path.
///
/// The returned value is always E.164 (`+` followed by 7-15 digits). Raw
/// values remain in the entity's `phone_number` column for display purposes.
class PhoneNumberNormalizer {
  PhoneNumberNormalizer._();

  static final RegExp _e164 = RegExp(r'^\+[1-9][0-9]{6,14}$');

  static String normalize({
    required String phoneNumber,
    String? countryCode,
  }) {
    final raw = phoneNumber.trim();
    if (raw.isEmpty) {
      throw const PhoneValidationException('Please enter a phone number.');
    }

    final compact = raw.replaceAll(RegExp(r'[\s()\-\.]'), '');
    if (compact.startsWith('+')) {
      var internationalDigits =
          compact.substring(1).replaceAll(RegExp(r'\D'), '');
      final suppliedCode = (countryCode ?? '').replaceAll(RegExp(r'\D'), '');

      // Some legacy UI paths supplied an international-looking value while
      // retaining the national trunk prefix (for example +971055...). Repair
      // that representation before E.164 validation, without double-prefixing
      // genuinely international input.
      if (suppliedCode.isNotEmpty &&
          internationalDigits.startsWith('${suppliedCode}0')) {
        internationalDigits =
            '$suppliedCode${internationalDigits.substring(suppliedCode.length + 1)}';
      }
      return _validate('+$internationalDigits');
    }

    var localDigits = compact.replaceAll(RegExp(r'\D'), '');
    if (localDigits.isEmpty) {
      throw const PhoneValidationException(
          'Please enter a valid phone number.');
    }

    var codeDigits = (countryCode ?? '').replaceAll(RegExp(r'\D'), '');
    if (codeDigits.isEmpty) {
      // Backwards-compatible handling for persisted international numbers
      // that lost their plus during formatting.
      if (localDigits.startsWith('971') && localDigits.length == 12) {
        return _validate('+$localDigits');
      }
      codeDigits = '971';
    }

    if (localDigits.startsWith(codeDigits)) {
      return _validate('+$localDigits');
    }

    // National trunk prefixes are not part of E.164. This is required for
    // UAE input such as +971 / 055 288 5142 and is also safe for country-code
    // plus national-number inputs elsewhere.
    if (localDigits.startsWith('0')) {
      localDigits = localDigits.substring(1);
    }

    return _validate('+$codeDigits$localDigits');
  }

  static String? normalizeOptional({
    required String? phoneNumber,
    String? countryCode,
  }) {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) return null;
    return normalize(phoneNumber: phoneNumber, countryCode: countryCode);
  }

  static bool isValidE164(String value) => _e164.hasMatch(value);

  static String _validate(String value) {
    if (!_e164.hasMatch(value)) {
      throw const PhoneValidationException(
        'Please enter a valid international phone number.',
      );
    }
    return value;
  }
}

class PhoneValidationException implements FormatException {
  const PhoneValidationException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  dynamic get source => null;

  @override
  String toString() => message;
}
