// P4.7a: the six entity list screens show the same week sections, in the
// same order, with the same records under them, before and after the shared
// week helper (ListWeekKeys) replaced their private `_getWeekKey`.
//
// Each screen is pumped with records spread over this week, last week, older
// weeks, a year ago and (for the three kinds whose date is optional) no date,
// in English and Arabic. The test checks the separators against the former
// helper's keys, and prints a digest of everything the list shows, in order,
// so a run before the change and a run after it can be compared exactly.
import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/broker_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_brokers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offices_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_owners_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_requests_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_watchmen_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/brokers_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/offers_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/offices_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/owners_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/requests_list_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/watchmen_list_view.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../search/search_fixtures.dart';

/// The screens' former key, verbatim (see list_week_keys_test.dart).
String _oldKey(DateTime date, DateTime now) {
  final weekStart = date.subtract(Duration(days: date.weekday - 1));
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

/// The separator text the screens show for [key], as they word it.
String _separator(String key, Locale locale) {
  String t(String k) => AppLocalizations.translateFor(locale.languageCode, k)!;
  if (key == 'this_week') return t('thisWeek');
  if (key == 'last_week') return t('lastWeek');
  final parts = key.split('-');
  final date =
      DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  final code = locale.toString();
  final sep = locale.languageCode == 'ar' ? '، ' : ', ';
  return '${DateFormat('MMMM d', code).format(date)}$sep'
      '${DateFormat('EEEE', code).format(date)}';
}

/// Dates relative to the real clock, since the screens read it themselves.
List<DateTime?> _dates({required bool withNulls}) {
  final now = DateTime.now();
  return [
    now,
    now.subtract(const Duration(days: 7)),
    now.subtract(const Duration(days: 8, hours: 3)),
    now.subtract(const Duration(days: 15)),
    now.subtract(const Duration(days: 16)),
    now.subtract(const Duration(days: 40)),
    now.subtract(const Duration(days: 400)),
    DateTime(now.year - 1, 12, 31, 23, 30), // a year edge
    // One undated record: two would be ordered by clock reads taken during
    // the sort (pre-existing; P4.7a leaves the sort as it is).
    if (withNulls) null,
  ];
}

class _Owners extends OwnerService {
  _Owners(this.c);
  final StreamController<List<OwnerModel>> c;
  @override
  Stream<List<OwnerModel>> watchUserOwnersLocalFirst() => c.stream;
}

class _Offers extends OfferService {
  _Offers(this.c);
  final StreamController<List<OfferModel>> c;
  @override
  Stream<List<OfferModel>> watchUserOffersLocalFirst() => c.stream;
}

class _Requests extends RequestService {
  _Requests(this.c);
  final StreamController<List<RequestModel>> c;
  @override
  Stream<List<RequestModel>> watchUserRequestsLocalFirst() => c.stream;
}

class _Offices extends OfficeService {
  _Offices(this.c);
  final StreamController<List<OfficeModel>> c;
  @override
  Stream<List<OfficeModel>> watchUserOfficesLocalFirst() => c.stream;
}

class _Brokers extends BrokerService {
  _Brokers(this.c);
  final StreamController<List<BrokerModel>> c;
  @override
  Stream<List<BrokerModel>> watchUserBrokersLocalFirst() => c.stream;
}

class _Watchmen extends WatchmenService {
  _Watchmen(this.c);
  final StreamController<List<WatchmenModel>> c;
  @override
  Stream<List<WatchmenModel>> watchUserWatchmenLocalFirst() => c.stream;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async => true,
    );
    await AppLocalizations.preloadAllLanguages();
  });

  Widget app(Widget child, Locale locale) => MaterialApp(
        locale: locale,
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

  /// Pumps [screen], delivers [items] (twice: a refresh with the same
  /// records), and returns every text the list shows, in order.
  Future<List<String>> shown<T>(
    WidgetTester tester,
    Widget screen,
    StreamController<List<T>> source,
    List<T> items,
    Locale locale,
  ) async {
    tester.view.physicalSize = const Size(412, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(screen, locale));
    await tester.pump();
    await tester.pump();
    source.add(items);
    await tester.pump();
    await tester.pump();
    List<String> texts() => [
          for (final e in find
              .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Text))
              .evaluate())
            (e.widget as Text).data ??
                (e.widget as Text).textSpan?.toPlainText() ??
                '',
        ];
    final first = texts();
    source.add([...items]); // the same records again
    await tester.pump();
    await tester.pump();
    expect(texts(), first, reason: 'a refresh shows exactly the same');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    return first;
  }

  void check(
      String screen, Locale locale, List<String> texts, List<DateTime?> dates) {
    final now = DateTime.now();
    // The separators the former helper implies, newest first, each once.
    final sorted = [for (final d in dates) d ?? now]
      ..sort((a, b) => b.compareTo(a));
    final expected = <String>[];
    for (final d in sorted) {
      final s = _separator(_oldKey(d, now), locale);
      if (!expected.contains(s)) expected.add(s);
    }
    final separators = [
      for (final t in texts)
        if (expected.contains(t)) t,
    ];
    expect(separators, expected, reason: '$screen ${locale.languageCode}');
    final digest = sha256.convert(utf8.encode(texts.join('␞')));
    // ignore: avoid_print
    print('[WeekGroupingDigest] $screen ${locale.languageCode} '
        'texts=${texts.length} separators=${expected.length} '
        'sha=${digest.toString().substring(0, 16)}');
  }

  for (final locale in const [Locale('en'), Locale('ar')]) {
    final lang = locale.languageCode;

    testWidgets('Owners $lang', (tester) async {
      final dates = _dates(withNulls: false);
      final c = StreamController<List<OwnerModel>>();
      final items = [
        for (var i = 0; i < dates.length; i++)
          owner(id: 'o$i', name: 'Owner $i')
              .copyWith(createdAt: dates[i], updatedAt: dates[i])
      ];
      final texts = await shown(
          tester,
          OwnersListView(
              createViewModel: () =>
                  OwnersListViewModel(ownerService: _Owners(c))),
          c,
          items,
          locale);
      check('owners', locale, texts, dates);
    });

    testWidgets('Offers $lang', (tester) async {
      final dates = _dates(withNulls: false);
      final c = StreamController<List<OfferModel>>();
      final items = [
        for (var i = 0; i < dates.length; i++)
          offer(
                  id: 'f$i',
                  specific: 'Offer $i',
                  type: i.isEven ? 'rent' : 'sell')
              .copyWith(createdAt: dates[i], updatedAt: dates[i])
      ];
      final texts = await shown(
          tester,
          OffersListView(
              viewModel: OffersListViewModel(offerService: _Offers(c))),
          c,
          items,
          locale);
      check('offers', locale, texts, dates);
    });

    testWidgets('Requests $lang', (tester) async {
      final dates = _dates(withNulls: false);
      final c = StreamController<List<RequestModel>>();
      final items = [
        for (var i = 0; i < dates.length; i++)
          request(id: 'r$i', specific: 'Request $i')
              .copyWith(createdAt: dates[i], updatedAt: dates[i])
      ];
      final texts = await shown(
          tester,
          RequestedListView(
              viewModel: RequestedListViewModel(requestService: _Requests(c))),
          c,
          items,
          locale);
      check('requests', locale, texts, dates);
    });

    testWidgets('Offices $lang (with undated records)', (tester) async {
      final dates = _dates(withNulls: true);
      final c = StreamController<List<OfficeModel>>();
      final items = [
        for (var i = 0; i < dates.length; i++)
          OfficeModel(
            id: 'c$i',
            userId: 'u1',
            officeName: 'Office $i',
            managerName: '',
            countryCode: '+971',
            phoneNumber: '',
            officeLocation: '',
            notes: '',
            pickUpLocation: '',
            pickUpAddress: '',
            createdAt: dates[i],
            updatedAt: dates[i],
          )
      ];
      final texts = await shown(
          tester,
          OfficesListView(
              createViewModel: () =>
                  OfficesListViewModel(officeService: _Offices(c))),
          c,
          items,
          locale);
      check('offices', locale, texts, dates);
    });

    testWidgets('Brokers $lang (with undated records)', (tester) async {
      final dates = _dates(withNulls: true);
      final c = StreamController<List<BrokerModel>>();
      final items = [
        for (var i = 0; i < dates.length; i++)
          BrokerModel(
            id: 'b$i',
            userId: 'u1',
            name: 'Broker $i',
            countryCode: '+971',
            phoneNumber: '',
            notes: '',
            createdAt: dates[i],
            updatedAt: dates[i],
          )
      ];
      final texts = await shown(
          tester,
          BrokersListView(
              createViewModel: () =>
                  BrokersListViewModel(brokerService: _Brokers(c))),
          c,
          items,
          locale);
      check('brokers', locale, texts, dates);
    });

    testWidgets('Watchmen $lang (with undated records)', (tester) async {
      final dates = _dates(withNulls: true);
      final c = StreamController<List<WatchmenModel>>();
      final items = [
        for (var i = 0; i < dates.length; i++)
          WatchmenModel(
            id: 'w$i',
            userId: 'u1',
            name: 'Watchman $i',
            countryCode: '+971',
            phoneNumber: '',
            buildingName: 'Tower $i',
            notes: '',
            buildingLocation: '',
            pickUpLocation: '',
            pickUpAddress: '',
            createdAt: dates[i],
            updatedAt: dates[i],
          )
      ];
      final texts = await shown(
          tester,
          WatchmenListView(
              createViewModel: () =>
                  WatchmenListViewModel(watchmenService: _Watchmen(c))),
          c,
          items,
          locale);
      check('watchmen', locale, texts, dates);
    });
  }
}
