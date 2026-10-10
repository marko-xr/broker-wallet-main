import 'package:intl/intl.dart' show NumberFormat;

/// The words that say how many places the map shows.
///
///     0 results    1 result    12 results                          (English)
///     لا توجد نتائج    نتيجة واحدة    نتيجتان    3 نتائج    12 نتيجة     (Arabic)
///
/// The words are the app's own, in `app_en.arb` and `app_ar.arb`. This only
/// picks the form that fits a number, the way each language counts: English has
/// "one" and "many"; Arabic has none, one, two, a few (3 to 10, and 103 to 110,
/// and so on) and the rest (11 to 99, 100, 101, ...), the plural categories of
/// the Unicode CLDR. The number itself is written by `intl` for the language,
/// the same formatter the rest of the map's filters use (the Near Me radius, the
/// counts in the Layers list), so the digits match theirs.
///
/// Plain Dart (and `intl`, for the digits): nothing here reads anything.
abstract final class MapResultCount {
  static const String none = 'mapResultsNone';
  static const String one = 'mapResultsOne';
  static const String two = 'mapResultsTwo';
  static const String few = 'mapResultsFew';
  static const String other = 'mapResultsOther';

  /// Every key, for the tables that must hold all of them.
  static const List<String> keys = <String>[none, one, two, few, other];

  /// The key of the words for [count] places in [languageCode].
  static String keyFor(int count, String languageCode) {
    if (count <= 0) return none;
    if (count == 1) return one;
    if (languageCode != 'ar') return other;
    if (count == 2) return two;
    final lastTwo = count % 100;
    return lastTwo >= 3 && lastTwo <= 10 ? few : other;
  }

  /// "12 results", "1 result", "لا توجد نتائج": [translate] gives the app's
  /// words for a key (`AppLocalizations.translate`), and `{count}` in them is
  /// replaced by the number, written for [languageCode].
  static String text(
    int count, {
    required String languageCode,
    required String Function(String key) translate,
  }) {
    final shown = count < 0 ? 0 : count;
    final number = NumberFormat.decimalPattern(languageCode).format(shown);
    return translate(keyFor(count, languageCode)).replaceAll('{count}', number);
  }
}
