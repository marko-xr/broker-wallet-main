// How the Home filters are wired, and what a person is told when they fail.
//
//  * the failure sorting and the words for it (the app's own strings, never the
//    technical error);
//  * guards over the source that keep the retired path from coming back: no
//    backend switch that turns the filters off, no Firestore read, no stream
//    combiner that shows a part of the answer, no unsupported Quotation tile.
//
// Source guards prove what the code says, not how a device behaves.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_controller.dart';
import 'package:broker_wallet/src/viewmodels/home_filter_errors.dart';
import 'package:broker_wallet/src/views/Widgets/filtered_items_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Future<AppLocalizations> _l10n(String languageCode) async {
  final l = AppLocalizations(Locale(languageCode));
  await l.load();
  return l;
}

/// The imports of a Dart file, one per line.
List<String> _imports(String path) => [
      for (final line in _source(path).split('\n'))
        if (line.startsWith('import ')) line,
    ];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    await AppLocalizations.preloadAllLanguages();
  });

  group('a failure is sorted for the person, not shown', () {
    test('no connection, a timeout and a socket error are connection problems',
        () {
      expect(classifyHomeFilterError(TimeoutException('too slow')),
          HomeFilterErrorKind.network);
      expect(classifyHomeFilterError(const SocketException('no route')),
          HomeFilterErrorKind.network);
    });

    test('a missing or expired sign-in is a session problem', () {
      expect(
          classifyHomeFilterError(
              StateError('A Supabase session is required.')),
          HomeFilterErrorKind.session);
      expect(classifyHomeFilterError(AuthException('JWT expired')),
          HomeFilterErrorKind.session);
      expect(
          classifyHomeFilterError(
              PostgrestException(message: 'denied', code: '42501')),
          HomeFilterErrorKind.session);
    });

    test('anything else is generic', () {
      expect(classifyHomeFilterError(Exception('boom')),
          HomeFilterErrorKind.generic);
      expect(
          classifyHomeFilterError(
              PostgrestException(message: 'duplicate', code: '23505')),
          HomeFilterErrorKind.generic);
      expect(classifyHomeFilterError(ArgumentError('x')),
          HomeFilterErrorKind.generic);
    });
  });

  group('the words for a failure', () {
    for (final code in ['en', 'ar']) {
      test('each kind has its own sentence from the ARB file: $code', () async {
        final l = await _l10n(code);
        final network =
            FilteredItemsView.errorMessage(l, HomeFilterErrorKind.network);
        final session =
            FilteredItemsView.errorMessage(l, HomeFilterErrorKind.session);
        final generic =
            FilteredItemsView.errorMessage(l, HomeFilterErrorKind.generic);

        expect(
            network, AppLocalizations.translateFor(code, 'authNetworkFailed'));
        expect(
            session, AppLocalizations.translateFor(code, 'userSessionExpired'));
        expect(generic, AppLocalizations.translateFor(code, 'errorOccurred'));
        for (final text in [network, session, generic]) {
          expect(text.trim(), isNotEmpty);
          expect(text.contains('not found'), isFalse,
              reason: 'a missing key would show "** key not found"');
        }
        expect({network, session, generic}, hasLength(3));
      });
    }

    test('every string the Home filters show exists in both languages', () {
      for (final code in ['en', 'ar']) {
        for (final key in [
          'recentlyAdded',
          'lessPrice',
          'thisWeek',
          'highestPrice',
          'recentlyUpdated',
          'homeFilterComingSoonTitle',
          'homeFilterComingSoonDesc',
          'loadingFilteredItems',
          'noFilteredItems',
          'noFilteredItemsDesc',
          'tryAgain',
          'authNetworkFailed',
          'userSessionExpired',
          'errorOccurred',
        ]) {
          final text = AppLocalizations.translateFor(code, key);
          expect(text, isNotNull, reason: '$code $key');
          expect(text!.trim(), isNotEmpty, reason: '$code $key');
        }
      }
    });
  });

  group('the retired Firebase-only path stays retired', () {
    final viewModel = _source('lib/src/viewmodels/home_viewmodel.dart');

    test('a tap is handed straight to the filter controller, whatever the mode',
        () {
      expect(
          viewModel.contains(
              'void toggleFilter(int index) => _filters.toggle(index);'),
          isTrue);
      // Auth mode is consulted for the counts and nothing else: the start-up of
      // the counts and their refresh.
      expect(
          RegExp(r'SupabaseConfig\.useSupabaseAuth')
              .allMatches(viewModel)
              .length,
          2);
    });

    test('there is no stream combiner left to show a part of the answer', () {
      for (final retired in [
        '_subscribeToFilteredData',
        '_subscribeToMultipleStreams',
        '_filterSubscriptions',
        '_updateFilteredCounts',
        '_applyRecentlyAddedFilter',
        '_filteredItems',
        '_isFilterLoading',
      ]) {
        expect(viewModel.contains(retired), isFalse, reason: retired);
      }
    });

    test('the filters read through the view model\'s own services', () {
      expect(viewModel.contains('SnapshotHomeFilterDataSource('), isTrue);
      for (final read in [
        'requests: _requestService.getUserRequests',
        'offers: _offerService.getUserOffers',
        'brokers: _brokerService.getUserBrokers',
        'owners: _ownerService.getUserOwners',
        'offices: _officeService.getUserOffices',
        'watchmen: _watchmenService.getUserWatchmen',
      ]) {
        expect(viewModel.contains(read), isTrue, reason: read);
      }
    });

    test('the filter logic imports no backend of its own', () {
      for (final path in [
        'lib/src/viewmodels/home_filter_rules.dart',
        'lib/src/viewmodels/home_filter_controller.dart',
        'lib/src/viewmodels/home_filter_data_source.dart',
      ]) {
        for (final line in _imports(path)) {
          for (final backend in [
            'cloud_firestore',
            'firebase',
            'supabase_flutter',
            'repository_provider',
            'supabase_config',
            'ScreenServices',
          ]) {
            expect(line.contains(backend), isFalse, reason: '$path: $line');
          }
        }
      }
    });

    test('no Firestore is touched by the filter files', () {
      for (final path in [
        'lib/src/viewmodels/home_filter_rules.dart',
        'lib/src/viewmodels/home_filter_controller.dart',
        'lib/src/viewmodels/home_filter_data_source.dart',
        'lib/src/viewmodels/home_filter_errors.dart',
      ]) {
        final source = _source(path);
        expect(source.contains('Firestore'), isFalse, reason: path);
        expect(source.contains('Supabase.instance'), isFalse, reason: path);
      }
    });
  });

  group('the answer is whole, fresh, and never invented', () {
    final controller =
        _source('lib/src/viewmodels/home_filter_controller.dart');
    final dataSource =
        _source('lib/src/viewmodels/home_filter_data_source.dart');
    final rules = _source('lib/src/viewmodels/home_filter_rules.dart');
    final viewModel = _source('lib/src/viewmodels/home_viewmodel.dart');

    test('the records are read together and waited for as a whole', () {
      expect(
          dataSource.contains('Future.wait(reads, eagerError: true)'), isTrue);
      expect(dataSource.contains('await records.first'), isTrue,
          reason: 'one snapshot, then let go');
      expect(dataSource.contains('.listen('), isFalse);
    });

    test('nothing is timed, polled or delayed', () {
      for (final source in [controller, dataSource, rules]) {
        expect(source.contains('Future.delayed'), isFalse);
        expect(source.contains('Timer('), isFalse);
        expect(source.contains('Timer.periodic'), isFalse);
        expect(source.contains('Stream.periodic'), isFalse);
      }
      // The only clock is a bound on a read that never answers.
      expect(controller.contains('.timeout(loadTimeout)'), isTrue);
    });

    test('the time comes in; no rule reads a clock of its own', () {
      expect(rules.contains('DateTime.now'), isFalse);
      expect(controller.contains('DateTime.now()'), isFalse,
          reason: 'only the injected clock, defaulting to the tear-off');
      expect(controller.contains('clock ?? DateTime.now'), isTrue);
    });

    test('a late answer is stamped out by a generation', () {
      expect(controller.contains('int _generation'), isTrue);
      expect(controller.contains('bool _isCurrent(int generation)'), isTrue);
      // Every read checks it twice over: on success and on failure.
      expect(
          RegExp(r'if \(!_isCurrent\(generation\)\) return;')
              .allMatches(controller)
              .length,
          2);
    });

    test('a pull keeps the chosen filter; leaving or signing out drops it', () {
      expect(
          viewModel.contains(
              'Future<void> refreshCounts({bool keepFilter = false})'),
          isTrue);
      expect(viewModel.contains('_filters.refresh()'), isTrue);
      expect(viewModel.contains('if (!keepFilter) _filters.clear();'), isTrue);
      expect(viewModel.contains('void clearAllFilters() => _filters.clear();'),
          isTrue);
      final signedOut = viewModel.substring(
        viewModel.indexOf('void _resetCountsForSignedOutUser()'),
        viewModel.indexOf('/// Initialize live streams'),
      );
      // Signing out also forgets every record that was read for the filters.
      expect(signedOut.contains('_filters.reset();'), isTrue);
      expect(signedOut.contains('_filters.clear();'), isFalse);
    });

    test('the records kept for the filters are tied to the signed-in account',
        () {
      expect(
          viewModel
              .contains('currentUserId: () => _authRepository.currentUserId,'),
          isTrue);
    });

    test('the home screen\'s pull asks to keep the filter', () {
      final view = _source('lib/src/views/Screens/home_view.dart');
      expect(view.contains('vm.refreshCounts(keepFilter: true)'), isTrue);
    });

    test('a change to the user\'s own records re-reads a chosen filter', () {
      final subscription = viewModel.substring(
        viewModel.indexOf('CoreEntityMutationNotifier.changes.listen'),
        viewModel.indexOf('Future<void> _loadSupabaseCounts()'),
      );
      expect(subscription.contains('_filters.onDataChanged();'), isTrue);
      expect(subscription.contains('_loadSupabaseCounts()'), isTrue,
          reason: 'the counts are still refreshed by it');
    });

    test('the filter owns its own state', () {
      expect(viewModel.contains('late final HomeFilterController _filters'),
          isTrue);
      expect(viewModel.contains('_filters.dispose();'), isTrue);
      // What the view model exposes about a filter is a read of the controller.
      for (final member in [
        'List<FilterModel> get filters => _filters.filters;',
        'List<UnifiedItemModel> get filteredItems => _filters.items;',
        'FilterModel? get selectedFilter => _filters.selectedFilter;',
        'bool get isFilterLoading => _filters.isLoading;',
        'bool get isFilterUnavailable => _filters.isUnavailable;',
        'HomeFilterErrorKind? get filterErrorKind => _filters.errorKind;',
        'void retryFilter() => _filters.retry();',
      ]) {
        expect(viewModel.contains(member), isTrue, reason: member);
      }
    });

    test('a filter never touches the canonical counts or their cache', () {
      // The controller knows nothing of the counts or their cache.
      for (final canonical in [
        'Count',
        'count_cache',
        'CountCache',
        'updateCachedCounts',
      ]) {
        expect(
            controller.replaceAll('countOf', '').contains(canonical), isFalse,
            reason: 'controller mentions $canonical');
      }
      // The counts are cached only by their own loader, so a filtered answer
      // can never be stored as a count.
      expect(RegExp(r'updateCachedCounts\(').allMatches(viewModel).length, 1);
      // With a filter chosen the grid's numbers come from its answer; with none
      // they are the canonical ones, untouched.
      expect(
          viewModel.contains(
              'hasSelectedFilter ? _filters.countOf(type) : unfiltered'),
          isTrue);
      for (final pair in {
        'ItemType.request': '_requestedCount',
        'ItemType.offer': '_offersCount',
        'ItemType.owner': '_ownersCount',
        'ItemType.office': '_officesCount',
        'ItemType.broker': '_brokersCount',
        'ItemType.watchmen': '_watchmenCount',
        'ItemType.quotation': '_quotationCount',
      }.entries) {
        expect(viewModel.contains('count(${pair.key}, ${pair.value})'), isTrue,
            reason: '${pair.key} falls back to ${pair.value}');
      }
    });
  });

  group('Quotations are outside the Home filters', () {
    test('nothing reads them and no tile is drawn for them', () {
      final dataSource =
          _source('lib/src/viewmodels/home_filter_data_source.dart');
      expect(dataSource.contains('ItemType.quotation'), isFalse);
      expect(dataSource.contains('fromQuotation'), isFalse);

      final view = _source('lib/src/views/Widgets/filtered_items_view.dart');
      expect(view.contains('UnimplementedError'), isFalse,
          reason: 'an unsupported kind must not crash the list');
      expect(view.contains('case ItemType.quotation:'), isTrue);
    });

    test('the model has one definition of "recent", in the rules', () {
      final model = _source('lib/src/data/models/unified_item_model.dart');
      expect(model.contains('isRecentlyAdded'), isFalse);
      expect(model.contains('isThisWeek'), isFalse);
      expect(model.contains('hasCreatedAt: broker.createdAt != null'), isTrue);
      expect(model.contains('hasCreatedAt: office.createdAt != null'), isTrue);
      expect(
          model.contains('hasCreatedAt: watchmen.createdAt != null'), isTrue);
      expect(model.contains('hasUpdatedAt: broker.updatedAt != null'), isTrue);
      expect(model.contains('hasUpdatedAt: office.updatedAt != null'), isTrue);
      expect(
          model.contains('hasUpdatedAt: watchmen.updatedAt != null'), isTrue);
    });
  });

  group('the filtered list tells a failure from "no items"', () {
    final view = _source('lib/src/views/Widgets/filtered_items_view.dart');

    test('a failure has its own state with a retry, before the empty state',
        () {
      expect(view.contains('vm.filterErrorKind'), isTrue);
      expect(view.contains('vm.retryFilter'), isTrue);
      expect(view.indexOf('vm.filterErrorKind'),
          lessThan(view.indexOf('vm.filteredItems.isEmpty')));
      expect(view.contains("loc.translate('tryAgain')"), isTrue);
    });

    test('only the app\'s own sentences are shown, never the error', () {
      final errorState = view.substring(
        view.indexOf('static String errorMessage'),
        view.indexOf('Widget _buildEmptyState('),
      );
      expect(errorState.contains("loc.translate('authNetworkFailed')"), isTrue);
      expect(
          errorState.contains("loc.translate('userSessionExpired')"), isTrue);
      expect(errorState.contains("loc.translate('errorOccurred')"), isTrue);
      for (final leak in [r'$error', 'toString()', 'exception', 'Exception']) {
        expect(errorState.contains(leak), isFalse, reason: leak);
      }
    });

    test('the loading state appears only after a short delay, never at once',
        () {
      final loading = view.substring(
        view.indexOf('Widget _buildLoadingState('),
        view.indexOf('static String errorMessage'),
      );
      expect(loading.contains('DelayedReveal('), isTrue);
      expect(loading.contains('CircularProgressIndicator('), isTrue);
      expect(loading.indexOf('DelayedReveal('),
          lessThan(loading.indexOf('CircularProgressIndicator(')),
          reason: 'the spinner is inside the delay, not beside it');
    });

    test('a short result can still be pulled to refresh', () {
      expect(view.contains('physics: const AlwaysScrollableScrollPhysics()'),
          isTrue);
    });

    test(
        'Recently Updated shows when a record last changed, the rest when it was added',
        () {
      expect(
          view.contains(
              'vm.selectedFilterKey == HomeFilterKind.recentlyUpdated.labelKey'),
          isTrue);
      expect(
          view.contains(
              'date: showsUpdateDate ? item.updatedAt : item.createdAt'),
          isTrue);
      // Every tile gets the chosen date, never the creation time directly.
      expect(view.contains('createdAt: item.createdAt'), isFalse);
      expect(RegExp(r'createdAt: date,').allMatches(view).length, 6);
    });

    test('a chip whose filter is not built says so, ahead of both', () {
      expect(view.contains('vm.isFilterUnavailable'), isTrue);
      expect(view.indexOf('vm.isFilterUnavailable'),
          lessThan(view.indexOf('vm.filterErrorKind')));
      expect(view.indexOf('vm.isFilterUnavailable'),
          lessThan(view.indexOf('vm.filteredItems.isEmpty')));
      final state = view.substring(
        view.indexOf('Widget _buildComingSoonState('),
        view.indexOf('Widget _buildEmptyState('),
      );
      expect(
          state.contains("loc.translate('homeFilterComingSoonTitle')"), isTrue);
      expect(
          state.contains("loc.translate('homeFilterComingSoonDesc')"), isTrue);
      // It must not borrow the words that say a filter ran and found nothing.
      expect(state.contains('noFilteredItems'), isFalse);
    });

    test('and its words are its own in both languages', () {
      for (final code in ['en', 'ar']) {
        final title =
            AppLocalizations.translateFor(code, 'homeFilterComingSoonTitle')!;
        final description =
            AppLocalizations.translateFor(code, 'homeFilterComingSoonDesc')!;
        expect(title,
            isNot(AppLocalizations.translateFor(code, 'noFilteredItems')),
            reason: code);
        expect(description,
            isNot(AppLocalizations.translateFor(code, 'noFilteredItemsDesc')),
            reason: code);
        expect(title.trim(), isNotEmpty, reason: code);
        expect(description.trim(), isNotEmpty, reason: code);
      }
    });
  });
}
