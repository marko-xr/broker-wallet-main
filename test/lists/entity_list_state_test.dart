import 'dart:async';

import 'package:broker_wallet/src/viewmodels/ListScreens/entity_list_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The list lifecycle shared by the Requests, Offers, Owners, Offices,
/// Brokers and Watchmen screens: loading only before the first list, a list
/// that stays on screen through refreshes and deletes, item-level delete
/// progress with recovery, and one subscription for the screen's lifetime.

class _Item {
  const _Item(this.id);
  final String id;
}

class _ProbeList extends ChangeNotifier with EntityListState<_Item> {
  _ProbeList(Stream<List<_Item>> source) {
    listenToEntities(source);
  }

  @override
  String? entityIdOf(_Item item) => item.id;

  @override
  String get debugListName => 'probe';

  Future<EntityDeleteOutcome> delete(String id, Future<void> Function() run) =>
      deleteEntity(id, run);

  List<String> get ids => [for (final item in entities) item.id];
}

List<_Item> _items(List<String> ids) => [for (final id in ids) _Item(id)];

/// What the screen would draw after each notification.
String _screen(_ProbeList list) {
  if (list.isInitialLoading) return 'loading';
  if (list.hasLoadError) return 'error';
  if (list.entities.isEmpty) return 'empty';
  return 'list';
}

void main() {
  late StreamController<List<_Item>> source;
  late int listens;
  late _ProbeList list;
  late List<String> screens;

  setUp(() {
    listens = 0;
    source = StreamController<List<_Item>>(onListen: () => listens++);
    list = _ProbeList(source.stream);
    screens = <String>[];
    list.addListener(() => screens.add(_screen(list)));
  });

  // Disposing cancels the only subscription; the source needs no close (and a
  // close after that cancel would never complete).
  tearDown(() => list.dispose());

  test('shows loading only until the first list, then a genuine empty state',
      () async {
    expect(list.isInitialLoading, isTrue);
    expect(list.hasLoadError, isFalse);
    expect(list.entities, isEmpty);

    source.add(const <_Item>[]);
    await pumpEventQueue();

    expect(list.isInitialLoading, isFalse);
    expect(list.hasLoadError, isFalse);
    expect(list.entities, isEmpty);
    expect(screens, ['empty']);
  });

  test('a newer list replaces the current one without passing through loading',
      () async {
    source.add(_items(['a', 'b']));
    await pumpEventQueue();
    source.add(_items(['a', 'b', 'c']));
    await pumpEventQueue();

    expect(list.ids, ['a', 'b', 'c']);
    expect(screens, ['list', 'list']);
  });

  test('a failed refresh keeps the current list on screen', () async {
    source.add(_items(['a', 'b']));
    await pumpEventQueue();

    source.addError(StateError('offline'));
    await pumpEventQueue();

    expect(list.ids, ['a', 'b']);
    expect(list.hasLoadError, isFalse);
    expect(list.loadError, isNull);
    expect(screens, everyElement('list'));

    source.add(_items(['a']));
    await pumpEventQueue();
    expect(list.ids, ['a']);
  });

  test('a failed first load is an error, never a false empty state', () async {
    source.addError(StateError('offline'));
    await pumpEventQueue();

    expect(list.isInitialLoading, isFalse);
    expect(list.hasLoadError, isTrue);
    expect(list.loadError, isA<StateError>());
    expect(screens, ['error']);

    source.add(_items(['a']));
    await pumpEventQueue();
    expect(list.hasLoadError, isFalse);
    expect(list.ids, ['a']);
  });

  test('a delete marks only its item while the rest of the list stays',
      () async {
    source.add(_items(['a', 'b', 'c']));
    await pumpEventQueue();
    screens.clear();

    final remote = Completer<void>();
    final pending = list.delete('b', () => remote.future);

    expect(list.isDeleting('b'), isTrue);
    expect(list.isDeleting('a'), isFalse);
    expect(list.ids, ['a', 'b', 'c']);

    remote.complete();
    expect(await pending, EntityDeleteOutcome.deleted);

    expect(list.isDeleting('b'), isFalse);
    expect(list.ids, ['a', 'c']);
    expect(screens, everyElement('list'));
  });

  test('a read that started before the delete cannot bring the item back',
      () async {
    source.add(_items(['a', 'b']));
    await pumpEventQueue();

    expect(await list.delete('b', () async {}), EntityDeleteOutcome.deleted);

    // A stale read, older than the delete, still lists the item.
    source.add(_items(['a', 'b']));
    await pumpEventQueue();
    expect(list.ids, ['a']);

    // The read after the delete agrees.
    source.add(_items(['a']));
    await pumpEventQueue();
    expect(list.ids, ['a']);
  });

  test('a failed delete puts the item back as it was', () async {
    source.add(_items(['a', 'b']));
    await pumpEventQueue();
    screens.clear();

    final outcome =
        await list.delete('b', () async => throw Exception('offline'));

    expect(outcome, EntityDeleteOutcome.failed);
    expect(list.isDeleting('b'), isFalse);
    expect(list.ids, ['a', 'b']);
    expect(screens, everyElement('list'));
  });

  test('a second delete of the same item while one is in flight runs nothing',
      () async {
    source.add(_items(['a', 'b']));
    await pumpEventQueue();

    var calls = 0;
    final remote = Completer<void>();
    Future<void> run() {
      calls++;
      return remote.future;
    }

    final first = list.delete('a', run);
    expect(await list.delete('a', run), EntityDeleteOutcome.ignored);
    expect(calls, 1);

    remote.complete();
    expect(await first, EntityDeleteOutcome.deleted);
    expect(await list.delete('a', run), EntityDeleteOutcome.ignored);
    expect(calls, 1);
  });

  test('deleting the last item leaves a genuinely empty list', () async {
    source.add(_items(['a']));
    await pumpEventQueue();

    expect(await list.delete('a', () async {}), EntityDeleteOutcome.deleted);

    expect(list.entities, isEmpty);
    expect(list.isInitialLoading, isFalse);
    expect(list.hasLoadError, isFalse);
    expect(_screen(list), 'empty');
  });

  test('the source is listened to once, through deletes and refreshes',
      () async {
    source.add(_items(['a', 'b', 'c']));
    await pumpEventQueue();

    await list.delete('a', () async {});
    await list.delete('b', () async => throw Exception('offline'));
    source.add(_items(['b', 'c']));
    await pumpEventQueue();

    expect(listens, 1);
  });

  test('a delete that finishes after the screen closed changes nothing',
      () async {
    final closing = _ProbeList(Stream<List<_Item>>.value(_items(['a'])));
    await pumpEventQueue();

    final remote = Completer<void>();
    final pending = closing.delete('a', () => remote.future);
    closing.dispose();
    remote.complete();

    // Notifying a disposed ChangeNotifier would throw here.
    expect(await pending, EntityDeleteOutcome.deleted);
  });
}
