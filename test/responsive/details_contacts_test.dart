import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/Views/Widgets/property_status_indicator.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/views/Screens/ViewDetails/brokers_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offers_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offices_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/owners_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/requested_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/watchmen_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../plan_attachment/fake_plan_transport.dart';
import 'r2_test_fakes.dart';
import 'r5_details_expectations.dart';
import 'r5d_entity_cases.dart'
    show LayoutRelatedService, relatedOffer, relatedRequest;
import 'responsive_harness.dart';

class _NoOfferUploads extends OfferService {
  final uploads = ChangeNotifier();
  @override
  Listenable get offerMediaUploadChanges => uploads;
  @override
  Stream<OfferMediaUploadCompleted> get offerMediaUploadCompletions =>
      const Stream.empty();
  @override
  Future<void> loadOfferMediaUploads() async {}

  @override
  Future<void> updateOffer(String offerId, OfferModel offer) async {
    throw StateError('Private update error');
  }

  @override
  Future<void> deleteOffer(String offerId) async {
    throw StateError('Private delete error');
  }
}

Widget _screen(String kind, String phone, {String code = '+971'}) {
  final related = LayoutRelatedService();
  switch (kind) {
    case 'Offer':
      return OffersDetailsView(
          offer: relatedOffer().copyWith(phoneNumber: phone, countryCode: code),
          initialOfferIsResolved: true,
          offerService: _NoOfferUploads(),
          resolveMedia: ({required offerId, required ownerId}) async =>
              OfferMediaResolution(
                  offerId: offerId, ownerId: ownerId, items: []),
          readCachedMedia: (_) => [],
          readPendingMedia: (_) => [],
          planTransport: FakePlanTransport());
    case 'Request':
      return RequestDetailsView(
          request:
              relatedRequest().copyWith(phoneNumber: phone, countryCode: code));
    case 'Owner':
      // An id-less Owner avoids unrelated private-media/Plan transport.
      return OwnersDetailsView(
          owner: OwnerModel(
              userId: 'local',
              name: 'Owner',
              phoneNumber: phone,
              countryCode: code,
              typeOfProperties: 'Apartment',
              propertyLocation: 'Dubai',
              notes: '',
              pickUpLocation: '',
              pickUpAddress: '',
              pickUpLatitude: null,
              pickUpLongitude: null,
              mediaUrls: [],
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026)),
          relatedItemsService: related);
    case 'Office':
      return OfficesDetailsView(
          office: OfficeModel(
              officeName: 'Office',
              managerName: 'Manager',
              phoneNumber: phone,
              countryCode: code,
              officeLocation: 'Dubai',
              notes: '',
              pickUpLocation: '',
              pickUpAddress: ''),
          relatedItemsService: related);
    case 'Broker':
      return BrokersDetailsView(
          broker: BrokerModel(
              name: 'Broker', phoneNumber: phone, countryCode: code, notes: ''),
          relatedItemsService: related);
    case 'Watchman':
      return WatchmenDetailsView(
          watchmen: WatchmenModel(
              name: 'Watchman',
              buildingName: 'Building',
              phoneNumber: phone,
              countryCode: code,
              buildingLocation: 'Dubai',
              notes: '',
              pickUpLocation: '',
              pickUpAddress: ''),
          relatedItemsService: related);
    default:
      throw StateError('Unknown fixture $kind');
  }
}

Finder get _call => find.byKey(const ValueKey('details-call'));
Finder get _whatsApp => find.byKey(const ValueKey('details-whatsapp'));

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

void main() {
  final launches = <Uri>[];
  final toasts = <String>[];
  var fail = false;
  var throws = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });
  setUp(() {
    fail = false;
    throws = false;
    launches.clear();
    toasts.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      if (call.method == 'canLaunch') throw StateError('No preflight required');
      launches.add(Uri.parse((call.arguments as Map)['url'] as String));
      if (throws) throw PlatformException(code: 'unavailable');
      return !fail;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('PonnamKarthik/fluttertoast'), (call) async {
      toasts.add((call.arguments as Map)['msg'] as String);
      return true;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('PonnamKarthik/fluttertoast'), null);
  });
  for (final language in ['en', 'ar']) {
    final scenario = ResponsiveCase(const Size(412, 915),
        locale: Locale(language), dark: language == 'ar');
    testWidgets(
        'Offer status and delete failures use safe localized feedback $language',
        (tester) async {
      await pumpResponsive(tester, scenario,
          home: withR2ScreenProviders(_screen('Offer', '')));
      final details = find.byType(OffersDetailsView);
      final loc = AppLocalizations.of(tester.element(details));
      await tapExpandedStatusBadge(tester, 'offer-details-status');
      await tester.pumpAndSettle();
      final status = find
          .descendant(
            of: find.byType(PropertyStatusSelector),
            matching: find.byType(ListTile),
          )
          .last;
      await tester.ensureVisible(status);
      await tester.tap(status);
      await tester.pumpAndSettle();
      expect(toasts, [loc.translate('failedToUpdateStatus')]);

      final menu = find.byTooltip(loc.translate('offerDetailsActions'));
      if (menu.evaluate().isEmpty) {
        await tester.scrollUntilVisible(menu, 120,
            scrollable: find.byType(Scrollable).first);
      }
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(loc.translate('deleteOffer')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.delete_rounded),
      ));
      await tester.pumpAndSettle();
      expect(toasts, [
        loc.translate('failedToUpdateStatus'),
        loc.translate('failedToDeleteOffer'),
      ]);
      expect(details, findsOneWidget);
      expectNoLayoutException(tester, scenario);
    });

    for (final (kind, nameKey, secondary, secondaryKey) in [
      ('Owner', 'name', 'Dubai', 'propertyLocation'),
      ('Office', 'officeName', 'Dubai', 'officeLocation'),
      ('Broker', 'brokerName', null, null),
      ('Watchman', 'watchmenName', 'Building', 'buildingName'),
    ]) {
      testWidgets('$kind consolidated summary and missing values $language',
          (tester) async {
        await pumpResponsive(tester, scenario,
            home: withR2ScreenProviders(_screen(kind, '')));
        final name = find.text(kind);
        expect(name, findsOneWidget);
        final context = tester.element(name);
        final loc = AppLocalizations.of(context);
        expect(tester.widget<Text>(name).semanticsLabel,
            '${loc.translate(nameKey)}: $kind');
        if (secondary != null) {
          final subtitle = find.text(secondary);
          expect(subtitle, findsOneWidget);
          expect(tester.widget<Text>(subtitle).semanticsLabel,
              '${loc.translate(secondaryKey!)}: $secondary');
        }
        final missing =
            tester.widget<Text>(find.text(loc.translate('phoneNotAdded')));
        expect(missing.style?.color,
            Theme.of(context).colorScheme.onSurfaceVariant);
      });
    }
    for (final kind in [
      'Offer',
      'Request',
      'Owner',
      'Office',
      'Broker',
      'Watchman'
    ]) {
      testWidgets('$kind contact validation and successful launches $language',
          (tester) async {
        for (final phone in ['', '   ', 'abc0501234567', '123', '+97112345']) {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpResponsive(tester, scenario,
              home: withR2ScreenProviders(_screen(kind, phone)));
          final call = tester.widget<OutlinedButton>(_call);
          final colors = Theme.of(tester.element(_call)).colorScheme;
          expect(call.onPressed, isNull);
          expect(
            call.style!.side!.resolve({WidgetState.disabled})!.color,
            colors.outlineVariant,
          );
          expect(tester.widget<FilledButton>(_whatsApp).onPressed, isNull);
          final mutedColor = colors.onSurfaceVariant.withValues(alpha: 0.5);
          final callIcon = tester.widget<Icon>(find.descendant(
            of: _call,
            matching: find.byIcon(Icons.phone_disabled_rounded),
          ));
          final whatsAppIcon = tester.widget<Image>(find.descendant(
            of: _whatsApp,
            matching: find.byType(Image),
          ));
          expect(callIcon.color, mutedColor);
          expect(whatsAppIcon.color, mutedColor);
        }
        expect(launches, isEmpty);
        for (final number in [
          ('0501234567', '+971', '+971501234567'),
          ('020 7946 0958', '+44', '+442079460958')
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpResponsive(tester, scenario,
              home: withR2ScreenProviders(
                  _screen(kind, number.$1, code: number.$2)));
          final headers = find.byType(DetailsHeaderControl);
          // Back, Favorite, Share and the record menu.
          expect(headers, findsNWidgets(4));
          for (final target in [
            headers.at(0),
            headers.at(1),
            headers.at(2),
            headers.at(3),
            _call,
            _whatsApp
          ]) {
            final size = tester.getSize(target);
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          final theme = Theme.of(tester.element(_call));
          final whatsappStyle = tester.widget<FilledButton>(_whatsApp).style!;
          expect(whatsappStyle.backgroundColor!.resolve({}),
              theme.colorScheme.primary);
          expect(
              _contrast(whatsappStyle.foregroundColor!.resolve({})!,
                  theme.colorScheme.primary),
              greaterThanOrEqualTo(4.5));
          final callStyle = tester.widget<OutlinedButton>(_call).style!;
          expect(callStyle.side!.resolve({})!.color,
              theme.colorScheme.primary.withValues(alpha: 0.7));
          expect(
              _contrast(callStyle.foregroundColor!.resolve({})!,
                  theme.colorScheme.surface),
              greaterThanOrEqualTo(4.5));
          expect(
              theme.textTheme.bodyMedium!.fontSize, greaterThanOrEqualTo(13));
          expect(theme.textTheme.bodySmall!.fontSize, greaterThanOrEqualTo(12));
          expect(theme.textTheme.bodyMedium!.fontFamily, 'Montserrat');
          await tester.tap(_call);
          await tester.pumpAndSettle();
          expect(launches.last.scheme, 'tel');
          expect(launches.last.path, number.$3);
          await tester.tap(_whatsApp);
          await tester.pumpAndSettle();
          expect(
              launches.last.queryParameters['phone'], number.$3.substring(1));
          // WhatsApp opens an empty chat: no pre-filled message.
          expect(launches.last.queryParameters.containsKey('text'), isFalse);
          expect(toasts, isEmpty);
        }
      });
      testWidgets('$kind contact false/exception feedback $language',
          (tester) async {
        await pumpResponsive(tester, scenario,
            home: withR2ScreenProviders(_screen(kind, '+971501234567')));
        final loc = AppLocalizations.of(tester.element(_call));
        for (final exception in [false, true]) {
          fail = true;
          throws = exception;
          launches.clear();
          toasts.clear();
          await tester.tap(_call);
          await tester.pumpAndSettle();
          expect(toasts.single, loc.translate('unableToMakePhoneCall'));
          expect(launches, hasLength(1));
          toasts.clear();
          launches.clear();
          await tester.tap(_whatsApp);
          await tester.pumpAndSettle();
          expect(toasts.single, loc.translate('couldNotOpenWhatsApp'));
          expect(launches, hasLength(3));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
