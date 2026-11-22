import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:broker_wallet/src/repositories/auth_failure.dart';
import 'package:broker_wallet/src/services/app_access_policy.dart';

/// Verifies a CONTACT phone number for a signed-in email account (Model X).
///
/// The number is checked by the Broker Wallet Worker through an SMS
/// provider's verification API and stored on the account's profile as a
/// contact number. It is never added to Supabase Auth, so it can never be
/// used to sign in, and a code never creates or returns a session. The
/// Worker binds every verification to the session that started it and to
/// the account's current app session (Single Active Device).
abstract class ContactPhoneGateway {
  /// Sends a code to [phoneE164]. Returns the verification id.
  /// Throws [AuthFailure].
  Future<String> startContactPhone({
    required String accessToken,
    required String phoneE164,
  });

  /// Checks [code] for [verificationId]. Returns the number the server now
  /// reports as the account's verified contact number. Throws [AuthFailure].
  Future<String> confirmContactPhone({
    required String accessToken,
    required String verificationId,
    required String code,
  });
}

/// Changes the sign-in number of a phone account (Model X). The server proves
/// the current number with a Supabase code and the new one with the
/// verification provider, for the current app session only, and changes the
/// number itself. No session is ever returned.
abstract class PhoneNumberChangeGateway {
  /// Sends a code to the account's current number (chosen by the server from
  /// the session) and one to [newPhoneE164]. Returns the verification id.
  /// Throws [AuthFailure].
  Future<String> startSignInNumberChange({
    required String accessToken,
    required String newPhoneE164,
  });

  /// Checks both codes and changes the number. [currentCode] may be null once
  /// the server accepted it for this verification. Returns the new number.
  /// Throws [AuthFailure]; [NewNumberCodeRejected] when only the new-number
  /// code was wrong (the current-number code was accepted and is not needed
  /// again).
  Future<String> confirmSignInNumberChange({
    required String accessToken,
    required String verificationId,
    required String newCode,
    String? currentCode,
  });
}

/// The new number's code was rejected after the current number was proven.
class NewNumberCodeRejected extends AuthFailure {
  const NewNumberCodeRejected()
      : super(
          code: AuthFailureCode.otpInvalidOrExpired,
          message: 'The verification code is invalid or has expired.',
        );
}

/// Calls `POST /account/contact-phone/start|confirm` on the media Worker.
///
/// Sends the live session's access token and the number or code the user
/// typed, and nothing else: no user id. Nothing is logged.
class WorkerContactPhoneGateway
    implements ContactPhoneGateway, PhoneNumberChangeGateway {
  WorkerContactPhoneGateway({http.Client? httpClient, String? workerUrl})
      : _http = AppAccessPolicy.guard(httpClient ?? http.Client()),
        _workerUrl = workerUrl ?? R2Config.workerUrl;

  static const Duration requestTimeout = Duration(seconds: 20);

  final http.Client _http;
  final String _workerUrl;

  @override
  Future<String> startContactPhone({
    required String accessToken,
    required String phoneE164,
  }) async {
    final body = await _post(
      '/account/contact-phone/start',
      accessToken,
      {'phone': phoneE164},
    );
    final id = body['verificationId'];
    if (id is! String || id.isEmpty) throw _unknown;
    return id;
  }

  @override
  Future<String> confirmContactPhone({
    required String accessToken,
    required String verificationId,
    required String code,
  }) async {
    final body = await _post(
      '/account/contact-phone/confirm',
      accessToken,
      {'verificationId': verificationId, 'code': code},
    );
    final phone = body['phone'];
    if (body['status'] != 'verified' || phone is! String) throw _unknown;
    return phone;
  }

  @override
  Future<String> startSignInNumberChange({
    required String accessToken,
    required String newPhoneE164,
  }) async {
    final body = await _post(
      '/account/phone-identity/start',
      accessToken,
      {'newPhone': newPhoneE164, 'currentProof': 'sms'},
    );
    final id = body['verificationId'];
    if (id is! String || id.isEmpty) throw _unknown;
    return id;
  }

  @override
  Future<String> confirmSignInNumberChange({
    required String accessToken,
    required String verificationId,
    required String newCode,
    String? currentCode,
  }) async {
    final Map<String, Object?> body;
    try {
      body = await _post(
        '/account/phone-identity/confirm',
        accessToken,
        {
          'verificationId': verificationId,
          'newCode': newCode,
          if (currentCode != null) 'currentCode': currentCode,
        },
      );
    } on _InvalidCode {
      // The Worker checks the new-number code only after the current number
      // was proven (and recorded) for this verification.
      throw const NewNumberCodeRejected();
    }
    final phone = body['phone'];
    if (body['status'] != 'changed' || phone is! String) throw _unknown;
    return phone;
  }

  Future<Map<String, Object?>> _post(
    String path,
    String accessToken,
    Map<String, Object?> payload,
  ) async {
    if (_workerUrl.trim().isEmpty) {
      throw const AuthFailure(
        code: AuthFailureCode.smsUnavailable,
        message: 'Phone verification is not configured.',
      );
    }
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('${_workerUrl.trim()}$path'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(requestTimeout);
    } catch (_) {
      throw const AuthFailure(
        code: AuthFailureCode.network,
        message: 'The request did not complete.',
      );
    }
    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, Object?>) return decoded;
      } catch (_) {}
      throw _unknown;
    }
    final failure = contactPhoneFailure(response.statusCode, response.body);
    if (path == '/account/phone-identity/confirm' &&
        _errorCode(response.body) == 'invalid_code') {
      throw const _InvalidCode();
    }
    throw failure;
  }

  static const AuthFailure _unknown = AuthFailure(
    code: AuthFailureCode.unknown,
    message: 'Phone verification failed.',
  );
}

class _InvalidCode implements Exception {
  const _InvalidCode();
}

String? _errorCode(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error'] is String) {
      return decoded['error'] as String;
    }
  } catch (_) {}
  return null;
}

/// Maps a Worker refusal to a typed failure. Only the fixed `error` code is
/// read; no server text is carried.
AuthFailure contactPhoneFailure(int statusCode, String body) {
  final error = _errorCode(body);

  AuthFailure typed(AuthFailureCode code, String message) =>
      AuthFailure(code: code, message: message);

  switch (error) {
    case 'session_expired':
    case 'session_superseded':
    case 'session_mismatch':
      return typed(AuthFailureCode.sessionExpired, 'No active session.');
    case 'invalid_phone':
      return typed(
        AuthFailureCode.invalidPhoneNumber,
        'The phone number is not a valid UAE mobile number.',
      );
    case 'invalid_code':
    case 'verification_expired':
    case 'verification_not_found':
      return typed(
        AuthFailureCode.otpInvalidOrExpired,
        'The verification code is invalid or has expired.',
      );
    case 'rate_limited':
    case 'too_many_attempts':
      return typed(AuthFailureCode.tooManyRequests, 'Rate limited.');
    case 'phone_unavailable':
      return typed(
        AuthFailureCode.phoneAlreadyInUse,
        'The phone number belongs to another account.',
      );
    case 'verification_unavailable':
      return typed(AuthFailureCode.smsUnavailable, 'SMS is unavailable.');
    case 'recovery_session':
    case 'not_available_for_account':
    case 'phone_already_verified':
    case 'reauthentication_unsupported':
      return typed(
        AuthFailureCode.operationNotAllowed,
        'Phone verification is not available for this account.',
      );
    case 'current_proof_failed':
      return typed(
        AuthFailureCode.invalidCurrentPassword,
        'The current number could not be confirmed.',
      );
    case 'account_mismatch':
      return typed(
        AuthFailureCode.accountChanged,
        'The authenticated account changed.',
      );
  }
  if (statusCode == 401) {
    return typed(AuthFailureCode.sessionExpired, 'No active session.');
  }
  return typed(AuthFailureCode.unknown, 'Phone verification failed.');
}
