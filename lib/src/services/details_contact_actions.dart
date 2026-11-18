import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:url_launcher/url_launcher.dart';

enum ContactLaunchResult { opened, invalidPhone, failed }

typedef ContactUrlLauncher = Future<bool> Function(Uri uri,
    {required LaunchMode mode});

/// Contact actions for Details only; never changes saved phone data.
class DetailsContactActions {
  DetailsContactActions._();

  static String? normalizePhone(String phone, {String? countryCode}) {
    var compact = phone.trim().replaceAll(RegExp(r'[\s().\-\u200E\u200F]'), '');
    if (compact.startsWith('00')) compact = '+${compact.substring(2)}';
    // Reject malformed input instead of silently discarding letters or pluses.
    if (!RegExp(r'^\+?[0-9]+$').hasMatch(compact)) return null;
    final code = countryCode?.trim();
    if (code != null &&
        code.isNotEmpty &&
        !RegExp(r'^\+?[1-9][0-9]{0,2}$').hasMatch(code)) return null;
    try {
      final dial = PhoneNumberNormalizer.normalize(
        phoneNumber: compact,
        // Preserve significant zeros in explicit international numbers. Only
        // UAE's established legacy +9710... form needs trunk-prefix repair.
        countryCode: compact.startsWith('+')
            ? (compact.startsWith('+971') ? '+971' : null)
            : (code == null || code.isEmpty ? '+971' : code),
      );
      // Keep UAE mobile/landline lengths; E.164 alone permits short UAE values.
      if (dial.startsWith('+971')) {
        if (dial.startsWith('+9715')) {
          if (!PhoneNumberNormalizer.isUaeMobile(dial)) return null;
        } else if (dial.length != 12 && dial.length != 11) {
          return null;
        }
      }
      return dial;
    } on PhoneValidationException {
      return null;
    }
  }

  static Future<ContactLaunchResult> call(String phone,
      {String? countryCode, ContactUrlLauncher? launcher}) async {
    final dial = normalizePhone(phone, countryCode: countryCode);
    if (dial == null) return ContactLaunchResult.invalidPhone;
    return await _launch(Uri(scheme: 'tel', path: dial),
            LaunchMode.platformDefault, launcher)
        ? ContactLaunchResult.opened
        : ContactLaunchResult.failed;
  }

  static Future<ContactLaunchResult> whatsApp(String phone,
      {String? countryCode,
      required String message,
      ContactUrlLauncher? launcher}) async {
    final dial = normalizePhone(phone, countryCode: countryCode);
    if (dial == null) return ContactLaunchResult.invalidPhone;
    final digits = dial.substring(1);
    final query = {'phone': digits, 'text': message};
    // Preserve the existing API -> short link -> web fallback order.
    final destinations = [
      Uri.https('api.whatsapp.com', '/send', query),
      Uri.https('wa.me', '/$digits', {'text': message}),
      Uri.https('web.whatsapp.com', '/send', query),
    ];
    for (final uri in destinations) {
      if (await _launch(uri, LaunchMode.externalApplication, launcher)) {
        return ContactLaunchResult.opened;
      }
    }
    return ContactLaunchResult.failed;
  }

  static Future<bool> _launch(
      Uri uri, LaunchMode mode, ContactUrlLauncher? launcher) async {
    try {
      return await (launcher == null
          ? launchUrl(uri, mode: mode)
          : launcher(uri, mode: mode));
    } on Exception {
      // The caller shows localized failure if no destination opens.
      return false;
    }
  }
}
