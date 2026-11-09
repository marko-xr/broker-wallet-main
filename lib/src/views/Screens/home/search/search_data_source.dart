import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/list_session_check.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'search_engine.dart';
import 'search_result.dart';

/// Where Search gets the records it looks through.
///
/// Search is local: it loads the signed-in user's own records once and searches
/// that copy. A data source is only that loading step, so the search itself can
/// be tested without a backend.
abstract class SearchDataSource {
  /// The signed-in user's id, or null when nobody is signed in. A copy of the
  /// records made for one user is never used for another.
  String? get currentUserId;

  /// Loads the signed-in user's records. Throws when they cannot be read — the
  /// caller decides what the user is told.
  Future<SearchData> load();
}

/// What this device saved for the signed-in account, as Search reads it
/// before (or without) the server.
class SavedSearchData {
  const SavedSearchData(this.data, this.covered);

  static const SavedSearchData none =
      SavedSearchData(SearchData(), <SearchResultType>{});

  final SearchData data;

  /// The kinds whose saved list could be read. Every other kind has no saved
  /// list on this device that can be trusted — which is not an empty list.
  final Set<SearchResultType> covered;

  bool get isEmpty => covered.isEmpty;
}

/// A [SearchDataSource] that can also answer from this device's saved lists.
abstract interface class LocalFirstSearchSource {
  /// The signed-in session; records read under one session are never used
  /// under another, even of the same account.
  String? get currentSessionId;

  /// This account's saved lists, read from this device only. Never throws.
  Future<SavedSearchData> loadSaved();

  /// Stops every server read in flight: their loads fail and nothing they
  /// read is returned. For a Search screen that has closed.
  void cancelReads();
}

/// The six server lists Search reads, each a stream whose first list is the
/// whole, complete list (see [SupabaseCoreEntitiesService]).
class SearchServerLists {
  const SearchServerLists({
    required this.requests,
    required this.offers,
    required this.owners,
    required this.offices,
    required this.brokers,
    required this.watchmen,
  });

  factory SearchServerLists.supabase(SupabaseCoreEntitiesService service) =>
      SearchServerLists(
        requests: service.getRequests,
        offers: service.getOffers,
        owners: service.getOwners,
        offices: service.getOffices,
        brokers: service.getBrokers,
        watchmen: service.getWatchmen,
      );

  final Stream<List<RequestModel>> Function() requests;
  final Stream<List<OfferModel>> Function() offers;
  final Stream<List<OwnerModel>> Function() owners;
  final Stream<List<OfficeModel>> Function() offices;
  final Stream<List<BrokerModel>> Function() brokers;
  final Stream<List<WatchmenModel>> Function() watchmen;
}

/// The app's own data: this device's saved lists first, then Supabase.
///
/// Every server read is scoped to the signed-in user (by `owner_id` and RLS),
/// and every saved list is that account's own encrypted copy, so Search can
/// never see another user's records. Nothing is created until it is first
/// used.
class DefaultSearchDataSource
    implements SearchDataSource, LocalFirstSearchSource {
  /// Every parameter is for tests only; production uses the canonical
  /// signed-in account and session, the six encrypted list caches, the
  /// Supabase lists and the shared session check.
  DefaultSearchDataSource({
    @visibleForTesting String? Function()? currentUserId,
    @visibleForTesting String? Function()? currentSession,
    @visibleForTesting SearchServerLists? serverLists,
    @visibleForTesting
    Future<bool>? Function(String? session)? confirmEmptyList,
  })  : _currentUserId = currentUserId,
        _currentSession = currentSession ?? ListSessionCheck.currentSession,
        _server = serverLists,
        _confirmEmpty = confirmEmptyList ?? ListSessionCheck.confirmFor;

  final String? Function()? _currentUserId;
  final String? Function() _currentSession;
  final Future<bool>? Function(String? session) _confirmEmpty;
  SearchServerLists? _server;
  final Set<_Reads> _inFlight = <_Reads>{};

  @override
  String? get currentUserId {
    final override = _currentUserId;
    if (override != null) return override();
    return RepositoryProvider.instance.authRepository.currentUserId;
  }

  @override
  String? get currentSessionId => _currentSession();

  String? _safeUserId() {
    try {
      return currentUserId;
    } catch (_) {
      return null;
    }
  }

  String? _safeSession() {
    try {
      return currentSessionId;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SavedSearchData> loadSaved() async {
    final uid = _safeUserId();
    if (uid == null || uid.isEmpty) return SavedSearchData.none;
    final session = _safeSession();

    // Each read checks the list's integrity, keeps only this account's
    // records and hides any the server confirmed deleted; a list that cannot
    // be read safely comes back null.
    final requests = const RequestsLocalCache().read(uid);
    final offers = const OffersLocalCache().read(uid);
    final owners = const OwnersLocalCache().read(uid);
    final offices = const OfficesLocalCache().read(uid);
    final brokers = const BrokersLocalCache().read(uid);
    final watchmen = const WatchmenLocalCache().read(uid);
    final r = await requests;
    final f = await offers;
    final o = await owners;
    final c = await offices;
    final b = await brokers;
    final w = await watchmen;

    if (_safeUserId() != uid || _safeSession() != session) {
      return SavedSearchData.none;
    }
    return SavedSearchData(
      SearchData(
        requests: r ?? const <RequestModel>[],
        offers: f ?? const <OfferModel>[],
        owners: o ?? const <OwnerModel>[],
        offices: c ?? const <OfficeModel>[],
        brokers: b ?? const <BrokerModel>[],
        watchmen: w ?? const <WatchmenModel>[],
      ),
      {
        if (r != null) SearchResultType.request,
        if (f != null) SearchResultType.offer,
        if (o != null) SearchResultType.owner,
        if (c != null) SearchResultType.office,
        if (b != null) SearchResultType.broker,
        if (w != null) SearchResultType.watchmen,
      },
    );
  }

  @override
  Future<SearchData> load() async {
    final session = _safeSession();
    final lists =
        _server ??= SearchServerLists.supabase(SupabaseCoreEntitiesService());
    final reads = _Reads();
    _inFlight.add(reads);
    try {
      // Each list's first answer is that whole list. A failure of any one
      // fails the load at once and stops the others, so no partial set is
      // ever returned and no page is read for nothing.
      final results = await Future.wait<List<Object?>>(
        [
          reads.first(lists.requests()),
          reads.first(lists.offers()),
          reads.first(lists.owners()),
          reads.first(lists.offices()),
          reads.first(lists.brokers()),
          reads.first(lists.watchmen()),
        ],
        eagerError: true,
      );
      // The database answers a replaced session's reads with no rows, not an
      // error: an empty list is taken only once this session is confirmed
      // (as the list screens do). A list with rows needs no check.
      if (results.any((rows) => rows.isEmpty)) {
        final check = _confirmEmpty(session);
        if (check != null && !await check) throw const ListSessionNotCurrent();
      }
      reads.ensureWanted();
      return SearchData(
        requests: results[0].cast<RequestModel>(),
        offers: results[1].cast<OfferModel>(),
        owners: results[2].cast<OwnerModel>(),
        offices: results[3].cast<OfficeModel>(),
        brokers: results[4].cast<BrokerModel>(),
        watchmen: results[5].cast<WatchmenModel>(),
      );
    } finally {
      reads.stop();
      _inFlight.remove(reads);
    }
  }

  @override
  void cancelReads() {
    for (final reads in List<_Reads>.of(_inFlight)) {
      reads.stop(cancelled: true);
    }
  }
}

/// Search closed while its records were being read.
class SearchReadCancelled implements Exception {
  const SearchReadCancelled();

  @override
  String toString() => 'SearchReadCancelled';
}

/// The server reads of one load: each list's first answer, and a way to stop
/// all of them. Stopping cancels the subscriptions, which ends the paging of
/// any list still being read.
class _Reads {
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<Completer<List<Object?>>> _waiting = [];
  bool _cancelled = false;

  Future<List<Object?>> first<T>(Stream<List<T>> stream) {
    final completer = Completer<List<Object?>>();
    _waiting.add(completer);
    if (_cancelled) {
      completer.completeError(const SearchReadCancelled());
      return completer.future;
    }
    late final StreamSubscription<List<T>> subscription;
    subscription = stream.listen(
      (rows) {
        if (!completer.isCompleted) completer.complete(rows);
        unawaited(subscription.cancel());
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
        unawaited(subscription.cancel());
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('list ended without an answer'));
        }
      },
      cancelOnError: true,
    );
    _subscriptions.add(subscription);
    return completer.future;
  }

  void ensureWanted() {
    if (_cancelled) throw const SearchReadCancelled();
  }

  void stop({bool cancelled = false}) {
    if (cancelled) _cancelled = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final completer in _waiting) {
      if (!completer.isCompleted) {
        completer.completeError(const SearchReadCancelled());
      }
    }
  }
}
