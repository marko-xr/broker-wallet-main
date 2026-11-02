import 'dart:async';

import 'package:broker_wallet/src/common/enums/add_requested_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_requests_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewAdd/add_requested_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/requested_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/requests_list_view.dart';
import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'r2_test_fakes.dart';
import 'responsive_harness.dart';

const _matrix = <ResponsiveCase>[
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

final _created = DateTime.utc(2026, 10, 28, 8);

ResponsiveCase _withoutKeyboard(ResponsiveCase scenario) => ResponsiveCase(
      scenario.size,
      locale: scenario.locale,
      dark: scenario.dark,
      textScale: scenario.textScale,
      safeArea: scenario.safeArea,
    );

RequestModel _request({String id = 'layout-request'}) => RequestModel(
      id: id,
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
      createdAt: _created,
      updatedAt: _created,
    );

class _StreamRequestService extends RequestService {
  _StreamRequestService(this.source);
  final Stream<List<RequestModel>> source;

  @override
  Stream<List<RequestModel>> getUserRequests() => source;
}

Future<void> _reachable(
    WidgetTester tester, Finder target, ResponsiveCase scenario) async {
  expect(target, findsWidgets);
  await tester.ensureVisible(target.first);
  await tester.pump();
  var rect = tester.getRect(target.first);
  if (scenario.keyboard > 0) {
    final visibleTop = scenario.safeArea.top + 56;
    final visibleBottom = scenario.size.height - scenario.keyboard;
    final visibleHeight =
        (rect.bottom < visibleBottom ? rect.bottom : visibleBottom) -
            (rect.top > visibleTop ? rect.top : visibleTop);
    expect(visibleHeight, greaterThan(20), reason: '$scenario rect=$rect');
    expectNoLayoutException(tester, scenario);
    return;
  }
  for (var i = 0; i < 10 && rect.bottom > scenario.size.height; i++) {
    final scroll = find.byType(SingleChildScrollView);
    if (scroll.evaluate().isEmpty) break;
    await tester.drag(scroll.first, const Offset(0, -120));
    await tester.pump();
    rect = tester.getRect(target.first);
  }
  expect(rect.width, greaterThan(0), reason: scenario.toString());
  expect(rect.top, greaterThanOrEqualTo(0), reason: '$scenario rect=$rect');
  expect(rect.bottom, lessThanOrEqualTo(scenario.size.height + 1),
      reason: '$scenario rect=$rect');
  expectNoLayoutException(tester, scenario);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });

  for (final scenario in _matrix) {
    testWidgets('Request add form $scenario', (tester) async {
      await pumpResponsive(tester, scenario, home: const AddRequestedView());
      expect(find.byType(AddRequestedView), findsOneWidget);
      if (scenario.keyboard == 0) {
        expect(find.byType(SaveCancelButtons), findsOneWidget);
        await _reachable(tester, find.byType(SaveCancelButtons), scenario);
      } else {
        expect(find.byType(SaveCancelButtons), findsNothing);
      }
      await _reachable(tester, find.byType(TextField).last, scenario);
    });

    testWidgets('Request edit form with long values $scenario', (tester) async {
      await pumpResponsive(tester, scenario,
          home: AddRequestedView(
              mode: AddRequestedMode.edit, requestData: _request()));
      expect(find.byType(AddRequestedView), findsOneWidget);
      await _reachable(tester, find.byType(TextField).last, scenario);
    });

    testWidgets('Populated Request list $scenario', (tester) async {
      final listScenario = _withoutKeyboard(scenario);
      final vm = RequestedListViewModel(
          requestService: _StreamRequestService(Stream.value([_request()])));
      await pumpResponsive(tester, listScenario,
          home: RequestedListView(viewModel: vm));
      await expectDateSeparatorCentered(tester);
      expect(find.byType(RequestedListView), findsOneWidget);
      await _reachable(tester, find.byType(FloatingActionButton), listScenario);
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -300));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('request_layout-request')), findsWidgets);
      expectNoLayoutException(tester, listScenario);
    });

    testWidgets('Long Request details $scenario', (tester) async {
      final detailsScenario = _withoutKeyboard(scenario);
      await pumpResponsive(tester, detailsScenario,
          home: withR2ScreenProviders(RequestDetailsView(request: _request())));
      expect(find.byType(RequestDetailsView), findsOneWidget);
      expectNoLayoutException(tester, detailsScenario);
      for (var section = 0; section < 5; section++) {
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, -500));
        await tester.pump();
        expectNoLayoutException(tester, detailsScenario);
      }
    });
  }

  testWidgets('Request list initial, empty, and error states', (tester) async {
    const scenario =
        ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.6);
    final pending = StreamController<List<RequestModel>>();
    addTearDown(pending.close);
    await pumpResponsive(tester, scenario,
        home: RequestedListView(
            viewModel: RequestedListViewModel(
                requestService: _StreamRequestService(pending.stream))));
    expectNoLayoutException(tester, scenario);
    pending.add([]);
    await tester.pump();
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpResponsive(tester, scenario,
        home: RequestedListView(
            viewModel: RequestedListViewModel(
                requestService: _StreamRequestService(
                    Stream.error(StateError('offline'))))));
    await tester.pump();
    expectNoLayoutException(tester, scenario);
  });

  testWidgets(
      'Request notes remain editable through a phone to landscape resize',
      (tester) async {
    const phone =
        ResponsiveCase(Size(393, 852), locale: Locale('ar'), textScale: 1.3);
    await pumpResponsive(tester, phone, home: const AddRequestedView());
    final notes = find.byType(TextField).last;
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Layout resize keeps these request notes');
    await tester.pump();
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(notes).controller?.text,
        'Layout resize keeps these request notes');
    expectNoLayoutException(tester, phone);
  });

  testWidgets('Request archive filter remains operable on a narrow phone',
      (tester) async {
    const phone =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final vm = RequestedListViewModel(
        requestService: _StreamRequestService(Stream.value([_request()])));
    await pumpResponsive(tester, phone, home: RequestedListView(viewModel: vm));
    await tester.tap(find.byIcon(Icons.archive));
    await tester.pump();
    expect(vm.showInactiveOnly, isTrue);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expectNoLayoutException(tester, phone);
  });
}
