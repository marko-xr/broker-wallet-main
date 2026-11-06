// Seven-list opening baseline (test-only instrumentation; no production code).
//
// MEASURED here, on the machine running `flutter test` (a desktop VM in JIT
// mode, with the secure-storage TEST store instead of the Android Keystore).
// These numbers rank the costs against each other; they are NOT phone
// timings. Samsung acceptance stays deferred.
//
// Part 1: what opening a cached list costs, phase by phase, with the real
//   encrypted cache (Hive in a temporary directory) and `localFirstList`.
// Part 2: what the real list screens cost to build their first frame and to
//   rebuild, with the list delivered by a fake source.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/common/utils/list_week_keys.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/brokers_local_cache.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/offices_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:broker_wallet/src/services/requests_local_cache.dart';
import 'package:broker_wallet/src/services/watchmen_local_cache.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_owners_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_requests_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/offers_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/owners_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/requests_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotation_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotations_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/search_fixtures.dart';

const _uid = 'u1';
final DateTime _thisWeek = DateTime.now();

List<OwnerModel> _owners(int n) => [
      for (var i = 0; i < n; i++)
        owner(
          id: 'owner-$i',
          name: 'Owner number $i',
          phone: '50${i.toString().padLeft(7, '0')}',
          typeOfProperties: 'Villa, Apartment',
          propertyLocation: 'Palm Jumeirah Frond $i',
          notes: 'Prefers calls after 6pm; keys with watchman $i',
        ).copyWith(createdAt: _thisWeek, updatedAt: _thisWeek),
    ];

List<OfferModel> _offers(int n) => [
      for (var i = 0; i < n; i++)
        offer(
          id: 'offer-$i',
          type: i.isEven ? 'rent' : 'sell',
          areas: const ['Dubai Marina', 'JBR'],
          location: 'Tower $i',
          phone: '55${i.toString().padLeft(7, '0')}',
          minPrice: '${100000 + i}',
          maxPrice: '${150000 + i}',
          squareFootage: '${900 + i}',
          notes: 'Sea view, high floor, chiller free, unit $i',
          propertyType: 'residential',
          specific: 'apartment',
          pickUpAddress: 'Marina Walk $i',
        ).copyWith(createdAt: _thisWeek, updatedAt: _thisWeek),
    ];

List<RequestModel> _requests(int n) => [
      for (var i = 0; i < n; i++)
        request(
          id: 'request-$i',
          type: i.isEven ? 'rent' : 'sale',
          areas: const ['Business Bay'],
          location: 'Near metro $i',
          minPrice: '${80000 + i}',
          maxPrice: '${120000 + i}',
          notes: 'Family of four, request $i',
          propertyType: 'residential',
          specific: 'villa',
        ).copyWith(createdAt: _thisWeek, updatedAt: _thisWeek),
    ];

int _ms(Stopwatch s) => s.elapsedMicroseconds ~/ 1000;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 1 — cached list open, phase by phase (MEASURED, test VM)', () {
    late Directory tempDir;
    String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
        '${EncryptedAccountListCache.directoryName}';

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('list_open_baseline');
      Hive.init(tempDir.path);
      EncryptedAccountListCache.debugStorageRoot = tempDir.path;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    tearDownAll(() async {
      await Hive.close();
      EncryptedAccountListCache.debugStorageRoot = null;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<void> closeBox(String name) async {
      if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();
    }

    Future<void> measure<T>(
      String label,
      EncryptedAccountListCache<T> cache,
      String boxName,
      String v2Key,
      List<T> items,
    ) async {
      // What a server answer costs the screen after it arrives: the
      // fingerprint `accept` makes, then the save (encode + seal + put +
      // read-back check).
      final fp = Stopwatch()..start();
      final fingerprint = cache.fingerprintOf(items);
      fp.stop();
      final write = Stopwatch()..start();
      await cache.write(_uid, items, serverReadAt: DateTime.now().toUtc());
      write.stop();

      // The raw sealed list, to time its parts on their own.
      final sealed = Hive.box<String>(boxName).get(v2Key)!;
      final payload = (json.decode(sealed) as Map)['p'] as String;
      final hmac = Stopwatch()..start();
      Hmac(sha256, List<int>.filled(32, 7)).convert(utf8.encode(payload));
      hmac.stop();
      final decode = Stopwatch()..start();
      json.decode(payload);
      decode.stop();

      // Cold: as the first open after a restart (box closed, nothing in
      // memory). Warm: as a reopen while the app runs (box still open).
      await closeBox(boxName);
      EncryptedAccountListCache.debugForgetProcessState();
      final cold = Stopwatch()..start();
      final first = await cache.readSaved(_uid);
      cold.stop();
      final warm = Stopwatch()..start();
      final again = await cache.readSaved(_uid);
      warm.stop();
      final fpAgain = Stopwatch()..start();
      cache.fingerprintOf(again!.items);
      fpAgain.stop();

      // End to end through `localFirstList`, as a screen subscribes: the
      // saved list first, then a server answer (here immediate) that is
      // fingerprinted and saved again.
      await closeBox(boxName);
      EncryptedAccountListCache.debugForgetProcessState();
      var serverReads = 0;
      final serverAnswer = Completer<void>();
      final open = Stopwatch()..start();
      int? firstListAt;
      int? serverListAt;
      final sub = localFirstList<T>(
        server: () {
          serverReads++;
          return Stream<List<T>>.fromFuture(
              serverAnswer.future.then((_) => [...items]));
        },
        cache: cache,
        currentUserId: () => _uid,
        refreshSignals: const Stream<void>.empty(),
        isAppActive: () => true,
        confirmEmptyList: (_) => null,
        sessionOf: () => null,
      ).listen((_) {
        if (firstListAt == null) {
          firstListAt = open.elapsedMicroseconds ~/ 1000;
          serverAnswer.complete();
        } else {
          serverListAt ??= open.elapsedMicroseconds ~/ 1000;
        }
      });
      for (var i = 0;
          i < 400 && (firstListAt == null || serverReads == 0);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // Let the save after the server answer finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await cache.readSaved(_uid);
      final saveDone = open.elapsedMicroseconds ~/ 1000;
      await sub.cancel();

      expect(first!.items, hasLength(items.length));
      expect(serverReads, 1, reason: 'one full server read per screen open');
      debugPrint('[ListOpen] $label n=${items.length} '
          'payload=${(payload.length / 1024).toStringAsFixed(0)}KiB | '
          'coldRead=${_ms(cold)}ms warmRead=${_ms(warm)}ms '
          '(hmac=${_ms(hmac)}ms jsonDecode=${_ms(decode)}ms) | '
          'fingerprint=${_ms(fp)}ms/${_ms(fpAgain)}ms save=${_ms(write)}ms | '
          'localFirst: firstList=${firstListAt}ms serverList=${serverListAt}ms '
          'savedAgainBy=${saveDone}ms | fp=${fingerprint.length}');
    }

    for (final n in [0, 100, 1000, 5000, 20000]) {
      test('Owners n=$n', () async {
        await measure('owners', const OwnersLocalCache(),
            OwnersLocalCache.boxNameForUid(_uid), 'owners_v2', _owners(n));
      }, timeout: const Timeout(Duration(minutes: 3)));
      test('Offers n=$n', () async {
        await measure('offers', const OffersLocalCache(),
            OffersLocalCache.boxNameForUid(_uid), 'offers_v2', _offers(n));
      }, timeout: const Timeout(Duration(minutes: 3)));
    }

    test('all six at n=1000 (first saved list, cold)', () async {
      Future<int> cold<T>(
          EncryptedAccountListCache<T> cache, String box, List<T> items) async {
        await cache.write(_uid, items);
        await closeBox(box);
        EncryptedAccountListCache.debugForgetProcessState();
        final s = Stopwatch()..start();
        await cache.readSaved(_uid);
        return _ms(s);
      }

      final results = {
        'requests': await cold(const RequestsLocalCache(),
            RequestsLocalCache.boxNameForUid(_uid), _requests(1000)),
        'offers': await cold(const OffersLocalCache(),
            OffersLocalCache.boxNameForUid(_uid), _offers(1000)),
        'owners': await cold(const OwnersLocalCache(),
            OwnersLocalCache.boxNameForUid(_uid), _owners(1000)),
        'offices': await cold(
            const OfficesLocalCache(), OfficesLocalCache.boxNameForUid(_uid), [
          for (var i = 0; i < 1000; i++)
            office(id: 'c$i', name: 'Office $i', location: 'Bay $i')
                .copyWith(userId: _uid)
        ]),
        'brokers': await cold(
            const BrokersLocalCache(), BrokersLocalCache.boxNameForUid(_uid), [
          for (var i = 0; i < 1000; i++)
            broker(id: 'b$i', name: 'Broker $i').copyWith(userId: _uid)
        ]),
        'watchmen': await cold(const WatchmenLocalCache(),
            WatchmenLocalCache.boxNameForUid(_uid), [
          for (var i = 0; i < 1000; i++)
            watchman(id: 'w$i', name: 'Watchman $i', building: 'T$i')
                .copyWith(userId: _uid)
        ]),
      };
      debugPrint('[ListOpen] six lists n=1000 coldRead ms: $results');
      expect(results, hasLength(6));
    });

    tearDown(() async {
      for (final name in [
        RequestsLocalCache.boxNameForUid(_uid),
        OffersLocalCache.boxNameForUid(_uid),
        OwnersLocalCache.boxNameForUid(_uid),
        OfficesLocalCache.boxNameForUid(_uid),
        BrokersLocalCache.boxNameForUid(_uid),
        WatchmenLocalCache.boxNameForUid(_uid),
      ]) {
        await Hive.deleteBoxFromDisk(name, path: listsDir());
      }
    });
  });

  group('Part 2 — list screen build cost (MEASURED, test VM)', () {
    setUpAll(() async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('PonnamKarthik/fluttertoast'),
        (call) async => true,
      );
      await AppLocalizations.preloadAllLanguages();
    });

    Widget app(Widget child) => MaterialApp(
          locale: const Locale('en'),
          theme: AppTheme.lightTheme,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        );

    Future<void> buildCost<T>(
      WidgetTester tester,
      String label,
      int n,
      StreamController<List<T>> source,
      List<T> items,
      Widget screen,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(screen));
      await tester.pump();
      await tester.pump();

      // Each frame on its own: the one the list is delivered in, the next,
      // and one with nothing new (as a frame during a scroll would be).
      source.add(items);
      final delivered = Stopwatch()..start();
      await tester.pump(); // the list event, and the frame it marks dirty
      delivered.stop();
      final first = Stopwatch()..start();
      await tester.pump();
      first.stop();
      final idle = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      idle.stop();
      final rebuild = Stopwatch()..start();
      source.add([...items]); // a refresh with the same records
      await tester.pump();
      await tester.pump();
      rebuild.stop();
      debugPrint('[ListBuild] $label n=$n deliveryFrame=${_ms(delivered)}ms '
          'nextFrame=${_ms(first)}ms idleFrame=${_ms(idle)}ms '
          'refreshRebuild=${_ms(rebuild)}ms');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }

    for (final n in [100, 1000, 5000]) {
      testWidgets('Owners n=$n', (tester) async {
        final source = StreamController<List<OwnerModel>>();
        await buildCost(
          tester,
          'owners',
          n,
          source,
          _owners(n),
          OwnersListView(
            createViewModel: () =>
                OwnersListViewModel(ownerService: _OwnerSource(source)),
          ),
        );
      });
      testWidgets('Offers n=$n', (tester) async {
        final source = StreamController<List<OfferModel>>();
        await buildCost(
          tester,
          'offers',
          n,
          source,
          _offers(n),
          OffersListView(
            viewModel: OffersListViewModel(offerService: _OfferSource(source)),
          ),
        );
      });
      testWidgets('Requests n=$n', (tester) async {
        final source = StreamController<List<RequestModel>>();
        await buildCost(
          tester,
          'requests',
          n,
          source,
          _requests(n),
          RequestedListView(
            viewModel:
                RequestedListViewModel(requestService: _RequestSource(source)),
          ),
        );
      });
    }
  });

  part3();
  part4(binding);
}

// Part 4: Quotations, the seventh list (no saved copy; one server read).
void part4(TestWidgetsFlutterBinding binding) {
  group('Part 4 — Quotations list (MEASURED, test VM)', () {
    setUpAll(() async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('PonnamKarthik/fluttertoast'),
        (call) async => true,
      );
      await AppLocalizations.preloadAllLanguages();
    });

    Widget app(Widget child) => MaterialApp(
          locale: const Locale('en'),
          theme: AppTheme.lightTheme,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        );

    List<QuotationModel> quotations(int n) => [
          for (var i = 0; i < n; i++)
            QuotationModel(
              id: 'q$i',
              userId: _uid,
              propertyTitle: 'Villa $i',
              officeName: 'Realtig',
              totalAmount: 120000.0 + i,
              createdAt: _thisWeek,
              updatedAt: _thisWeek,
            ),
        ];

    for (final n in [100, 500, 1000]) {
      testWidgets('first frame with the list, n=$n', (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final source = _QuotationSource();
        await tester.pumpWidget(app(QuotationListView(
            viewModel: QuotationListViewModel(quotationService: source))));
        await tester.pump();
        source.controller.add(quotations(n));
        await tester.pump();
        final first = Stopwatch()..start();
        await tester.pump();
        first.stop();
        debugPrint('[QuotationBuild] n=$n firstFrameWithList=${_ms(first)}ms '
            'tilesBuilt=${find.byType(AnimatedContainer).evaluate().length} '
            'serverReads=${source.reads}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    // Q-1a: this documented the bug (the list was replaced by the error
    // state); it now holds the fix: the list stays.
    testWidgets('a failed refresh keeps the list on screen (Q-1a)',
        (tester) async {
      final source = _QuotationSource();
      await tester.pumpWidget(app(QuotationListView(
          viewModel: QuotationListViewModel(quotationService: source))));
      await tester.pump();
      source.controller.add(quotations(3));
      await tester.pump();
      await tester.pump();
      expect(find.text('Villa 0'), findsOneWidget);

      source.controller.addError(const SocketException('lost'));
      await tester.pump();
      await tester.pump();

      final failed =
          AppLocalizations.translateFor('en', 'quotationListLoadFailed')!;
      debugPrint('[QuotationRefreshFailure] list kept: '
          '${find.text('Villa 0').evaluate().isNotEmpty}; error shown: '
          '${find.text(failed).evaluate().isNotEmpty}');
      expect(find.text(failed), findsNothing);
      expect(find.text('Villa 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _QuotationSource extends QuotationService {
  final StreamController<List<QuotationModel>> controller =
      StreamController<List<QuotationModel>>();
  int reads = 0;

  @override
  Stream<List<QuotationModel>> getUserQuotations() {
    reads++;
    return controller.stream;
  }
}

// Part 3 lives in its own group below `main`'s groups: what the per-build
// list work costs on its own (filter + newest-first sort), for 5,000 Offers.
void part3() {
  test('Part 3 — per-build list work on its own (MEASURED, test VM)', () async {
    final source = StreamController<List<OfferModel>>();
    final vm = OffersListViewModel(offerService: _OfferSource(source));
    final items = _offers(5000);
    source.add(items);
    await pumpEventQueue();
    final filter = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      vm.filteredOffers;
    }
    filter.stop();
    final sort = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      List<OfferModel>.from(items)
          .sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    sort.stop();
    final group = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      final grouped = <String, List<OfferModel>>{};
      for (final o in items) {
        (grouped[_weekKeyAsTheScreensDo(o.createdAt)] ??= []).add(o);
      }
    }
    group.stop();
    final candidate = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      final keys = _WeekKeys(DateTime.now());
      final grouped = <String, List<OfferModel>>{};
      for (final o in items) {
        (grouped[keys.of(o.createdAt)] ??= []).add(o);
      }
    }
    candidate.stop();
    // The candidate must give exactly the screens' keys: UTC and local dates
    // over three years, around today, at every hour.
    final keys = _WeekKeys(DateTime.now());
    final base = DateTime.now();
    var compared = 0;
    for (var d = -600; d <= 500; d++) {
      for (final h in [0, 1, 11, 12, 22, 23]) {
        final local = DateTime(base.year, base.month, base.day + d, h, 30);
        for (final date in [local, local.toUtc()]) {
          expect(keys.of(date), _weekKeyAsTheScreensDo(date),
              reason: date.toIso8601String());
          compared++;
        }
      }
    }
    // Realistic spread: one record a day for the last 5,000 / 365 years
    // spread over about two years, so most fall in older weeks.
    final spread = [
      for (var i = 0; i < 5000; i++)
        items[i].copyWith(
            createdAt: DateTime.now().subtract(Duration(hours: i * 4)))
    ];
    final oldGroup = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      for (final o in spread) {
        _weekKeyAsTheScreensDo(o.createdAt);
      }
    }
    oldGroup.stop();
    final newGroup = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      final k = _WeekKeys(DateTime.now());
      for (final o in spread) {
        k.of(o.createdAt);
      }
    }
    newGroup.stop();
    // P4.7a: the shared helper the six screens now use, same data.
    Duration shipped(List<OfferModel> records) {
      final s = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        final weeks = ListWeekKeys(DateTime.now());
        for (final o in records) {
          weeks.keyOf(o.createdAt);
        }
      }
      return s.elapsed;
    }

    final shippedSpread = shipped(spread);
    final shippedThisWeek = shipped(items);
    debugPrint('[ListWork] spread over ~2 years: weekGrouping '
        'screens=${(oldGroup.elapsedMicroseconds / 10000).toStringAsFixed(1)}ms '
        'candidate=${(newGroup.elapsedMicroseconds / 10000).toStringAsFixed(1)}ms '
        'ListWeekKeys=${(shippedSpread.inMicroseconds / 10000).toStringAsFixed(1)}ms '
        '(per build)');
    debugPrint('[ListWork] this week: ListWeekKeys='
        '${(shippedThisWeek.inMicroseconds / 10000).toStringAsFixed(1)}ms '
        '(per build)');
    debugPrint('[ListWork] candidate weekGrouping='
        '${(candidate.elapsedMicroseconds / 10000).toStringAsFixed(1)}ms '
        '(per build), identical keys for $compared dates');
    debugPrint('[ListWork] offers n=5000 filteredOffers='
        '${(filter.elapsedMicroseconds / 10000).toStringAsFixed(1)}ms '
        'copy+sort=${(sort.elapsedMicroseconds / 10000).toStringAsFixed(1)}ms '
        'weekGrouping=${(group.elapsedMicroseconds / 10000).toStringAsFixed(1)}ms '
        '(per build)');
    vm.dispose();
  });
}

/// TEST-ONLY candidate for the recommended fix (not production code): the
/// "today" bounds once per build, and each record's calendar day by UTC day
/// arithmetic instead of building local DateTimes per record.
class _WeekKeys {
  _WeekKeys(DateTime now)
      : _thisWeekStart = _day(now.year, now.month, now.day) - (now.weekday - 1);

  final int _thisWeekStart;

  static int _day(int y, int m, int d) =>
      DateTime.utc(y, m, d).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  String of(DateTime date) {
    final day = _day(date.year, date.month, date.day);
    if (day >= _thisWeekStart && day <= _thisWeekStart + 6) return 'this_week';
    final lastWeekStart = _thisWeekStart - 7;
    if (day >= lastWeekStart && day <= lastWeekStart + 6) return 'last_week';
    // As the screens: `date` minus (weekday - 1) days, in its own zone.
    final weekStart = date.subtract(Duration(days: date.weekday - 1));
    return '${weekStart.year}-${weekStart.month}-${weekStart.day}';
  }
}

/// A copy of the list screens' private `_getWeekKey` (identical in the six
/// views), to time it on its own.
String _weekKeyAsTheScreensDo(DateTime date) {
  final weekStart = date.subtract(Duration(days: date.weekday - 1));
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dateOnly = DateTime(date.year, date.month, date.day);
  final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final thisWeekEnd = thisWeekStart.add(const Duration(days: 6));
  if (dateOnly.isAfter(thisWeekStart.subtract(const Duration(days: 1))) &&
      dateOnly.isBefore(thisWeekEnd.add(const Duration(days: 1)))) {
    return 'this_week';
  }
  final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
  final lastWeekEnd = lastWeekStart.add(const Duration(days: 6));
  if (dateOnly.isAfter(lastWeekStart.subtract(const Duration(days: 1))) &&
      dateOnly.isBefore(lastWeekEnd.add(const Duration(days: 1)))) {
    return 'last_week';
  }
  return '${weekStart.year}-${weekStart.month}-${weekStart.day}';
}

class _OwnerSource extends OwnerService {
  _OwnerSource(this.source);
  final StreamController<List<OwnerModel>> source;
  @override
  Stream<List<OwnerModel>> watchUserOwnersLocalFirst() => source.stream;
}

class _OfferSource extends OfferService {
  _OfferSource(this.source);
  final StreamController<List<OfferModel>> source;
  @override
  Stream<List<OfferModel>> watchUserOffersLocalFirst() => source.stream;
}

class _RequestSource extends RequestService {
  _RequestSource(this.source);
  final StreamController<List<RequestModel>> source;
  @override
  Stream<List<RequestModel>> watchUserRequestsLocalFirst() => source.stream;
}
