import 'dart:math' as math;

/// How many private-media reads (one Worker call each) a list of records
/// runs at once.
const int mediaReadsAtOnce = 4;

/// Runs [task] for every item of [items], at most [limit] at a time, and
/// returns the results in the order of [items].
///
/// Once [stop] returns true no further task is started; the items not started
/// get null. A task's error is passed on, as from `Future.wait`.
Future<List<R?>> mapWithLimit<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T item) task, {
  bool Function()? stop,
}) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (next < items.length) {
      if (stop?.call() ?? false) return;
      final index = next++;
      results[index] = await task(items[index]);
    }
  }

  final workers = math.min(math.max(limit, 1), items.length);
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  return results;
}
