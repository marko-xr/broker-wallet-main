/// The weekly section a record falls in on the six entity list screens
/// (Requests, Offers, Owners, Offices, Brokers, Watchmen): `this_week`,
/// `last_week`, or the record's week start as `year-month-day`.
///
/// Make one per grouping, from that grouping's `DateTime.now()`. What depends
/// only on "now" — today and the bounds of this week and last week — is then
/// worked out once instead of for every record, which is what made a list's
/// build cost grow so fast with its size. Everything that depends on the
/// record is the same local-calendar arithmetic, in the same order, as the
/// screens' former per-record method, so every key is the same:
/// equivalence is checked in `test/lists/list_week_keys_test.dart`.
///
/// One instance holds no state that can go stale: a later grouping makes a
/// new one, from its own "now". The only thing kept is each calendar day's
/// local midnight, which depends on nothing but that day.
class ListWeekKeys {
  factory ListWeekKeys(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final thisWeekEnd = thisWeekStart.add(const Duration(days: 6));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = lastWeekStart.add(const Duration(days: 6));
    return ListWeekKeys._(
      thisWeekAfter: thisWeekStart.subtract(const Duration(days: 1)),
      thisWeekBefore: thisWeekEnd.add(const Duration(days: 1)),
      lastWeekAfter: lastWeekStart.subtract(const Duration(days: 1)),
      lastWeekBefore: lastWeekEnd.add(const Duration(days: 1)),
    );
  }

  ListWeekKeys._({
    required DateTime thisWeekAfter,
    required DateTime thisWeekBefore,
    required DateTime lastWeekAfter,
    required DateTime lastWeekBefore,
  })  : _thisWeekAfter = thisWeekAfter,
        _thisWeekBefore = thisWeekBefore,
        _lastWeekAfter = lastWeekAfter,
        _lastWeekBefore = lastWeekBefore;

  final DateTime _thisWeekAfter;
  final DateTime _thisWeekBefore;
  final DateTime _lastWeekAfter;
  final DateTime _lastWeekBefore;

  /// Local midnight of each calendar day met so far, by `year-month-day`.
  final Map<int, DateTime> _midnights = <int, DateTime>{};

  /// The section of a record dated [date].
  String keyOf(DateTime date) {
    final year = date.year;
    final month = date.month;
    final day = date.day;
    final dateOnly = _midnights.putIfAbsent(
      year * 10000 + month * 100 + day,
      () => DateTime(year, month, day),
    );
    if (dateOnly.isAfter(_thisWeekAfter) &&
        dateOnly.isBefore(_thisWeekBefore)) {
      return 'this_week';
    }
    if (dateOnly.isAfter(_lastWeekAfter) &&
        dateOnly.isBefore(_lastWeekBefore)) {
      return 'last_week';
    }
    // For other weeks, the week start date (from the record itself).
    final weekStart = date.subtract(Duration(days: date.weekday - 1));
    return '${weekStart.year}-${weekStart.month}-${weekStart.day}';
  }
}
