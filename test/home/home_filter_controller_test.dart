// The Home filter controller: the chips, the loading state, the answer, and what
// happens when the answer is late, wrong, or no longer true. A fake source puts
// every moment under the test's control; no backend, mode or widget is involved.

import 'dart:async';

import 'package:broker_wallet/src/data/models/unified_item_model.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_controller.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime now = DateTime.utc(2026, 10, 4, 12);

const Duration hour = Duration(hours: 1);

UnifiedItemModel record(
  ItemType type,
  String id, {
  Duration age = Duration.zero,
  Duration? changedAge,
  double? min,
  double? max,
}) {
  final created = now.subtract(age);
  return UnifiedItemModel(
    id: id,
    title: id,
    subtitle: '',
    type: type,
    createdAt: created,
    updatedAt: changedAge == null ? created : now.subtract(changedAge),
    minPrice: min,
    maxPrice: max,
    originalModel: null,
  );
}

List<String> ids(Iterable<UnifiedItemModel> items) =>
    [for (final item in items) item.id];

/// A source whose every read waits until the test answers it.
class FakeSource implements HomeFilterDataSource {
  final List<List<ItemType>> asked = [];
  final List<Completer<List<UnifiedItemModel>>> _pending = [];

  @override
  Future<List<UnifiedItemModel>> load(List<ItemType> types) {
    asked.add(List<ItemType>.of(types));
    final completer = Completer<List<UnifiedItemModel>>();
    _pending.add(completer);
    return completer.future;
  }

  int get calls => asked.length;

  void answer(int call, List<UnifiedItemModel> records) =>
      _pending[call].complete(records);

  void fail(int call, Object error) => _pending[call].completeError(error);

  void releaseAll() {
    for (final completer in _pending) {
      if (!completer.isCompleted) completer.complete(const []);
    }
  }
}

HomeFilterErrorKind classify(Object error) {
  if (error is TimeoutException) return HomeFilterErrorKind.network;
  if (error is StateError) return HomeFilterErrorKind.session;
  return HomeFilterErrorKind.generic;
}

class Harness {
  /// [unbuilt] names chips whose filter does not exist yet. Every chip has one
  /// today, so this is how the state a new chip starts in is exercised.
  Harness({
    Duration timeout = const Duration(seconds: 30),
    Set<HomeFilterKind> unbuilt = const {},
    Duration validFor = HomeFilterController.defaultRecordsValidFor,
    bool accountBound = false,
  }) {
    controller = HomeFilterController(
      dataSource: source,
      classifyError: classify,
      currentUserId: accountBound ? () => user : null,
      clock: () => clock,
      loadTimeout: timeout,
      recordsValidFor: validFor,
      isBuilt: (kind) => !unbuilt.contains(kind),
    );
    controller.addListener(() => notifications++);
    addTearDown(() {
      source.releaseAll();
      if (!disposed) controller.dispose();
    });
  }

  final FakeSource source = FakeSource();
  late final HomeFilterController controller;

  /// What "now" is for the controller; tests move it.
  DateTime clock = now;

  /// The signed-in user, when the harness is bound to an account.
  String? user = 'user-a';
  int notifications = 0;
  bool disposed = false;

  void dispose() {
    disposed = true;
    controller.dispose();
  }

  /// Taps chip [index] and lets the read it starts finish with [records].
  Future<void> tapAndAnswer(int index, List<UnifiedItemModel> records) async {
    final call = source.calls;
    controller.toggle(index);
    source.answer(call, records);
    await pumpEventQueue();
  }

  List<int> get chosen => [
        for (var i = 0; i < controller.filters.length; i++)
          if (controller.filters[i].selected) i,
      ];
}

const int recentlyAdded = 0;
const int lessPrice = 1;
const int thisWeek = 2;
const int highestPrice = 3;
const int recentlyUpdated = 4;

/// The two chips used to stand for "a chip whose filter is not built yet".
const Set<HomeFilterKind> unbuilt = {
  HomeFilterKind.highestPrice,
  HomeFilterKind.recentlyUpdated,
};

void main() {
  group('the chips', () {
    test('there are five, in order, and none is chosen to begin with', () {
      final h = Harness();
      expect([
        for (final f in h.controller.filters) f.labelKey
      ], [
        'recentlyAdded',
        'lessPrice',
        'thisWeek',
        'highestPrice',
        'recentlyUpdated',
      ]);
      expect(h.chosen, isEmpty);
      expect(h.controller.selectedFilter, isNull);
      expect(h.controller.selectedFilterKey, isNull);
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.isUnavailable, isFalse);
      expect(h.controller.errorKind, isNull);
      expect(h.controller.items, isEmpty);
      expect(h.source.calls, 0,
          reason: 'nothing is read until a chip is tapped');
    });

    test('a tap chooses the chip at once and starts loading', () {
      final h = Harness();
      h.controller.toggle(lessPrice);
      expect(h.chosen, [lessPrice]);
      expect(h.controller.selectedFilterKey, 'lessPrice');
      expect(h.controller.isLoading, isTrue);
      expect(h.controller.items, isEmpty);
      expect(h.controller.errorKind, isNull);
      expect(h.source.calls, 1);
      expect(h.notifications, 1, reason: 'the screen is told straight away');
    });

    test('every chip starts a read: a tap is never a no-op', () {
      // The controller has no backend and no mode of its own, so what mode the
      // app is in cannot switch the filters off.
      final h = Harness();
      for (final index in [
        recentlyAdded,
        lessPrice,
        thisWeek,
        highestPrice,
        recentlyUpdated,
      ]) {
        h.controller.toggle(index);
        expect(h.controller.isLoading, isTrue, reason: 'chip $index');
        expect(h.controller.isUnavailable, isFalse, reason: 'chip $index');
      }
      expect(h.source.calls, 5);
    });

    test('one chip is chosen at a time; another tap switches directly', () {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.controller.toggle(thisWeek);
      expect(h.chosen, [thisWeek]);
      expect(h.controller.selectedFilterKey, 'thisWeek');
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 2);
    });

    test(
        'switching drops the old chip\'s list at once, so it is never shown '
        'under the new chip', () async {
      final h = Harness();
      // Less Price holds only Requests and Offers; Recently Added still needs
      // the other four kinds, so it has to read.
      await h.tapAndAnswer(
          lessPrice, [record(ItemType.offer, 'a', min: 10, age: hour)]);
      expect(ids(h.controller.items), ['a']);
      h.controller.toggle(recentlyAdded);
      expect(h.controller.items, isEmpty);
      expect(h.controller.isLoading, isTrue);
    });

    test('a chip that holds what it needs shows its own answer, not the last',
        () async {
      final h = Harness();
      await h.tapAndAnswer(
          recentlyAdded, [record(ItemType.offer, 'a', age: hour)]);
      expect(ids(h.controller.items), ['a']);
      // 'a' has no price: Less Price has nothing, and says so at once.
      h.controller.toggle(lessPrice);
      expect(h.controller.items, isEmpty);
      expect(h.controller.isLoading, isFalse);
    });

    test('tapping the chosen chip clears the filter', () async {
      final h = Harness();
      await h.tapAndAnswer(lessPrice, [record(ItemType.offer, 'a', min: 10)]);
      expect(ids(h.controller.items), ['a']);

      h.controller.toggle(lessPrice);
      expect(h.chosen, isEmpty);
      expect(h.controller.selectedFilter, isNull);
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.errorKind, isNull);
      expect(h.controller.items, isEmpty);
    });

    test('tapping the chosen chip while it is still loading clears at once',
        () {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.controller.toggle(recentlyAdded);
      expect(h.chosen, isEmpty);
      expect(h.controller.isLoading, isFalse);
    });

    test('a tap on something that is not a chip is ignored', () {
      final h = Harness();
      h.controller.toggle(-1);
      h.controller.toggle(5);
      expect(h.chosen, isEmpty);
      expect(h.source.calls, 0);
      expect(h.notifications, 0);
    });
  });

  group('what each chip reads', () {
    test('Recently Added and This Week read the six kinds of record', () {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.controller.toggle(thisWeek);
      expect(h.source.asked, [
        HomeFilterRules.filterable,
        HomeFilterRules.filterable,
      ]);
    });

    test('Less Price and Highest Price read only Offers and Requests', () {
      final h = Harness();
      h.controller.toggle(lessPrice);
      h.controller.toggle(highestPrice);
      expect(h.source.asked, [
        [ItemType.request, ItemType.offer],
        [ItemType.request, ItemType.offer],
      ]);
    });

    test('Recently Updated reads the six kinds of record', () {
      final h = Harness();
      h.controller.toggle(recentlyUpdated);
      expect(h.source.asked, [HomeFilterRules.filterable]);
    });

    test('no chip ever asks for Quotations', () {
      final h = Harness();
      for (final index in [
        recentlyAdded,
        lessPrice,
        thisWeek,
        highestPrice,
        recentlyUpdated,
      ]) {
        h.controller.toggle(index);
      }
      for (final types in h.source.asked) {
        expect(types.contains(ItemType.quotation), isFalse);
      }
    });
  });

  group('a chip whose filter is not built yet (the state a new chip starts in)',
      () {
    for (final entry in {
      'Highest Price': highestPrice,
      'Recently Updated': recentlyUpdated,
    }.entries) {
      final index = entry.value;

      test('${entry.key}: chosen at once, says so, and reads nothing', () {
        final h = Harness(unbuilt: unbuilt);
        h.controller.toggle(index);
        expect(h.chosen, [index]);
        expect(h.controller.isUnavailable, isTrue);
        // Not a spinner, not a failure and not "no items": it was never asked.
        expect(h.controller.isLoading, isFalse);
        expect(h.controller.errorKind, isNull);
        expect(h.controller.items, isEmpty);
        expect(h.source.calls, 0, reason: 'nothing is read for it');
        expect(h.notifications, 1, reason: 'the screen is told straight away');
      });

      test('${entry.key}: tapping it again clears it', () {
        final h = Harness(unbuilt: unbuilt);
        h.controller.toggle(index);
        h.controller.toggle(index);
        expect(h.chosen, isEmpty);
        expect(h.controller.isUnavailable, isFalse);
        expect(h.controller.selectedFilter, isNull);
        expect(h.notifications, 2);
      });
    }

    test('it is one chip at a time: another chip replaces it, and back',
        () async {
      final h = Harness(unbuilt: unbuilt);
      h.controller.toggle(highestPrice);
      expect(h.controller.isUnavailable, isTrue);

      h.controller.toggle(lessPrice);
      expect(h.chosen, [lessPrice]);
      expect(h.controller.isUnavailable, isFalse);
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 1);
      h.source.answer(0, [record(ItemType.offer, 'a', min: 5)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['a']);

      h.controller.toggle(recentlyUpdated);
      expect(h.chosen, [recentlyUpdated]);
      expect(h.controller.isUnavailable, isTrue);
      expect(h.controller.items, isEmpty,
          reason: 'the earlier chip\'s list is never shown under this one');
      expect(h.source.calls, 1, reason: 'still only the one real read');
    });

    test('a read still going for the chip before it can no longer show up',
        () async {
      final h = Harness(unbuilt: unbuilt);
      h.controller.toggle(recentlyAdded); // call 0, in flight
      h.controller.toggle(highestPrice);
      h.source.answer(0, [record(ItemType.offer, 'late', age: hour)]);
      await pumpEventQueue();
      expect(h.controller.isUnavailable, isTrue);
      expect(h.controller.items, isEmpty);
      expect(h.controller.isLoading, isFalse);
    });

    test('a pull, a change to the records and Retry do nothing for it',
        () async {
      final h = Harness(unbuilt: unbuilt);
      h.controller.toggle(recentlyUpdated);
      final told = h.notifications;

      await h.controller.refresh();
      h.controller.onDataChanged();
      h.controller.retry();
      await pumpEventQueue();

      expect(h.source.calls, 0);
      expect(h.notifications, told);
      expect(h.controller.isUnavailable, isTrue);
    });

    test('nothing is counted for it', () {
      final h = Harness(unbuilt: unbuilt);
      h.controller.toggle(highestPrice);
      for (final type in ItemType.values) {
        expect(h.controller.countOf(type), 0, reason: type.name);
      }
    });

    test('leaving or signing out clears it too, once', () {
      final h = Harness(unbuilt: unbuilt);
      h.controller.toggle(highestPrice);
      final told = h.notifications;
      h.controller.clear();
      expect(h.chosen, isEmpty);
      expect(h.controller.isUnavailable, isFalse);
      expect(h.notifications, told + 1);
      h.controller.clear();
      expect(h.notifications, told + 1);
    });
  });

  group('Highest Price and Recently Updated answer like the other chips', () {
    test('Highest Price shows the dearest Offers and Requests, dearest first',
        () async {
      final h = Harness();
      await h.tapAndAnswer(highestPrice, [
        record(ItemType.offer, 'cheap', min: 100),
        record(ItemType.request, 'dear', min: 900),
        record(ItemType.offer, 'middle', min: 500),
        record(ItemType.owner, 'owner', min: 5000),
      ]);
      expect(h.controller.isUnavailable, isFalse);
      expect(h.controller.isLoading, isFalse);
      expect(ids(h.controller.items), ['dear', 'middle', 'cheap']);
    });

    test('Recently Updated shows records changed after they were created',
        () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyUpdated, [
        record(ItemType.offer, 'never-edited', age: hour),
        record(ItemType.offer, 'edited',
            age: hour * 30, changedAge: const Duration(minutes: 5)),
        record(ItemType.owner, 'edited-long-ago',
            age: hour * 90, changedAge: hour * 30),
      ]);
      expect(ids(h.controller.items), ['edited']);
    });

    test('a record changed after the clock moved on drops out of the list',
        () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyUpdated, [
        record(ItemType.offer, 'a', age: hour * 30, changedAge: hour),
      ]);
      expect(ids(h.controller.items), ['a']);

      // A later re-read, 13 hours on, sees the same record as too old.
      h.clock = now.add(hour * 13);
      final call = h.source.calls;
      h.controller.onDataChanged();
      h.source.answer(call, [
        record(ItemType.offer, 'a', age: hour * 30, changedAge: hour),
      ]);
      await pumpEventQueue();
      expect(h.controller.items, isEmpty);
    });

    test('an edit while the chip is chosen is read again quietly', () async {
      final h = Harness();
      await h.tapAndAnswer(highestPrice, [
        record(ItemType.offer, 'a', min: 100),
      ]);
      final told = h.notifications;

      final call = h.source.calls;
      h.controller.onDataChanged();
      expect(h.controller.isLoading, isFalse,
          reason: 'what is on screen stays while the new answer is read');
      h.source.answer(call, [
        record(ItemType.offer, 'a', min: 100),
        record(ItemType.offer, 'b', min: 200),
      ]);
      await pumpEventQueue();

      expect(ids(h.controller.items), ['b', 'a']);
      expect(h.notifications, told + 1);
    });

    test('a failure is shown with Try Again, never as an empty list', () async {
      final h = Harness();
      h.controller.toggle(recentlyUpdated);
      h.source.fail(0, TimeoutException('slow'));
      await pumpEventQueue();
      expect(h.controller.errorKind, HomeFilterErrorKind.network);
      expect(h.controller.items, isEmpty);

      h.controller.retry();
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 2);
    });
  });

  group('loading until the whole answer is in', () {
    test('one loading state, then the answer; never a part of it', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      expect(h.controller.isLoading, isTrue);
      expect(h.controller.items, isEmpty);
      await pumpEventQueue();
      expect(h.controller.isLoading, isTrue,
          reason: 'still loading: the read has not finished');

      h.source.answer(0, [
        record(ItemType.offer, 'a', age: hour),
        record(ItemType.request, 'b', age: hour),
      ]);
      await pumpEventQueue();
      expect(h.controller.isLoading, isFalse);
      expect(ids(h.controller.items), ['b', 'a']);
      expect(h.chosen, [recentlyAdded], reason: 'the chip stays chosen');
    });

    test('the screen is told once for the answer', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      expect(h.notifications, 1);
      h.source.answer(0, [record(ItemType.offer, 'a', age: hour)]);
      await pumpEventQueue();
      expect(h.notifications, 2);
    });

    test('an answer of nothing is an answer, not a failure', () async {
      final h = Harness();
      await h.tapAndAnswer(thisWeek, const []);
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.errorKind, isNull);
      expect(h.controller.items, isEmpty);
      expect(h.chosen, [thisWeek]);
    });

    test('the filter is applied with the clock it is given', () async {
      final h = Harness();
      final item = record(ItemType.offer, 'a', age: const Duration(hours: 11));
      await h.tapAndAnswer(recentlyAdded, [item]);
      expect(ids(h.controller.items), ['a']);

      h.controller.toggle(recentlyAdded); // clear
      h.clock = now.add(const Duration(hours: 2)); // the item is now 13 h old
      await h.tapAndAnswer(recentlyAdded, [item]);
      expect(h.controller.items, isEmpty);
    });

    test('Less Price shows the cheapest first, at most six', () async {
      final h = Harness();
      await h.tapAndAnswer(lessPrice, [
        for (var i = 8; i >= 1; i--)
          record(ItemType.offer, 'p$i', min: i * 10.0),
      ]);
      expect(ids(h.controller.items), ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
    });

    test('the answer is counted by kind, and only while the filter is chosen',
        () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyAdded, [
        record(ItemType.offer, 'o1', age: hour),
        record(ItemType.offer, 'o2', age: hour),
        record(ItemType.request, 'r1', age: hour),
      ]);
      expect(h.controller.countOf(ItemType.offer), 2);
      expect(h.controller.countOf(ItemType.request), 1);
      expect(h.controller.countOf(ItemType.broker), 0);
      expect(h.controller.countOf(ItemType.quotation), 0);

      h.controller.clear();
      expect(h.controller.countOf(ItemType.offer), 0);
    });
  });

  group('an answer that arrives late never replaces a newer one', () {
    test('the first chip\'s answer arriving last changes nothing', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded); // call 0
      h.controller.toggle(thisWeek); // call 1

      h.source.answer(1, [record(ItemType.offer, 'week', age: hour * 30)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['week']);

      h.source.answer(0, [record(ItemType.offer, 'recent', age: hour)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['week'],
          reason: 'the late Recently Added answer must not replace This Week');
      expect(h.chosen, [thisWeek]);
      expect(h.controller.isLoading, isFalse);
    });

    test('the first chip\'s answer arriving first is ignored too', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.controller.toggle(thisWeek);

      h.source.answer(0, [record(ItemType.offer, 'recent', age: hour)]);
      await pumpEventQueue();
      expect(h.controller.isLoading, isTrue,
          reason: 'This Week is still being read');
      expect(h.controller.items, isEmpty);

      h.source.answer(1, [record(ItemType.offer, 'week', age: hour * 30)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['week']);
    });

    test('an answer arriving after the filter was cleared changes nothing',
        () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.controller.toggle(recentlyAdded); // clear
      h.source.answer(0, [record(ItemType.offer, 'late', age: hour)]);
      await pumpEventQueue();
      expect(h.chosen, isEmpty);
      expect(h.controller.items, isEmpty);
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.errorKind, isNull);
    });

    test('a failure arriving after a switch changes nothing', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.controller.toggle(lessPrice);
      h.source.fail(0, TimeoutException('too slow'));
      await pumpEventQueue();
      expect(h.controller.errorKind, isNull);
      expect(h.controller.isLoading, isTrue);

      h.source.answer(1, [record(ItemType.offer, 'a', min: 5)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['a']);
    });

    test('an answer arriving after dispose changes nothing and tells nobody',
        () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      final told = h.notifications;
      h.dispose();
      h.source.answer(0, [record(ItemType.offer, 'a', age: hour)]);
      await pumpEventQueue();
      expect(h.notifications, told);
    });
  });

  group('when it cannot be answered', () {
    test('the failure is shown; it is never an empty list or a spinner',
        () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.source.fail(0, TimeoutException('no connection'));
      await pumpEventQueue();
      expect(h.controller.errorKind, HomeFilterErrorKind.network);
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.items, isEmpty);
      expect(h.chosen, [recentlyAdded], reason: 'the chip stays chosen');
    });

    test('a failure is sorted into connection, session, or anything else',
        () async {
      final h = Harness();
      final expectations = <Object, HomeFilterErrorKind>{
        TimeoutException('t'): HomeFilterErrorKind.network,
        StateError('A Supabase session is required.'):
            HomeFilterErrorKind.session,
        Exception('something else'): HomeFilterErrorKind.generic,
      };
      var call = 0;
      for (final entry in expectations.entries) {
        h.controller.toggle(thisWeek);
        h.source.fail(call++, entry.key);
        await pumpEventQueue();
        expect(h.controller.errorKind, entry.value, reason: '${entry.key}');
        h.controller.toggle(thisWeek); // clear before the next
      }
    });

    test('Retry reads again and recovers', () async {
      final h = Harness();
      h.controller.toggle(thisWeek);
      h.source.fail(0, TimeoutException('no connection'));
      await pumpEventQueue();
      expect(h.controller.errorKind, isNotNull);

      h.controller.retry();
      expect(h.controller.isLoading, isTrue);
      expect(h.controller.errorKind, isNull);
      expect(h.source.calls, 2);

      h.source.answer(1, [record(ItemType.offer, 'a', age: hour)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['a']);
      expect(h.controller.errorKind, isNull);
    });

    test('Retry does nothing unless there is a failure to retry', () async {
      final h = Harness();
      h.controller.retry();
      expect(h.source.calls, 0, reason: 'nothing chosen');

      h.controller.toggle(thisWeek);
      h.controller.retry();
      expect(h.source.calls, 1, reason: 'still loading');

      h.source.answer(0, const []);
      await pumpEventQueue();
      h.controller.retry();
      expect(h.source.calls, 1, reason: 'it succeeded');
    });

    test('a read that never answers ends as a connection problem', () async {
      final h = Harness(timeout: Duration.zero);
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isTrue);
      await pumpEventQueue();
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.errorKind, HomeFilterErrorKind.network);
    });
  });

  group('a pull to refresh', () {
    test('keeps the filter and what is on screen while it reads again',
        () async {
      final h = Harness();
      await h.tapAndAnswer(
          recentlyAdded, [record(ItemType.offer, 'a', age: hour)]);

      final done = h.controller.refresh();
      expect(h.source.calls, 2);
      expect(h.chosen, [recentlyAdded]);
      expect(h.controller.isLoading, isFalse,
          reason: 'no spinner replaces the list during a refresh');
      expect(ids(h.controller.items), ['a']);

      h.source.answer(1, [
        record(ItemType.offer, 'a', age: hour),
        record(ItemType.request, 'b', age: hour),
      ]);
      await done;
      expect(ids(h.controller.items), ['b', 'a']);
      expect(h.chosen, [recentlyAdded]);
    });

    test('if it cannot be read the failure is shown, not the old list',
        () async {
      final h = Harness();
      await h.tapAndAnswer(
          recentlyAdded, [record(ItemType.offer, 'a', age: hour)]);
      final done = h.controller.refresh();
      h.source.fail(1, TimeoutException('no connection'));
      await done;
      expect(h.controller.errorKind, HomeFilterErrorKind.network);
      expect(h.controller.items, isEmpty);
    });

    test('never throws, whatever went wrong', () async {
      final h = Harness();
      await h.tapAndAnswer(thisWeek, const []);
      final done = h.controller.refresh();
      h.source.fail(1, ArgumentError('anything at all'));
      await done; // completes normally
      expect(h.controller.errorKind, HomeFilterErrorKind.generic);
    });

    test('from a failure it shows the loading state again', () async {
      final h = Harness();
      h.controller.toggle(thisWeek);
      h.source.fail(0, TimeoutException('no connection'));
      await pumpEventQueue();

      final done = h.controller.refresh();
      expect(h.controller.isLoading, isTrue);
      expect(h.controller.errorKind, isNull);
      h.source.answer(1, [record(ItemType.offer, 'a', age: hour)]);
      await done;
      expect(ids(h.controller.items), ['a']);
    });

    test('does nothing when no filter is chosen', () async {
      final h = Harness();
      await h.controller.refresh();
      expect(h.source.calls, 0);
      expect(h.notifications, 0);
    });

    test('a tap on another chip while it is reading wins', () async {
      final h = Harness();
      await h.tapAndAnswer(
          recentlyAdded, [record(ItemType.offer, 'a', age: hour)]);
      final done = h.controller.refresh(); // call 1
      h.controller.toggle(thisWeek); // call 2

      h.source.answer(2, [record(ItemType.owner, 'owner', age: hour * 30)]);
      await pumpEventQueue();
      h.source.answer(1, [record(ItemType.offer, 'stale', age: hour)]);
      await done;
      expect(ids(h.controller.items), ['owner']);
      expect(h.chosen, [thisWeek]);
    });
  });

  group('the user\'s own records changed', () {
    test('a chosen filter reads again quietly and swaps in the new answer',
        () async {
      final h = Harness();
      await h.tapAndAnswer(
          recentlyAdded, [record(ItemType.offer, 'a', age: hour)]);
      final told = h.notifications;

      h.controller.onDataChanged();
      expect(h.source.calls, 2);
      expect(h.controller.isLoading, isFalse, reason: 'no flash of a spinner');
      expect(ids(h.controller.items), ['a']);
      expect(h.notifications, told, reason: 'nothing changes on screen yet');

      h.source.answer(1, [
        record(ItemType.offer, 'a', age: hour),
        record(ItemType.offer, 'new', age: hour),
      ]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['a', 'new']);
    });

    test('a deleted record disappears from the answer', () async {
      final h = Harness();
      await h.tapAndAnswer(thisWeek, [
        record(ItemType.offer, 'keep', age: hour),
        record(ItemType.offer, 'gone', age: hour * 2),
      ]);
      expect(ids(h.controller.items), ['keep', 'gone']);
      h.controller.onDataChanged();
      h.source.answer(1, [record(ItemType.offer, 'keep', age: hour)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['keep']);
    });

    test('if that read fails, what is on screen stays', () async {
      final h = Harness();
      await h.tapAndAnswer(
          recentlyAdded, [record(ItemType.offer, 'a', age: hour)]);
      h.controller.onDataChanged();
      h.source.fail(1, TimeoutException('no connection'));
      await pumpEventQueue();
      expect(ids(h.controller.items), ['a']);
      expect(h.controller.errorKind, isNull);
      expect(h.controller.isLoading, isFalse);
    });

    test('with nothing chosen it does nothing', () {
      final h = Harness();
      h.controller.onDataChanged();
      expect(h.source.calls, 0);
      expect(h.notifications, 0);
    });

    test('while the first read is still loading it starts over', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded); // call 0
      h.controller.onDataChanged(); // call 1

      h.source.answer(0, [record(ItemType.offer, 'stale', age: hour)]);
      await pumpEventQueue();
      expect(h.controller.isLoading, isTrue,
          reason: 'the first read is out of date and is not used');

      h.source.answer(1, [record(ItemType.offer, 'fresh', age: hour)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['fresh']);
    });

    test('with nothing on screen yet, a failed re-read is shown', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.controller.onDataChanged();
      h.source.fail(1, TimeoutException('no connection'));
      await pumpEventQueue();
      expect(h.controller.errorKind, HomeFilterErrorKind.network);
    });

    test('a failed filter recovers when the data changes and reads', () async {
      final h = Harness();
      h.controller.toggle(thisWeek);
      h.source.fail(0, TimeoutException('no connection'));
      await pumpEventQueue();
      expect(h.controller.errorKind, isNotNull);

      h.controller.onDataChanged();
      h.source.answer(1, [record(ItemType.offer, 'a', age: hour)]);
      await pumpEventQueue();
      expect(h.controller.errorKind, isNull);
      expect(ids(h.controller.items), ['a']);
    });

    test('several changes in a row end with the last answer', () async {
      final h = Harness();
      await h.tapAndAnswer(
          recentlyAdded, [record(ItemType.offer, 'a', age: hour)]);
      h.controller.onDataChanged(); // call 1
      h.controller.onDataChanged(); // call 2
      h.controller.onDataChanged(); // call 3

      h.source.answer(3, [record(ItemType.offer, 'last', age: hour)]);
      await pumpEventQueue();
      h.source.answer(1, [record(ItemType.offer, 'first', age: hour)]);
      h.source.answer(2, [record(ItemType.offer, 'second', age: hour)]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['last']);
    });
  });

  group('the records are read once and kept', () {
    final kept = [
      record(ItemType.offer, 'cheap', min: 100, age: hour),
      record(ItemType.request, 'dear', min: 900, age: hour * 2),
      record(ItemType.owner, 'owner', age: hour * 3),
    ];

    test(
        'after the first answer every other chip answers at once, reading '
        'nothing', () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyAdded, kept);
      expect(h.source.calls, 1);

      for (final index in [
        lessPrice,
        thisWeek,
        highestPrice,
        recentlyUpdated
      ]) {
        final told = h.notifications;
        h.controller.toggle(index);
        expect(h.controller.isLoading, isFalse, reason: 'chip $index');
        expect(h.controller.errorKind, isNull, reason: 'chip $index');
        expect(h.notifications, told + 1,
            reason: 'one change, already holding the answer');
      }
      expect(h.source.calls, 1, reason: 'no chip read again');
      expect(ids(h.controller.items), isEmpty,
          reason: 'Recently Updated: nothing was edited');
      h.controller.toggle(highestPrice);
      expect(ids(h.controller.items), ['dear', 'cheap']);
      h.controller.toggle(lessPrice);
      expect(ids(h.controller.items), ['cheap', 'dear']);
    });

    test('a chip reads only the kinds it does not hold yet, and uses both',
        () async {
      final h = Harness();
      await h.tapAndAnswer(lessPrice, [
        record(ItemType.offer, 'cheap', min: 100, age: hour),
        record(ItemType.request, 'dear', min: 900, age: hour * 2),
      ]);
      expect(h.source.asked, [
        [ItemType.request, ItemType.offer],
      ]);

      h.controller.toggle(recentlyAdded);
      expect(h.controller.isLoading, isTrue);
      expect(h.source.asked.last, [
        ItemType.broker,
        ItemType.owner,
        ItemType.office,
        ItemType.watchmen,
      ]);
      h.source.answer(1, [record(ItemType.broker, 'b', age: hour)]);
      await pumpEventQueue();

      // The Offer and Request held from before and the Broker just read.
      expect(ids(h.controller.items), ['dear', 'cheap', 'b']);
    });

    test('an empty answer is an answer: it is kept, not read again', () async {
      final h = Harness();
      await h.tapAndAnswer(lessPrice, const []);
      h.controller.toggle(highestPrice);
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.items, isEmpty);
      expect(h.source.calls, 1);
    });

    test('the answer is worked out when the chip is tapped, with that clock',
        () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyAdded, [
        record(ItemType.offer, 'a',
            age: const Duration(hours: 11, minutes: 58)),
      ]);
      expect(ids(h.controller.items), ['a']);

      // Still trusted (under 5 minutes), but the clock has moved on.
      h.clock = now.add(const Duration(minutes: 3));
      h.controller.toggle(recentlyAdded); // off
      h.controller.toggle(recentlyAdded); // on again
      expect(h.source.calls, 1, reason: 'the records are held');
      expect(h.controller.items, isEmpty,
          reason: '12 h 1 min old now: outside the window');
    });

    test('records older than the time they are trusted are read again',
        () async {
      final h = Harness(validFor: const Duration(minutes: 5));
      await h.tapAndAnswer(recentlyAdded, kept);

      h.clock = now.add(const Duration(minutes: 4, seconds: 59));
      h.controller.toggle(thisWeek);
      expect(h.controller.isLoading, isFalse);
      expect(h.source.calls, 1);

      h.clock = now.add(const Duration(minutes: 5));
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 2);
    });

    test('a clock that went back proves nothing, so records are read again',
        () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyAdded, kept);
      h.clock = now.subtract(const Duration(minutes: 1));
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 2);
    });

    test('a change to the user\'s records forgets them, chip chosen or not',
        () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyAdded, kept);
      h.controller.clear();

      h.controller.onDataChanged(); // nothing chosen: nothing to read now
      expect(h.source.calls, 1);
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isTrue,
          reason: 'what was held no longer matches the records');
      expect(h.source.calls, 2);
    });

    test('a change while a chip is chosen is read again, and then kept',
        () async {
      final h = Harness();
      await h
          .tapAndAnswer(highestPrice, [record(ItemType.offer, 'a', min: 100)]);

      final call = h.source.calls;
      h.controller.onDataChanged();
      h.source.answer(call, [
        record(ItemType.offer, 'a', min: 100),
        record(ItemType.offer, 'b', min: 200),
      ]);
      await pumpEventQueue();
      expect(ids(h.controller.items), ['b', 'a']);

      h.controller.toggle(lessPrice);
      expect(ids(h.controller.items), ['a', 'b'],
          reason: 'the new answer was kept for the next chip');
      expect(h.source.calls, call + 1);
    });

    test('a refresh asks again instead of using what is held', () async {
      final h = Harness();
      await h
          .tapAndAnswer(highestPrice, [record(ItemType.offer, 'a', min: 100)]);

      final call = h.source.calls;
      final refreshing = h.controller.refresh();
      h.source.answer(call, [record(ItemType.offer, 'z', min: 300)]);
      await refreshing;

      expect(h.source.calls, call + 1);
      expect(ids(h.controller.items), ['z']);
      h.controller.toggle(lessPrice);
      expect(ids(h.controller.items), ['z']);
      expect(h.source.calls, call + 1);
    });

    test('a refresh that fails leaves nothing held to show the next chip',
        () async {
      final h = Harness();
      await h
          .tapAndAnswer(highestPrice, [record(ItemType.offer, 'a', min: 100)]);

      final call = h.source.calls;
      final refreshing = h.controller.refresh();
      h.source.fail(call, TimeoutException('slow'));
      await refreshing;
      expect(h.controller.errorKind, HomeFilterErrorKind.network);

      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isTrue,
          reason: 'the old answer may no longer be true');
    });

    test('clear keeps what was read for the next chip; reset forgets it',
        () async {
      final h = Harness();
      await h.tapAndAnswer(recentlyAdded, kept);

      h.controller.clear();
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isFalse);
      expect(h.source.calls, 1);

      h.controller.reset();
      expect(h.chosen, isEmpty);
      expect(h.controller.items, isEmpty);
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 2);
    });

    test('reset also drops a read still going, like clear', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded); // call 0, in flight
      h.controller.reset();
      h.source.answer(0, kept);
      await pumpEventQueue();
      expect(h.chosen, isEmpty);
      expect(h.controller.items, isEmpty);
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isTrue,
          reason: 'what the dropped read found was never kept');
    });

    test('records read for one account are never used for another', () async {
      final h = Harness(accountBound: true);
      await h.tapAndAnswer(recentlyAdded, kept);
      h.controller.toggle(lessPrice);
      expect(h.controller.isLoading, isFalse, reason: 'same account: held');

      h.user = 'user-b';
      h.controller.toggle(lessPrice); // off
      h.controller.toggle(lessPrice); // on again, as someone else
      expect(h.controller.isLoading, isTrue);
      expect(h.controller.items, isEmpty,
          reason: 'user-a\'s records are not shown to user-b');
      expect(h.source.calls, 2);
    });

    test('nobody signed in holds nothing', () async {
      final h = Harness(accountBound: true);
      await h.tapAndAnswer(recentlyAdded, kept);
      h.user = null;
      h.controller.toggle(recentlyAdded); // off
      h.controller.toggle(recentlyAdded); // on
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 2);
    });

    test('a read that fails holds nothing, and Try Again reads', () async {
      final h = Harness();
      h.controller.toggle(recentlyAdded);
      h.source.fail(0, TimeoutException('slow'));
      await pumpEventQueue();
      expect(h.controller.errorKind, HomeFilterErrorKind.network);

      h.controller.retry();
      expect(h.controller.isLoading, isTrue);
      expect(h.source.calls, 2);
    });

    test('what an earlier chip read stays held when a later read fails',
        () async {
      final h = Harness();
      await h.tapAndAnswer(lessPrice, [record(ItemType.offer, 'a', min: 10)]);

      h.controller.toggle(recentlyAdded); // needs four more kinds
      h.source.fail(1, TimeoutException('slow'));
      await pumpEventQueue();
      expect(h.controller.errorKind, HomeFilterErrorKind.network);

      h.controller.toggle(lessPrice); // another chip, whose kinds are held
      expect(h.controller.isLoading, isFalse, reason: 'its kinds are held');
      expect(h.controller.errorKind, isNull);
      expect(ids(h.controller.items), ['a']);
    });
  });

  group('leaving the screen or signing out', () {
    test('clear drops the filter, its answer and anything still being read',
        () async {
      final h = Harness();
      await h.tapAndAnswer(
          lessPrice, [record(ItemType.offer, 'a', min: 10, age: hour)]);
      h.controller.toggle(thisWeek); // call 1, in flight: needs four more kinds
      h.controller.clear();
      expect(h.chosen, isEmpty);
      expect(h.controller.isLoading, isFalse);
      expect(h.controller.items, isEmpty);

      h.source.answer(1, [record(ItemType.offer, 'late', age: hour)]);
      await pumpEventQueue();
      expect(h.chosen, isEmpty);
      expect(h.controller.items, isEmpty);
    });

    test('clearing when nothing is chosen tells nobody', () {
      final h = Harness();
      h.controller.clear();
      expect(h.notifications, 0);
    });

    test('clearing tells the screen once', () async {
      final h = Harness();
      await h.tapAndAnswer(thisWeek, const []);
      final told = h.notifications;
      h.controller.clear();
      expect(h.notifications, told + 1);
      h.controller.clear();
      expect(h.notifications, told + 1);
    });

    test('a failed filter is cleared too', () async {
      final h = Harness();
      h.controller.toggle(thisWeek);
      h.source.fail(0, TimeoutException('no connection'));
      await pumpEventQueue();
      h.controller.clear();
      expect(h.controller.errorKind, isNull);
      expect(h.chosen, isEmpty);
    });
  });
}
