import 'package:flutter/foundation.dart';
import 'package:pinput/pinput.dart';
import 'package:smart_auth/smart_auth.dart';

/// Android SMS autofill for Broker Wallet's OTP fields, through Google's
/// **SMS User Consent API** (smart_auth).
///
/// Why User Consent and not the SMS Retriever API: the Retriever only reads an
/// SMS that ends with this app's signature hash, and the SMS text is decided by
/// Supabase Auth and the verification provider, not by the app. User Consent
/// needs no hash and no Android permission: Android asks the user, once per
/// message, whether the app may read that one SMS.
///
/// Only the six-digit code is taken from the message; the message itself is
/// not kept, logged or returned. A code is only ever a suggestion typed into
/// the field: the flow's own server-side verification decides everything.
/// iOS needs nothing here: the keyboard offers the code through
/// `AutofillHints.oneTimeCode`.
class SmsUserConsentRetriever implements SmsRetriever {
  SmsUserConsentRetriever({SmartAuth? smartAuth})
      : _smartAuth = smartAuth ?? SmartAuth();

  final SmartAuth _smartAuth;

  /// Six digits not part of a longer number (a phone number in the same SMS
  /// is never taken for the code).
  static const String codePattern = r'(?<!\d)\d{6}(?!\d)';

  /// Android only, and never on the web.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// One consent request per field: a second dialog for every later SMS
  /// would be noise. Resent codes are typed or offered by the keyboard.
  @override
  bool get listenForMultipleSms => false;

  @override
  Future<String?> getSmsCode() async {
    if (!isSupported) return null;
    try {
      final result = await _smartAuth.getSmsCode(
        useUserConsentApi: true,
        matcher: codePattern,
      );
      final code = result.code;
      return code != null && RegExp(r'^\d{6}$').hasMatch(code) ? code : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    if (!isSupported) return;
    try {
      await _smartAuth.removeSmsUserConsentListener();
    } catch (_) {}
  }
}

/// Passes a code on only while [isOpen] says the field still accepts one, so
/// an SMS that arrives after the flow ended, the session changed or the field
/// was disabled can never fill it.
class GatedSmsRetriever implements SmsRetriever {
  GatedSmsRetriever(this._inner, {required bool Function() isOpen})
      : _isOpen = isOpen;

  final SmsRetriever _inner;
  final bool Function() _isOpen;

  @override
  bool get listenForMultipleSms => _inner.listenForMultipleSms;

  @override
  Future<String?> getSmsCode() async {
    final code = await _inner.getSmsCode();
    return _isOpen() ? code : null;
  }

  @override
  Future<void> dispose() => _inner.dispose();
}
