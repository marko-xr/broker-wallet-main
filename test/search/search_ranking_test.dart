// How Search matches and orders records, on synthetic records: every word must
// match in some field, the best field decides each word, a name beats a place
// beats a note, numbers match from their start, phone numbers match however they
// are written, and the order is the same every time. Pure Dart.

import 'dart:math';

import 'package:broker_wallet/src/common/utils/search_ranking.dart';
import 'package:broker_wallet/src/common/utils/search_text.dart';
import 'package:flutter_test/flutter_test.dart';

RankedEntry<String> _entry(
  String key, {
  String title = '',
  int group = 0,
  List<(String, FieldWeight)> fields = const [],
  List<String> numbers = const [],
  List<String> phones = const [],
}) =>
    RankedEntry<String>(
      fields: [
        for (final (text, weight) in fields)
          RankField(SearchText.fold(text), weight),
        for (final number in numbers)
          RankField(SearchText.digits(number), FieldWeight.number,
              isNumber: true),
      ],
      phoneForms: phones,
      group: group,
      titleKey: SearchText.fold(title),
      key: key,
      item: key,
    );

List<String> _rank(List<RankedEntry<String>> entries, String query) =>
    SearchRanking.rank(entries, SearchText.tokens(query));

void main() {
  group('levels', () {
    test('exact, prefix, word prefix, contains, none', () {
      expect(SearchRanking.level('sam', 'sam'), SearchRanking.exact);
      expect(SearchRanking.level('samir', 'sam'), SearchRanking.prefix);
      expect(SearchRanking.level('abu sam', 'sam'), SearchRanking.wordPrefix);
      expect(SearchRanking.level('misam', 'sam'), SearchRanking.contains);
      expect(SearchRanking.level('omar', 'sam'), 0);
    });

    test('a later word boundary beats an earlier mid-word match', () {
      // "sam" is inside "misam" first, then starts a word.
      expect(SearchRanking.level('misam sam', 'sam'), SearchRanking.wordPrefix);
    });

    test('words begin after a space, comma, hyphen or bracket', () {
      expect(SearchRanking.level('a,sam', 'sam'), SearchRanking.wordPrefix);
      expect(SearchRanking.level('a-sam', 'sam'), SearchRanking.wordPrefix);
      expect(SearchRanking.level('a(sam)', 'sam'), SearchRanking.wordPrefix);
    });
  });

  group('matching', () {
    test('every word must match, in any field, in any order', () {
      final entries = [
        _entry('r1', fields: [
          ('Villa', FieldWeight.primary),
          ('Dubai', FieldWeight.place),
        ]),
        _entry('r2', fields: [
          ('Villa', FieldWeight.primary),
          ('Abu Dhabi', FieldWeight.place),
        ]),
        _entry('r3', fields: [
          ('Studio', FieldWeight.primary),
          ('Dubai', FieldWeight.place),
        ]),
      ];
      expect(_rank(entries, 'villa dubai'), ['r1']);
      expect(_rank(entries, 'dubai villa'), ['r1']);
      expect(_rank(entries, 'villa').toSet(), {'r1', 'r2'});
      expect(_rank(entries, 'villa sharjah'), isEmpty);
    });

    test('no words, no results', () {
      expect(_rank([_entry('a', title: 'x')], ''), isEmpty);
      expect(SearchRanking.rank([_entry('a')], const <String>[]), isEmpty);
    });

    test('a field that is empty matches nothing', () {
      expect(
          _rank([
            _entry('a', fields: [('', FieldWeight.primary)])
          ], 'x'),
          isEmpty);
    });
  });

  group('numbers and phone numbers', () {
    test('a number matches from its start only', () {
      final entries = [
        _entry('r1', numbers: ['15000', '20500', '1050']),
      ];
      expect(_rank(entries, '05'), isEmpty);
      expect(_rank(entries, '5000'), isEmpty);
      expect(_rank(entries, '1500'), ['r1']);
      expect(_rank(entries, '1050'), ['r1']);
      expect(_rank(entries, '20500'), ['r1']);
    });

    test('a phone number matches in every form given', () {
      final entries = [
        _entry('o1', phones: ['501234567', '0501234567', '971501234567']),
      ];
      for (final query in [
        '501234567',
        '0501234567',
        '971501234567',
        '+971501234567',
        '12345',
        '05',
      ]) {
        expect(_rank(entries, query), ['o1'], reason: query);
      }
      expect(_rank(entries, '0501234560'), isEmpty);
    });

    test('a single digit is not a phone search', () {
      final entries = [
        _entry('o1', phones: ['0501234567']),
      ];
      expect(_rank(entries, '5'), isEmpty);
    });

    test('Arabic-Indic digits find the same number', () {
      final entries = [
        _entry('o1', phones: ['0501234567']),
      ];
      expect(_rank(entries, '٠٥٠١٢٣'), ['o1']);
    });

    test('an exact number beats a fragment of one', () {
      final entries = [
        _entry('fragment', phones: ['0509991234']),
        _entry('exact', phones: ['999']),
      ];
      expect(_rank(entries, '999'), ['exact', 'fragment']);
    });
  });

  group('ranking', () {
    test('exact, then prefix, then word-prefix, then contains', () {
      final entries = [
        _entry('contains', fields: [('Misam', FieldWeight.primary)]),
        _entry('word', fields: [('Abu Sam', FieldWeight.primary)]),
        _entry('prefix', fields: [('Samir', FieldWeight.primary)]),
        _entry('exact', fields: [('Sam', FieldWeight.primary)]),
      ];
      expect(_rank(entries, 'sam'), ['exact', 'prefix', 'word', 'contains']);
    });

    test('a name outranks a place outranks a note', () {
      final entries = [
        _entry('note', fields: [('friend of marina', FieldWeight.note)]),
        _entry('place', fields: [('marina', FieldWeight.place)]),
        _entry('name', fields: [('Marina', FieldWeight.primary)]),
      ];
      expect(_rank(entries, 'marina'), ['name', 'place', 'note']);
    });

    test('a number field counts less than a name', () {
      final entries = [
        _entry('size', numbers: ['1200']),
        _entry('name', fields: [('1200 Tower', FieldWeight.primary)]),
      ];
      expect(_rank(entries, '1200'), ['name', 'size']);
    });

    test('a phrase written as typed outranks the same words scattered', () {
      final entries = [
        _entry('scattered',
            fields: [('Marina Dubai Tower', FieldWeight.primary)]),
        _entry('phrase', fields: [('Dubai Marina Tower', FieldWeight.primary)]),
      ];
      expect(_rank(entries, 'dubai marina'), ['phrase', 'scattered']);
    });

    test('the whole field as typed outranks the phrase inside a longer one',
        () {
      final entries = [
        _entry('inside', fields: [('Dubai Marina Tower', FieldWeight.primary)]),
        _entry('whole', fields: [('Dubai Marina', FieldWeight.primary)]),
      ];
      expect(_rank(entries, 'dubai marina'), ['whole', 'inside']);
    });

    test('Arabic spellings rank like their folded form', () {
      final entries = [
        _entry('b', fields: [('مُحَمَّد علي', FieldWeight.primary)]),
        _entry('a', fields: [('محمد', FieldWeight.primary)]),
      ];
      expect(_rank(entries, 'مـحـمـد'), ['a', 'b']);
    });
  });

  group('order is stable', () {
    test('ties go by group, then title, then key', () {
      final entries = [
        _entry('b2',
            title: 'Sam', group: 1, fields: [('Sam', FieldWeight.primary)]),
        _entry('a2',
            title: 'Sam', group: 0, fields: [('Sam', FieldWeight.primary)]),
        _entry('a1',
            title: 'Sam', group: 0, fields: [('Sam', FieldWeight.primary)]),
        _entry('a0',
            title: 'Adam', group: 0, fields: [('Sam', FieldWeight.primary)]),
      ];
      expect(_rank(entries, 'sam'), ['a0', 'a1', 'a2', 'b2']);
    });

    test('the same input in any order gives the same output', () {
      final entries = [
        for (var i = 0; i < 40; i++)
          _entry(
            'k$i',
            title: 'Sam ${i % 7}',
            group: i % 3,
            fields: [('Sam ${i % 7}', FieldWeight.primary)],
          ),
      ];
      final expected = _rank(entries, 'sam');
      expect(expected, hasLength(40));
      for (var seed = 1; seed <= 8; seed++) {
        final shuffled = [...entries]..shuffle(Random(seed));
        expect(_rank(shuffled, 'sam'), expected, reason: 'seed $seed');
      }
    });

    test('ranking does not change the entries it is given', () {
      final entries = [
        _entry('a', fields: [('Sam', FieldWeight.primary)]),
        _entry('b', fields: [('Misam', FieldWeight.primary)]),
      ];
      final before = entries.map((e) => e.key).toList();
      _rank(entries, 'sam');
      expect(entries.map((e) => e.key).toList(), before);
    });
  });
}
