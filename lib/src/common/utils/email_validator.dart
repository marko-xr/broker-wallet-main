import 'dart:convert';
import 'package:broker_wallet/src/services/app_access_policy.dart';

class EmailValidator {
  // Basic regex validation
  static bool isValidFormat(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  /// The message key for an address the user has finished typing, or null.
  ///
  /// Checked when the user leaves the field ("on blur"), never while typing:
  /// an empty field says nothing here (the form's own submit says it is
  /// required), and only the format, plus a disposable domain when
  /// [rejectDisposable], are checked. Nothing is sent anywhere.
  static String? fieldErrorKey(String email, {bool rejectDisposable = false}) {
    final value = email.trim();
    if (value.isEmpty) return null;
    if (!isValidFormat(value)) return 'emailInvalidFormat';
    if (rejectDisposable && isDisposableEmail(value)) {
      return 'emailDisposableNotAllowed';
    }
    return null;
  }

  // Check for common disposable email domains
  static bool isDisposableEmail(String email) {
    final disposableDomains = [
      '10minutemail.com',
      'tempmail.org',
      'guerrillamail.com',
      'mailinator.com',
      'yopmail.com',
      'temp-mail.org',
      // Add more disposable domains as needed
    ];

    final domain = email.split('@').last.toLowerCase();
    return disposableDomains.contains(domain);
  }

  /// The well-known providers: the ones Sign Up accepts, and the ones a
  /// likely typo is matched against.
  static const List<String> knownProviders = [
    'gmail.com',
    'yahoo.com',
    'outlook.com',
    'hotmail.com',
    'icloud.com',
    'protonmail.com',
    // Add more legitimate domains
  ];

  // Validate against common email providers
  static bool hasValidDomain(String email) {
    final domain = email.split('@').last.toLowerCase();
    return knownProviders.contains(domain);
  }

  /// The address with a likely typo in its domain corrected, or null.
  ///
  /// Only for an address whose format is already valid: its domain is
  /// compared with [knownProviders], and one at most two edits away (a
  /// letter missing, added, changed, or two letters swapped — `gail.com`,
  /// `gmial.com`, `gmail.co`) is suggested. It is a hint the user may
  /// ignore, never an error, and nothing is sent anywhere.
  static String? suggestedCorrection(String email) {
    final value = email.trim();
    if (!isValidFormat(value)) return null;
    final at = value.lastIndexOf('@');
    final local = value.substring(0, at);
    final domain = value.substring(at + 1).toLowerCase();
    if (knownProviders.contains(domain)) return null;

    String? best;
    var bestDistance = 3;
    for (final provider in knownProviders) {
      final distance = _editDistance(domain, provider);
      if (distance < bestDistance) {
        best = provider;
        bestDistance = distance;
      }
    }
    return best == null ? null : '$local@$best';
  }

  /// Edits between [a] and [b], counting two swapped neighbours as one
  /// (optimal string alignment distance).
  static int _editDistance(String a, String b) {
    final rows = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) {
      rows[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      rows[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = rows[i - 1][j] + 1;
        if (rows[i][j - 1] + 1 < best) best = rows[i][j - 1] + 1;
        if (rows[i - 1][j - 1] + cost < best) best = rows[i - 1][j - 1] + cost;
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1] &&
            rows[i - 2][j - 2] + 1 < best) {
          best = rows[i - 2][j - 2] + 1;
        }
        rows[i][j] = best;
      }
    }
    return rows[a.length][b.length];
  }

  // API-based validation (optional - requires internet)
  static Future<bool> verifyEmailExists(String email) async {
    try {
      // Using a free email validation API
      final response = await AppAccessPolicy.shared.get(
        Uri.parse('https://api.eva.pingutil.com/email?email=$email'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'success' && data['data']['deliverable'];
      }
    } catch (e) {
      // If API fails, fall back to basic validation
      return isValidFormat(email);
    }
    return false;
  }

  // Comprehensive validation
  static Future<ValidationResult> validateEmail(String email) async {
    if (!isValidFormat(email)) {
      return ValidationResult(false, 'Invalid email format');
    }

    if (isDisposableEmail(email)) {
      return ValidationResult(
          false, 'Disposable email addresses are not allowed');
    }

    if (!hasValidDomain(email)) {
      return ValidationResult(false, 'Please use a valid email provider');
    }

    // Optional: Check if email exists
    final exists = await verifyEmailExists(email);
    if (!exists) {
      return ValidationResult(false, 'Email address does not exist');
    }

    return ValidationResult(true, 'Valid email');
  }
}

class ValidationResult {
  final bool isValid;
  final String message;

  ValidationResult(this.isValid, this.message);
}
