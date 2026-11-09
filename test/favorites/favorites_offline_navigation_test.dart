// A favorite drawn from the saved Favorites copy carries no record. Tapping a
// Requests, Owners, Offices, Brokers or Watchmen one used to push its details
// route with `extra: null`, and those routes force-cast `state.extra`, so the
// tap threw `type 'Null' is not a subtype of type 'OwnerModel'` (reproduced
// against the unchanged code for all five kinds). The card now opens them with
// this account's own saved record, or opens nothing and says so.
//
// Widget tests use routes that cast `state.extra` exactly as `app.dart` does
// (a source check below keeps the two the same). The lookup is tested against
// the real encrypted list caches in a temporary Hive directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_card.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/favorite_saved_records.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/r2_test_fakes.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';

const _kinds = ['requests', 'owners', 'offices', 'brokers', 'watchmen'];

RequestModel _request(String id, String account) => RequestModel(
      id: id,
      userId: account,
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina'],
      location: 'Tower 1',
      phoneNumber: '500000000',
      countryCode: '+971',
      minPrice: '1000',
      maxPrice: '2000',
      squareFootage: '900',
      notes: 'note $id',
      propertyType: 'residential',
      specificPropertyType: 'apartment',
      rooms: 2,
      bathrooms: 1,
      status: PropertyStatus.active,
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      updatedAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
    );

OwnerModel _owner(String id, String account) => OwnerModel(
      id: id,
      userId: account,
      name: 'Owner $id',
      phoneNumber: '502223344',
      countryCode: '+971',
      typeOfProperties: 'Villa',
      propertyLocation: 'Palm Jumeirah',
      notes: 'notes $id',
      pickUpLocation: 'Gate 3',
      pickUpLatitude: 25.2048,
      pickUpLongitude: 55.2708,
      pickUpAddress: 'Frond K',
      mediaUrls: const [],
      createdAt: DateTime.utc(2026, 5, 6, 7, 8, 9),
      updatedAt: DateTime.utc(2026, 6, 7, 8, 9, 10),
    );

OfficeModel _office(String id, String account) => OfficeModel(
      id: id,
      userId: account,
      officeName: 'Office $id',
      managerName: 'Manager $id',
      countryCode: '+971',
      phoneNumber: '503334455',
      officeLocation: 'Business Bay',
      notes: 'notes $id',
      pickUpLocation: 'Reception',
      pickUpLatitude: 25.1972,
      pickUpLongitude: 55.2744,
      pickUpAddress: 'Bay Square 5',
      createdAt: DateTime.utc(2026, 7, 8, 9, 10, 11),
      updatedAt: DateTime.utc(2026, 8, 9, 10, 11, 12),
    );

BrokerModel _broker(String id, String account) => BrokerModel(
      id: id,
      userId: account,
      name: 'Broker $id',
      countryCode: '+971',
      phoneNumber: '504445566',
      notes: 'notes $id',
      createdAt: DateTime.utc(2026, 9, 1, 2, 3, 4),
      updatedAt: DateTime.utc(2026, 10, 2, 3, 4, 5),
    );

WatchmenModel _watchman(String id, String account) => WatchmenModel(
      id: id,
      userId: account,
      name: 'Watchman $id',
      countryCode: '+971',
      phoneNumber: '505556677',
      buildingName: 'Tower $id',
      notes: 'notes $id',
      buildingLocation: 'Dubai Marina',
      pickUpLocation: 'Security desk',
      pickUpLatitude: 25.0657,
      pickUpLongitude: 55.1713,
      pickUpAddress: 'Marina Promenade 9',
      createdAt: DateTime.utc(2026, 11, 1, 2, 3, 4),
      updatedAt: DateTime.utc(2026, 11, 2, 3, 4, 5),
    );

Object _record(String kind, String id, String account) => switch (kind) {
      'requests' => _request(id, account),
      'owners' => _owner(id, account),
      'offices' => _office(id, account),
      'brokers' => _broker(id, account),
      'watchmen' => _watchman(id, account),
      _ => throw ArgumentError(kind),
    };

String? _idOf(Object? record) => switch (record) {
      RequestModel r => r.id,
      OwnerModel o => o.id,
      OfficeModel o => o.id,
      BrokerModel b => b.id,
      WatchmenModel w => w.id,
      _ => null,
    };

/// A favorite as the saved Favorites copy gives it back: no record.
FavoriteItem _savedFavorite(String kind, String id) => CachedFavoriteItem(
      id: id,
      type: kind,
      title: 'Saved $kind',
      subtitle: 'Saved subtitle',
      addedAt: DateTime.utc(2026, 11, 1),
      cachedAt: DateTime.utc(2026, 11, 2),
    ).toFavoriteItem();

/// A lookup answered by the test, counting its calls.
class _Records extends FavoriteSavedRecords {
  _Records(this.answer);

  final FutureOr<Object?> Function(String type, String id) answer;
  final List<String> asked = [];

  @override
  Future<Object?> find(String type, String id) async {
    asked.add('$type/$id');
    return answer(type, id);
  }
}

/// What a details route was opened with.
class _Opened {
  String? path;
  Object? extra;
}

/// The details routes, casting `state.extra` as `app.dart` does.
GoRouter _router(Widget home, _Opened opened) {
  Widget open(GoRouterState state, Object record) {
    opened
      ..path = state.uri.path
      ..extra = record;
    return Scaffold(body: Text('details ${_idOf(record)}'));
  }

  return GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: home)),
    GoRoute(
      path: '/requested-details',
      builder: (_, s) => open(s, s.extra as RequestModel),
    ),
    GoRoute(
      path: '/owners-details',
      builder: (_, s) => open(s, s.extra as OwnerModel),
    ),
    GoRoute(
      path: '/offices-details',
      builder: (_, s) => open(s, s.extra as OfficeModel),
    ),
    GoRoute(
      path: '/watchmen-details',
      builder: (_, s) => open(s, s.extra as WatchmenModel),
    ),
    GoRoute(
      path: '/brokers-details',
      builder: (_, s) => open(s, s.extra as BrokerModel),
    ),
    GoRoute(
      path: '/offers-details-by-id/:id',
      builder: (_, s) {
        opened
          ..path = s.uri.path
          ..extra = s.extra;
        return const Scaffold(body: Text('offer details'));
      },
    ),
  ]);
}

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card,
  _Opened opened,
) async {
  await tester.pumpWidget(withR2ScreenProviders(MaterialApp.router(
    routerConfig: _router(card, opened),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  )));
  await tester.pumpAndSettle();
}

Future<void> _tapCard(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(FavoriteCard),
          matching: find.byType(InkWell),
        )
        .first,
    warnIfMissed: false,
  );
}

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final file = File(utf8.decode(message!.buffer.asUint8List()));
        if (!file.existsSync()) return null;
        return ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer);
      },
    );
    await AppLocalizations.preloadAllLanguages();
  });

  String loadError() =>
      AppLocalizations.translateFor('en', 'errorLoadingData')!;

  group('tapping a favorite from the saved copy', () {
    for (final kind in _kinds) {
      testWidgets('$kind: opens with the saved record', (tester) async {
        final saved = _record(kind, 'rec-1', _alice);
        final records = _Records((_, __) => saved);
        final opened = _Opened();
        await _pumpCard(
          tester,
          FavoriteCard(
            favorite: _savedFavorite(kind, 'rec-1'),
            savedRecords: records,
          ),
          opened,
        );

        await _tapCard(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(records.asked, ['$kind/rec-1']);
        expect(opened.extra, same(saved));
        expect(find.text('details rec-1'), findsOneWidget);
      });

      testWidgets('$kind: none saved ⇒ no crash, nothing opens, a message',
          (tester) async {
        final records = _Records((_, __) => null);
        final opened = _Opened();
        await _pumpCard(
          tester,
          FavoriteCard(
            favorite: _savedFavorite(kind, 'gone'),
            savedRecords: records,
          ),
          opened,
        );

        await _tapCard(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(opened.path, isNull);
        expect(find.byType(FavoriteCard), findsOneWidget);
        expect(find.text(loadError()), findsOneWidget);
      });
    }

    testWidgets('the real lookup with no one signed in fails closed',
        (tester) async {
      final opened = _Opened();
      await _pumpCard(
        tester,
        FavoriteCard(
          favorite: _savedFavorite('owners', 'rec-1'),
          savedRecords: FavoriteSavedRecords(
            currentUserId: () => null,
            currentSession: () => null,
          ),
        ),
        opened,
      );

      await _tapCard(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(opened.path, isNull);
      expect(find.text(loadError()), findsOneWidget);
    });

    testWidgets('a second tap while looking up runs one lookup',
        (tester) async {
      final answer = Completer<Object?>();
      final records = _Records((_, __) => answer.future);
      final opened = _Opened();
      await _pumpCard(
        tester,
        FavoriteCard(
          favorite: _savedFavorite('brokers', 'rec-1'),
          savedRecords: records,
        ),
        opened,
      );

      await _tapCard(tester);
      await tester.pump();
      await _tapCard(tester);
      await tester.pump();
      answer.complete(_broker('rec-1', _alice));
      await tester.pumpAndSettle();

      expect(records.asked, ['brokers/rec-1']);
      expect(opened.path, '/brokers-details');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card gone before the lookup ends opens nothing',
        (tester) async {
      final answer = Completer<Object?>();
      final records = _Records((_, __) => answer.future);
      final opened = _Opened();
      final show = ValueNotifier(true);
      addTearDown(show.dispose);
      // As a list does when the favorite leaves it, the card can go away.
      await _pumpCard(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, visible, __) => visible
              ? FavoriteCard(
                  favorite: _savedFavorite('watchmen', 'rec-1'),
                  savedRecords: records,
                )
              : const SizedBox(),
        ),
        opened,
      );

      await _tapCard(tester);
      await tester.pump();
      show.value = false;
      await tester.pump();
      answer.complete(_watchman('rec-1', _alice));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(opened.path, isNull);
      expect(find.text(loadError()), findsNothing);
    });
  });

  group('online favorites open as before', () {
    for (final kind in _kinds) {
      testWidgets('$kind: with its record, no lookup', (tester) async {
        final record = _record(kind, 'rec-1', _alice);
        final records = _Records((_, __) => fail('no lookup expected'));
        final opened = _Opened();
        await _pumpCard(
          tester,
          FavoriteCard(
            favorite: FavoriteItem(
              id: 'rec-1',
              type: kind,
              title: 'Online $kind',
              subtitle: 'Online subtitle',
              addedAt: DateTime.utc(2026, 11, 1),
              originalData: record,
            ),
            savedRecords: records,
          ),
          opened,
        );

        await _tapCard(tester);
        await tester.pumpAndSettle();

        expect(records.asked, isEmpty);
        expect(opened.extra, same(record));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Offers: unchanged — by id, with what the card has',
        (tester) async {
      final records = _Records((_, __) => fail('no lookup expected'));
      final opened = _Opened();
      await _pumpCard(
        tester,
        FavoriteCard(
          favorite: _savedFavorite('offers', 'offer-1'),
          savedRecords: records,
        ),
        opened,
      );

      await _tapCard(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(records.asked, isEmpty);
      expect(opened.path, '/offers-details-by-id/offer-1');
      expect(opened.extra, isNull);
    });
  });

  group('the lookup reads only this account\'s own saved list', () {
    late Directory tempDir;
    String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
        '${EncryptedAccountListCache.directoryName}';

    Future<void> save(String kind, String account, List<String> ids) async {
      switch (kind) {
        case 'requests':
          await const RequestsLocalCache()
              .write(account, [for (final id in ids) _request(id, account)]);
        case 'owners':
          await const OwnersLocalCache()
              .write(account, [for (final id in ids) _owner(id, account)]);
        case 'offices':
          await const OfficesLocalCache()
              .write(account, [for (final id in ids) _office(id, account)]);
        case 'brokers':
          await const BrokersLocalCache()
              .write(account, [for (final id in ids) _broker(id, account)]);
        case 'watchmen':
          await const WatchmenLocalCache()
              .write(account, [for (final id in ids) _watchman(id, account)]);
      }
    }

    List<String> boxNames(String uid) => [
          RequestsLocalCache.boxNameForUid(uid),
          OwnersLocalCache.boxNameForUid(uid),
          OfficesLocalCache.boxNameForUid(uid),
          BrokersLocalCache.boxNameForUid(uid),
          WatchmenLocalCache.boxNameForUid(uid),
        ];

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('favorites_offline_nav');
      Hive.init(tempDir.path);
      EncryptedAccountListCache.debugStorageRoot = tempDir.path;
    });

    tearDownAll(() async {
      await Hive.close();
      EncryptedAccountListCache.debugStorageRoot = null;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      EncryptedAccountListCache.debugForgetProcessState();
    });

    tearDown(() async {
      for (final name in [...boxNames(_alice), ...boxNames(_bob)]) {
        for (var attempt = 0;; attempt++) {
          try {
            await Hive.deleteBoxFromDisk(name, path: listsDir());
            break;
          } on FileSystemException {
            if (attempt == 20) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
      }
    });

    FavoriteSavedRecords signedIn(String? account, {String? session}) =>
        FavoriteSavedRecords(
          currentUserId: () => account,
          currentSession: () => session,
        );

    for (final kind in _kinds) {
      test('$kind: the saved record, with its saved fields', () async {
        await save(kind, _alice, ['a1', 'a2']);

        final found = await signedIn(_alice).find(kind, 'a2');

        expect(_idOf(found), 'a2');
        expect(found.runtimeType, _record(kind, 'a2', _alice).runtimeType);
        expect(await signedIn(_alice).find(kind, 'missing'), isNull);
      });

      test('$kind: another account never sees it', () async {
        await save(kind, _alice, ['a1']);
        await save(kind, _bob, ['b1']);

        expect(await signedIn(_bob).find(kind, 'a1'), isNull);
        expect(_idOf(await signedIn(_bob).find(kind, 'b1')), 'b1');
        expect(await signedIn(_alice).find(kind, 'b1'), isNull);
      });
    }

    test('signed out: nothing, and nothing is read', () async {
      await save('owners', _alice, ['a1']);
      for (final account in [null, '']) {
        expect(await signedIn(account).find('owners', 'a1'), isNull);
      }
    });

    test('the account changing during the read: nothing', () async {
      await save('owners', _alice, ['a1']);
      var calls = 0;
      final records = FavoriteSavedRecords(
        currentUserId: () => calls++ == 0 ? _alice : _bob,
        currentSession: () => 'same',
      );

      expect(await records.find('owners', 'a1'), isNull);
    });

    test('a new session (sign-out and in) during the read: nothing', () async {
      await save('offices', _alice, ['a1']);
      var calls = 0;
      final records = FavoriteSavedRecords(
        currentUserId: () => _alice,
        currentSession: () => calls++ == 0 ? 'before' : 'after',
      );

      expect(await records.find('offices', 'a1'), isNull);
      expect(
        _idOf(await signedIn(_alice, session: 'after').find('offices', 'a1')),
        'a1',
      );
    });

    test('a record the server confirmed deleted is not found', () async {
      await save('watchmen', _alice, ['a1', 'a2']);
      await const WatchmenLocalCache().rememberConfirmedDeletion(_alice, 'a1');

      expect(await signedIn(_alice).find('watchmen', 'a1'), isNull);
      expect(_idOf(await signedIn(_alice).find('watchmen', 'a2')), 'a2');
    });

    test('after a restart the saved record is still found', () async {
      await save('brokers', _alice, ['a1']);
      for (final name in boxNames(_alice)) {
        if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
      }
      EncryptedAccountListCache.debugForgetProcessState();

      expect(_idOf(await signedIn(_alice).find('brokers', 'a1')), 'a1');
    });

    test('no saved list, Offers or an unknown kind: nothing', () async {
      expect(await signedIn(_alice).find('requests', 'a1'), isNull);
      await save('requests', _alice, ['a1']);
      expect(await signedIn(_alice).find('offers', 'a1'), isNull);
      expect(await signedIn(_alice).find('unknown', 'a1'), isNull);
      expect(await signedIn(_alice).find('requests', '  '), isNull);
    });

    test('a lookup that throws reads as nothing', () async {
      final records = FavoriteSavedRecords(
        currentUserId: () => throw StateError('no identity yet'),
      );
      expect(await records.find('owners', 'a1'), isNull);
    });
  });

  group('source', () {
    test('app.dart still needs a record for these five details routes', () {
      final app = _source('lib/app.dart');
      for (final cast in [
        'final request = state.extra as RequestModel;',
        'final owner = state.extra as OwnerModel;',
        'final office = state.extra as OfficeModel;',
        'final watchmen = state.extra as WatchmenModel;',
        'final broker = state.extra as BrokerModel;',
      ]) {
        expect(app, contains(cast), reason: cast);
      }
    });

    test('the card never pushes those routes with a raw originalData', () {
      final card =
          _source('lib/src/views/Screens/home/favorites/favorites_card.dart');
      for (final route in [
        "'/requested-details', extra: widget.favorite.originalData",
        "'/owners-details', extra: widget.favorite.originalData",
        "'/offices-details', extra: widget.favorite.originalData",
        "'/brokers-details', extra: widget.favorite.originalData",
        "'/watchmen-details', extra: widget.favorite.originalData",
      ]) {
        expect(card, isNot(contains(route)), reason: route);
      }
    });
  });
}
