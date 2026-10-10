import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';

/// Reads which of the supported UAE cities a text names.
///
/// The cities are [UaeAreaCatalog.supportedCities] and nothing else. A city goes
/// by its catalog spelling, its localization key, and the labels the app writes
/// it with ([labelsOf]; the app passes the English and the Arabic ones, so text
/// the forms wrote in either language is read).
///
/// Two readings, both on whole words:
///
///  * [canonical] — the text IS a city's name and nothing else (an Offer's
///    stored city).
///  * [cityIn] — a free text (a saved location, an address) that names a city
///    anywhere in it: `Ajman, Al Jurf` and `Al Jurf, Ajman` are both Ajman.
///
/// It is deliberately conservative. A name only counts as whole words, so
/// `Dubailand` is not Dubai and `Ain Dubai` is not Al Ain; a name inside a road's
/// name (`Sharjah Road`) is not the city; and a text that names two unrelated
/// cities is no city at all rather than a guess. Nothing here asks the network
/// or a geocoder.
class UaeCityMatcher {
  UaeCityMatcher({Iterable<String> Function(String city)? labelsOf})
      : _cityByName = _namesOf(labelsOf);

  /// Every name of every city, written compactly (see [_tokens]), to its city.
  final Map<String, String> _cityByName;

  /// The most words a city's name has (`Ra's Al Khaimah` is four).
  static const int _widestName = 5;

  /// Cities that lie inside another listed city's emirate. An address names the
  /// emirate after the city (`Al Ain, Abu Dhabi`), so when both appear the inner
  /// one is the answer. A place in the inner city may also be listed under the
  /// emirate (Al Ain under Abu Dhabi), which is why the map's city/pin check
  /// reads this table as well.
  static const Map<String, String> withinEmirateOf = <String, String>{
    'Al Ain': 'Abu Dhabi',
    'Khor Fakkan': 'Sharjah',
  };

  /// A city's name followed by one of these is a road named after it.
  static const Set<String> _roadAfter = <String>{
    'road',
    'rd',
    'street',
    'st',
    'highway',
    'hwy',
    'طريق',
    'شارع',
  };

  /// ...and, in Arabic, the road comes first.
  static const Set<String> _roadBefore = <String>{'طريق', 'شارع'};

  /// Where one part of an address ends: commas (also the Arabic one),
  /// semicolons, bars, slashes, line breaks, and a dash with spaces around it
  /// (`Al Ain - Abu Dhabi`).
  static final RegExp _partBreak = RegExp(r'[,،;؛|/\\\n\r]+|\s[-–—]+\s');

  static final RegExp _word = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

  /// The city [stored] is the name of, or null. The whole text must be the name
  /// (case, spaces, hyphens and Arabic spelling variants do not matter).
  String? canonical(String? stored) {
    if (stored == null) return null;
    final words = _tokens(stored);
    if (words.isEmpty || words.length > _widestName) return null;
    return _cityByName[words.join()];
  }

  /// The one city [text] names, or null when it names none or is unsure.
  ///
  /// A part of the address that is a city's name on its own (`Ajman`) beats a
  /// city named inside a longer part (`Ajman Free Zone`); only when no part is a
  /// city on its own are the longer parts read.
  String? cityIn(String? text) {
    if (text == null) return null;
    final wholeParts = <String>[];
    final insideParts = <String>[];

    for (final part in text.split(_partBreak)) {
      final words = _tokens(part);
      if (words.isEmpty) continue;

      final whole =
          words.length <= _widestName ? _cityByName[words.join()] : null;
      if (whole != null) {
        if (!wholeParts.contains(whole)) wholeParts.add(whole);
        continue;
      }

      for (var start = 0; start < words.length; start++) {
        for (var end = start + 1;
            end <= words.length && end - start <= _widestName;
            end++) {
          final city = _cityByName[words.sublist(start, end).join()];
          if (city == null || _isRoadName(words, start, end)) continue;
          if (!insideParts.contains(city)) insideParts.add(city);
        }
      }
    }
    return _theOne(wholeParts.isNotEmpty ? wholeParts : insideParts);
  }

  /// The single answer among [cities] (in the order they were found), or null.
  static String? _theOne(List<String> cities) {
    if (cities.length == 1) return cities.first;
    if (cities.length == 2) {
      final first = cities[0];
      final second = cities[1];
      if (withinEmirateOf[first] == second) return first;
      if (withinEmirateOf[second] == first) return second;
    }
    return null;
  }

  static bool _isRoadName(List<String> words, int start, int end) =>
      (end < words.length && _roadAfter.contains(words[end])) ||
      (start > 0 && _roadBefore.contains(words[start - 1]));

  static Map<String, String> _namesOf(
    Iterable<String> Function(String city)? labelsOf,
  ) {
    final byName = <String, String>{};
    for (final city in UaeAreaCatalog.supportedCities) {
      final names = <String>[
        city,
        UaeAreaCatalog.cityKey(city),
        ...?labelsOf?.call(city),
      ];
      for (final name in names) {
        final compact = _tokens(name).join();
        if (compact.isNotEmpty) byName[compact] = city;
      }
    }
    return byName;
  }

  /// The words of [text], folded so spelling variants meet: lower case, no
  /// Arabic marks, one alef, one yeh and one heh. Joining a name's words back
  /// with nothing between them (`abudhabi`) makes `Abu Dhabi`, `AbuDhabi`,
  /// `Abu-Dhabi` and the Arabic `أبو ظبي` / `أبوظبي` the same name.
  static List<String> _tokens(String text) => [
        for (final match in _word.allMatches(_fold(text))) match.group(0)!,
      ];

  static String _fold(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      // Arabic vowel marks and the stretching tatweel carry no name.
      if ((rune >= 0x064B && rune <= 0x065F) ||
          rune == 0x0670 ||
          rune == 0x0640) {
        continue;
      }
      switch (rune) {
        case 0x0622: // آ
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0671: // ٱ
          out.writeCharCode(0x0627); // ا
        case 0x0649: // ى
          out.writeCharCode(0x064A); // ي
        case 0x0629: // ة
          out.writeCharCode(0x0647); // ه
        default:
          out.writeCharCode(rune);
      }
    }
    return out.toString().toLowerCase();
  }
}
