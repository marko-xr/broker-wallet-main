import 'dart:async';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/views/Screens/ViewDetails/offers_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offices_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/owners_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/watchmen_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/details_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as maps;
import 'package:shared_preferences/shared_preferences.dart';

import '../plan_attachment/fake_plan_transport.dart';
import 'r2_test_fakes.dart';
import 'r5d_entity_cases.dart' show LayoutRelatedService, relatedOffer;
import 'responsive_harness.dart';

enum _Kind { offer, owner, office, watchman }

const _address = 'Selected-place address عنوان المكان المحدد';
const _location = 'Selected-place label اسم المكان المحدد';
final _date = DateTime.utc(2026, 11, 18);

// Native pixels alone are replaced. Tests inspect the real GoogleMap's camera,
// markers and callbacks, without initializing a native controller or network.
class _MapPixels extends maps.GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required maps.MapWidgetConfiguration widgetConfiguration,
    maps.MapConfiguration mapConfiguration = const maps.MapConfiguration(),
    maps.MapObjects mapObjects = const maps.MapObjects(),
  }) =>
      const SizedBox.expand(key: ValueKey('map-pixels'));
}

class _OfferMedia extends OfferService {
  final uploads = ChangeNotifier();
  @override
  String? get currentOwnerId => 'map-owner';
  @override
  Listenable get offerMediaUploadChanges => uploads;
  @override
  Stream<OfferMediaUploadCompleted> get offerMediaUploadCompletions =>
      const Stream.empty();
  @override
  Future<void> loadOfferMediaUploads() async {}
  @override
  List<OfferMediaRef> pendingOfferMedia(String id) => [];
  @override
  List<OfferMediaRef> cachedOfferMedia(String id) => [];
  @override
  Future<OfferMediaResolution?> resolveOfferMedia({
    required String offerId,
    required String ownerId,
  }) async =>
      OfferMediaResolution(offerId: offerId, ownerId: ownerId, items: []);
}

class _OwnerMedia extends OwnerService {
  final uploads = ChangeNotifier();
  @override
  String? get currentOwnerId => 'map-owner';
  @override
  Listenable get uploadChanges => uploads;
  @override
  Stream<OfferMediaUploadCompleted> get uploadCompletions =>
      const Stream.empty();
  @override
  Future<void> loadUploads() async {}
  @override
  List<OfferMediaRef> pendingMedia(String id) => [];
  @override
  List<OfferMediaRef> cachedMedia(String id) => [];
  @override
  Future<OfferMediaResolution?> resolveMedia({
    required String recordId,
    required String ownerId,
  }) async =>
      OfferMediaResolution(offerId: recordId, ownerId: ownerId, items: []);
}

Object _record(_Kind kind, double? lat, double? lng,
    {String address = _address, String location = _location}) {
  switch (kind) {
    case _Kind.offer:
      return relatedOffer().copyWith(
          pickUpLatitude: lat,
          pickUpLongitude: lng,
          pickUpAddress: address,
          pickUpLocation: location);
    case _Kind.owner:
      return OwnerModel(
          id: 'map-record',
          userId: 'map-owner',
          name: 'Owner مالك',
          phoneNumber: '',
          countryCode: '+971',
          typeOfProperties: 'Apartment',
          propertyLocation: 'Summary location',
          notes: '',
          pickUpLocation: location,
          pickUpAddress: address,
          pickUpLatitude: lat,
          pickUpLongitude: lng,
          mediaUrls: const [],
          createdAt: _date,
          updatedAt: _date);
    case _Kind.office:
      return OfficeModel(
          id: 'map-record',
          userId: 'map-owner',
          officeName: 'Office مكتب',
          managerName: 'Manager مدير',
          phoneNumber: '',
          countryCode: '+971',
          officeLocation: 'Summary location',
          notes: '',
          pickUpLocation: location,
          pickUpAddress: address,
          pickUpLatitude: lat,
          pickUpLongitude: lng);
    case _Kind.watchman:
      return WatchmenModel(
          id: 'map-record',
          userId: 'map-owner',
          name: 'Watchman حارس',
          buildingName: 'Building مبنى',
          phoneNumber: '',
          countryCode: '+971',
          buildingLocation: 'Unrelated building summary',
          notes: '',
          pickUpLocation: location,
          pickUpAddress: address,
          pickUpLatitude: lat,
          pickUpLongitude: lng);
  }
}

Widget _screen(_Kind kind, Object record) {
  final related = LayoutRelatedService();
  switch (kind) {
    case _Kind.offer:
      return OffersDetailsView(
          offer: record as OfferModel,
          initialOfferIsResolved: true,
          offerService: _OfferMedia(),
          planTransport: FakePlanTransport());
    case _Kind.owner:
      return OwnersDetailsView(
          owner: record as OwnerModel,
          ownerService: _OwnerMedia(),
          relatedItemsService: related,
          planTransport: FakePlanTransport());
    case _Kind.office:
      return OfficesDetailsView(
          office: record as OfficeModel, relatedItemsService: related);
    case _Kind.watchman:
      return WatchmenDetailsView(
          watchmen: record as WatchmenModel, relatedItemsService: related);
  }
}

Finder _mapCard(_Kind kind) => kind == _Kind.offer
    ? find.byKey(const ValueKey('offer-details-map'))
    : find.byType(DetailsMap);

Future<void> _reachMap(WidgetTester tester, _Kind kind) async {
  await tester.scrollUntilVisible(_mapCard(kind), 180,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(_mapCard(kind));
  await tester.pumpAndSettle();
}

TextButton _mapButton(WidgetTester tester, _Kind kind) =>
    tester.widget<TextButton>(
        find.descendant(of: _mapCard(kind), matching: find.byType(TextButton)));

void _expectMap(WidgetTester tester, _Kind kind, double? lat, double? lng,
    {required bool available}) {
  if (!available) {
    expect(find.byType(GoogleMap), findsNothing);
    if (kind == _Kind.offer) {
      // Without a location the Offer card has no Maps button at all.
      expect(find.byKey(const ValueKey('offer-details-view-larger')),
          findsNothing);
    } else {
      expect(tester.widget<DetailsMap>(_mapCard(kind)).onOpen, isNull);
    }
    final loc = AppLocalizations.of(tester.element(_mapCard(kind)));
    expect(find.text(loc.translate('mapLocationNotAvailable')), findsWidgets);
  } else {
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.initialCameraPosition.target, LatLng(lat!, lng!));
    expect(map.markers.single.position, LatLng(lat, lng));
    expect(_mapButton(tester, kind).onPressed, isNotNull);
  }
  expect(tester.takeException(), isNull);
}

void main() {
  final launches = <String>[];
  final checks = <String>[];
  late maps.GoogleMapsFlutterPlatform originalMaps;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });
  setUp(() {
    originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPixels();
    launches.clear();
    checks.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'),
            (call) async {
      final url = (call.arguments as Map)['url'] as String;
      if (call.method == 'canLaunch') checks.add(url);
      if (call.method == 'launch') launches.add(url);
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            (_) async => true);
  });
  tearDown(() {
    maps.GoogleMapsFlutterPlatform.instance = originalMaps;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), null);
  });

  for (final language in ['en', 'ar']) {
    final scenario =
        ResponsiveCase(const Size(412, 915), locale: Locale(language));
    for (final kind in _Kind.values) {
      testWidgets('${kind.name} invalid coordinates never build maps $language',
          (tester) async {
        for (final point in <(double?, double?)>[
          (null, null),
          (null, 55.3),
          (25.2, null),
          (double.nan, 55.3),
          (25.2, double.nan),
          (double.infinity, 55.3),
          (double.negativeInfinity, 55.3),
          (25.2, double.infinity),
          (25.2, double.negativeInfinity),
          (90.1, 55.3),
          (-90.1, 55.3),
          (25.2, 180.1),
          (25.2, -180.1),
          (0, 0),
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpResponsive(tester, scenario,
              home: withR2ScreenProviders(
                  _screen(kind, _record(kind, point.$1, point.$2))));
          await _reachMap(tester, kind);
          _expectMap(tester, kind, point.$1, point.$2, available: false);
          if (kind != _Kind.offer) {
            expect(find.text(kind == _Kind.watchman ? _location : _address),
                findsOneWidget);
          }
        }
        expect(checks, isEmpty);
        expect(launches, isEmpty);
      });

      testWidgets('${kind.name} valid map camera and destination $language',
          (tester) async {
        for (final point in [
          (25.2048, 55.2708),
          (-90.0, -180.0),
          (90.0, 180.0),
          (-33.8688, 151.2093),
          (0.0, 55.3),
          (25.2, 0.0)
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpResponsive(tester, scenario,
              home: withR2ScreenProviders(
                  _screen(kind, _record(kind, point.$1, point.$2))));
          await _reachMap(tester, kind);
          _expectMap(tester, kind, point.$1, point.$2, available: true);
          if (kind != _Kind.offer) {
            expect(tester.widget<DetailsMap>(_mapCard(kind)).address,
                kind == _Kind.watchman ? _location : _address);
          }
          _mapButton(tester, kind).onPressed!();
          await tester.pumpAndSettle();
          final destination =
              'https://www.google.com/maps/search/?api=1&query=${point.$1},${point.$2}';
          expect(checks.last, destination);
          expect(launches.last, destination);
          final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
          map.onTap!(map.initialCameraPosition.target);
          await tester.pumpAndSettle();
          expect(launches.last, destination);
        }
        expect(launches, hasLength(12));
      });

      if (kind != _Kind.offer) {
        for (final input in [
          (address: _address, location: _location),
          (address: '', location: _location),
          (address: _address, location: ''),
          (address: '   ', location: _location),
          (address: _address, location: '   '),
          (address: '', location: ''),
        ]) {
          testWidgets('${kind.name} address precedence $input $language',
              (tester) async {
            await pumpResponsive(tester, scenario,
                home: withR2ScreenProviders(_screen(
                    kind,
                    _record(kind, null, null,
                        address: input.address, location: input.location))));
            await _reachMap(tester, kind);
            final card = tester.widget<DetailsMap>(_mapCard(kind));
            final loc = AppLocalizations.of(tester.element(_mapCard(kind)));
            final primary =
                kind == _Kind.watchman ? input.location : input.address;
            final secondary =
                kind == _Kind.watchman ? input.address : input.location;
            // With neither, there is no address line: the card's own "location
            // not available" message already says so.
            final expected = primary.trim().isNotEmpty
                ? primary
                : secondary.trim().isNotEmpty
                    ? secondary
                    : null;
            expect(card.address, expected);
            if (expected != null) {
              expect(
                  find.descendant(
                      of: _mapCard(kind), matching: find.text(expected)),
                  findsOneWidget);
            }
            for (final key in [
              'specificLocationNotProvided',
              'noSpecificAddressProvided'
            ]) {
              expect(find.text(loc.translate(key)), findsNothing);
            }
            expect(Directionality.of(tester.element(_mapCard(kind))),
                language == 'ar' ? TextDirection.rtl : TextDirection.ltr);
            _expectMap(tester, kind, null, null, available: false);
          });
        }
      }

      testWidgets(
          '${kind.name} edit refreshes camera address and guarded callbacks $language',
          (tester) async {
        Object? edited;
        final path = switch (kind) {
          _Kind.offer => '/add-offers',
          _Kind.owner => '/add-owners',
          _Kind.office => '/add-offices',
          _Kind.watchman => '/add-watchmen',
        };
        final router = GoRouter(initialLocation: '/', routes: [
          GoRoute(
              path: '/',
              builder: (_, __) => withR2ScreenProviders(
                  _screen(kind, _record(kind, 25.2, 55.3)))),
          GoRoute(
              path: path,
              builder: (context, state) => Scaffold(
                  body: TextButton(
                      key: const ValueKey('finish-edit'),
                      onPressed: () => context.pop(edited),
                      child: const Text('Return edit result')))),
        ]);
        addTearDown(router.dispose);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp.router(
            routerConfig: router,
            locale: scenario.locale,
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: AppTheme.lightTheme));
        await tester.pumpAndSettle();
        await _reachMap(tester, kind);
        _expectMap(tester, kind, 25.2, 55.3, available: true);
        final staleMapTap =
            tester.widget<GoogleMap>(find.byType(GoogleMap)).onTap!;

        for (final point in [
          (24.4539, 54.3773),
          (double.nan, 55.3),
          (-33.8688, 151.2093)
        ]) {
          edited = _record(kind, point.$1, point.$2,
              address: 'Edited address عنوان معدل',
              location: 'Edited label مكان معدل');
          // Every kind, Offers included, uses the shared Details menu.
          final menu = find.byKey(const ValueKey('details-actions'));
          await tester.scrollUntilVisible(menu, -160,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(menu);
          await tester.pumpAndSettle();
          await tester.tap(menu);
          await tester.pumpAndSettle();
          final loc = AppLocalizations.of(tester.element(menu));
          await tester.tap(find.text(loc.translate('edit')).last);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('finish-edit')), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('finish-edit')));
          await tester.pumpAndSettle();
          await _reachMap(tester, kind);
          final available = !point.$1.isNaN;
          _expectMap(tester, kind, point.$1, point.$2, available: available);
          if (kind != _Kind.offer) {
            expect(
                tester.widget<DetailsMap>(_mapCard(kind)).address,
                kind == _Kind.watchman
                    ? 'Edited label مكان معدل'
                    : 'Edited address عنوان معدل');
          }
          checks.clear();
          launches.clear();
          staleMapTap(const LatLng(25.2, 55.3));
          await tester.pumpAndSettle();
          if (available) {
            expect(launches.single,
                'https://www.google.com/maps/search/?api=1&query=${point.$1},${point.$2}');
          } else {
            expect(checks, isEmpty);
            expect(launches, isEmpty);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
