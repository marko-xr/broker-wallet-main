import 'dart:async';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

import 'package:broker_wallet/src/common/enums/add_offers_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_offers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_offers_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewAdd/add_offers_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/offers_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/offers_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_loading_placeholder.dart';
import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:broker_wallet/src/Views/Widgets/plan_attachment_section.dart';
import 'package:broker_wallet/src/Views/Widgets/plan_attachment_details_card.dart';
import 'package:broker_wallet/src/Views/Widgets/media_upload_widget.dart';
import 'package:broker_wallet/src/views/Widgets/offer_media_upload_status.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../plan_attachment/fake_plan_transport.dart';
import 'r2_test_fakes.dart';
import 'responsive_harness.dart';

const _owner = 'layout-owner';
const _offerId = 'layout-offer';
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

OfferModel _offer() => OfferModel(
      id: _offerId,
      userId: _owner,
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Business Bay', 'Dubai Marina'],
      location:
          'Long mixed-language Offer location near the transit station منطقة الخليج التجاري',
      phoneNumber: '+971501234567',
      countryCode: '+971',
      minPrice: '100000000',
      maxPrice: '250000000',
      squareFootage: '2500',
      notes:
          'Very long Offer description with several requirements and accessibility information. تفاصيل طويلة عن العقار والموقع والمساحة المطلوبة.',
      propertyType: 'residential',
      specificPropertyType: 'Apartment',
      rooms: 4,
      bathrooms: 3,
      pickUpLocation: 'Long pickup location',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      createdAt: _created,
      updatedAt: _created,
      mediaUrls: const [],
    );

class _OfflineOfferService extends OfferService {
  _OfflineOfferService({this.list});
  final Stream<List<OfferModel>>? list;
  final ChangeNotifier uploads = ChangeNotifier();
  int subscriptions = 0;

  @override
  String? get currentOwnerId => _owner;

  @override
  Stream<List<OfferModel>> getUserOffers() {
    subscriptions++;
    return list ?? const Stream<List<OfferModel>>.empty();
  }

  @override
  Listenable get offerMediaUploadChanges => uploads;

  @override
  Stream<OfferMediaUploadCompleted> get offerMediaUploadCompletions =>
      const Stream<OfferMediaUploadCompleted>.empty();

  @override
  Future<void> loadOfferMediaUploads() async {}

  @override
  List<OfferMediaRef> pendingOfferMedia(String offerId) => const [];

  @override
  List<OfferMediaRef> cachedOfferMedia(String offerId) => const [];

  @override
  Future<OfferMediaResolution?> resolveOfferMedia({
    required String offerId,
    required String ownerId,
  }) async =>
      OfferMediaResolution(offerId: offerId, ownerId: ownerId, items: const []);

  @override
  Future<OfferModel?> getOfferMetadata(String offerId) async => _offer();
}

const _plan = PlanAttachmentRef(
  mediaObjectId: 'layout-plan',
  kind: PlanAttachmentKind.pdf,
  contentType: PlanContentTypes.pdf,
  displayName:
      'Very long plot plan file name for the selected property and its surrounding land.pdf',
  byteLength: 4096,
);

Future<void> _visible(
    WidgetTester tester, Finder finder, ResponsiveCase scenario) async {
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  final rect = tester.getRect(finder.first);
  final bottom = scenario.size.height - scenario.keyboard;
  if (scenario.keyboard == 0) {
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$scenario $rect');
    expect(rect.bottom, lessThanOrEqualTo(bottom + 1),
        reason: '$scenario $rect');
  } else {
    final top = scenario.safeArea.top + 56;
    final visible = (rect.bottom < bottom ? rect.bottom : bottom) -
        (rect.top > top ? rect.top : top);
    expect(visible, greaterThan(20), reason: '$scenario $rect');
  }
  expectNoLayoutException(tester, scenario);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });

  for (final scenario in _matrix) {
    testWidgets('Offer add form $scenario', (tester) async {
      final service = _OfflineOfferService();
      final vm = AddOffersViewModel(
        offerService: service,
        usesMediaQueue: true,
        mediaPicker: OfferMediaPicker(isAndroid: false),
        planTransport: FakePlanTransport(),
      );
      await pumpResponsive(tester, scenario,
          home: AddOffersView(viewModel: vm));
      expect(find.byType(AddOffersView), findsOneWidget);
      expect(find.byKey(const Key('planAttachment.add')), findsWidgets);
      if (scenario.keyboard == 0) {
        await _visible(tester, find.byType(SaveCancelButtons), scenario);
      } else {
        expect(find.byType(SaveCancelButtons), findsNothing);
      }
      await _visible(tester, find.byType(TextField).last, scenario);
    });

    testWidgets('Offer edit form with existing Plan $scenario', (tester) async {
      final service = _OfflineOfferService();
      final transport = FakePlanTransport()..current = _plan;
      final vm = AddOffersViewModel(
        mode: AddOffersMode.edit,
        offerId: _offerId,
        offerData: _offer(),
        offerService: service,
        usesMediaQueue: true,
        mediaPicker: OfferMediaPicker(isAndroid: false),
        planTransport: transport,
      );
      await pumpResponsive(tester, scenario,
          home: AddOffersView(
              mode: AddOffersMode.edit, offerData: _offer(), viewModel: vm));
      expect(find.byType(AddOffersView), findsOneWidget);
      expect(find.byKey(const Key('planAttachment.card')), findsWidgets);
      await _visible(
          tester, find.byKey(const Key('planAttachment.card')), scenario);
      expect(transport.calls.where((call) => call == 'fetch').length, 1);
    });

    testWidgets('Populated Offer list $scenario', (tester) async {
      final listScenario = _withoutKeyboard(scenario);
      final service = _OfflineOfferService(list: Stream.value([_offer()]));
      final vm = OffersListViewModel(offerService: service);
      await pumpResponsive(tester, listScenario,
          home: OffersListView(viewModel: vm));
      await expectDateSeparatorCentered(tester);
      expect(find.byType(OffersListView), findsOneWidget);
      await _visible(tester, find.byType(FloatingActionButton), listScenario);
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -300));
      await tester.pump();
      expect(find.byKey(const ValueKey('offer_layout-offer')), findsWidgets);
      expect(service.subscriptions, 1);
      expectNoLayoutException(tester, listScenario);
    });

    testWidgets('Offer details with separate Plan $scenario', (tester) async {
      final detailsScenario = _withoutKeyboard(scenario);
      final service = _OfflineOfferService();
      final transport = FakePlanTransport()..current = _plan;
      await pumpResponsive(tester, detailsScenario,
          home: withR2ScreenProviders(OffersDetailsView(
            offer: _offer(),
            initialOfferIsResolved: true,
            offerService: service,
            planTransport: transport,
          )));
      expect(find.byType(OffersDetailsView), findsOneWidget);
      expectNoLayoutException(tester, detailsScenario);
      for (var section = 0; section < 5; section++) {
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, -500));
        await tester.pump();
        expectNoLayoutException(tester, detailsScenario);
      }
      expect(find.byType(PlanAttachmentDetailsCard, skipOffstage: false),
          findsWidgets);
      final openPlan = find.byKey(const Key('planAttachment.details.open'),
          skipOffstage: false);
      await tester.ensureVisible(openPlan);
      await tester.pump();
      expect(openPlan.hitTestable(), findsOneWidget);
      expect(transport.calls.where((call) => call == 'fetch').length, 1);
    });
  }

  testWidgets('Offer list initial, empty, error, and archive toggle',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.6);
    final pending = StreamController<List<OfferModel>>();
    addTearDown(pending.close);
    final vm = OffersListViewModel(
        offerService: _OfflineOfferService(list: pending.stream));
    await pumpResponsive(tester, scenario, home: OffersListView(viewModel: vm));
    expectNoLayoutException(tester, scenario);
    pending.add([]);
    await tester.pump();
    expectNoLayoutException(tester, scenario);
    await tester.tap(find.byIcon(Icons.archive));
    await tester.pump();
    expect(vm.showInactiveOnly, isTrue);
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpResponsive(tester, scenario,
        home: OffersListView(
            viewModel: OffersListViewModel(
          offerService:
              _OfflineOfferService(list: Stream.error(StateError('offline'))),
        )));
    await tester.pump();
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Offer Plan status cards stay in bounds without external actions',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    const states = <PlanAttachmentView>[
      PlanAttachmentView(display: PlanDisplay.none),
      PlanAttachmentView(
          display: PlanDisplay.existing,
          kind: PlanAttachmentKind.pdf,
          displayName:
              'Very long plot plan file name for the selected property and its surrounding land.pdf'),
      PlanAttachmentView(
          display: PlanDisplay.working,
          kind: PlanAttachmentKind.word,
          displayName: 'Very long pending land plan document.docx'),
      PlanAttachmentView(
          display: PlanDisplay.failed,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Very long failed land plan.pdf'),
    ];
    for (final state in states) {
      await pumpResponsive(tester, scenario,
          settle: false,
          home: Scaffold(
              body: Builder(
                  builder: (context) => PlanAttachmentSection(
                        view: state,
                        localization: AppLocalizations.of(context),
                        onSelect: () {},
                        onRemove: () {},
                        onKeep: () {},
                        onRetry: () {},
                      ))));
      expectNoLayoutException(tester, scenario);
    }
  });

  for (final phase in <OfferMediaUploadPhase>[
    OfferMediaUploadPhase.queued,
    OfferMediaUploadPhase.retrying,
    OfferMediaUploadPhase.permanentFailure,
  ]) {
    testWidgets('Offer media $phase remains visible without transport',
        (tester) async {
      const scenario =
          ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
      final item = OfferMediaRef(
        mediaObjectId: 'layout-${phase.name}',
        cacheKey: null,
        isVideo: true,
        uploadPhase: phase,
        displayName:
            'Very long selected Offer video filename for this layout test.mp4',
      );
      await pumpResponsive(tester, scenario,
          settle: false,
          home: Scaffold(
              body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Builder(
                builder: (context) => MediaUploadWidget(
                      selectedFiles: const [],
                      onSelectMedia: () {},
                      onRemoveFile: (_) {},
                      onClearAll: () {},
                      localization: AppLocalizations.of(context),
                      showUploadButton: false,
                      showImagePreview: false,
                      offerMedia: [item],
                      onRemoveOfferMedia: (_) {},
                      onRetryOfferMedia: (_) {},
                    )),
          )));
      expect(find.byType(OfferMediaUploadStatus), findsOneWidget);
      expectNoLayoutException(tester, scenario);
    });
  }

  testWidgets('Offer details loading media uses a local pending resolver',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.6);
    final pending = Completer<OfferMediaResolution?>();
    final transport = FakePlanTransport();
    await pumpResponsive(tester, scenario,
        settle: false,
        home: withR2ScreenProviders(OffersDetailsView(
          offer: _offer(),
          initialOfferIsResolved: true,
          offerService: _OfflineOfferService(),
          planTransport: transport,
          resolveMedia: ({required offerId, required ownerId}) =>
              pending.future,
        )));
    await tester.pump();
    expect(find.byType(MediaLoadingPlaceholder, skipOffstage: false),
        findsOneWidget);
    expectNoLayoutException(tester, scenario);
    pending.complete(const OfferMediaResolution(
        offerId: _offerId, ownerId: _owner, items: []));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Offer details media failure keeps its retry UI reachable',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    await pumpResponsive(tester, scenario,
        settle: false,
        home: withR2ScreenProviders(OffersDetailsView(
          offer: _offer(),
          initialOfferIsResolved: true,
          offerService: _OfflineOfferService(),
          planTransport: FakePlanTransport(),
          resolveMedia: ({required offerId, required ownerId}) async =>
              throw StateError('local fixture failure'),
        )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(TextButton).hitTestable(), findsWidgets);
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Offer field, focus, and city survive portrait-landscape-portrait resize',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(393, 852), locale: Locale('ar'), textScale: 1.3);
    final vm = AddOffersViewModel(
      offerService: _OfflineOfferService(),
      usesMediaQueue: true,
      mediaPicker: OfferMediaPicker(isAndroid: false),
      planTransport: FakePlanTransport(),
    )..selectCity('Dubai');
    await pumpResponsive(tester, scenario, home: AddOffersView(viewModel: vm));
    final field = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.maxLines == 7);
    expect(field, findsOneWidget);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Offer notes text stays through resize');
    await tester.pump();
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    expectNoLayoutException(tester, scenario);
    tester.view.physicalSize = const Size(786, 1704);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text,
        'Offer notes text stays through resize');
    expect(vm.notes, 'Offer notes text stays through resize');
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
    expect(vm.selectedCity, 'Dubai');
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Offer list resize retains its one fake stream subscription',
      (tester) async {
    const scenario = ResponsiveCase(Size(393, 852));
    final service = _OfflineOfferService(list: Stream.value([_offer()]));
    await pumpResponsive(tester, scenario,
        home: OffersListView(
            viewModel: OffersListViewModel(offerService: service)));
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    tester.view.physicalSize = const Size(786, 1704);
    await tester.pump();
    expect(service.subscriptions, 1);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Offer swipe confirmation stays usable without deleting',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final service = _OfflineOfferService(list: Stream.value([_offer()]));
    await pumpResponsive(tester, scenario,
        home: OffersListView(
            viewModel: OffersListViewModel(offerService: service)));
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pump();
    await tester.ensureVisible(find.byType(Dismissible).first);
    await tester.pump();
    await tester.drag(find.byType(Dismissible).first, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expectNoLayoutException(tester, scenario);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byIcon(Icons.close_rounded),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.subscriptions, 1);
  });
}
