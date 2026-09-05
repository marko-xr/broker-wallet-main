import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:broker_wallet/src/repositories/auth_failure.dart';

void main() {
  group('AuthFailure Firebase Mapping Tests', () {
    test('maps invalid-credential to invalidCredentials', () {
      final fbException = FirebaseAuthException(code: 'invalid-credential');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.invalidCredentials);
      expect(failure.isInvalidCredentials, isTrue);
    });

    test('maps user-not-found to invalidCredentials', () {
      final fbException = FirebaseAuthException(code: 'user-not-found');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.invalidCredentials);
    });

    test('maps wrong-password to invalidCredentials', () {
      final fbException = FirebaseAuthException(code: 'wrong-password');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.invalidCredentials);
    });

    test('maps email-already-in-use to emailAlreadyInUse', () {
      final fbException = FirebaseAuthException(code: 'email-already-in-use');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.emailAlreadyInUse);
      expect(failure.isEmailAlreadyInUse, isTrue);
    });

    test('maps weak-password to weakPassword', () {
      final fbException = FirebaseAuthException(code: 'weak-password');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.weakPassword);
    });

    test('maps invalid-email to invalidEmail', () {
      final fbException = FirebaseAuthException(code: 'invalid-email');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.invalidEmail);
    });

    test('maps too-many-requests to tooManyRequests', () {
      final fbException = FirebaseAuthException(code: 'too-many-requests');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.tooManyRequests);
    });

    test('maps network-request-failed to network', () {
      final fbException = FirebaseAuthException(code: 'network-request-failed');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.network);
    });

    test('maps operation-not-allowed to operationNotAllowed', () {
      final fbException = FirebaseAuthException(code: 'operation-not-allowed');
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.operationNotAllowed);
    });

    test('maps unknown code to unknown', () {
      final fbException = FirebaseAuthException(
        code: 'random-unknown-code',
        message: 'Something unexpected happened',
      );
      final failure = AuthFailure.fromFirebase(fbException);

      expect(failure.code, AuthFailureCode.unknown);
      expect(failure.message, 'Something unexpected happened');
    });
  });

  group('AuthFailure Supabase Mapping Tests', () {
    test('maps email_not_confirmed to emailNotConfirmed', () {
      final sbException =
          sb.AuthException('Email not confirmed', code: 'email_not_confirmed');
      final failure = AuthFailure.fromSupabase(sbException);

      expect(failure.code, AuthFailureCode.emailNotConfirmed);
      expect(failure.isEmailNotConfirmed, isTrue);
    });

    test('maps Email not confirmed message to emailNotConfirmed', () {
      final sbException = sb.AuthException('Email not confirmed');
      final failure = AuthFailure.fromSupabase(sbException);

      expect(failure.code, AuthFailureCode.emailNotConfirmed);
    });

    test('maps user_already_exists code to emailAlreadyInUse', () {
      final sbException = sb.AuthException('User already registered',
          code: 'user_already_exists');
      final failure = AuthFailure.fromSupabase(sbException);

      expect(failure.code, AuthFailureCode.emailAlreadyInUse);
      expect(failure.isEmailAlreadyInUse, isTrue);
    });

    test('maps invalid_credentials code to invalidCredentials', () {
      final sbException = sb.AuthException('Invalid login credentials',
          code: 'invalid_credentials');
      final failure = AuthFailure.fromSupabase(sbException);

      expect(failure.code, AuthFailureCode.invalidCredentials);
      expect(failure.isInvalidCredentials, isTrue);
    });

    test('maps weak_password to weakPassword', () {
      final sbException = sb.AuthException(
          'Password should be at least 6 characters',
          code: 'weak_password');
      final failure = AuthFailure.fromSupabase(sbException);

      expect(failure.code, AuthFailureCode.weakPassword);
    });

    test('maps over_request_rate_limit code to tooManyRequests', () {
      final sbException = sb.AuthException('Too many requests',
          code: 'over_request_rate_limit');
      final failure = AuthFailure.fromSupabase(sbException);

      expect(failure.code, AuthFailureCode.tooManyRequests);
    });

    test('maps network error to network', () {
      final sbException =
          sb.AuthException('SocketException: Failed host lookup');
      final failure = AuthFailure.fromSupabase(sbException);

      expect(failure.code, AuthFailureCode.network);
    });

    test('providerUnavailable factory creates controlled failure', () {
      final failure = AuthFailure.providerUnavailable('Google');

      expect(failure.code, AuthFailureCode.providerUnavailable);
      expect(failure.isProviderUnavailable, isTrue);
      expect(failure.message, contains('Google'));
    });
  });
}
