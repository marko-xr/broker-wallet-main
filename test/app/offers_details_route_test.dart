import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/app.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

OfferModel _offer(String? id, {List<String> mediaUrls = const []}) {
  final now = DateTime(2026, 1, 1);
  return OfferModel(
    id: id,
    userId: 'owner-a',
    offerType: 'rent',
    selectedCity: 'Dubai',
    selectedAreas: const [],
    location: 'Dubai',
    phoneNumber: '',
    countryCode: '+971',
    minPrice: '1',
    maxPrice: '2',
    notes: '',
    specificPropertyType: '',
    rooms: 1,
    bathrooms: 1,
    pickUpLocation: '',
    pickUpLatitude: null,
    pickUpLongitude: null,
    pickUpAddress: '',
    uploadedFileName: '',
    createdAt: now,
    updatedAt: now,
    mediaUrls: mediaUrls,
  );
}

Widget _localizedWidget(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

GoRouter _legacyContractRouter() => GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('root')),
        ),
        GoRoute(
          path: '/start',
          builder: (context, state) => const Scaffold(body: Text('start')),
        ),
        GoRoute(
          path: '/offers-details',
          redirect: (context, state) => redirectLegacyOfferDetailsRoute(state),
        ),
        GoRoute(
          path: '/offers-details-by-id/:id',
          builder: (context, state) => Scaffold(
            body: Text('offer:${state.pathParameters['id']}'),
          ),
        ),
      ],
    );

Widget _localizedRouter(GoRouter router) => MaterialApp.router(
      routerConfig: router,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.preloadAllLanguages();
  });

  group('legacy /offers-details compatibility contract', () {
    testWidgets('missing extra returns to the bootstrap gate, not not-found',
        (tester) async {
      final router = _legacyContractRouter();
      await tester.pumpWidget(_localizedRouter(router));
      await tester.pumpAndSettle();

      router.push('/offers-details');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('root'), findsOneWidget);
      expect(find.text('Offer not found'), findsNothing);
    });

    testWidgets('a surviving model redirects by its stable ID without looping',
        (tester) async {
      final router = _legacyContractRouter();
      await tester.pumpWidget(_localizedRouter(router));
      await tester.pumpAndSettle();

      router.push('/offers-details', extra: _offer('offer-a'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('offer:offer-a'), findsOneWidget);
      expect(find.text('root'), findsNothing);
    });

    testWidgets('a model without identity returns to bootstrap safely',
        (tester) async {
      final router = _legacyContractRouter();
      await tester.pumpWidget(_localizedRouter(router));
      await tester.pumpAndSettle();

      router.push('/offers-details', extra: _offer(null));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('root'), findsOneWidget);
    });
  });

  group('canonical ID loader', () {
    testWidgets('valid ID is fetched once and marked resolved for the view',
        (tester) async {
      var calls = 0;
      var receivedResolved = false;

      await tester.pumpWidget(_localizedWidget(
        OfferDetailsLoader(
          offerId: 'offer-a',
          loadOffer: (id) async {
            calls++;
            expect(id, 'offer-a');
            return _offer('offer-a', mediaUrls: const ['resolved-media']);
          },
          detailsBuilder: (context, offer, initialOfferIsResolved) {
            receivedResolved = initialOfferIsResolved;
            return Text('loaded:${offer.id}:${offer.mediaUrls.single}');
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(receivedResolved, isTrue);
      expect(find.text('loaded:offer-a:resolved-media'), findsOneWidget);
    });

    testWidgets(
        'pending metadata shows a localized themed loading state, not a blank page',
        (tester) async {
      final pending = Completer<OfferModel?>();
      await tester.pumpWidget(_localizedWidget(
        OfferDetailsLoader(
          offerId: 'offer-a',
          loadOffer: (id) => pending.future,
          detailsBuilder: (context, offer, initialOfferIsResolved) =>
              Text('loaded:${offer.id}'),
        ),
      ));
      await tester.pump();

      expect(find.text('Loading'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNotNull);

      pending.complete(_offer('offer-a'));
      await tester.pumpAndSettle();
    });

    testWidgets('whitespace ID fails safely without calling the service',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_localizedWidget(
        OfferDetailsLoader(
          offerId: '   ',
          loadOffer: (id) async {
            calls++;
            return _offer(id);
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(tester.takeException(), isNull);
      expect(find.text('Offer not found'), findsOneWidget);
    });

    testWidgets('nonexistent or inaccessible ID shows localized not-found',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_localizedWidget(
        OfferDetailsLoader(
          offerId: 'missing-offer',
          loadOffer: (id) async {
            calls++;
            return null;
          },
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(tester.takeException(), isNull);
      expect(find.text('العرض غير موجود'), findsOneWidget);
      expect(find.text('رجوع'), findsOneWidget);
    });

    testWidgets('loader errors fail safely', (tester) async {
      await tester.pumpWidget(_localizedWidget(
        OfferDetailsLoader(
          offerId: 'offer-a',
          loadOffer: (id) => Future<OfferModel?>.error(StateError('denied')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Offer not found'), findsOneWidget);
    });

    testWidgets('a mismatched loader result is never displayed',
        (tester) async {
      var detailsBuilt = false;
      await tester.pumpWidget(_localizedWidget(
        OfferDetailsLoader(
          offerId: 'offer-a',
          loadOffer: (id) async => _offer('offer-b'),
          detailsBuilder: (context, offer, initialOfferIsResolved) {
            detailsBuilt = true;
            return Text('wrong:${offer.id}');
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(detailsBuilt, isFalse);
      expect(find.text('Offer not found'), findsOneWidget);
      expect(find.text('wrong:offer-b'), findsNothing);
    });
  });

  group('initial refresh contract', () {
    test('only an extra matching the authoritative path ID may render', () {
      final offerA = _offer('offer-a');
      expect(matchingOfferDetailsExtra(offerA, 'offer-a'), same(offerA));
      expect(matchingOfferDetailsExtra(offerA, 'offer-b'), isNull);
      expect(matchingOfferDetailsExtra(null, 'offer-a'), isNull);
    });
  });

  group('auth routing remains the single authority', () {
    test('normal startup destinations are unchanged', () {
      expect(resolveAuthRedirect(AuthStatus.authenticated, '/'), '/home');
      expect(resolveAuthRedirect(AuthStatus.unauthenticated, '/'), '/welcome');
    });

    test('Offer Details waits for bootstrap and requires authentication', () {
      const path = '/offers-details-by-id/offer-a';
      expect(resolveAuthRedirect(AuthStatus.unknown, path), '/');
      expect(resolveAuthRedirect(AuthStatus.unauthenticated, path), '/welcome');
      expect(resolveAuthRedirect(AuthStatus.authenticated, path), isNull);
      expect(
        resolveAuthRedirect(
          AuthStatus.authenticated,
          path,
          passwordRecoveryActive: true,
        ),
        '/reset-password',
      );
    });
  });

  test('all seven in-app Offer entry points carry the canonical ID path', () {
    const paths = [
      'lib/src/widgets/compact_offer_card.dart',
      'lib/src/views/Widgets/filtered_tiles.dart',
      'lib/src/views/Screens/ViewLists/offers_list_view.dart',
      'lib/src/views/Screens/home/map/map_view.dart',
      'lib/src/views/Screens/home/search/search_view.dart',
      'lib/src/views/Screens/home/favorites/favorites_card.dart',
      'lib/src/views/Screens/home/notifications/match_details_view.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('/offers-details-by-id/'), reason: path);
      expect(
        source,
        isNot(contains("context.push('/offers-details'")),
        reason: path,
      );
    }
  });
}
