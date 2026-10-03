import 'search_text.dart';

/// How much a field counts when a query matches it.
enum FieldWeight {
  /// A name: the owner's, the office's, the building's; a property type.
  primary(1.0),

  /// A place: city, area, location text; a deal type.
  place(0.85),

  /// A phone number.
  phone(0.8),

  /// Notes, pick-up addresses: matched, but never above a name or a place.
  note(0.35),

  /// A number (price, size): matched only from the start of the number.
  number(0.4);

  const FieldWeight(this.value);
  final double value;
}

/// One searchable piece of a record.
class RankField {
  const RankField(this.text, this.weight, {this.isNumber = false});

  /// Folded ([SearchText.fold]), for comparison. For a number, only its digits.
  final String text;
  final FieldWeight weight;
  final bool isNumber;
}

/// A record as the ranking sees it: its folded fields and whatever it needs to
/// be ordered the same way every time. [item] is carried along untouched.
class RankedEntry<T> {
  const RankedEntry({
    required this.fields,
    required this.phoneForms,
    required this.group,
    required this.titleKey,
    required this.key,
    required this.item,
  });

  final List<RankField> fields;

  /// Every way a person might type this record's phone number, as digits.
  final List<String> phoneForms;

  /// What the record is — equally good matches of different kinds are ordered by
  /// this first.
  final int group;

  /// The folded title: the next tie-break.
  final String titleKey;

  /// A unique key for the record: the last tie-break.
  final String key;

  final T item;
}

/// Decides which records match a query and in what order.
///
/// A record matches when EVERY word of the query matches somewhere in it. For
/// each word the best field decides — an exact field beats a field that starts
/// with the word, which beats a word that starts with it, which beats the word
/// merely appearing inside — weighted by the field ([FieldWeight]): a name beats
/// a place beats a note. A multi-word query that appears, as written, inside one
/// field scores a bonus. Ties are broken by group, then title, then key, so the
/// order is the same every time, whatever order the records came in.
abstract final class SearchRanking {
  static const int exact = 100;
  static const int prefix = 80;
  static const int wordPrefix = 60;
  static const int contains = 30;

  /// Added when a multi-word query appears, as written, inside one field (one
  /// and a half times that when it is the whole field).
  static const double phraseBonus = 40;

  /// The items of [entries] that match every word of [tokens], best first.
  static List<T> rank<T>(Iterable<RankedEntry<T>> entries, List<String> tokens) {
    if (tokens.isEmpty) return <T>[];
    final phrase = tokens.length > 1 ? tokens.join(' ') : null;

    final scored = <_Scored<T>>[];
    for (final entry in entries) {
      final value = score(entry, tokens, phrase: phrase);
      if (value != null) scored.add(_Scored<T>(entry, value));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byGroup = a.entry.group.compareTo(b.entry.group);
      if (byGroup != 0) return byGroup;
      final byTitle = a.entry.titleKey.compareTo(b.entry.titleKey);
      if (byTitle != 0) return byTitle;
      return a.entry.key.compareTo(b.entry.key);
    });

    return scored.map((s) => s.entry.item).toList(growable: false);
  }

  /// The entry's score for [tokens], or null when any word matches nothing.
  static double? score(
    RankedEntry<Object?> entry,
    List<String> tokens, {
    String? phrase,
  }) {
    var total = 0.0;
    for (final token in tokens) {
      final best = _bestScore(entry, token);
      if (best <= 0) return null;
      total += best;
    }
    final whole = phrase ?? (tokens.length > 1 ? tokens.join(' ') : null);
    if (whole != null) {
      for (final field in entry.fields) {
        if (field.isNumber) continue;
        if (field.text == whole) {
          total += phraseBonus * 1.5;
          break;
        }
        if (field.text.contains(whole)) {
          total += phraseBonus;
          break;
        }
      }
    }
    return total;
  }

  static double _bestScore(RankedEntry<Object?> entry, String token) {
    var best = 0.0;
    final isNumeric = SearchText.isPhoneLike(token);
    final digits = isNumeric ? SearchText.digits(token) : '';

    for (final field in entry.fields) {
      final double score;
      if (field.isNumber) {
        // A number matches from its start only: "05" is not "1050".
        if (!isNumeric) continue;
        score = field.text == digits
            ? exact * field.weight.value
            : field.text.startsWith(digits)
                ? prefix * field.weight.value
                : 0.0;
      } else {
        score = level(field.text, token) * field.weight.value;
      }
      if (score > best) best = score;
    }

    if (isNumeric) {
      for (final form in entry.phoneForms) {
        final int matchLevel;
        if (form == digits) {
          matchLevel = exact;
        } else if (form.startsWith(digits)) {
          matchLevel = prefix;
        } else if (form.contains(digits)) {
          matchLevel = contains;
        } else {
          matchLevel = 0;
        }
        final score = matchLevel * FieldWeight.phone.value;
        if (score > best) best = score;
      }
    }
    return best;
  }

  /// How well [token] matches [text] (both folded): 100 when it is the whole
  /// field, 80 when the field starts with it, 60 when a word of the field does,
  /// 30 when it merely appears inside, 0 when it does not appear.
  static int level(String text, String token) {
    if (text == token) return exact;
    var at = text.indexOf(token);
    if (at < 0) return 0;
    if (at == 0) return prefix;
    var result = contains;
    while (at >= 0) {
      final before = text.codeUnitAt(at - 1);
      if (before == 0x20 ||
          before == 0x2C ||
          before == 0x2D ||
          before == 0x28) {
        result = wordPrefix;
        break;
      }
      at = text.indexOf(token, at + 1);
    }
    return result;
  }
}

class _Scored<T> {
  const _Scored(this.entry, this.score);

  final RankedEntry<T> entry;
  final double score;
}
