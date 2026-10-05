// The Home filters' rules — Recently Added, Less Price, This Week — as pure
// functions: the records and "now" go in, a list comes out, always in the same
// order. Plain Dart: no backend, no clock, no widget.

import 'package:broker_wallet/src/data/models/unified_item_model.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Sunday at noon, UTC. Every age below is measured back from here.
final DateTime now = DateTime.utc(2026, 10, 4, 12);

const Duration hour = Duration(hours: 1);
const Duration day = Duration(days: 1);

UnifiedItemModel record(
  ItemType type,
  String id, {
  Duration age = Duration.zero,
  DateTime? at,
  bool known = true,
  double? min,
  double? max,
}) {
  final created = at ?? now.subtract(age);
  return UnifiedItemModel(
    id: id,
    title: id,
    subtitle: '',
    type: type,
    createdAt: created,
    updatedAt: created,
    hasCreatedAt: known,
    minPrice: min,
    maxPrice: max,
    originalModel: null,
  );
}

List<String> ids(Iterable<UnifiedItemModel> items) =>
    [for (final item in items) item.id];

List<UnifiedItemModel> recently(Iterable<UnifiedItemModel> items,
        {DateTime? at}) =>
    HomeFilterRules.apply(HomeFilterKind.recentlyAdded, items, now: at ?? now);

List<UnifiedItemModel> thisWeek(Iterable<UnifiedItemModel> items) =>
    HomeFilterRules.apply(HomeFilterKind.thisWeek, items, now: now);

List<UnifiedItemModel> cheapest(Iterable<UnifiedItemModel> items) =>
    HomeFilterRules.apply(HomeFilterKind.lessPrice, items, now: now);

/// The filters that have an implementation, in chip order.
final List<HomeFilterKind> implemented = [
  for (final kind in HomeFilterKind.values)
    if (kind.isImplemented) kind,
];

/// What [body] throws, or null if it does not.
Object? thrownBy(void Function() body) {
  try {
    body();
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  group('the definitions', () {
    test('Recently Added is 12 hours, This Week 7 days, Less Price keeps 6',
        () {
      expect(HomeFilterRules.recentlyAddedWindow, const Duration(hours: 12));
      expect(HomeFilterRules.thisWeekWindow, const Duration(days: 7));
      expect(HomeFilterRules.lessPriceLimit, 6);
    });

    test('the chips are the three filters, then the two still to be built', () {
      expect(
        [for (final kind in HomeFilterKind.values) kind.labelKey],
        [
          'recentlyAdded',
          'lessPrice',
          'thisWeek',
          'highestPrice',
          'recentlyUpdated',
        ],
      );
      expect(
        [for (final kind in HomeFilterKind.values) kind.label],
        [
          'Recently Added',
          'Less Price',
          'This Week',
          'Highest Price',
          'Recently Updated',
        ],
      );
    });

    test('only the first three have a filter behind them', () {
      expect(
        [for (final kind in HomeFilterKind.values) kind.isImplemented],
        [true, true, true, false, false],
      );
    });

    test('each filter reads only the kinds of record it needs', () {
      const all = [
        ItemType.request,
        ItemType.offer,
        ItemType.broker,
        ItemType.owner,
        ItemType.office,
        ItemType.watchmen,
      ];
      expect(HomeFilterRules.filterable, all);
      expect(HomeFilterRules.typesFor(HomeFilterKind.recentlyAdded), all);
      expect(HomeFilterRules.typesFor(HomeFilterKind.thisWeek), all);
      // Only Requests and Offers carry a price.
      expect(HomeFilterRules.typesFor(HomeFilterKind.lessPrice),
          [ItemType.request, ItemType.offer]);
    });

    test('Quotations are outside every filter, and so are never read', () {
      expect(HomeFilterRules.filterable.contains(ItemType.quotation), isFalse);
      expect(HomeFilterRules.priced.contains(ItemType.quotation), isFalse);
      for (final kind in implemented) {
        expect(HomeFilterRules.typesFor(kind).contains(ItemType.quotation),
            isFalse,
            reason: kind.name);
      }
    });
  });

  group('a chip whose filter is not built yet', () {
    for (final kind in [
      HomeFilterKind.highestPrice,
      HomeFilterKind.recentlyUpdated,
    ]) {
      test('${kind.name} has no records to read and no answer to give', () {
        // Neither call may return something that would pass for an answer: an
        // empty list would read as "nothing found".
        expect(thrownBy(() => HomeFilterRules.typesFor(kind)),
            isA<UnsupportedError>());
        expect(
          thrownBy(() => HomeFilterRules.apply(
                kind,
                [record(ItemType.offer, 'a', age: hour, min: 10)],
                now: now,
              )),
          isA<UnsupportedError>(),
        );
      });
    }

    test('the three that are built are the ones that can be asked', () {
      expect(implemented, [
        HomeFilterKind.recentlyAdded,
        HomeFilterKind.lessPrice,
        HomeFilterKind.thisWeek,
      ]);
      for (final kind in implemented) {
        expect(thrownBy(() => HomeFilterRules.typesFor(kind)), isNull,
            reason: kind.name);
      }
    });
  });

  group('Recently Added', () {
    test('keeps a record created inside the last 12 hours', () {
      expect(
        ids(recently([
          record(ItemType.offer, 'new', age: const Duration(minutes: 1)),
          record(ItemType.offer, 'eleven', age: const Duration(hours: 11)),
        ])),
        containsAll(['new', 'eleven']),
      );
    });

    test('drops a record older than 12 hours', () {
      expect(
        recently([
          record(ItemType.offer, 'old',
              age: const Duration(hours: 12, minutes: 1)),
          record(ItemType.request, 'older', age: const Duration(days: 3)),
        ]),
        isEmpty,
      );
    });

    test('the boundary is explicit: exactly 12 hours old is out', () {
      final exactly = record(ItemType.offer, 'exactly',
          age: HomeFilterRules.recentlyAddedWindow);
      final justInside = record(ItemType.offer, 'inside',
          age: HomeFilterRules.recentlyAddedWindow -
              const Duration(microseconds: 1));
      final justOutside = record(ItemType.offer, 'outside',
          age: HomeFilterRules.recentlyAddedWindow +
              const Duration(microseconds: 1));
      expect(ids(recently([exactly, justInside, justOutside])), ['inside']);
    });

    test('combines every kind of record, grouped in the order Home lists them',
        () {
      final items = [
        record(ItemType.watchmen, 'w', age: hour),
        record(ItemType.office, 'f', age: hour),
        record(ItemType.owner, 'o', age: hour),
        record(ItemType.broker, 'b', age: hour),
        record(ItemType.offer, 'offer', age: hour),
        record(ItemType.request, 'req', age: hour),
      ];
      expect(ids(recently(items)), ['req', 'offer', 'b', 'o', 'f', 'w']);
    });

    test('inside a kind the newest comes first', () {
      final items = [
        record(ItemType.offer, 'old', age: const Duration(hours: 9)),
        record(ItemType.offer, 'newest', age: const Duration(minutes: 5)),
        record(ItemType.offer, 'middle', age: const Duration(hours: 3)),
      ];
      expect(ids(recently(items)), ['newest', 'middle', 'old']);
    });

    test('equal creation times fall back to the id, so the order is stable',
        () {
      final items = [
        record(ItemType.offer, 'b', age: hour),
        record(ItemType.offer, 'a', age: hour),
      ];
      expect(ids(recently(items)), ['a', 'b']);
      expect(ids(recently(items.reversed)), ['a', 'b']);
    });

    test('a record dated slightly ahead of this clock is recent, not dropped',
        () {
      // A phone whose clock runs behind the server's.
      expect(
        ids(recently([record(ItemType.offer, 'ahead', age: hour * -5)])),
        ['ahead'],
      );
    });

    test('uses the clock it is given, never its own', () {
      final items = [record(ItemType.offer, 'a', age: hour)];
      expect(ids(recently(items)), ['a']);
      expect(recently(items, at: now.add(const Duration(hours: 12))), isEmpty);
    });

    test('a timestamp held in local time is the same instant as in UTC', () {
      final instant = now.subtract(const Duration(hours: 2));
      final items = [
        record(ItemType.offer, 'utc', at: instant.toUtc()),
        record(ItemType.request, 'local', at: instant.toLocal()),
      ];
      expect(ids(recently(items)), ['local', 'utc']);
      final stale = now.subtract(const Duration(hours: 13));
      expect(
        recently([
          record(ItemType.offer, 'utc', at: stale.toUtc()),
          record(ItemType.offer, 'local', at: stale.toLocal()),
        ]),
        isEmpty,
      );
    });

    test('a record with no creation time of its own is never recent', () {
      // Its createdAt is only a stand-in (today's date); it proves nothing.
      final unknown = record(ItemType.broker, 'unknown', known: false);
      expect(unknown.createdAt, now);
      expect(recently([unknown]), isEmpty);
      expect(
        ids(recently([unknown, record(ItemType.broker, 'known', age: hour)])),
        ['known'],
      );
    });
  });

  group('This Week', () {
    test('keeps a record created inside the last 7 days', () {
      expect(
        ids(thisWeek([
          record(ItemType.offer, 'today', age: hour),
          record(ItemType.offer, 'six-days', age: const Duration(days: 6)),
          record(ItemType.owner, 'almost',
              age: const Duration(days: 6, hours: 23)),
        ])),
        containsAll(['today', 'six-days', 'almost']),
      );
    });

    test('drops a record older than 7 days', () {
      expect(
        thisWeek([
          record(ItemType.offer, 'a', age: const Duration(days: 7, hours: 1)),
          record(ItemType.request, 'b', age: const Duration(days: 30)),
        ]),
        isEmpty,
      );
    });

    test('the boundary is explicit: exactly 7 x 24 hours old is out', () {
      final exactly = record(ItemType.offer, 'exactly',
          age: HomeFilterRules.thisWeekWindow);
      final justInside = record(ItemType.offer, 'inside',
          age:
              HomeFilterRules.thisWeekWindow - const Duration(microseconds: 1));
      expect(ids(thisWeek([exactly, justInside])), ['inside']);
    });

    test('is the last 7 days, not the calendar week', () {
      // A Wednesday at noon. The Friday before is 5 days and 3 hours back: it
      // is inside, although no calendar week (Monday- or Sunday-based) holds
      // both days. The Tuesday before that is 8 days and 1 hour back: outside.
      final wednesday = DateTime.utc(2026, 10, 7, 12);
      final fridayBefore = DateTime.utc(2026, 10, 2, 9);
      final tuesdayBefore = DateTime.utc(2026, 9, 29, 11);
      final kept = HomeFilterRules.apply(
        HomeFilterKind.thisWeek,
        [
          record(ItemType.offer, 'friday', at: fridayBefore),
          record(ItemType.offer, 'tuesday', at: tuesdayBefore),
        ],
        now: wednesday,
      );
      expect(ids(kept), ['friday']);
    });

    test('everything recently added is also this week', () {
      final items = [
        record(ItemType.request, 'r', age: const Duration(hours: 2)),
        record(ItemType.broker, 'b', age: const Duration(hours: 11)),
        record(ItemType.office, 'o', age: const Duration(days: 2)),
        record(ItemType.owner, 'old', age: const Duration(days: 9)),
      ];
      final week = ids(thisWeek(items));
      for (final id in ids(recently(items))) {
        expect(week.contains(id), isTrue, reason: id);
      }
      expect(week.contains('o'), isTrue);
      expect(week.contains('old'), isFalse);
    });

    test('groups by kind and puts the newest first, like Recently Added', () {
      final items = [
        record(ItemType.owner, 'owner-old', age: const Duration(days: 5)),
        record(ItemType.owner, 'owner-new', age: const Duration(days: 1)),
        record(ItemType.request, 'request', age: const Duration(days: 3)),
      ];
      expect(ids(thisWeek(items)), ['request', 'owner-new', 'owner-old']);
    });

    test('a record with no creation time of its own is never this week', () {
      expect(thisWeek([record(ItemType.watchmen, 'unknown', known: false)]),
          isEmpty);
    });
  });

  group('Less Price', () {
    test('looks only at Requests and Offers', () {
      final items = [
        record(ItemType.broker, 'broker', min: 1),
        record(ItemType.owner, 'owner', min: 1),
        record(ItemType.office, 'office', min: 1),
        record(ItemType.watchmen, 'watchman', min: 1),
        record(ItemType.request, 'request', min: 500),
        record(ItemType.offer, 'offer', min: 400),
      ];
      expect(ids(cheapest(items)), ['offer', 'request']);
    });

    test('ranks by the average of the range, or by the one price given', () {
      final items = [
        record(ItemType.offer, 'range', min: 100, max: 300), // 200
        record(ItemType.request, 'only-min', min: 150), // 150
        record(ItemType.offer, 'only-max', max: 250), // 250
      ];
      expect(ids(cheapest(items)), ['only-min', 'range', 'only-max']);
    });

    test('compares prices as numbers, never as text', () {
      final items = [
        record(ItemType.offer, 'one-million', min: 1000000),
        record(ItemType.offer, 'nine-hundred', min: 900),
        record(ItemType.offer, 'eighty-five-thousand', min: 85000),
      ];
      // As text "1000000" < "85000" < "900".
      expect(ids(cheapest(items)),
          ['nine-hundred', 'eighty-five-thousand', 'one-million']);
    });

    test('a record with no usable price is never the lowest price', () {
      final items = [
        record(ItemType.offer, 'none'),
        record(ItemType.offer, 'zero', min: 0, max: 0),
        record(ItemType.offer, 'negative', min: -50, max: 0),
        record(ItemType.offer, 'not-a-number', min: double.nan),
        record(ItemType.offer, 'infinite', max: double.infinity),
        record(ItemType.request, 'valid', min: 10),
      ];
      expect(ids(cheapest(items)), ['valid']);
    });

    test('equal prices: newest first, then the kind, then the id', () {
      final items = [
        record(ItemType.offer, 'offer-old', min: 100, age: hour * 5),
        record(ItemType.offer, 'offer-new', min: 100, age: hour),
        record(ItemType.request, 'request-old', min: 100, age: hour * 5),
        record(ItemType.offer, 'unknown-time', min: 100, known: false),
      ];
      expect(
        ids(cheapest(items)),
        ['offer-new', 'request-old', 'offer-old', 'unknown-time'],
      );
    });

    test('same price, same time, same kind: the id decides', () {
      final items = [
        record(ItemType.offer, 'b', min: 100, age: hour),
        record(ItemType.offer, 'a', min: 100, age: hour),
      ];
      expect(ids(cheapest(items)), ['a', 'b']);
      expect(ids(cheapest(items.reversed)), ['a', 'b']);
    });

    test('keeps only the 6 cheapest, cheapest first', () {
      final items = [
        for (var i = 8; i >= 1; i--)
          record(ItemType.offer, 'p$i', min: i * 10.0),
      ];
      expect(ids(cheapest(items)), ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
    });

    test('fewer than 6 priced records are all kept', () {
      expect(
        ids(cheapest([
          record(ItemType.offer, 'a', min: 20),
          record(ItemType.request, 'b', min: 10),
        ])),
        ['b', 'a'],
      );
    });

    test('does not depend on how old a record is', () {
      expect(
        ids(cheapest([
          record(ItemType.offer, 'ancient', min: 5, age: day * 400),
        ])),
        ['ancient'],
      );
    });
  });

  group('whatever the input order, the answer is the same', () {
    final mixed = [
      record(ItemType.watchmen, 'w1', age: hour, min: 1),
      record(ItemType.offer, 'o1', age: hour * 2, min: 300),
      record(ItemType.offer, 'o2', age: hour * 2, min: 300),
      record(ItemType.request, 'r1', age: hour * 3, min: 200, max: 400),
      record(ItemType.broker, 'b1', age: hour * 4),
      record(ItemType.owner, 'ow1', age: day * 2),
      record(ItemType.office, 'of1', age: hour * 30),
      record(ItemType.offer, 'old', age: day * 10, min: 50),
    ];

    for (final kind in implemented) {
      test(kind.name, () {
        final expected = ids(HomeFilterRules.apply(kind, mixed, now: now));
        expect(
          ids(HomeFilterRules.apply(kind, mixed.reversed, now: now)),
          expected,
        );
        final rotated = [...mixed.skip(3), ...mixed.take(3)];
        expect(ids(HomeFilterRules.apply(kind, rotated, now: now)), expected);
      });
    }
  });

  group('Quotations never reach the list', () {
    final quotations = [
      record(ItemType.quotation, 'q-recent', age: hour, min: 1),
      record(ItemType.quotation, 'q-priced', age: day * 2, min: 1, max: 2),
    ];

    for (final kind in implemented) {
      test('${kind.name} drops them even if one is handed in', () {
        expect(HomeFilterRules.apply(kind, quotations, now: now), isEmpty);
        final withOthers = [
          ...quotations,
          record(ItemType.offer, 'offer', age: hour, min: 10),
        ];
        expect(
          ids(HomeFilterRules.apply(kind, withOthers, now: now)),
          ['offer'],
        );
      });
    }
  });
}
