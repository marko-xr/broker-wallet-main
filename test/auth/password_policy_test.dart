import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/utils/password_policy.dart';
import 'package:broker_wallet/src/viewmodels/change_password_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_recovery_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/password_reset_request_viewmodel.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String language) => json.decode(
      File('lib/src/common/localization/app_$language.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  group('Password policy', () {
    test('accepts a password meeting every requirement', () {
      expect(PasswordPolicy.validate('Passw0rdd').isValid, isTrue);
      expect(PasswordPolicy.unmetRequirements('Passw0rdd'), isEmpty);
    });

    test('an empty password is refused and reports every requirement', () {
      final result = PasswordPolicy.validate('');
      expect(result.isValid, isFalse);
      expect(result.violation, PasswordViolation.empty);
      expect(result.messageKey, 'passwordRequired');
      expect(
        PasswordPolicy.unmetRequirements(''),
        PasswordPolicy.requirements.toSet(),
      );
    });

    test('seven characters is short, eight is the minimum', () {
      expect(PasswordPolicy.validate('Passw0r').isValid, isFalse);
      expect(
        PasswordPolicy.unmetRequirements('Passw0r'),
        contains(PasswordRequirement.minLength),
      );
      expect(PasswordPolicy.validate('Passw0rd').isValid, isTrue);
      expect(PasswordPolicy.minLength, 8);
    });

    test('each missing character class is reported on its own', () {
      expect(
        PasswordPolicy.unmetRequirements('PASSW0RDD'),
        {PasswordRequirement.lowercase},
      );
      expect(
        PasswordPolicy.unmetRequirements('passw0rdd'),
        {PasswordRequirement.uppercase},
      );
      expect(
        PasswordPolicy.unmetRequirements('Passwordd'),
        {PasswordRequirement.digit},
      );
    });

    test('a password longer than bcrypt can hash is refused, not truncated',
        () {
      final tooLong = 'Aa1${'x' * 70}';
      expect(tooLong.length, greaterThan(PasswordPolicy.maxLengthBytes));
      final result = PasswordPolicy.validate(tooLong);
      expect(result.violation, PasswordViolation.tooLong);
      expect(result.messageKey, 'passwordTooLong');
    });

    test('length is measured in UTF-8 bytes, as bcrypt measures it', () {
      // 24 four-byte runes plus three ASCII: 99 bytes from 27 characters.
      final multiByte = 'Aa1${'\u{1F600}' * 24}';
      expect(multiByte.length, lessThan(PasswordPolicy.maxLengthBytes));
      expect(
        PasswordPolicy.validate(multiByte).violation,
        PasswordViolation.tooLong,
      );
    });

    test('confirmation is only judged once the password itself is valid', () {
      final stillTyping = PasswordPolicy.validatePair(
        password: 'Pas',
        confirmation: 'totally different',
      );
      expect(stillTyping.violation, PasswordViolation.requirementsUnmet);
      expect(stillTyping.messageKey, 'passwordDoesNotMeetRequirements');
    });

    test('an empty confirmation and a mismatch are distinct outcomes', () {
      expect(
        PasswordPolicy.validatePair(password: 'Passw0rdd', confirmation: '')
            .messageKey,
        'confirmPasswordRequired',
      );
      expect(
        PasswordPolicy.validatePair(
          password: 'Passw0rdd',
          confirmation: 'Passw0rde',
        ).messageKey,
        'passwordsDoNotMatch',
      );
      expect(
        PasswordPolicy.validatePair(
          password: 'Passw0rdd',
          confirmation: 'Passw0rdd',
        ).isValid,
        isTrue,
      );
    });

    test('the policy is pure: validating never mutates the input', () {
      const password = 'Passw0rdd';
      PasswordPolicy.validate(password);
      PasswordPolicy.unmetRequirements(password);
      expect(password, 'Passw0rdd');
    });
  });

  group('One canonical policy across surfaces', () {
    test('Sign-up rules are exactly the shared policy rules', () {
      // The values Sign-up enforced before the policy existed. If the shared
      // policy ever diverges from them, an existing account could be locked
      // out of Change Password by a rule its password never had to meet.
      const acceptedBySignup = ['Passw0rd', 'LongerPassw0rd1'];
      const refusedBySignup = ['pass', 'passw0rdd', 'PASSW0RDD', 'Passwordd'];
      for (final value in acceptedBySignup) {
        expect(PasswordPolicy.validate(value).isValid, isTrue, reason: value);
      }
      for (final value in refusedBySignup) {
        expect(PasswordPolicy.validate(value).isValid, isFalse, reason: value);
      }
    });

    test('change and recovery view models expose the same checklist', () {
      final change = ChangePasswordViewModel(
        gateway: null,
        authRepository: null,
      );
      final recovery = PasswordRecoveryViewModel(
        gateway: null,
        authRepository: null,
      );
      addTearDown(change.dispose);
      addTearDown(recovery.dispose);

      const partial = 'passw0rdd';
      expect(
        change.unmetRequirements(partial),
        PasswordPolicy.unmetRequirements(partial),
      );
      expect(
        recovery.unmetRequirements(partial),
        PasswordPolicy.unmetRequirements(partial),
      );
    });
  });

  group('Localization', () {
    test('every password message key exists in English and Arabic', () {
      final en = _arb('en');
      final ar = _arb('ar');

      final keys = <String>{
        'passwordRequired',
        'passwordTooLong',
        'passwordDoesNotMeetRequirements',
        'confirmPasswordRequired',
        'passwordsDoNotMatch',
        'passwordMeetsRequirements',
        'showPassword',
        'hidePassword',
        'currentPassword',
        'enterCurrentPassword',
        'currentPasswordRequired',
        'newPassword',
        'enterNewPassword',
        'confirmNewPassword',
        'enterConfirmNewPassword',
        'changePassword',
        'changePasswordDescription',
        'changePasswordRowHint',
        'updatePassword',
        'passwordUpdated',
        'forgotPassword',
        'forgotPasswordTitle',
        'forgotPasswordDescription',
        'sendResetLink',
        'passwordResetSentTitle',
        'passwordResetGenericSuccess',
        'resetPasswordTitle',
        'resetPasswordHeadline',
        'resetPasswordDescription',
        'resetPasswordSuccessTitle',
        'resetPasswordSuccessMessage',
        'resetLinkExpiredTitle',
        'requestNewResetLink',
        'backToLogin',
        'continueLabel',
        for (final requirement in PasswordPolicy.requirements)
          passwordRequirementKey(requirement),
        for (final code in AuthFailureCode.values) changePasswordErrorKey(code),
        for (final code in AuthFailureCode.values)
          passwordResetRequestErrorKey(code),
      };

      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
        expect(
          (ar[key] as String) != (en[key] as String),
          isTrue,
          reason: 'ar: $key must be translated',
        );
      }
    });

    test('no password message leaks an English provider phrase', () {
      final ar = _arb('ar');
      for (final code in AuthFailureCode.values) {
        final message = ar[changePasswordErrorKey(code)] as String;
        expect(
          RegExp(r'[a-zA-Z]{4,}').hasMatch(message),
          isFalse,
          reason: changePasswordErrorKey(code),
        );
      }
    });
  });
}
