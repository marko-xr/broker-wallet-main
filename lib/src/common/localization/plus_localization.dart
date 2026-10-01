import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Placeholder-aware lookup for the Plus subscription strings.
///
/// The app's ARB files are loaded as plain JSON (not ICU), so placeholders are
/// written as `{name}` and substituted here, the same way the existing quota
/// messages do it.
extension PlusLocalizationX on AppLocalizations {
  String plusText(String key, [Map<String, String> args = const {}]) {
    var text = translate(key);
    args.forEach((name, value) {
      text = text.replaceAll('{$name}', value);
    });
    return text;
  }
}
