/// How Search compares text. This is for COMPARISON ONLY: stored values are
/// never rewritten, only a folded copy is matched against a folded query.
///
/// Folding makes the two spellings a person can type the same thing:
///
///  * letters are lower-cased;
///  * Arabic diacritics (tashkeel) and the tatweel stretch are dropped;
///  * the Alef variants (أ إ آ ٱ) become a plain Alef (ا), Alef Maqsura (ى)
///    becomes Yeh (ي) and Teh Marbuta (ة) becomes Heh (ه), the usual search
///    equivalences, applied to the query and to the data alike;
///  * Arabic-Indic digits (٠-٩, ۰-۹) become 0-9, so a phone number typed on an
///    Arabic keyboard finds the same record;
///  * the invisible direction marks that RTL typing can leave in a string are
///    dropped, and any run of whitespace is one space.
///
/// Nothing else is changed: hamza on waw/yeh and the rest are NOT folded, so
/// unrelated words are not made to match.
abstract final class SearchText {
  /// [text] folded for comparison. Trimmed; whitespace collapsed.
  static String fold(String text) {
    final out = StringBuffer();
    _foldInto(text, out, null);
    return _trimmed(out.toString());
  }

  /// The words of a query: [fold]ed, split on whitespace and on the separators
  /// people type between words (`, ؛ ; : / \ | ( ) [ ] { } " “ ” -`), with
  /// stray punctuation trimmed off each end. Empty when the query has nothing
  /// to search for — blank, or only punctuation.
  static List<String> tokens(String query) {
    final folded = fold(query);
    if (folded.isEmpty) return const <String>[];
    final words = <String>[];
    final word = StringBuffer();
    void flush() {
      if (word.isEmpty) return;
      final trimmed = _trimPunctuation(word.toString());
      if (trimmed.isNotEmpty) words.add(trimmed);
      word.clear();
    }

    for (var i = 0; i < folded.length; i++) {
      final unit = folded.codeUnitAt(i);
      if (_isSeparator(unit)) {
        flush();
      } else {
        word.writeCharCode(unit);
      }
    }
    flush();
    return List<String>.unmodifiable(words);
  }

  /// [text] as the user typed it, trimmed and with whitespace collapsed — what
  /// to show back as "Results for …". Not folded: case and letters are kept.
  static String collapse(String text) {
    final out = StringBuffer();
    var lastWasSpace = true;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (_isInvisibleMark(unit)) continue;
      if (_isSpace(unit)) {
        if (!lastWasSpace) out.write(' ');
        lastWasSpace = true;
      } else {
        out.writeCharCode(unit);
        lastWasSpace = false;
      }
    }
    return _trimmed(out.toString());
  }

  /// Only the digits of [text] (Arabic-Indic ones read as 0-9).
  static String digits(String text) {
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0x30 && unit <= 0x39) {
        out.writeCharCode(unit);
      } else if (unit >= 0x0660 && unit <= 0x0669) {
        out.writeCharCode(0x30 + (unit - 0x0660));
      } else if (unit >= 0x06F0 && unit <= 0x06F9) {
        out.writeCharCode(0x30 + (unit - 0x06F0));
      }
    }
    return out.toString();
  }

  /// Whether [token] is a number or a phone-number fragment: digits, with an
  /// optional leading `+`, and at least two digits.
  static bool isPhoneLike(String token) {
    if (token.length < 2) return false;
    var digitCount = 0;
    for (var i = 0; i < token.length; i++) {
      final unit = token.codeUnitAt(i);
      if (unit >= 0x30 && unit <= 0x39) {
        digitCount++;
      } else if (!(unit == 0x2B && i == 0)) {
        return false;
      }
    }
    return digitCount >= 2;
  }

  /// The parts of [text] a search for [tokens] matched, as `[start, end)` ranges
  /// into [text] itself, sorted and merged. A word is highlighted wherever it
  /// occurs in the folded text; a phone-like token is highlighted across the
  /// spaces and dashes of a formatted number. Tokens are as [tokens] returns.
  static List<(int, int)> highlightRanges(String text, List<String> tokens) {
    if (text.isEmpty || tokens.isEmpty) return const <(int, int)>[];
    final folded = StringBuffer();
    final origin = <int>[];
    _foldInto(text, folded, origin);
    final foldedText = folded.toString();

    final ranges = <(int, int)>[];

    void addFolded(int start, int end) {
      if (end <= start || start >= origin.length) return;
      final last = end - 1 < origin.length ? end - 1 : origin.length - 1;
      ranges.add((origin[start], origin[last] + 1));
    }

    for (final token in tokens) {
      if (token.isEmpty) continue;
      var from = 0;
      while (true) {
        final at = foldedText.indexOf(token, from);
        if (at < 0) break;
        addFolded(at, at + token.length);
        from = at + token.length;
      }

      if (isPhoneLike(token)) {
        final wanted = digits(token);
        // Positions (in the folded text) of every digit, to read a number
        // across its formatting.
        final digitAt = <int>[];
        final digitText = StringBuffer();
        for (var i = 0; i < foldedText.length; i++) {
          final unit = foldedText.codeUnitAt(i);
          if (unit >= 0x30 && unit <= 0x39) {
            digitAt.add(i);
            digitText.writeCharCode(unit);
          }
        }
        final run = digitText.toString();
        var searchFrom = 0;
        while (wanted.isNotEmpty) {
          final at = run.indexOf(wanted, searchFrom);
          if (at < 0) break;
          addFolded(digitAt[at], digitAt[at + wanted.length - 1] + 1);
          searchFrom = at + wanted.length;
        }
      }
    }

    if (ranges.isEmpty) return const <(int, int)>[];
    ranges.sort(
        (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final merged = <(int, int)>[ranges.first];
    for (final range in ranges.skip(1)) {
      final last = merged.last;
      if (range.$1 <= last.$2) {
        if (range.$2 > last.$2) merged[merged.length - 1] = (last.$1, range.$2);
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  // ---------------------------------------------------------------------------

  /// Folds [text] into [out]. When [origin] is given it receives, for every
  /// emitted code unit, the index of the code unit of [text] it came from.
  static void _foldInto(String text, StringBuffer out, List<int>? origin) {
    var lastWasSpace = true;

    void emit(int unit, int from) {
      out.writeCharCode(unit);
      origin?.add(from);
    }

    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);

      if (_isInvisibleMark(unit)) continue;
      if (_isSpace(unit)) {
        if (!lastWasSpace) emit(0x20, i);
        lastWasSpace = true;
        continue;
      }

      // ASCII: lower-case without allocating.
      if (unit < 0x80) {
        emit(unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit, i);
        lastWasSpace = false;
        continue;
      }

      // Arabic block: the search equivalences.
      if (unit >= 0x0600 && unit <= 0x06FF) {
        final mapped = _foldArabic(unit);
        if (mapped == null) continue; // a mark that is dropped
        emit(mapped, i);
        lastWasSpace = false;
        continue;
      }

      // Anything else: ordinary lower-casing, which can be more than one unit.
      if (unit >= 0xD800 && unit <= 0xDFFF) {
        emit(unit, i); // part of a surrogate pair: copied as it is
      } else {
        final lowered = String.fromCharCode(unit).toLowerCase();
        for (var k = 0; k < lowered.length; k++) {
          emit(lowered.codeUnitAt(k), i);
        }
      }
      lastWasSpace = false;
    }
  }

  /// The folded form of one Arabic-block code unit; null when it is dropped.
  static int? _foldArabic(int unit) {
    // Tatweel and the diacritics.
    if (unit == 0x0640) return null;
    if (unit >= 0x064B && unit <= 0x065F) return null;
    if (unit == 0x0670) return null;
    if (unit >= 0x06D6 && unit <= 0x06DC) return null;
    if (unit >= 0x06DF && unit <= 0x06E8) return null;
    if (unit >= 0x06EA && unit <= 0x06ED) return null;

    switch (unit) {
      case 0x0622: // آ
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0671: // ٱ
        return 0x0627; // ا
      case 0x0629: // ة
        return 0x0647; // ه
      case 0x0649: // ى
        return 0x064A; // ي
      case 0x060C: // ،
      case 0x061B: // ؛
        return 0x2C; // , ;
    }

    // Arabic-Indic and Extended Arabic-Indic digits.
    if (unit >= 0x0660 && unit <= 0x0669) return 0x30 + (unit - 0x0660);
    if (unit >= 0x06F0 && unit <= 0x06F9) return 0x30 + (unit - 0x06F0);

    return unit;
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 ||
      (unit >= 0x09 && unit <= 0x0D) ||
      unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000;

  /// Zero-width and direction marks, which are never part of what was meant.
  static bool _isInvisibleMark(int unit) =>
      (unit >= 0x200B && unit <= 0x200F) ||
      (unit >= 0x202A && unit <= 0x202E) ||
      unit == 0x2060 ||
      (unit >= 0x2066 && unit <= 0x2069) ||
      unit == 0xFEFF;

  /// Characters that separate query words (the text is already folded, so the
  /// Arabic comma and semicolon are `,` and `;` by now).
  static bool _isSeparator(int unit) {
    switch (unit) {
      case 0x20: // space
      case 0x2C: // ,
      case 0x3B: // ;
      case 0x3A: // :
      case 0x2F: // /
      case 0x5C: // \
      case 0x7C: // |
      case 0x28: // (
      case 0x29: // )
      case 0x5B: // [
      case 0x5D: // ]
      case 0x7B: // {
      case 0x7D: // }
      case 0x22: // "
      case 0x201C: // “
      case 0x201D: // ”
      case 0x2D: // -
      case 0x5F: // _
        return true;
    }
    return false;
  }

  static String _trimmed(String text) =>
      text.endsWith(' ') ? text.substring(0, text.length - 1) : text;

  /// Removes sentence punctuation from both ends of a word, keeping a leading
  /// `+` (a phone number's) and anything inside the word.
  static String _trimPunctuation(String word) {
    var start = 0;
    var end = word.length;
    bool strip(int unit) =>
        unit == 0x2E || // .
        unit == 0x21 || // !
        unit == 0x3F || // ?
        unit == 0x27 || // '
        unit == 0x2019 || // ’
        unit == 0x2018 || // ‘
        unit == 0x60; // `
    while (start < end && strip(word.codeUnitAt(start))) {
      start++;
    }
    while (end > start && strip(word.codeUnitAt(end - 1))) {
      end--;
    }
    return word.substring(start, end);
  }
}
