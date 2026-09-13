import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Backend-neutral authentication failure codes.
enum AuthFailureCode {
  invalidCredentials,
  emailAlreadyInUse,
  weakPassword,
  invalidEmail,
  emailNotConfirmed,
  userDisabled,
  tooManyRequests,
  network,
  providerUnavailable,
  operationNotAllowed,

  /// The verification code was wrong or has expired. Supabase Auth reports
  /// both as `otp_expired` ("Token has expired or is invalid"), so the two
  /// cannot be told apart and are deliberately one outcome.
  otpInvalidOrExpired,

  /// The phone number is not a valid UAE mobile number.
  invalidPhoneNumber,

  /// The number already belongs to another account.
  phoneAlreadyInUse,

  /// SMS could not be sent: no SMS provider, or the provider failed.
  smsUnavailable,

  /// The session that started the operation is gone or no longer valid.
  sessionExpired,
  sameEmail,
  accountChanged,
  noPendingEmailChange,

  /// The current password supplied for a password change was rejected.
  invalidCurrentPassword,

  /// The new password is already the account's current password.
  samePassword,

  /// The backend wants a fresh reauthentication before the password may be
  /// changed — Supabase's "Secure password change" setting.
  reauthenticationRequired,

  unknown,
}

/// Unified, backend-neutral authentication failure representation.
///
/// Both [FirebaseAuthRepository] and [SupabaseAuthRepository] translate their
/// vendor-specific exceptions into [AuthFailure]. ViewModels and UI layers
/// only handle [AuthFailure] without needing vendor-specific imports.
class AuthFailure implements Exception {
  final AuthFailureCode code;
  final String message;
  final dynamic originalException;

  const AuthFailure({
    required this.code,
    required this.message,
    this.originalException,
  });

  /// Map Firebase authentication exceptions to [AuthFailure].
  factory AuthFailure.fromFirebase(dynamic exception) {
    if (exception is AuthFailure) return exception;

    if (exception is fb.FirebaseAuthException) {
      switch (exception.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return AuthFailure(
            code: AuthFailureCode.invalidCredentials,
            message: 'Invalid email or password.',
            originalException: exception,
          );
        case 'email-already-in-use':
          return AuthFailure(
            code: AuthFailureCode.emailAlreadyInUse,
            message: 'An account already exists for this email.',
            originalException: exception,
          );
        case 'weak-password':
          return AuthFailure(
            code: AuthFailureCode.weakPassword,
            message: 'The password provided is too weak.',
            originalException: exception,
          );
        case 'invalid-email':
          return AuthFailure(
            code: AuthFailureCode.invalidEmail,
            message: 'The email address is not valid.',
            originalException: exception,
          );
        case 'user-disabled':
          return AuthFailure(
            code: AuthFailureCode.userDisabled,
            message: 'This user account has been disabled.',
            originalException: exception,
          );
        case 'too-many-requests':
          return AuthFailure(
            code: AuthFailureCode.tooManyRequests,
            message: 'Too many attempts. Please try again later.',
            originalException: exception,
          );
        case 'network-request-failed':
          return AuthFailure(
            code: AuthFailureCode.network,
            message: 'Network error. Please check your internet connection.',
            originalException: exception,
          );
        case 'operation-not-allowed':
          return AuthFailure(
            code: AuthFailureCode.operationNotAllowed,
            message: 'This sign-in method is not enabled.',
            originalException: exception,
          );
        default:
          return AuthFailure(
            code: AuthFailureCode.unknown,
            message: exception.message ??
                'An unexpected authentication error occurred.',
            originalException: exception,
          );
      }
    }

    return AuthFailure(
      code: AuthFailureCode.unknown,
      message: exception?.toString() ?? 'An unexpected error occurred.',
      originalException: exception,
    );
  }

  /// Map Supabase authentication exceptions to [AuthFailure].
  factory AuthFailure.fromSupabase(dynamic exception) {
    if (exception is AuthFailure) return exception;

    if (exception is sb.AuthException) {
      final msg = exception.message.toLowerCase();
      final codeStr = exception.code?.toLowerCase() ?? '';
      final status = exception.statusCode;

      if (codeStr == 'email_not_confirmed' ||
          msg.contains('email not confirmed') ||
          msg.contains('not confirmed')) {
        return AuthFailure(
          code: AuthFailureCode.emailNotConfirmed,
          message: 'Please verify your email address before logging in.',
          originalException: exception,
        );
      }

      if (codeStr == 'user_already_exists' ||
          msg.contains('already registered') ||
          msg.contains('already in use') ||
          msg.contains('user already exists')) {
        return AuthFailure(
          code: AuthFailureCode.emailAlreadyInUse,
          message: 'An account already exists for this email.',
          originalException: exception,
        );
      }

      if (codeStr == 'invalid_credentials' ||
          codeStr == 'invalid_grant' ||
          msg.contains('invalid login credentials') ||
          msg.contains('invalid credentials')) {
        return AuthFailure(
          code: AuthFailureCode.invalidCredentials,
          message: 'Invalid email or password.',
          originalException: exception,
        );
      }

      if (codeStr == 'weak_password' ||
          msg.contains('password should be at least') ||
          msg.contains('weak password')) {
        return AuthFailure(
          code: AuthFailureCode.weakPassword,
          message: 'The password provided is too weak.',
          originalException: exception,
        );
      }

      if (codeStr == 'validation_failed' ||
          codeStr == 'invalid_email' ||
          msg.contains('valid email') ||
          msg.contains('invalid email')) {
        return AuthFailure(
          code: AuthFailureCode.invalidEmail,
          message: 'The email address is not valid.',
          originalException: exception,
        );
      }

      if (codeStr == 'over_request_rate_limit' ||
          codeStr == 'too_many_requests' ||
          status == '429' ||
          msg.contains('rate limit') ||
          msg.contains('too many requests')) {
        return AuthFailure(
          code: AuthFailureCode.tooManyRequests,
          message: 'Too many attempts. Please try again later.',
          originalException: exception,
        );
      }

      if (msg.contains('network') ||
          msg.contains('connection') ||
          msg.contains('socket') ||
          msg.contains('failed host lookup')) {
        return AuthFailure(
          code: AuthFailureCode.network,
          message: 'Network error. Please check your internet connection.',
          originalException: exception,
        );
      }

      return AuthFailure(
        code: AuthFailureCode.unknown,
        message: exception.message,
        originalException: exception,
      );
    }

    return AuthFailure(
      code: AuthFailureCode.unknown,
      message: exception?.toString() ?? 'An unexpected error occurred.',
      originalException: exception,
    );
  }

  /// Maps a Supabase phone-verification failure to a typed outcome.
  ///
  /// Only the code is carried forward. [message] is a fixed internal string and
  /// the original exception is deliberately not attached, so no provider
  /// response, token or code can reach a caller that displays failures.
  factory AuthFailure.fromSupabasePhoneVerification(Object exception) {
    if (exception is AuthFailure) return exception;

    AuthFailure typed(AuthFailureCode code, String message) =>
        AuthFailure(code: code, message: message);

    if (exception is PhoneValidationException) {
      return typed(
        AuthFailureCode.invalidPhoneNumber,
        'The phone number is not a valid UAE mobile number.',
      );
    }
    if (exception is sb.AuthSessionMissingException) {
      return typed(AuthFailureCode.sessionExpired, 'No active session.');
    }
    if (exception is TimeoutException) {
      return typed(AuthFailureCode.network, 'The request did not complete.');
    }
    // gotrue raises this for two different things. With no status it is a
    // transport failure — offline, DNS, a dropped connection. With a status it
    // is a server 5xx, and gotrue has discarded the error code: an SMS
    // provider failure (`sms_send_failed`) arrives this way, and reporting it
    // as "check your connection" would send the user after the wrong problem.
    // The code is still in the response body, which is read here and never
    // shown.
    if (exception is sb.AuthRetryableFetchException) {
      if (exception.statusCode == null) {
        return typed(AuthFailureCode.network, 'The request did not complete.');
      }
      final serverCode = _errorCodeInBody(exception.message);
      if (serverCode == 'sms_send_failed' ||
          serverCode == 'hook_timeout' ||
          serverCode == 'hook_timeout_after_retry') {
        return typed(AuthFailureCode.smsUnavailable, 'SMS is unavailable.');
      }
      return typed(AuthFailureCode.unknown, 'Phone verification failed.');
    }
    if (exception is sb.AuthException) {
      switch (exception.code) {
        case 'otp_expired':
          return typed(
            AuthFailureCode.otpInvalidOrExpired,
            'The verification code is invalid or has expired.',
          );
        case 'over_sms_send_rate_limit':
        case 'over_request_rate_limit':
          return typed(AuthFailureCode.tooManyRequests, 'Rate limited.');
        case 'phone_exists':
          return typed(
            AuthFailureCode.phoneAlreadyInUse,
            'The phone number belongs to another account.',
          );
        case 'sms_send_failed':
        case 'phone_provider_disabled':
        case 'provider_disabled':
        case 'otp_disabled':
          return typed(AuthFailureCode.smsUnavailable, 'SMS is unavailable.');
        case 'validation_failed':
          return typed(
            AuthFailureCode.invalidPhoneNumber,
            'The phone number was rejected.',
          );
        case 'session_not_found':
        case 'session_expired':
        case 'session_missing':
        case 'bad_jwt':
        case 'user_not_found':
          return typed(AuthFailureCode.sessionExpired, 'Session is invalid.');
      }
      if (exception.statusCode == '429') {
        return typed(AuthFailureCode.tooManyRequests, 'Rate limited.');
      }
    }
    return typed(AuthFailureCode.unknown, 'Phone verification failed.');
  }

  /// Maps email-change failures to fixed domain outcomes.
  ///
  /// Provider messages and the original exception are deliberately discarded
  /// so an auth response, link token, or other backend detail can never be
  /// rendered by the email-change UI.
  factory AuthFailure.fromSupabaseEmailChange(Object exception) {
    if (exception is AuthFailure) return exception;

    AuthFailure typed(AuthFailureCode code, String message) =>
        AuthFailure(code: code, message: message);

    if (exception is TimeoutException) {
      return typed(AuthFailureCode.network, 'The request did not complete.');
    }
    if (exception is sb.AuthSessionMissingException) {
      return typed(AuthFailureCode.sessionExpired, 'No active session.');
    }
    if (exception is sb.AuthRetryableFetchException) {
      return typed(AuthFailureCode.network, 'The request did not complete.');
    }
    if (exception is sb.AuthException) {
      switch (exception.code) {
        case 'email_address_invalid':
        case 'validation_failed':
          return typed(
            AuthFailureCode.invalidEmail,
            'The email address is not valid.',
          );
        case 'email_exists':
        case 'user_already_exists':
          return typed(
            AuthFailureCode.emailAlreadyInUse,
            'That email address is already in use.',
          );
        case 'over_email_send_rate_limit':
        case 'over_request_rate_limit':
        case 'too_many_requests':
          return typed(AuthFailureCode.tooManyRequests, 'Rate limited.');
        case 'otp_expired':
        case 'flow_state_expired':
        case 'flow_state_not_found':
          return typed(
            AuthFailureCode.otpInvalidOrExpired,
            'The confirmation link is invalid or has expired.',
          );
        case 'session_not_found':
        case 'session_expired':
        case 'session_missing':
        case 'bad_jwt':
        case 'user_not_found':
          return typed(AuthFailureCode.sessionExpired, 'Session is invalid.');
        case 'email_provider_disabled':
        case 'email_address_not_authorized':
        case 'user_sso_managed':
          return typed(
            AuthFailureCode.providerUnavailable,
            'Email change is unavailable for this account.',
          );
      }
      if (exception.statusCode == '429') {
        return typed(AuthFailureCode.tooManyRequests, 'Rate limited.');
      }
      final message = exception.message.toLowerCase();
      if (message.contains('network') ||
          message.contains('connection') ||
          message.contains('socket') ||
          message.contains('failed host lookup')) {
        return typed(AuthFailureCode.network, 'The request did not complete.');
      }
    }
    return typed(AuthFailureCode.unknown, 'Email change failed.');
  }

  /// Maps a Supabase password failure to a fixed domain outcome.
  ///
  /// Provider messages and the original exception are deliberately discarded,
  /// exactly as in [AuthFailure.fromSupabaseEmailChange]: nothing that a
  /// password screen renders may carry backend prose, a token, a nonce or the
  /// password itself.
  ///
  /// [AuthWeakPasswordException] is checked before the general
  /// [sb.AuthException] branch because it is a subclass of it, and its
  /// `reasons` list is deliberately not carried: the local policy already
  /// tells the user what a password needs, in their own language.
  factory AuthFailure.fromSupabasePassword(Object exception) {
    if (exception is AuthFailure) return exception;

    AuthFailure typed(AuthFailureCode code, String message) =>
        AuthFailure(code: code, message: message);

    if (exception is TimeoutException) {
      return typed(AuthFailureCode.network, 'The request did not complete.');
    }
    if (exception is sb.AuthSessionMissingException) {
      return typed(AuthFailureCode.sessionExpired, 'No active session.');
    }
    if (exception is sb.AuthWeakPasswordException) {
      return typed(AuthFailureCode.weakPassword, 'The password is too weak.');
    }
    if (exception is sb.AuthRetryableFetchException) {
      return typed(AuthFailureCode.network, 'The request did not complete.');
    }
    if (exception is sb.AuthException) {
      switch (exception.code) {
        case 'weak_password':
        case 'validation_failed':
          return typed(
            AuthFailureCode.weakPassword,
            'The password is too weak.',
          );
        case 'same_password':
          return typed(
            AuthFailureCode.samePassword,
            'The new password matches the current one.',
          );
        // GoTrue reports a rejected `current_password` as a credential
        // mismatch. This branch is only reachable once the hosted
        // "require current password" setting is enabled, which is also the
        // only configuration in which the app collects a current password.
        case 'invalid_credentials':
          return typed(
            AuthFailureCode.invalidCurrentPassword,
            'The current password is incorrect.',
          );
        case 'reauthentication_needed':
        case 'reauthentication_not_valid':
          return typed(
            AuthFailureCode.reauthenticationRequired,
            'Reauthentication is required.',
          );
        case 'over_email_send_rate_limit':
        case 'over_request_rate_limit':
        case 'too_many_requests':
          return typed(AuthFailureCode.tooManyRequests, 'Rate limited.');
        case 'otp_expired':
        case 'flow_state_expired':
        case 'flow_state_not_found':
          return typed(
            AuthFailureCode.otpInvalidOrExpired,
            'The link is invalid or has expired.',
          );
        case 'session_not_found':
        case 'session_expired':
        case 'session_missing':
        case 'bad_jwt':
        case 'user_not_found':
          return typed(AuthFailureCode.sessionExpired, 'Session is invalid.');
        case 'email_provider_disabled':
        case 'signup_disabled':
          return typed(
            AuthFailureCode.providerUnavailable,
            'Password operations are unavailable for this account.',
          );
      }
      if (exception.statusCode == '429') {
        return typed(AuthFailureCode.tooManyRequests, 'Rate limited.');
      }
      final message = exception.message.toLowerCase();
      if (message.contains('network') ||
          message.contains('connection') ||
          message.contains('socket') ||
          message.contains('failed host lookup')) {
        return typed(AuthFailureCode.network, 'The request did not complete.');
      }
    }
    return typed(AuthFailureCode.unknown, 'The password operation failed.');
  }

  /// Reads the Supabase error code from a raw error body, or null.
  static String? _errorCodeInBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        for (final key in const ['error_code', 'code']) {
          final value = decoded[key];
          if (value is String) return value;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Helper for providers not yet supported in the active configuration.
  factory AuthFailure.providerUnavailable([String provider = 'This provider']) {
    return AuthFailure(
      code: AuthFailureCode.providerUnavailable,
      message: '$provider sign-in is not available in this configuration.',
    );
  }

  bool get isEmailNotConfirmed => code == AuthFailureCode.emailNotConfirmed;
  bool get isInvalidCredentials => code == AuthFailureCode.invalidCredentials;
  bool get isEmailAlreadyInUse => code == AuthFailureCode.emailAlreadyInUse;
  bool get isProviderUnavailable => code == AuthFailureCode.providerUnavailable;

  @override
  String toString() => message;
}
