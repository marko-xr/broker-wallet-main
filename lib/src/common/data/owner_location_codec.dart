import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// The text of a localization key in one language, or null when unknown.
typedef LocalizedLabelLookup = String? Function(
    String languageCode, String key);

/// What a saved Owner property location says: a city, optionally an area in it,
/// and anything the owner wrote after them.
class OwnerLocationParts {
  const OwnerLocationParts({
    required this.city,
    this.areaKey,
    this.detail = '',
  });

  /// A supported city's name, as [UaeAreaCatalog] spells it (e.g. `Dubai`).
  final String city;

  /// The area's catalog key; null when only a city was chosen.
  final String? areaKey;

  /// The owner's own words after the city and area; empty when there are none.
  final String detail;
}

/// Writes and reads an Owner's property location as ordinary text.
///
/// An Owner stores ONE location in a single free-text field. Choosing a city
/// and an area from the shared UAE catalog must therefore keep that field a
/// plain, readable string — every list, detail and search screen shows it as
/// is — and must keep reading back what older owners typed. So a choice is
/// written as `Area, City` (or just `City`), in the language the owner is
/// using, optionally followed by `, their own detail`:
///
///   Dubai Marina, Dubai
///   مرسى دبي, دبي
///   Dubai Marina, Dubai, Marina Gate tower 2
///
/// Reading is the reverse and recognises both of the app's languages, so a
/// location saved in Arabic still restores its city and area in English. Text
/// that does not start with a known city or `area, city` is simply the owner's
/// own text: it is never changed, and never mistaken for a choice.
class OwnerLocationCodec {
  OwnerLocationCodec({
    LocalizedLabelLookup? lookup,
    List<String> languages = const <String>['en', 'ar'],
  })  : _lookup = lookup ?? AppLocalizations.translateFor,
        _languages = languages;

  final LocalizedLabelLookup _lookup;
  final List<String> _languages;

  List<_Encoding>? _cache;

  /// The text for a choice in [language]: `Area, City`, or `City` when
  /// [areaKey] is null or empty, followed by `, detail` when there is one.
  String encode({
    required String city,
    String? areaKey,
    required String language,
    String detail = '',
  }) {
    final cityLabel = _label(UaeAreaCatalog.cityKey(city), language);
    final base = (areaKey != null && areaKey.isNotEmpty)
        ? '${_label(areaKey, language)}, $cityLabel'
        : cityLabel;
    return detail.isEmpty ? base : '$base, $detail';
  }

  /// The city, area and detail a saved [text] starts with, or null when it
  /// starts with no known `Area, City` or `City` (the owner's own text).
  OwnerLocationParts? decode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    for (final encoding in _encodings()) {
      final rest = _detailAfter(trimmed, encoding.lowered);
      if (rest != null) {
        return OwnerLocationParts(
          city: encoding.city,
          areaKey: encoding.areaKey,
          detail: rest,
        );
      }
    }
    return null;
  }

  /// The detail after the choice [city] / [areaKey] at the start of [text], or
  /// null when [text] no longer starts with that choice (in either language).
  String? detailOf(String text, {required String city, String? areaKey}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    for (final language in _languages) {
      final prefix = _strictEncoding(city, areaKey, language);
      if (prefix == null) continue;
      final rest = _detailAfter(trimmed, prefix.toLowerCase());
      if (rest != null) return rest;
    }
    return null;
  }

  String _label(String key, String language) =>
      _lookup(language, key) ?? _lookup('en', key) ?? key;

  /// `Area, City` / `City` using only [language]'s own labels; null when a
  /// label is missing, so a language that is not loaded never matches.
  String? _strictEncoding(String city, String? areaKey, String language) {
    final cityLabel = _lookup(language, UaeAreaCatalog.cityKey(city));
    if (cityLabel == null || cityLabel.isEmpty) return null;
    if (areaKey == null || areaKey.isEmpty) return cityLabel;
    final areaLabel = _lookup(language, areaKey);
    if (areaLabel == null || areaLabel.isEmpty) return null;
    return '$areaLabel, $cityLabel';
  }

  /// Every `Area, City` and `City` text the app can write, in each language,
  /// longest first so the most specific one wins.
  List<_Encoding> _encodings() {
    final cached = _cache;
    if (cached != null) return cached;

    final all = <_Encoding>[];
    var loadedLanguages = 0;
    for (final language in _languages) {
      var hasLabels = false;
      for (final city in UaeAreaCatalog.supportedCities) {
        final cityLabel = _lookup(language, UaeAreaCatalog.cityKey(city));
        if (cityLabel == null || cityLabel.isEmpty) continue;
        hasLabels = true;
        all.add(_Encoding(cityLabel.toLowerCase(), city, null));
        final areaKeys = <String>[
          ...UaeAreaCatalog.areasFor(city),
          ...(UaeAreaCatalog.legacyOnlyAreas[city] ?? const <String>[]),
        ];
        for (final areaKey in areaKeys) {
          final areaLabel = _lookup(language, areaKey);
          if (areaLabel == null || areaLabel.isEmpty) continue;
          all.add(
            _Encoding('$areaLabel, $cityLabel'.toLowerCase(), city, areaKey),
          );
        }
      }
      if (hasLabels) loadedLanguages++;
    }
    all.sort((a, b) => b.lowered.length.compareTo(a.lowered.length));
    // Only keep the list once every language contributed, so a language that
    // had not finished loading is picked up on the next read.
    if (loadedLanguages == _languages.length) _cache = all;
    return all;
  }

  /// What follows [loweredPrefix] at the start of [text]: '' when it ends
  /// there, the detail when a comma follows, and null when [text] does not
  /// start with the prefix at a clean boundary (so `Dubai Marina` is not
  /// mistaken for the city `Dubai`).
  static String? _detailAfter(String text, String loweredPrefix) {
    if (text.length < loweredPrefix.length) return null;
    final head = text.substring(0, loweredPrefix.length).toLowerCase();
    if (head != loweredPrefix) return null;
    final tail = text.substring(loweredPrefix.length).trimLeft();
    if (tail.isEmpty) return '';
    final first = tail[0];
    if (first == ',' || first == '\u060C') return tail.substring(1).trim();
    return null;
  }
}

class _Encoding {
  const _Encoding(this.lowered, this.city, this.areaKey);

  final String lowered;
  final String city;
  final String? areaKey;
}
