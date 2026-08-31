import 'package:broker_wallet/src/services/phone_input_service.dart';

class PhoneOtpArgs {
  final String phoneNumber;
  final String verificationId;
  final bool isSignup;
  final String? displayName;
  final int? resendToken;
  final bool isLinkingPhone;

  const PhoneOtpArgs({
    required this.phoneNumber,
    required this.verificationId,
    required this.isSignup,
    this.displayName,
    this.resendToken,
    this.isLinkingPhone = false,
  });

  String get formattedPhone => PhoneInputService.formatForDisplay(phoneNumber);

  static PhoneOtpArgs empty() {
    return const PhoneOtpArgs(
      phoneNumber: '',
      verificationId: '',
      isSignup: false,
    );
  }

  PhoneOtpArgs copyWith({
    String? phoneNumber,
    String? verificationId,
    bool? isSignup,
    String? displayName,
    int? resendToken,
    bool? isLinkingPhone,
  }) {
    return PhoneOtpArgs(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      verificationId: verificationId ?? this.verificationId,
      isSignup: isSignup ?? this.isSignup,
      displayName: displayName ?? this.displayName,
      resendToken: resendToken ?? this.resendToken,
      isLinkingPhone: isLinkingPhone ?? this.isLinkingPhone,
    );
  }
}
