import 'package:broker_wallet/src/services/phone_input_service.dart';

/// What the phone code screen needs to finish a phone sign-in or sign-up.
///
/// Supabase Auth keeps the pending code on the server, so nothing here is
/// secret and no verification id is carried. [phoneNumber] is the E.164
/// number the code was sent to; [codeSentAt] lets the resend countdown start
/// from when the code was actually requested.
class PhoneOtpArgs {
  final String phoneNumber;
  final bool isSignup;
  final String? displayName;
  final DateTime? codeSentAt;

  const PhoneOtpArgs({
    required this.phoneNumber,
    required this.isSignup,
    this.displayName,
    this.codeSentAt,
  });

  String get formattedPhone => PhoneInputService.formatForDisplay(phoneNumber);

  static PhoneOtpArgs empty() {
    return const PhoneOtpArgs(phoneNumber: '', isSignup: false);
  }

  PhoneOtpArgs copyWith({
    String? phoneNumber,
    bool? isSignup,
    String? displayName,
    DateTime? codeSentAt,
  }) {
    return PhoneOtpArgs(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isSignup: isSignup ?? this.isSignup,
      displayName: displayName ?? this.displayName,
      codeSentAt: codeSentAt ?? this.codeSentAt,
    );
  }
}
