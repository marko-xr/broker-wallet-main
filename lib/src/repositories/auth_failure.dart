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
