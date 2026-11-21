// Notification UX fixes (2026-11-21, owner's Samsung review): a reminder tap
// opens the record without a loading screen, delete all, the Arabic swipe
// background, the whole bell circle as one button, and the reminder time
// wheels. No Supabase, no device.
import 'dart:async';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/reminder_time_sheet.dart';
import 'package:broker_wallet/src/views/Screens/home/notifications/notification_target_resolver.dart';
import 'package:broker_wallet/src/views/Screens/home/notifications/notifications_list_view.dart';
import 'package:broker_wallet/src/views/Widgets/delete_confirmation_dialog.dart';
import 'package:broker_wallet/src/views/Widgets/notification_icon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../responsive/r3_test_fakes.dart';

final DateTime _at = DateTime.utc(2026, 11, 21, 9);

String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

NotificationModel _reminder(int id, {String? requestId, String? offerId}) =>
    NotificationModel(
      id: _uuid(id),
      title: 'Follow-up reminder',
      body: 'A request is due for follow-up.',
      category: NotificationCategory.reminder,
      isRead: false,
      createdAt: _at.subtract(Duration(minutes: id)),
      data: {
        'kind': 'follow_up',
        'target': offerId != null ? 'offer' : 'request',
      },
      requestId: requestId,
      offerId: offerId,
    );

RequestModel _request(String id) => RequestModel(
      id: id,
      userId: 'user-a',
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina'],
      location: 'Tower 1',
      phoneNumber: '500000000',
      countryCode: '+971',
      minPrice: '1000',
      maxPrice: '2000',
      squareFootage: '900',
      notes: 'note',
      propertyType: 'residential',
      specificPropertyType: 'apartment',
      rooms: 2,
      bathrooms: 1,
      status: PropertyStatus.active,
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 2, 3),
    );

OfferModel _offer(String id) => OfferModel(
      id: id,
      userId: 'user-a',
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
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      mediaUrls: const [],
    );

/// Records every lookup so a test can see which source was used.
class _Sources {
  final Map<String, RequestModel> cachedRequests = {};
  final Map<String, RequestModel> serverRequests = {};
  final Map<String, OfferModel> cachedOffers = {};
  final Map<String, OfferModel> serverOffers = {};
  final List<String> calls = [];
  bool cacheThrows = false;
  bool serverThrows = false;
  Completer<void>? serverGate;

  NotificationRecordLookup lookup({
    Duration budget = const Duration(seconds: 2),
  }) =>
      NotificationRecordLookup(
        fetchBudget: budget,
        cachedRequest: (id) async {
          calls.add('cache:request');
          if (cacheThrows) throw StateError('cache');
          return cachedRequests[id];
        },
        fetchRequest: (id) async {
          calls.add('server:request');
          await serverGate?.future;
          if (serverThrows) throw StateError('server');
          return serverRequests[id];
        },
        cachedOffer: (id) async {
          calls.add('cache:offer');
          if (cacheThrows) throw StateError('cache');
          return cachedOffers[id];
        },
        fetchOffer: (id) async {
          calls.add('server:offer');
          await serverGate?.future;
          if (serverThrows) throw StateError('server');
          return serverOffers[id];
        },
      );
}

Widget _localized(Widget child, {Locale locale = const Locale('en')}) {
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

/// A signed-in inbox whose feed has already answered (with no rows), so the
/// screen is never in its loading state: its spinner never stops moving and
/// `pumpAndSettle` would wait for it forever.
({NotificationViewModel vm, ControlledNotificationRepository repo}) _feed() {
  final repo = ControlledNotificationRepository();
  final vm = NotificationViewModel(repository: repo, isOnline: () => true)
    ..attachUser('user-a');
  repo.emit(const []);
  return (vm: vm, repo: repo);
}

void main() {
  // The app's translations are read from asset files; widget tests need them
  // cached up front, as the other widget tests do, or no localized screen
  // ever finishes building.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.preloadAllLanguages();
  });

  group('inbox destination (decided at once)', () {
    test('a Request reminder opens the inbox Request route', () {
      final target = inboxDestination(_reminder(1, requestId: _uuid(60)))!;
      expect(target.location, '$notificationRequestRoute/${_uuid(60)}');
      expect(target.extra, isNull);
    });

    test('an Offer reminder opens the inbox Offer route', () {
      final target = inboxDestination(_reminder(1, offerId: _uuid(50)))!;
      expect(target.location, '$notificationOfferRoute/${_uuid(50)}');
    });

    test('a reminder without a valid record id opens nothing', () {
      expect(inboxDestination(_reminder(1, requestId: 'not-an-id')), isNull);
    });

    test('match notifications keep their own destination', () {
      final match = NotificationModel(
        id: _uuid(1),
        title: 't',
        body: 'b',
        category: NotificationCategory.match,
        isRead: false,
        createdAt: _at,
        data: const {},
        offerId: _uuid(8),
        requestId: _uuid(9),
      );
      expect(inboxDestination(match)!.location, '/match-details');
    });
  });

  group('record lookup', () {
    test('an Offer on the phone is used, no server read', () async {
      final s = _Sources()..cachedOffers[_uuid(50)] = _offer(_uuid(50));
      expect((await s.lookup().findOffer(_uuid(50)))!.id, _uuid(50));
      expect(s.calls, ['cache:offer']);
    });

    test('a Request not on the phone is read from the server', () async {
      final s = _Sources()..serverRequests[_uuid(60)] = _request(_uuid(60));
      expect((await s.lookup().findRequest(_uuid(60)))!.id, _uuid(60));
      expect(s.calls, ['cache:request', 'server:request']);
    });

    test('a copy with another id is never used', () async {
      final s = _Sources()
        ..cachedRequests[_uuid(60)] = _request(_uuid(61))
        ..serverRequests[_uuid(60)] = _request(_uuid(60));
      expect((await s.lookup().findRequest(_uuid(60)))!.id, _uuid(60));
    });

    test('failures and a slow server find nothing, never throw', () async {
      final failing = _Sources()
        ..cacheThrows = true
        ..serverThrows = true;
      expect(await failing.lookup().findRequest(_uuid(60)), isNull);
      final slow = _Sources()..serverGate = Completer<void>();
      expect(
        await slow
            .lookup(budget: const Duration(milliseconds: 20))
            .findOffer(_uuid(50)),
        isNull,
      );
    });

    test('with no signed-in account nothing is found', () async {
      final none = NotificationRecordLookup.forAccount(null);
      expect(await none.findRequest(_uuid(60)), isNull);
      expect(await none.findOffer(_uuid(50)), isNull);
    });
  });

  group('inbox-opened details screen', () {
    Widget screen(Future<RequestModel?> Function() find) => _localized(
          NotificationRecordScreen<RequestModel>(
            find: find,
            details: (r) => Text('details ${r.id}'),
            fallback: (_) => const Text('fallback'),
          ),
        );

    testWidgets('a record found at once shows the details, no loader',
        (tester) async {
      await tester.pumpWidget(screen(() async => _request(_uuid(60))));
      await tester.pumpAndSettle();
      expect(find.text('details ${_uuid(60)}'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a slow lookup shows a blank page first, a spinner only later',
        (tester) async {
      final answer = Completer<RequestModel?>();
      await tester.pumpWidget(screen(() => answer.future));
      // The screen (and its spinner timer) starts once translations load.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('notification-record-waiting')),
          findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      answer.complete(_request(_uuid(60)));
      await tester.pump();
      expect(find.text('details ${_uuid(60)}'), findsOneWidget);
    });

    testWidgets('nothing found hands over to the regular screen',
        (tester) async {
      await tester.pumpWidget(screen(() async => null));
      await tester.pumpAndSettle();
      expect(find.text('fallback'), findsOneWidget);
    });
  });

  group('inbox screen', () {
    testWidgets('a reminder tap starts opening at once and shows the record',
        (tester) async {
      final f = _feed();
      addTearDown(f.vm.dispose);
      final s = _Sources()..cachedRequests[_uuid(60)] = _request(_uuid(60));
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ChangeNotifierProvider.value(
            value: f.vm,
            child: const NotificationsListView(),
          ),
        ),
        GoRoute(
          path: '$notificationRequestRoute/:id',
          builder: (_, state) => NotificationRecordScreen<RequestModel>(
            find: () => s.lookup().findRequest(state.pathParameters['id']!),
            details: (r) => Text('details ${r.id}'),
            fallback: (_) => const Text('loader'),
          ),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ));
      await tester.pumpAndSettle();
      f.repo.emit([_reminder(1, requestId: _uuid(60))]);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      // One frame after the tap the details route is already on its way:
      // nothing was awaited before navigating (one frame for the router to
      // apply the push, one for the new page).
      await tester.pump();
      await tester.pump();
      expect(
          find.byType(NotificationRecordScreen<RequestModel>), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('details ${_uuid(60)}'), findsOneWidget);
      expect(find.text('loader'), findsNothing);
    });

    for (final (locale, dragBy, endOnRight) in [
      (const Locale('en'), -200.0, true),
      (const Locale('ar'), 200.0, false),
    ]) {
      testWidgets(
          '${locale.languageCode}: the bin shows on the side the swipe opens',
          (tester) async {
        final f = _feed();
        addTearDown(f.vm.dispose);
        await tester.pumpWidget(_localized(
          ChangeNotifierProvider.value(
            value: f.vm,
            child: const NotificationsListView(),
          ),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        f.repo.emit([_reminder(1, requestId: _uuid(60))]);
        await tester.pumpAndSettle();

        final gesture =
            await tester.startGesture(tester.getCenter(find.byType(ListTile)));
        await gesture.moveBy(Offset(dragBy / 2, 0));
        await gesture.moveBy(Offset(dragBy / 2, 0));
        await tester.pump();
        final bin = tester.getCenter(find.byIcon(Icons.delete));
        final card = tester.getRect(
            find.byKey(const ValueKey('notification-delete-background')));
        expect(bin.dx > card.center.dx, endOnRight);
        await gesture.up();
        await tester.pumpAndSettle();
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets(
          '${brightness.name}: read cards are neutral, unread ones are marked '
          'by signals, not by recolouring the card', (tester) async {
        final f = _feed();
        addTearDown(f.vm.dispose);
        final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF02957D),
            brightness: brightness,
          ),
        );
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ChangeNotifierProvider.value(
            value: f.vm,
            child: const NotificationsListView(),
          ),
        ));
        await tester.pumpAndSettle();
        final read = NotificationModel(
          id: _uuid(2),
          title: 't',
          body: 'b',
          category: NotificationCategory.reminder,
          isRead: true,
          createdAt: _at.subtract(const Duration(minutes: 2)),
          data: const {},
          requestId: _uuid(60),
        );
        f.repo.emit([_reminder(1, requestId: _uuid(60)), read]);
        await tester.pumpAndSettle();

        BoxDecoration card(int id) => tester
            .widget<DecoratedBox>(
                find.byKey(ValueKey('notification-card-${_uuid(id)}')))
            .decoration as BoxDecoration;
        final scheme = theme.colorScheme;
        final dark = brightness == Brightness.dark;
        final unreadCard = card(1);
        final readCard = card(2);
        Color borderOf(BoxDecoration c) => (c.border! as Border).top.color;

        // Read: the plain card surface with a fine neutral outline.
        expect(readCard.color, dark ? scheme.surface : Colors.white);
        expect(readCard.gradient, isNull);
        expect(borderOf(readCard),
            scheme.onSurface.withValues(alpha: dark ? 0.12 : 0.08));
        // Unread: a light flat brand tint and a brand outline, no gradient.
        expect(unreadCard.gradient, isNull);
        expect(unreadCard.color, isNot(readCard.color));
        expect(borderOf(unreadCard), scheme.primary.withValues(alpha: 0.28));
        // Shadows: soft and neutral in light mode, none in dark mode; never
        // tinted with a colour.
        for (final c in [readCard, unreadCard]) {
          expect(c.borderRadius, const BorderRadius.all(Radius.circular(16)));
          if (dark) {
            expect(c.boxShadow, isNull);
          } else {
            expect(c.boxShadow!.single.color,
                Colors.black.withValues(alpha: 0.04));
          }
        }
        // The unread dot is on the unread card only.
        expect(
          find.descendant(
            of: find.byKey(ValueKey('notification-card-${_uuid(1)}')),
            matching: find.byKey(const ValueKey('notification-unread-dot')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey('notification-card-${_uuid(2)}')),
            matching: find.byKey(const ValueKey('notification-unread-dot')),
          ),
          findsNothing,
        );
      });
    }

    testWidgets('delete all asks first, then empties the inbox',
        (tester) async {
      final f = _feed();
      addTearDown(f.vm.dispose);
      await tester.pumpWidget(_localized(ChangeNotifierProvider.value(
        value: f.vm,
        child: const NotificationsListView(),
      )));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('notifications-delete-all')), findsNothing);
      f.repo.emit([
        _reminder(1, requestId: _uuid(60)),
        _reminder(2, offerId: _uuid(50)),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notifications-delete-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DeleteConfirmationDialog.cancelKey));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('notifications-delete-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DeleteConfirmationDialog.deleteKey));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(
          find.byKey(const ValueKey('notifications-delete-all')), findsNothing);
    });
  });

  group('bell', () {
    testWidgets('a tap anywhere on the circle, badge included, opens it',
        (tester) async {
      final f = _feed();
      addTearDown(f.vm.dispose);
      f.repo.emitUnread(3);
      var opened = 0;
      await tester.pumpWidget(_localized(Center(
        child: ChangeNotifierProvider.value(
          value: f.vm,
          child: NotificationIcon(onPressed: () => opened++),
        ),
      )));
      await tester.pumpAndSettle();
      final circle = tester
          .getRect(find.byKey(const ValueKey('notification-icon-button')));
      expect(circle.size, const Size(48, 48));
      // The unread count is a red badge with white digits.
      final badge = tester.widget<Container>(
          find.byKey(const ValueKey('notification-icon-badge')));
      expect((badge.decoration! as BoxDecoration).color,
          AppColors.notificationBadge);
      expect(tester.widget<Text>(find.text('3')).style!.color, Colors.white);
      // Near the left edge (outside the bell image), and on the badge.
      await tester.tapAt(circle.centerLeft + const Offset(4, 0));
      await tester.tapAt(circle.topRight + const Offset(-12, 8));
      await tester.tapAt(circle.center);
      expect(opened, 3);
    });
  });

  group('reminder time', () {
    testWidgets('the time is chosen on wheels and Save returns it',
        (tester) async {
      TimeOfDay? chosen;
      var closed = false;
      await tester.pumpWidget(_localized(Scaffold(
          body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            chosen = await showReminderTimeSheet(
              context,
              initial: const TimeOfDay(hour: 10, minute: 42),
            );
            closed = true;
          },
          child: const Text('open'),
        ),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('follow-up-time-save')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(chosen, const TimeOfDay(hour: 10, minute: 42));
    });

    testWidgets('Cancel returns nothing', (tester) async {
      TimeOfDay? chosen = const TimeOfDay(hour: 1, minute: 1);
      await tester.pumpWidget(_localized(Scaffold(
          body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => chosen = await showReminderTimeSheet(
            context,
            initial: const TimeOfDay(hour: 10, minute: 42),
          ),
          child: const Text('open'),
        ),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('follow-up-time-cancel')));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
    });

    testWidgets('Arabic shows the wheels right to left', (tester) async {
      await tester.pumpWidget(_localized(
        const Scaffold(
          body: ReminderTimeSheet(initial: TimeOfDay(hour: 10, minute: 42)),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(CupertinoDatePicker))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
