// The Search screen's state: when a search runs (debounce, the keyboard's Search
// action, a filter), which answer wins when several are in flight, that the
// records are loaded once and kept fresh, what a failure becomes, how the filter
// chips behave and that nothing happens after the screen is gone.
//
// Plain tests with a fake data source whose loads the test controls. No backend,
// no widgets. A real (short) debounce is used, so a few tests wait briefly.

import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_data_source.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_engine.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'search_fixtures.dart';

/// A data source the test drives: it can answer at once, hold every load until
/// told, or fail.
class _FakeDataSource implements SearchDataSource {
  _FakeDataSource(this.data);

  SearchData data;
  String? userId = 'u1';

  /// When true, a load waits on a completer in [pending].
  bool manual = false;
  final List<Completer<SearchData>> pending = <Completer<SearchData>>[];

  /// When set, the next loads throw it.
  Object? failure;

  int loadCount = 0;

  @override
  String? get currentUserId => userId;

  @override
  Future<SearchData> load() {
    loadCount++;
    final error = failure;
    if (error != null) return Future<SearchData>.error(error);
    if (manual) {
      final completer = Completer<SearchData>();
      pending.add(completer);
      return completer.future;
    }
    return Future<SearchData>.value(data);
  }

  /// Finishes the oldest held load with the current [data].
  void finishNext() => pending.removeAt(0).complete(data);
}

/// An engine that counts how many searches it answers.
class _CountingEngine extends SearchEngine {
  _CountingEngine() : super(lookup: arbLookup);

  int searches = 0;

  @override
  List<SearchResult> search(
    SearchCorpus corpus, {
    required List<String> tokens,
    required String displayQuery,
    SearchResultType? type,
  }) {
    searches++;
    return super.search(
      corpus,
      tokens: tokens,
      displayQuery: displayQuery,
      type: type,
    );
  }
}

/// A failure whose type name looks like a network client's.
class ClientException implements Exception {
  @override
  String toString() => 'ClientException: Connection reset by peer';
}

SearchData _sample() => SearchData(
      owners: [
        owner(id: 'o1', name: 'Dubai Owner'),
        owner(id: 'o2', name: 'Dub Guy'),
        owner(id: 'o3', name: 'Sam Brown'),
      ],
      offers: [offer(id: 'f1', city: 'Dubai')],
      requests: [request(id: 'r1', city: 'Abu Dhabi')],
      offices: [office(id: 'e1', name: 'Sam Office')],
    );

const _all = 0;
const _offers = 2;
const _owners = 3;
const _offices = 4;

const Duration _debounce = Duration(milliseconds: 20);

/// Long enough for the short debounce to fire and the search to finish.
Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 90));
  await pumpEventQueue();
}

void main() {
  late _FakeDataSource source;
  late _CountingEngine engine;
  late StreamController<void> changes;
  late DateTime now;
  SearchViewModel? created;

  SearchViewModel make({Duration debounce = _debounce}) {
    final vm = SearchViewModel(
      dataSource: source,
      engine: engine,
      debounce: debounce,
      dataChanges: changes.stream,
      clock: () => now,
    );
    created = vm;
    return vm;
  }

  setUp(() {
    source = _FakeDataSource(_sample());
    engine = _CountingEngine();
    changes = StreamController<void>.broadcast(sync: true);
    now = DateTime(2026, 10, 3, 9);
    created = null;
  });

  tearDown(() async {
    // Disposing twice is an error; a test that already disposed it says so.
    try {
      created?.dispose();
    } catch (_) {}
    await changes.close();
  });

  List<String> titles(SearchViewModel vm) =>
      vm.searchResults.map((r) => r.title).toList();

  group('the starting state', () {
    test('nothing asked, nothing shown', () {
      final vm = make();
      expect(vm.hasQuery, isFalse);
      expect(vm.hasAnswer, isFalse);
      expect(vm.hasResults, isFalse);
      expect(vm.isLoading, isFalse);
      expect(vm.errorKind, isNull);
      expect(vm.searchResults, isEmpty);
      expect(vm.resultsQuery, '');
      expect(source.loadCount, 0, reason: 'nothing is loaded until asked');
    });

    test('the default debounce is 300 ms', () {
      expect(
          SearchViewModel.defaultDebounce, const Duration(milliseconds: 300));
    });

    test('exactly one filter is selected: All', () {
      final vm = make();
      final selected = vm.filters.where((f) => f.selected).toList();
      expect(selected, hasLength(1));
      expect(selected.single.labelKey, 'all');
      expect(vm.selectedFilterKey, 'all');
    });
  });

  group('debounce', () {
    test('nothing runs until typing pauses', () async {
      final vm = make();
      vm.updateQuery('sam');
      expect(source.loadCount, 0);
      expect(engine.searches, 0);
      await _settle();
      expect(engine.searches, 1);
      expect(titles(vm), isNotEmpty);
    });

    test('rapid typing runs one search, for the last text', () async {
      final vm = make();
      vm.updateQuery('s');
      vm.updateQuery('sa');
      vm.updateQuery('sam');
      await _settle();
      expect(engine.searches, 1);
      expect(source.loadCount, 1);
      expect(vm.resultsQuery, 'sam');
      expect(titles(vm).toSet(), {'Sam Brown', 'Sam Office'});
    });

    test('typing that keeps going keeps postponing the search', () async {
      final vm = make(debounce: const Duration(milliseconds: 60));
      vm.updateQuery('s');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      vm.updateQuery('sa');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      vm.updateQuery('sam');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(engine.searches, 0, reason: 'each keystroke restarted the wait');
      await _settle();
      expect(engine.searches, 1);
    });

    test('the same text again is not a new query', () async {
      final vm = make();
      vm.updateQuery('sam');
      await _settle();
      expect(engine.searches, 1);
      vm.updateQuery('sam');
      await _settle();
      expect(engine.searches, 1);
    });

    test('only spacing or case changing keeps the answer on screen', () async {
      final vm = make();
      vm.updateQuery('sam');
      await _settle();
      final before = vm.searchResults;
      final searches = engine.searches;

      vm.updateQuery('sam ');
      vm.updateQuery('  SAM  ');
      await _settle();

      expect(engine.searches, searches);
      expect(identical(vm.searchResults, before), isTrue);
    });

    test('the keyboard Search action runs now, without waiting', () async {
      final vm = make(debounce: const Duration(seconds: 30));
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(vm.hasAnswer, isTrue);
      expect(titles(vm).toSet(), {'Sam Brown', 'Sam Office'});
    });

    test('submitting cancels a search that was waiting', () async {
      final vm = make();
      vm.updateQuery('sam');
      vm.submitQuery('sam');
      await _settle();
      expect(engine.searches, 1);
    });
  });

  group('empty and meaningless queries', () {
    test('blank, spaces and punctuation are the starting state', () async {
      final vm = make();
      for (final query in ['', '   ', '...', ' , ; ', '‏']) {
        vm.updateQuery(query);
        await _settle();
        expect(vm.hasQuery, isFalse, reason: 'query "$query"');
        expect(vm.hasAnswer, isFalse);
        expect(vm.searchResults, isEmpty);
      }
      expect(source.loadCount, 0, reason: 'no load for a meaningless query');
      expect(engine.searches, 0);
    });

    test('clearing returns to the starting state at once', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(vm.hasResults, isTrue);

      vm.updateQuery('');
      expect(vm.hasQuery, isFalse);
      expect(vm.hasAnswer, isFalse);
      expect(vm.searchResults, isEmpty);
      expect(vm.resultsQuery, '');
      expect(vm.errorKind, isNull);
    });

    test('clearing cancels a search that was waiting', () async {
      final vm = make();
      vm.updateQuery('sam');
      vm.updateQuery('');
      await _settle();
      expect(source.loadCount, 0);
      expect(engine.searches, 0);
      expect(vm.hasAnswer, isFalse);
    });

    test('clearing the filter chips does not clear the query', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      vm.toggleFilter(_owners);
      await pumpEventQueue();
      vm.toggleFilter(_owners);
      await pumpEventQueue();
      expect(vm.query, 'sam');
      expect(vm.resultsQuery, 'sam');
    });
  });

  group('latest query wins', () {
    test('a slow first answer cannot overwrite a newer query', () async {
      source.manual = true;
      final vm = make();
      final seen = <String>[];
      vm.addListener(
          () => seen.add('${vm.resultsQuery}:${vm.searchResults.length}'));

      vm.submitQuery('dub'); // starts loading
      vm.submitQuery('dubai'); // a newer query while the load is in flight
      expect(source.loadCount, 1, reason: 'both wait for the one load');

      source.finishNext();
      await pumpEventQueue();

      expect(vm.resultsQuery, 'dubai');
      // "dubai" is the owner's name and the Dubai offer (titled by its deal type).
      expect(titles(vm).toSet(), {'Dubai Owner', 'SELL'});
      expect(vm.isLoading, isFalse);
      expect(seen.any((s) => s.startsWith('dub:')), isFalse,
          reason: 'the superseded query never showed an answer');
    });

    test('clearing while loading leaves the starting state', () async {
      source.manual = true;
      final vm = make();
      vm.submitQuery('sam');
      expect(vm.isLoading, isTrue);

      vm.updateQuery('');
      expect(vm.isLoading, isFalse);

      source.finishNext();
      await pumpEventQueue();
      expect(vm.hasAnswer, isFalse);
      expect(vm.searchResults, isEmpty);
      expect(vm.isLoading, isFalse);
    });

    test('changing the filter while loading answers with the new filter',
        () async {
      source.manual = true;
      final vm = make();
      vm.submitQuery('sam');
      vm.toggleFilter(_offices);
      expect(source.loadCount, 1);

      source.finishNext();
      await pumpEventQueue();

      expect(titles(vm), ['Sam Office']);
      expect(vm.selectedFilterKey, 'offices');
    });

    test('a query changed during loading is answered once, not twice',
        () async {
      source.manual = true;
      final vm = make();
      vm.submitQuery('sam');
      vm.submitQuery('sam brown');
      source.finishNext();
      await pumpEventQueue();
      expect(engine.searches, 1, reason: 'the superseded search never ran');
      expect(titles(vm), ['Sam Brown']);
    });

    test('a search that has an answer keeps it while the next is pending',
        () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      final answered = vm.searchResults;

      vm.updateQuery('samir'); // waits for the debounce
      expect(identical(vm.searchResults, answered), isTrue);
      expect(vm.resultsQuery, 'sam', reason: 'the label names what is shown');
      expect(vm.hasAnswer, isTrue);
    });

    test('searching again does not flash a loading state', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();

      final loadingSeen = <bool>[];
      vm.addListener(() => loadingSeen.add(vm.isLoading));
      vm.submitQuery('dub');
      await pumpEventQueue();
      expect(loadingSeen, isNotEmpty);
      expect(loadingSeen.every((loading) => !loading), isTrue);
    });
  });

  group('one load', () {
    test('searches that arrive during a load share it', () async {
      source.manual = true;
      final vm = make();
      vm.submitQuery('sam');
      vm.submitQuery('dub');
      vm.toggleFilter(_owners);
      expect(source.loadCount, 1);
      source.finishNext();
      await pumpEventQueue();
      expect(source.loadCount, 1);
    });

    test('later searches reuse the loaded records', () async {
      final vm = make();
      for (final query in ['sam', 'dub', 'brown', 'office']) {
        vm.submitQuery(query);
        await pumpEventQueue();
      }
      expect(source.loadCount, 1);
    });

    test('a load that fails is not remembered', () async {
      source.failure = const SocketException('offline');
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(vm.errorKind, SearchErrorKind.network);
      expect(source.loadCount, 1);

      source.failure = null;
      vm.retry();
      await pumpEventQueue();
      expect(source.loadCount, 2, reason: 'retry reads the records again');
      expect(vm.errorKind, isNull);
      expect(vm.hasResults, isTrue);
    });

    test('shows loading only while there is nothing to search yet', () async {
      source.manual = true;
      final vm = make();
      vm.submitQuery('sam');
      expect(vm.isLoading, isTrue);
      source.finishNext();
      await pumpEventQueue();
      expect(vm.isLoading, isFalse);
    });
  });

  group('records stay fresh', () {
    test('a change to the user\'s data makes the next search read again',
        () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(source.loadCount, 1);

      changes.add(null);
      expect(source.loadCount, 1, reason: 'reloading waits until it is needed');

      vm.submitQuery('dub');
      await pumpEventQueue();
      expect(source.loadCount, 2);
    });

    test('a deleted record disappears when the Search tab is shown again',
        () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(titles(vm), contains('Sam Office'));

      // The office is deleted elsewhere in the app.
      source.data = SearchData(
        owners: [owner(id: 'o3', name: 'Sam Brown')],
      );
      changes.add(null);
      vm.refreshIfStale();
      await pumpEventQueue();

      expect(titles(vm), ['Sam Brown']);
      expect(source.loadCount, 2);
    });

    test('showing the tab again changes nothing when the records are fresh',
        () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      final answered = vm.searchResults;
      vm.refreshIfStale();
      await pumpEventQueue();
      expect(source.loadCount, 1);
      expect(identical(vm.searchResults, answered), isTrue);
    });

    test('showing the tab again with no query loads nothing', () async {
      final vm = make();
      vm.refreshIfStale();
      await pumpEventQueue();
      expect(source.loadCount, 0);
    });

    test('old records are read again', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();

      now = now.add(
          SearchViewModel.defaultCacheValidFor + const Duration(seconds: 1));
      vm.submitQuery('dub');
      await pumpEventQueue();
      expect(source.loadCount, 2);
    });

    test('records just inside their lifetime are reused', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      now = now.add(
          SearchViewModel.defaultCacheValidFor - const Duration(seconds: 1));
      vm.submitQuery('dub');
      await pumpEventQueue();
      expect(source.loadCount, 1);
    });

    test('records loaded for one user are never used for another', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(vm.hasResults, isTrue);

      source.userId = 'u2';
      source.manual = true;
      source.data = SearchData(owners: [owner(id: 'x1', name: 'Samira')]);
      vm.submitQuery('sam');
      expect(vm.isLoading, isTrue, reason: 'nothing of the first user to show');
      expect(source.loadCount, 2);

      source.finishNext();
      await pumpEventQueue();
      expect(titles(vm), ['Samira']);
    });

    test('records already loaded keep serving when a reload fails', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();

      changes.add(null);
      source.failure = const SocketException('offline');
      vm.submitQuery('brown');
      await pumpEventQueue();

      expect(vm.errorKind, isNull, reason: 'the old records still answer');
      expect(titles(vm), ['Sam Brown']);
    });

    test('data that changes while it loads is read again next time', () async {
      source.manual = true;
      final vm = make();
      vm.submitQuery('sam');
      changes.add(null); // a change lands while the load is in flight
      source.finishNext();
      await pumpEventQueue();
      expect(vm.hasAnswer, isTrue, reason: 'what was loaded is still shown');

      source.manual = false;
      vm.refreshIfStale();
      await pumpEventQueue();
      expect(source.loadCount, 2);
    });

    test('refreshing the cache by hand reads again', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      vm.refreshCache();
      await pumpEventQueue();
      expect(source.loadCount, 2);
    });
  });

  group('failures become safe states', () {
    for (final entry in <String, (Object, SearchErrorKind)>{
      'no connection': (const SocketException('x'), SearchErrorKind.network),
      'a timeout': (TimeoutException('slow'), SearchErrorKind.network),
      'a network client error': (ClientException(), SearchErrorKind.network),
      'a missing session': (
        StateError('A Supabase session is required.'),
        SearchErrorKind.session
      ),
      'an auth error': (
        const AuthException('JWT expired'),
        SearchErrorKind.session
      ),
      'a permission error': (
        const PostgrestException(message: 'denied', code: '42501'),
        SearchErrorKind.session,
      ),
      'a database error': (
        const PostgrestException(message: 'relation "x" does not exist'),
        SearchErrorKind.generic,
      ),
      'anything else': (Exception('boom'), SearchErrorKind.generic),
    }.entries) {
      test('${entry.key} is ${entry.value.$2.name}', () async {
        source.failure = entry.value.$1;
        final vm = make();
        vm.submitQuery('sam');
        await pumpEventQueue();

        expect(vm.errorKind, entry.value.$2);
        expect(vm.isLoading, isFalse);
        expect(vm.searchResults, isEmpty);
        expect(vm.hasAnswer, isFalse);
        expect(classifySearchError(entry.value.$1), entry.value.$2);
      });
    }

    test('an error state is not an empty answer', () async {
      source.failure = Exception('boom');
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(vm.errorKind, isNotNull);
      expect(vm.hasAnswer, isFalse);

      // A successful search that finds nothing is a different state.
      source.failure = null;
      vm.retry();
      await pumpEventQueue();
      vm.submitQuery('nobody-at-all');
      await pumpEventQueue();
      expect(vm.errorKind, isNull);
      expect(vm.hasAnswer, isTrue);
      expect(vm.hasResults, isFalse);
    });

    test('a retry that works clears the error', () async {
      source.failure = const SocketException('offline');
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      source.failure = null;
      vm.retry();
      await pumpEventQueue();
      expect(vm.errorKind, isNull);
      expect(vm.hasResults, isTrue);
    });

    test('retry with nothing typed does nothing', () async {
      final vm = make();
      vm.retry();
      await pumpEventQueue();
      expect(source.loadCount, 0);
    });

    test('a new query after an error searches again', () async {
      source.failure = const SocketException('offline');
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      source.failure = null;
      vm.submitQuery('dub');
      await pumpEventQueue();
      expect(vm.errorKind, isNull);
      expect(vm.hasResults, isTrue);
    });

    test('the view-model exposes a kind, never the technical message', () {
      // errorKind is an enum: there is no field the raw exception could be in.
      final vm = make();
      expect(vm.errorKind, isNull);
      expect(SearchErrorKind.values.map((k) => k.name),
          ['network', 'session', 'generic']);
    });
  });

  group('the filter chips', () {
    test('choosing a chip limits the results to that type', () async {
      final vm = make();
      vm.submitQuery('dub');
      await pumpEventQueue();
      expect(
          vm.searchResults.map((r) => r.type).toSet().length, greaterThan(1));

      vm.toggleFilter(_owners);
      await pumpEventQueue();
      expect(vm.searchResults.map((r) => r.type).toSet(),
          {SearchResultType.owner});
      expect(vm.selectedFilterKey, 'owners');
    });

    test('every chip maps to its own type', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      for (final entry in {
        _offices: SearchResultType.office,
        _owners: SearchResultType.owner,
      }.entries) {
        vm.toggleFilter(entry.key);
        await pumpEventQueue();
        expect(vm.searchResults.every((r) => r.type == entry.value), isTrue,
            reason: vm.selectedFilterKey);
        expect(vm.searchResults, isNotEmpty);
      }
    });

    test('exactly one chip is selected after any tap', () async {
      final vm = make();
      for (var i = 0; i < vm.filters.length; i++) {
        vm.toggleFilter(i);
        expect(vm.filters.where((f) => f.selected), hasLength(1), reason: '$i');
      }
    });

    test('tapping the chosen chip goes back to All', () async {
      final vm = make();
      vm.toggleFilter(_owners);
      expect(vm.selectedFilterKey, 'owners');
      vm.toggleFilter(_owners);
      expect(vm.selectedFilterKey, 'all');
      expect(vm.filters.first.selected, isTrue);
    });

    test('tapping All when All is chosen changes nothing', () async {
      final vm = make();
      var notified = 0;
      vm.addListener(() => notified++);
      vm.toggleFilter(_all);
      expect(notified, 0);
      expect(vm.selectedFilterKey, 'all');
    });

    test('a chip that hides every result can be cleared', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      vm.toggleFilter(_offers); // there is no offer called sam
      await pumpEventQueue();
      expect(vm.hasAnswer, isTrue);
      expect(vm.hasResults, isFalse);

      vm.toggleFilter(_offers); // the same chip again
      await pumpEventQueue();
      expect(vm.selectedFilterKey, 'all');
      expect(vm.hasResults, isTrue);
    });

    test('changing the chip runs exactly one search', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      final before = engine.searches;
      vm.toggleFilter(_owners);
      await pumpEventQueue();
      expect(engine.searches, before + 1);
    });

    test('changing the chip while a search waits runs one, not two', () async {
      final vm = make();
      vm.updateQuery('sam'); // waiting for the debounce
      vm.toggleFilter(_owners);
      await _settle();
      expect(engine.searches, 1);
      expect(titles(vm), ['Sam Brown']);
    });

    test('with nothing typed, a chip changes only the chip', () async {
      final vm = make();
      vm.toggleFilter(_owners);
      await pumpEventQueue();
      expect(source.loadCount, 0);
      expect(engine.searches, 0);
      expect(vm.selectedFilterKey, 'owners');
    });

    test('an index that is not a chip is ignored', () {
      final vm = make();
      vm.toggleFilter(-1);
      vm.toggleFilter(99);
      expect(vm.selectedFilterKey, 'all');
    });

    test('reading the selected chip never changes it', () {
      final vm = make();
      for (final FilterModel f in vm.filters) {
        f.selected = false;
      }
      expect(vm.selectedFilter, same(vm.filters.first));
      expect(vm.filters.first.selected, isFalse,
          reason: 'a getter must not change state');
      expect(vm.selectedFilterKey, 'all');
    });

    test('a filtered answer never keeps results of the previous filter',
        () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      vm.toggleFilter(_owners);
      await pumpEventQueue();
      expect(titles(vm), ['Sam Brown']);
      vm.toggleFilter(_offices);
      await pumpEventQueue();
      expect(titles(vm), ['Sam Office']);
    });
  });

  group('the answer', () {
    test('is the collapsed query and unmodifiable', () async {
      final vm = make();
      vm.submitQuery('  Sam   Brown ');
      await pumpEventQueue();
      expect(vm.resultsQuery, 'Sam Brown');
      expect(
          vm.searchResults.every((r) => r.searchQuery == 'Sam Brown'), isTrue);
      expect(() => vm.searchResults.add(vm.searchResults.first),
          throwsUnsupportedError);
    });

    test('has no record twice', () async {
      source.data = SearchData(owners: [
        owner(id: 'o1', name: 'Sam'),
        owner(id: 'o1', name: 'Sam'),
      ]);
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      expect(vm.searchResults, hasLength(1));
    });

    test('is empty, not an error, when nothing matches', () async {
      final vm = make();
      vm.submitQuery('zzzz');
      await pumpEventQueue();
      expect(vm.hasAnswer, isTrue);
      expect(vm.hasResults, isFalse);
      expect(vm.errorKind, isNull);
      expect(vm.isLoading, isFalse);
    });

    test('finds Arabic text however it is typed', () async {
      source.data = SearchData(owners: [owner(id: 'o1', name: 'أحمد')]);
      final vm = make();
      vm.submitQuery('احمد');
      await pumpEventQueue();
      expect(vm.hasResults, isTrue);
    });
  });

  group('nothing happens after the screen is gone', () {
    test('disposing while loading is safe and silent', () async {
      source.manual = true;
      final vm = make();
      var notified = 0;
      vm.addListener(() => notified++);
      vm.submitQuery('sam');
      final before = notified;

      vm.dispose();
      source.finishNext();
      await pumpEventQueue();

      expect(notified, before, reason: 'no notification after dispose');
    });

    test('disposing cancels a search that was waiting', () async {
      final vm = make();
      vm.updateQuery('sam');
      vm.dispose();
      await _settle();
      expect(source.loadCount, 0);
      expect(engine.searches, 0);
    });

    test('disposing stops listening for data changes', () async {
      final vm = make();
      vm.submitQuery('sam');
      await pumpEventQueue();
      vm.dispose();
      expect(changes.hasListener, isFalse);
      changes.add(null); // must not throw
    });

    test('a failing load after dispose is swallowed', () async {
      source.manual = true;
      final vm = make();
      vm.submitQuery('sam');
      vm.dispose();
      source.pending.removeAt(0).completeError(const SocketException('x'));
      await pumpEventQueue();
    });

    test('using it after dispose does not throw', () async {
      final vm = make();
      vm.dispose();
      vm.updateQuery('sam');
      vm.submitQuery('sam');
      vm.toggleFilter(_owners);
      vm.retry();
      vm.refreshIfStale();
      await _settle();
    });
  });

  group('classifySearchError', () {
    test('network failures', () {
      expect(classifySearchError(const SocketException('x')),
          SearchErrorKind.network);
      expect(
          classifySearchError(TimeoutException('x')), SearchErrorKind.network);
      expect(classifySearchError(ClientException()), SearchErrorKind.network);
    });

    test('session failures', () {
      expect(classifySearchError(StateError('A session is required.')),
          SearchErrorKind.session);
      expect(classifySearchError(const AuthException('x')),
          SearchErrorKind.session);
      for (final code in ['42501', 'PGRST301', 'PGRST303']) {
        expect(
          classifySearchError(PostgrestException(message: 'm', code: code)),
          SearchErrorKind.session,
          reason: code,
        );
      }
    });

    test('everything else is generic', () {
      expect(classifySearchError(StateError('something else')),
          SearchErrorKind.generic);
      expect(classifySearchError(const FormatException('x')),
          SearchErrorKind.generic);
      expect(
          classifySearchError(
              const PostgrestException(message: 'm', code: '23505')),
          SearchErrorKind.generic);
      expect(classifySearchError('a string'), SearchErrorKind.generic);
    });
  });
}
