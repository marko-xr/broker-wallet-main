class PhoneUtils {
  static final RegExp _uaeMobileRegex = RegExp(r'^05\d{8}$');

  static bool isValidUaeMobile(String local) {
    final trimmed = local.trim();
    return _uaeMobileRegex.hasMatch(trimmed);
  }

  static String toE164Uae(String local) {
    final trimmed = local.trim();
    if (!_uaeMobileRegex.hasMatch(trimmed)) {
      throw ArgumentError('Invalid UAE mobile number: $local');
    }
    return '+971${trimmed.substring(1)}';
  }

  static String normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }
}
