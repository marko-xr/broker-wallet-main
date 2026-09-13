/// The single password policy for Broker Wallet.
///
/// Sign-up, Change Password and Reset Password all validate through this class
/// so a password that one surface accepts can never be rejected by another.
///
/// The rules are deliberately the ones Sign-up already enforced — eight
/// characters with an upper-case letter, a lower-case letter and a digit — so
/// adopting this policy changes no existing account's ability to sign in and
/// changes no existing Sign-up outcome. Supabase's own guidance is a minimum
/// of eight characters plus configurable character classes, which this meets.
///
/// The maximum is not a style choice: GoTrue hashes passwords with bcrypt,
/// which ignores everything past 72 bytes. Accepting a longer password would
/// silently store a truncated secret, so it is refused here instead.
///
/// This class is pure. It performs no I/O, holds no state and never logs: the
/// password value is read, measured and discarded.
abstract final class PasswordPolicy {
  /// Supabase's recommended minimum, and this project's canonical value.
  static const int minLength = 8;

  /// bcrypt's effective input limit. Measured in UTF-8 bytes, not characters.
  static const int maxLengthBytes = 72;

  /// Every requirement the policy can report, in display order.
  static const List<PasswordRequirement> requirements = [
    PasswordRequirement.minLength,
    PasswordRequirement.lowercase,
    PasswordRequirement.uppercase,
    PasswordRequirement.digit,
  ];

  /// Requirements [password] does **not** yet meet, in display order.
  ///
  /// An empty password reports every requirement as unmet rather than being
  /// treated as a separate state, so a freshly opened form can render the same
  /// checklist it will keep updating as the user types.
  static Set<PasswordRequirement> unmetRequirements(String password) {
    return {
      for (final requirement in requirements)
        if (!_isMet(requirement, password)) requirement,
    };
  }

  static bool _isMet(PasswordRequirement requirement, String password) {
    switch (requirement) {
      case PasswordRequirement.minLength:
        return password.length >= minLength;
      case PasswordRequirement.lowercase:
        return password.contains(RegExp(r'[a-z]'));
      case PasswordRequirement.uppercase:
        return password.contains(RegExp(r'[A-Z]'));
      case PasswordRequirement.digit:
        return password.contains(RegExp(r'[0-9]'));
    }
  }

  /// Validates [password] on its own, without a confirmation field.
  static PasswordValidation validate(String password) {
    if (password.isEmpty) {
      return const PasswordValidation._(PasswordViolation.empty);
    }
    if (_utf8Length(password) > maxLengthBytes) {
      return const PasswordValidation._(PasswordViolation.tooLong);
    }
    if (unmetRequirements(password).isNotEmpty) {
      return const PasswordValidation._(PasswordViolation.requirementsUnmet);
    }
    return const PasswordValidation._(null);
  }

  /// Validates a new password together with its confirmation.
  ///
  /// The confirmation is only checked once the password itself is valid, so a
  /// user who is still typing is told what the password needs rather than that
  /// two incomplete values differ.
  static PasswordValidation validatePair({
    required String password,
    required String confirmation,
  }) {
    final result = validate(password);
    if (!result.isValid) return result;
    if (confirmation.isEmpty) {
      return const PasswordValidation._(PasswordViolation.confirmationEmpty);
    }
    if (password != confirmation) {
      return const PasswordValidation._(PasswordViolation.mismatch);
    }
    return const PasswordValidation._(null);
  }

  /// UTF-8 byte length without importing `dart:convert` for a single measure.
  static int _utf8Length(String value) {
    var length = 0;
    for (final rune in value.runes) {
      if (rune <= 0x7F) {
        length += 1;
      } else if (rune <= 0x7FF) {
        length += 2;
      } else if (rune <= 0xFFFF) {
        length += 3;
      } else {
        length += 4;
      }
    }
    return length;
  }
}

/// One rule a password must satisfy. Rendered as a checklist, never as prose.
enum PasswordRequirement { minLength, lowercase, uppercase, digit }

/// Why a password was refused locally, before any network call.
enum PasswordViolation {
  empty,
  tooLong,
  requirementsUnmet,
  confirmationEmpty,
  mismatch,
}

/// The outcome of a local policy check.
class PasswordValidation {
  const PasswordValidation._(this.violation);

  final PasswordViolation? violation;

  bool get isValid => violation == null;

  /// The ARB key describing this outcome, or null when the password is valid.
  String? get messageKey {
    switch (violation) {
      case null:
        return null;
      case PasswordViolation.empty:
        return 'passwordRequired';
      case PasswordViolation.tooLong:
        return 'passwordTooLong';
      case PasswordViolation.requirementsUnmet:
        return 'passwordDoesNotMeetRequirements';
      case PasswordViolation.confirmationEmpty:
        return 'confirmPasswordRequired';
      case PasswordViolation.mismatch:
        return 'passwordsDoNotMatch';
    }
  }
}

/// The ARB key naming [requirement] in the requirement checklist.
String passwordRequirementKey(PasswordRequirement requirement) {
  switch (requirement) {
    case PasswordRequirement.minLength:
      return 'passwordRuleMinLength';
    case PasswordRequirement.lowercase:
      return 'passwordRuleLowercase';
    case PasswordRequirement.uppercase:
      return 'passwordRuleUppercase';
    case PasswordRequirement.digit:
      return 'passwordRuleDigit';
  }
}
