// P4.7a: the six entity list screens' week sections, from one shared helper.
//
// `ListWeekKeys` must give exactly the key the screens' former private
// `_getWeekKey` gave (identical in all six), for every date and every "now".
// `_oldKey` below is that method copied verbatim, with `DateTime.now()` made a
// parameter so the clock is controlled.
//
// The process time zone decides local calendar days. Run this file under
// several offsets too, e.g. `TZ=EST5EDT`, `TZ=UTC0`, `TZ=NZST-12` (on Windows
// the Dart VM follows TZ's offset but not its daylight-saving rules, so DST
// transitions themselves are covered by construction — the helper performs the
// same local DateTime operations — not by execution here).
import 'dart:io';

import 'package:broker_wallet/src/common/utils/list_week_keys.dart';
import 'package:flutter_test/flutter_test.dart';

String _oldKey(DateTime date, DateTime now) {
  // Get the start of the week (Monday)
  final weekStart = date.subtract(Duration(days: date.weekday - 1));

  final today = DateTime(now.year, now.month, now.day);
  final dateOnly = DateTime(date.year, date.month, date.day);

  // Check if it's this week
  final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final thisWeekEnd = thisWeekStart.add(const Duration(days: 6));

  if (dateOnly.isAfter(thisWeekStart.subtract(const Duration(days: 1))) &&
      dateOnly.isBefore(thisWeekEnd.add(const Duration(days: 1)))) {
    return 'this_week';
  }

  // Check if it's last week
  final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
  final lastWeekEnd = lastWeekStart.add(const Duration(days: 6));

  if (dateOnly.isAfter(lastWeekStart.subtract(const Duration(days: 1))) &&
      dateOnly.isBefore(lastWeekEnd.add(const Duration(days: 1)))) {
    return 'last_week';
  }

  // For other weeks, use the week start date
  return '${weekStart.year}-${weekStart.month}-${weekStart.day}';
}

const _times = [
  [0, 0, 0, 0],
  [0, 0, 0, 1],
  [0, 59, 59, 999],
  [1, 0, 0, 0],
  [11, 59, 59, 999],
  [12, 0, 0, 0],
  [22, 59, 59, 999],
  [23, 0, 0, 0],
  [23, 59, 59, 999],
];

/// "Now" values that put the week, month and year edges under test.
final List<DateTime> _clocks = [
  DateTime(2026, 11, 2), // Monday 00:00
  DateTime(2026, 11, 8, 23, 59, 59, 999), // Sunday, last instant
  DateTime(2026, 11, 5, 12), // mid-week
  DateTime(2026, 2, 1, 0, 0, 0, 1), // first day of a month (Sunday)
  DateTime(2026, 1, 31, 23, 59), // last day of a month (Saturday)
  DateTime(2026, 12, 31, 23, 59, 59, 999), // year end (Thursday)
  DateTime(2027, 1, 1), // year start: this week began last year
  DateTime(2027, 1, 4), // Monday after a year-spanning week
  DateTime(2028, 2, 29, 9), // leap day
  DateTime(2028, 3, 1), // after a leap day
  DateTime(2026, 3, 8, 2, 30), // US DST start day (2nd Sunday of March)
  DateTime(2026, 3, 29, 1, 30), // EU DST start day
  DateTime(2026, 10, 25, 2, 30), // EU DST end day
  DateTime(2026, 11, 1, 1, 30), // US DST end day
  DateTime.now(),
  DateTime.now().toUtc(), // a UTC "now", which the old code also accepted
];

void main() {
  test('runs in this process time zone', () {
    // Recorded so a run under another TZ shows which offset it covered.
    // ignore: avoid_print
    print('[ListWeekKeys] tz=${DateTime.now().timeZoneName} '
        'offset=${DateTime.now().timeZoneOffset} '
        'TZ=${Platform.environment['TZ'] ?? '(unset)'}');
  });

  for (final now in _clocks) {
    test('identical keys to the screens\' former helper, now=$now', () {
      final keys = ListWeekKeys(now);
      final base = DateTime(now.year, now.month, now.day);
      var compared = 0;
      for (var d = -420; d <= 21; d++) {
        for (final t in _times) {
          final local = DateTime(
              base.year, base.month, base.day + d, t[0], t[1], t[2], t[3]);
          for (final date in [local, local.toUtc()]) {
            expect(keys.keyOf(date), _oldKey(date, now),
                reason: 'date=${date.toIso8601String()} '
                    'utc=${date.isUtc} now=$now');
            compared++;
          }
        }
      }
      expect(compared, greaterThan(7000));
    });
  }

  test('historical, far-future and epoch dates', () {
    final dates = [
      DateTime(1970),
      DateTime.utc(1970),
      DateTime.fromMillisecondsSinceEpoch(0),
      DateTime(1999, 12, 31, 23, 59, 59),
      DateTime(2000),
      DateTime(2000, 2, 29),
      DateTime(1900, 3, 1),
      DateTime(2099, 12, 31),
      DateTime.utc(2100, 1, 1),
    ];
    for (final now in _clocks) {
      final keys = ListWeekKeys(now);
      for (final date in dates) {
        expect(keys.keyOf(date), _oldKey(date, now), reason: '$date / $now');
      }
    }
  });

  test('one instance gives the same key every time (no stale cache)', () {
    final now = DateTime(2026, 11, 5, 12);
    final keys = ListWeekKeys(now);
    final date = DateTime(2026, 10, 30, 23, 30);
    final first = keys.keyOf(date);
    for (var i = 0; i < 5; i++) {
      keys.keyOf(DateTime(2026, 10, 30, i)); // same calendar day, other times
      expect(keys.keyOf(date), first);
    }
    expect(first, _oldKey(date, now));
  });

  test('a new grouping after midnight sees the new day', () {
    final beforeMidnight = DateTime(2026, 11, 8, 23, 59, 59, 999); // Sunday
    final afterMidnight = DateTime(2026, 11, 9); // Monday: a new week
    final date = DateTime(2026, 11, 3, 10); // Tuesday of the earlier week
    expect(ListWeekKeys(beforeMidnight).keyOf(date), 'this_week');
    expect(ListWeekKeys(afterMidnight).keyOf(date), 'last_week');
    expect(
        ListWeekKeys(afterMidnight).keyOf(date), _oldKey(date, afterMidnight));
  });

  test('the six screens use the shared helper, once per grouping', () {
    const screens = [
      'requests',
      'offers',
      'owners',
      'offices',
      'brokers',
      'watchmen',
    ];
    for (final screen in screens) {
      final source = File('lib/src/views/Screens/ViewLists/'
              '${screen}_list_view.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(source, isNot(contains('_getWeekKey')), reason: screen);
      expect('ListWeekKeys(DateTime.now())'.allMatches(source), hasLength(1),
          reason: '$screen: one set of bounds per grouping');
      expect(source, contains('weeks.keyOf(date)'), reason: screen);
    }
  });
}
