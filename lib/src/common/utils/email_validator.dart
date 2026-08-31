import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailValidator {
  // Basic regex validation
  static bool isValidFormat(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
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

  // Validate against common email providers
  static bool hasValidDomain(String email) {
    final validDomains = [
      'gmail.com',
      'yahoo.com',
      'outlook.com',
      'hotmail.com',
      'icloud.com',
      'protonmail.com',
      // Add more legitimate domains
    ];

    final domain = email.split('@').last.toLowerCase();
    return validDomains.contains(domain);
  }

  // API-based validation (optional - requires internet)
  static Future<bool> verifyEmailExists(String email) async {
    try {
      // Using a free email validation API
      final response = await http.get(
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
