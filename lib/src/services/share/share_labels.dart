/// The text of a localization key in one language, or null when unknown.
///
/// The same shape as `AppLocalizations.translateFor` and the Owner location
/// codec's lookup, so the Share code reads the app's own ARB files and keeps no
/// translation table of its own.
typedef ShareLabelLookup = String? Function(String languageCode, String key);

/// The words a shared message is written in.
///
/// A message is written in the language the app is showing. A key missing from
/// that language falls back to English; a key missing from both yields nothing
/// at all, never the key and never a "not found" marker, so a missing string can
/// only shorten a message, not put developer text in front of a client.
class ShareLabels {
  const ShareLabels({
    required this.languageCode,
    required ShareLabelLookup lookup,
  }) : _lookup = lookup;

  /// The language the message is written in (`en` or `ar`).
  final String languageCode;

  final ShareLabelLookup _lookup;

  /// Whether the message is right-to-left.
  bool get isRtl => languageCode == 'ar';

  /// The raw lookup, for helpers that need to ask for a specific language
  /// (the Owner location codec, file names).
  String? lookup(String language, String key) => _lookup(language, key);

  /// [key] in this message's language, else English; null when neither has it.
  String? maybe(String key) {
    final own = _clean(_lookup(languageCode, key));
    if (own != null) return own;
    return _clean(_lookup('en', key));
  }

  /// [key] in this message's language, else English; empty when neither has it.
  String text(String key) => maybe(key) ?? '';

  /// [key] in English only. File names are English so they stay plain ASCII on
  /// every phone and in every app, whatever language the message is in.
  String? english(String key) => _clean(_lookup('en', key));

  /// The same words, written in English whatever language the message is in.
  ShareLabels get inEnglish => ShareLabels(languageCode: 'en', lookup: _lookup);

  /// Every supported language's text of [key]: what saved text may say.
  Iterable<String> every(String key) sync* {
    for (final language in const <String>['en', 'ar']) {
      final value = _clean(_lookup(language, key));
      if (value != null) yield value;
    }
  }

  /// [key]'s text with each `{name}` replaced by its value.
  String fill(String key, Map<String, Object> values) {
    var out = text(key);
    values.forEach((name, value) {
      out = out.replaceAll('{$name}', '$value');
    });
    return out;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    // `AppLocalizations.translate` answers `** key not found` for an unknown key.
    if (trimmed.startsWith('** ') && trimmed.endsWith(' not found')) {
      return null;
    }
    return trimmed;
  }
}
