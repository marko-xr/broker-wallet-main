import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:broker_wallet/src/repositories/auth_failure.dart';

void main() {
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
