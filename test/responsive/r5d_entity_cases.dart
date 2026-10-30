import 'dart:async';

import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/related_items_service.dart';
import 'package:broker_wallet/src/widgets/auto_scrolling_related_items_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'r2_test_fakes.dart';
import 'responsive_harness.dart';

const entityMatrix = <ResponsiveCase>[
  ResponsiveCase(Size(280, 600), textScale: 2),
  ResponsiveCase(Size(320, 568),
      locale: Locale('ar'), dark: true, textScale: 1.6),
  ResponsiveCase(Size(360, 640),
      safeArea: EdgeInsets.only(top: 24, bottom: 20), keyboard: 240),
  ResponsiveCase(Size(393, 852), locale: Locale('ar'), textScale: 1.3),
  ResponsiveCase(Size(430, 932), dark: true),
  ResponsiveCase(Size(640, 360),
      locale: Locale('ar'), dark: true, textScale: 2, keyboard: 240),
  ResponsiveCase(Size(600, 800), textScale: 1.6),
  ResponsiveCase(Size(800, 1280),
      locale: Locale('ar'), dark: true, textScale: 1.3),
];

ResponsiveCase noKeyboard(ResponsiveCase c) => ResponsiveCase(c.size,
    locale: c.locale,
    dark: c.dark,
    textScale: c.textScale,
    safeArea: c.safeArea);

// Source fixture fields are shared with the existing R5 offer/request tests.
OfferModel relatedOffer() => OfferModel(
      id: 'related-offer',
      userId: 'layout-user',
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Business Bay'],
      location: 'Long location موقع طويل',
      phoneNumber: '+971501234567',
      countryCode: '+971',
      minPrice: '100000000',
      maxPrice: '250000000',
      squareFootage: '2500',
      notes: 'Long property notes تفاصيل طويلة',
      propertyType: 'residential',
      specificPropertyType: 'Apartment',
      rooms: 4,
      bathrooms: 3,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
      mediaUrls: const [],
    );

RequestModel relatedRequest() => RequestModel(
      id: 'related-request',
      userId: 'layout-only',
      requestType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Business Bay', 'Dubai Marina'],
      location:
          'Very long mixed language request location منطقة الخليج التجاري دبي',
      phoneNumber: '+971501234567',
      countryCode: '+971',
      minPrice: '100000',
      maxPrice: '250000',
      squareFootage: '2500',
      notes:
          'Long request notes for a property near transit with detailed requirements. تفاصيل طويلة عن العقار والموقع والمساحة المطلوبة.',
      propertyType: 'residential',
      specificPropertyType: 'Apartment',
      rooms: 4,
      bathrooms: 3,
      createdAt: DateTime.utc(2026, 10, 28),
      updatedAt: DateTime.utc(2026, 10, 28),
    );

class LayoutRelatedService extends RelatedItemsService {
  LayoutRelatedService({this.state = 'empty'});
  final String state;
  int offerReads = 0;
  int requestReads = 0;
  @override
  Stream<List<OfferModel>> getRelatedOffers(String phone) {
    offerReads++;
    if (state == 'pending') return const Stream.empty();
    if (state == 'error')
      return Stream.error(StateError('local related failure'));
    return Stream.value(state == 'populated' ? [relatedOffer()] : []);
  }

  @override
  Stream<List<RequestModel>> getRelatedRequests(String phone) {
    requestReads++;
    return Stream.value(state == 'populated' ? [relatedRequest()] : []);
  }
}

Future<void> reachable(
    WidgetTester tester, Finder control, ResponsiveCase c) async {
  expect(control, findsWidgets);
  await tester.ensureVisible(control.first);
  await tester.pump();
  final r = tester.getRect(control.first);
  final top = c.safeArea.top + 56;
  final bottom = c.size.height - c.keyboard;
  final visible =
      (r.bottom < bottom ? r.bottom : bottom) - (r.top > top ? r.top : top);
  expect(visible, greaterThanOrEqualTo((r.height < 20 ? r.height : 20) - 1),
      reason: '$c $r');
  expectNoLayoutException(tester, c);
}

// Each registration renders real screens; only service streams and map pixels are fake.
void entityCases<T, V extends ChangeNotifier>({
  required String name,
  required String keyPrefix,
  bool mapSupported = false,
  required T Function(int index, bool mapped) record,
  required V Function(T? edit) model,
  required Widget Function(V vm, bool edit) form,
  required Widget Function(Stream<List<T>> stream, VoidCallback onRead) list,
  required Widget Function(T record, RelatedItemsService related) details,
  required void Function(V vm, String value) setPhone,
  required String? Function(V vm) phoneError,
}) {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });
  for (final c in entityMatrix) {
    for (final edit in [false, true]) {
      testWidgets('$name ${edit ? "edit" : "add"} $c', (tester) async {
        final vm = model(edit ? record(0, true) : null);
        await pumpResponsive(tester, c, home: form(vm, edit));
        for (var i = 0; i < find.byType(TextField).evaluate().length; i++) {
          await reachable(tester, find.byType(TextField).at(i), c);
        }
        if (c.keyboard == 0) {
          expect(find.byType(OutlinedButton).hitTestable(), findsWidgets);
          expect(find.byType(ElevatedButton).hitTestable(), findsWidgets);
        } else {
          expect(find.byType(SaveCancelButtons), findsNothing);
          final before = tester
              .widgetList<TextField>(find.byType(TextField))
              .map((w) => w.controller?.text)
              .toList();
          await pumpResponsive(tester, noKeyboard(c), home: form(vm, edit));
          expect(
              tester
                  .widgetList<TextField>(find.byType(TextField))
                  .map((w) => w.controller?.text)
                  .toList(),
              before);
          expect(find.byType(OutlinedButton).hitTestable(), findsWidgets);
          expect(find.byType(ElevatedButton).hitTestable(), findsWidgets);
        }
      });
    }
    testWidgets('$name list top middle bottom $c', (tester) async {
      final window = noKeyboard(c);
      var reads = 0;
      await pumpResponsive(tester, window,
          home: list(Stream.value(List.generate(8, (i) => record(i, false))),
              () => reads++));
      expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget);
      for (final i in [0, 3, 7]) {
        final tile = find.byWidgetPredicate(
            (w) => w is Dismissible && w.key == ValueKey('${keyPrefix}_$i'));
        await tester.scrollUntilVisible(tile, 250,
            scrollable: find.byType(Scrollable).first);
        final call =
            find.descendant(of: tile, matching: find.byIcon(Icons.phone)).last;
        await reachable(tester, call, window);
        expect(call.hitTestable(), findsOneWidget);
      }
      expect(reads, 1);
    });
    testWidgets('$name details and collapse $c', (tester) async {
      final window = noKeyboard(c);
      await pumpResponsive(tester, window,
          home: withR2ScreenProviders(
              details(record(0, true), LayoutRelatedService())));
      expect(find.byIcon(Icons.share_outlined).hitTestable(), findsWidgets);
      expect(find.byKey(const Key('local-map-preview')),
          mapSupported ? findsOneWidget : findsNothing);
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pump();
        expectNoLayoutException(tester, window);
      }
    });
  }

  testWidgets('$name input focus selection resize and invalid phone',
      (tester) async {
    const c =
        ResponsiveCase(Size(393, 852), locale: Locale('ar'), textScale: 1.3);
    final vm = model(null);
    await pumpResponsive(tester, c, home: form(vm, false));
    final field =
        find.byWidgetPredicate((w) => w is TextField && w.maxLines == 7);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Long retained notes تفاصيل الملاحظات');
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 6);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    tester.view.physicalSize = const Size(786, 1704);
    await tester.pump();
    expect(controller.text, 'Long retained notes تفاصيل الملاحظات');
    expect(controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6));
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    setPhone(vm, '12');
    await tester.pump();
    expect(phoneError(vm), isNotNull);
    expectNoLayoutException(tester, c);
  });

  testWidgets('$name list initial empty error and failed refresh',
      (tester) async {
    const c =
        ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.6);
    final stream = StreamController<List<T>>();
    addTearDown(stream.close);
    var reads = 0;
    await pumpResponsive(tester, c, home: list(stream.stream, () => reads++));
    stream.add([]);
    await tester.pump();
    await tester.pump();
    expectNoLayoutException(tester, c);
    stream.add([record(0, false)]);
    await tester.pump();
    await tester.pump();
    stream.addError(StateError('local refresh failure'));
    await tester.pump();
    await tester.pump();
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    expect(reads, 1);
    expect(find.byType(Dismissible), findsWidgets);
    expectNoLayoutException(tester, c);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpResponsive(tester, c,
        home: list(Stream.error(StateError('local initial failure')), () {}));
    expectNoLayoutException(tester, c);
  });

  for (final c in const [
    ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2),
    ResponsiveCase(Size(640, 360), locale: Locale('ar'), textScale: 2)
  ]) {
    for (final isDetails in [false, true]) {
      testWidgets('$name ${isDetails ? "detail" : "swipe"} cancel dialog $c',
          (tester) async {
        await pumpResponsive(tester, c,
            home: isDetails
                ? withR2ScreenProviders(
                    details(record(0, false), LayoutRelatedService()))
                : list(Stream.value([record(0, false)]), () {}));
        if (isDetails) {
          await tester.tap(find.byIcon(Icons.delete_outline));
        } else {
          await tester.drag(
              find.byType(CustomScrollView), const Offset(0, -300));
          await tester.pump();
          final call = find
              .descendant(
                  of: find.byType(Dismissible),
                  matching: find.byIcon(Icons.phone))
              .last;
          await tester.ensureVisible(call);
          await tester.pump();
          expect(call.hitTestable(), findsOneWidget);
          await tester.dragFrom(tester.getCenter(call), const Offset(500, 0));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expectNoLayoutException(tester, c);
        final cancel = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byIcon(Icons.close_rounded));
        await tester.ensureVisible(cancel);
        await tester.pump();
        expect(cancel.hitTestable(), findsOneWidget);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }

  for (final state in ['pending', 'error', 'populated']) {
    testWidgets('$name related $state and stable streams', (tester) async {
      final c = state == 'populated'
          ? const ResponsiveCase(Size(280, 600),
              locale: Locale('ar'), textScale: 2)
          : const ResponsiveCase(Size(393, 852),
              locale: Locale('ar'), textScale: 1.3);
      final related = LayoutRelatedService(state: state);
      await pumpResponsive(tester, c,
          home: withR2ScreenProviders(details(record(0, false), related)),
          settle: false);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pump();
        expectNoLayoutException(tester, c);
      }
      expect(find.byType(AutoScrollingRelatedItemsCarousel),
          state == 'populated' ? findsOneWidget : findsNothing);
      if (state == 'populated') {
        final carousel = find.byType(AutoScrollingRelatedItemsCarousel);
        await tester.ensureVisible(carousel);
        await tester.pump();
        final page =
            find.descendant(of: carousel, matching: find.byType(PageView));
        expect(page, findsOneWidget);
        await tester.ensureVisible(page);
        await tester.pump();
        final bounds = tester.getRect(page);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(c.size.width));
        await tester.drag(page, const Offset(240, 0));
        await tester.pump(const Duration(milliseconds: 600));
        expectNoLayoutException(tester, c);
      }
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pump();
      expect(related.offerReads, 1);
      expect(related.requestReads, 1);
      expectNoLayoutException(tester, c);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
