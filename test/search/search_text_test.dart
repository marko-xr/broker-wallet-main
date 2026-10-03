// How Search compares text: folding for comparison only, the words of a query,
// and the ranges a highlight covers. Pure Dart; no widgets, no backend.
//
// Arabic cases are written with the real letters on purpose: the point is what a
// person types on an Arabic keyboard, not an escaped approximation of it.

import 'package:broker_wallet/src/common/utils/search_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fold: English and whitespace', () {
    test('lower-cases', () {
      expect(SearchText.fold('Dubai MARINA'), 'dubai marina');
      expect(SearchText.fold('Café'), 'café');
    });

    test('trims and collapses whitespace of every kind', () {
      expect(SearchText.fold('   dubai  '), 'dubai');
      expect(SearchText.fold('dubai    marina'), 'dubai marina');
      expect(SearchText.fold('dubai\tmarina\n'), 'dubai marina');
      // A non-breaking space, which a phone keyboard can type.
      expect(SearchText.fold('dubai  marina'), 'dubai marina');
      expect(SearchText.fold('   '), '');
      expect(SearchText.fold(''), '');
    });

    test('drops invisible direction marks', () {
      expect(SearchText.fold('‏dubai‎'), 'dubai');
      expect(SearchText.fold('du​bai'), 'dubai');
      expect(SearchText.fold('﻿dubai'), 'dubai');
    });

    test('leaves punctuation and digits inside words alone', () {
      expect(SearchText.fold('Arabian Ranches 3'), 'arabian ranches 3');
      expect(SearchText.fold('A-1'), 'a-1');
    });
  });

  group('fold: Arabic', () {
    test('removes diacritics', () {
      expect(SearchText.fold('مُحَمَّد'), 'محمد');
      expect(SearchText.fold('دُبَيّ'), 'دبي');
    });

    test('removes tatweel', () {
      expect(SearchText.fold('مـحـمـد'), 'محمد');
      expect(SearchText.fold('دبــي'), 'دبي');
    });

    test('Alef variants are one letter', () {
      final variants = ['أحمد', 'احمد', 'إحمد', 'آحمد', 'ٱحمد'];
      final folded = variants.map(SearchText.fold).toSet();
      expect(folded, {'احمد'});
    });

    test('Yeh and Alef Maqsura are one letter', () {
      expect(SearchText.fold('دبى'), SearchText.fold('دبي'));
      expect(SearchText.fold('مصطفى'), SearchText.fold('مصطفي'));
    });

    test('Teh Marbuta and Heh are one letter', () {
      expect(SearchText.fold('الشارقة'), SearchText.fold('الشارقه'));
      expect(SearchText.fold('فيلا'), 'فيلا', reason: 'Alef itself is kept');
    });

    test('does not over-normalize: hamza on Waw and Yeh is kept', () {
      // These are different words; folding them together would make unrelated
      // names match each other.
      expect(SearchText.fold('مؤمن'), isNot(SearchText.fold('مومن')));
      expect(SearchText.fold('رئيس'), isNot(SearchText.fold('ريس')));
      expect(SearchText.fold('سؤال'), isNot(SearchText.fold('سوال')));
    });

    test('does not merge different letters', () {
      expect(SearchText.fold('عمان'), isNot(SearchText.fold('امان')));
      expect(SearchText.fold('كلب'), isNot(SearchText.fold('قلب')));
    });

    test('Arabic-Indic digits become digits', () {
      expect(SearchText.fold('٠٥٥ ١٢٣'), '055 123');
      expect(SearchText.fold('۰۵۵'), '055');
      expect(SearchText.digits('٠٥٥-١٢٣'), '055123');
      expect(SearchText.digits('+971 (50) 123'), '97150123');
    });

    test('is the same for the data and the query', () {
      // Whatever is stored, a differently spelled query lands on the same text.
      expect(SearchText.fold('أَبُو ظَبْي'), SearchText.fold('ابو ظبي'));
    });
  });

  group('tokens', () {
    test('splits on whitespace and folds', () {
      expect(SearchText.tokens('Dubai Marina'), ['dubai', 'marina']);
      expect(SearchText.tokens('  dubai   marina  '), ['dubai', 'marina']);
    });

    test('splits on the separators people type', () {
      expect(SearchText.tokens('marina, dubai'), ['marina', 'dubai']);
      expect(SearchText.tokens('marina;dubai'), ['marina', 'dubai']);
      expect(SearchText.tokens('marina/dubai'), ['marina', 'dubai']);
      expect(SearchText.tokens('al-ain'), ['al', 'ain']);
      expect(SearchText.tokens('(dubai)'), ['dubai']);
      expect(SearchText.tokens('"dubai marina"'), ['dubai', 'marina']);
    });

    test('splits on the Arabic comma and semicolon', () {
      expect(SearchText.tokens('دبي،مارينا'), ['دبي', 'مارينا']);
      expect(SearchText.tokens('دبي؛مارينا'), ['دبي', 'مارينا']);
    });

    test('trims stray punctuation off a word', () {
      expect(SearchText.tokens('dubai.'), ['dubai']);
      expect(SearchText.tokens('dubai!?'), ['dubai']);
      expect(SearchText.tokens("'dubai'"), ['dubai']);
    });

    test('a query with nothing to search for has no tokens', () {
      expect(SearchText.tokens(''), isEmpty);
      expect(SearchText.tokens('   '), isEmpty);
      expect(SearchText.tokens('...'), isEmpty);
      expect(SearchText.tokens(' , ; '), isEmpty);
      expect(SearchText.tokens('‏‎'), isEmpty);
    });

    test('a phone number keeps its plus', () {
      expect(SearchText.tokens('+971 50'), ['+971', '50']);
      expect(SearchText.tokens('٠٥٥'), ['055']);
    });

    test('is unmodifiable', () {
      expect(() => SearchText.tokens('a b').add('c'), throwsUnsupportedError);
    });
  });

  group('collapse', () {
    test('trims and collapses but keeps case and letters', () {
      expect(SearchText.collapse('  Dubai   Marina '), 'Dubai Marina');
      expect(SearchText.collapse('أَحمد'), 'أَحمد');
      expect(SearchText.collapse('‏abc‎'), 'abc');
      expect(SearchText.collapse('   '), '');
    });
  });

  group('isPhoneLike', () {
    test('digits, optionally led by a plus, at least two', () {
      expect(SearchText.isPhoneLike('05'), isTrue);
      expect(SearchText.isPhoneLike('0501234567'), isTrue);
      expect(SearchText.isPhoneLike('+971'), isTrue);
    });

    test('anything else is not', () {
      expect(SearchText.isPhoneLike('5'), isFalse);
      expect(SearchText.isPhoneLike('+'), isFalse);
      expect(SearchText.isPhoneLike('05a'), isFalse);
      expect(SearchText.isPhoneLike('97+1'), isFalse);
      expect(SearchText.isPhoneLike('villa'), isFalse);
      expect(SearchText.isPhoneLike(''), isFalse);
    });
  });

  group('highlightRanges', () {
    String mark(String text, List<(int, int)> ranges) =>
        ranges.map((r) => text.substring(r.$1, r.$2)).join('|');

    test('marks every occurrence, any case', () {
      const text = 'Dubai Marina, dubai';
      final ranges = SearchText.highlightRanges(text, ['dubai']);
      expect(mark(text, ranges), 'Dubai|dubai');
    });

    test('marks each word of a multi-word query', () {
      const text = 'Villa in Dubai Marina';
      final ranges = SearchText.highlightRanges(text, ['villa', 'marina']);
      expect(mark(text, ranges), 'Villa|Marina');
    });

    test('merges overlapping and touching ranges', () {
      const text = 'abcdef';
      final ranges = SearchText.highlightRanges(text, ['abc', 'cde', 'f']);
      // abc + cde overlap, and f touches their end: one range.
      expect(ranges, [(0, 6)]);
      expect(mark(text, ranges), 'abcdef');
    });

    test('maps folded matches back onto the original text', () {
      // The query has no diacritics; the text does. The marked part is the
      // original word, diacritics and all.
      const text = 'مُحَمَّد علي';
      final ranges = SearchText.highlightRanges(text, ['محمد']);
      expect(mark(text, ranges), 'مُحَمَّد');
      expect(ranges.first.$1, 0);
    });

    test('maps Alef variants and Arabic digits', () {
      const text = 'أحمد 055';
      expect(mark(text, SearchText.highlightRanges(text, ['احمد'])), 'أحمد');
      // The highlighter is given the query's tokens, which are folded.
      final tokens = SearchText.tokens('٠٥٥');
      expect(mark(text, SearchText.highlightRanges(text, tokens)), '055');
    });

    test('reads a phone number across its formatting', () {
      const text = 'Call 050-123 4567 now';
      final ranges = SearchText.highlightRanges(text, ['0501234567']);
      expect(mark(text, ranges), '050-123 4567');
    });

    test('a fragment of a formatted number', () {
      const text = '050-123 4567';
      final ranges = SearchText.highlightRanges(text, ['123']);
      expect(mark(text, ranges), '123');
    });

    test('nothing to mark', () {
      expect(SearchText.highlightRanges('Dubai', ['zzz']), isEmpty);
      expect(SearchText.highlightRanges('Dubai', const <String>[]), isEmpty);
      expect(SearchText.highlightRanges('', ['dubai']), isEmpty);
    });

    test('ranges are valid, ordered and inside the text', () {
      const text = 'Arabian Ranches 3, Dubai - Villa 3';
      final ranges = SearchText.highlightRanges(text, ['3', 'villa', 'dubai']);
      var previousEnd = 0;
      for (final range in ranges) {
        expect(range.$1, greaterThanOrEqualTo(previousEnd));
        expect(range.$2, greaterThan(range.$1));
        expect(range.$2, lessThanOrEqualTo(text.length));
        previousEnd = range.$2;
      }
    });
  });
}
