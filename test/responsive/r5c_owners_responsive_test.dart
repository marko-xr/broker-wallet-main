import 'dart:async';
import 'dart:io';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_offers_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewAdd/add_offers_view.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/views/Widgets/entity_delete_progress.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/Views/Widgets/selectable_chip.dart';
import 'package:broker_wallet/src/services/related_items_service.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

import 'package:broker_wallet/src/common/enums/add_owners_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_owners_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_owners_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewAdd/add_owners_view.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/owners_view_details.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/owners_list_view.dart';
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
const _recordId = 'layout-record';
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

OwnerModel _record() => OwnerModel(
      id: _recordId,
      userId: _owner,
      name: 'Long property owner name اسم المالك الطويل للاختبار',
      phoneNumber: '+971501234567',
      countryCode: '+971',
      typeOfProperties: 'Apartment and residential buildings عقارات سكنية',
      propertyLocation: 'Dubai Marina long property location منطقة المارينا',
      notes:
          'Long owner notes with requirements and access information. تفاصيل طويلة عن العقار والموقع والمساحة المطلوبة.',
      pickUpLocation: 'Long pickup location',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      mediaUrls: const [],
      createdAt: _created,
      updatedAt: _created,
    );

class _OfflineOwnerService extends OwnerService {
  _OfflineOwnerService({this.list});
  final Stream<List<OwnerModel>>? list;
  final ChangeNotifier uploads = ChangeNotifier();
  Future<OfferMediaResolution?> Function()? resolver;
  int subscriptions = 0;
  int resolutions = 0;
  List<OfferMediaRef> pending = [];
  List<OfferMediaRef> cached = [];

  @override
  String? get currentOwnerId => _owner;

  @override
  Stream<List<OwnerModel>> getUserOwners() {
    subscriptions++;
    return list ?? const Stream<List<OwnerModel>>.empty();
  }

  @override
  Listenable get uploadChanges => uploads;

  @override
  Stream<OfferMediaUploadCompleted> get uploadCompletions =>
      const Stream<OfferMediaUploadCompleted>.empty();

  @override
  Future<void> loadUploads() async {}

  @override
  List<OfferMediaRef> pendingMedia(String offerId) => pending;

  @override
  List<OfferMediaRef> cachedMedia(String offerId) => cached;

  @override
  Future<OfferMediaResolution?> resolveMedia({
    required String recordId,
    required String ownerId,
  }) async {
    resolutions++;
    return resolver != null
        ? resolver!()
        : OfferMediaResolution(
            offerId: recordId, ownerId: ownerId, items: cached);
  }
}

class _DeletionPresentation extends OwnersListViewModel {
  _DeletionPresentation(superService) : super(ownerService: superService);
  @override
  bool isDeleting(String? id) => id == _recordId;
}

class _PendingPlan extends FakePlanTransport {
  final gate = Completer<PlanAttachmentRef?>();
  @override
  Future<PlanAttachmentRef?> fetchCurrent(
      {required PlanParent parent, required String parentId}) {
    fetched.add((parent, parentId));
    return gate.future;
  }
}

class _LayoutOfferService extends OfferService {}

class _OfflineRelated extends RelatedItemsService {
  int offersReads = 0;
  int requestsReads = 0;
  @override
  Stream<List<OfferModel>> getRelatedOffers(String phone) {
    offersReads++;
    return const Stream.empty();
  }

  @override
  Stream<List<RequestModel>> getRelatedRequests(String phone) {
    requestsReads++;
    return const Stream.empty();
  }
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
    expect(visible,
        greaterThanOrEqualTo((rect.height < 20 ? rect.height : 20) - 1),
        reason: '$scenario $rect');
  }
  expectNoLayoutException(tester, scenario);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });

  for (final scenario in _matrix) {
    testWidgets('Owner add form $scenario', (tester) async {
      final service = _OfflineOwnerService();
      final vm = AddOwnersViewModel(
        ownerService: service,
        usesMediaQueue: true,
        mediaPicker: OfferMediaPicker(isAndroid: false),
        planTransport: FakePlanTransport(),
      );
      await pumpResponsive(tester, scenario,
          home: AddOwnersView(viewModel: vm));
      expect(find.byType(AddOwnersView), findsOneWidget);
      expect(find.byKey(const Key('planAttachment.add')), findsWidgets);
      if (scenario.keyboard == 0) {
        await _visible(tester, find.byType(SaveCancelButtons), scenario);
      } else {
        expect(find.byType(SaveCancelButtons), findsNothing);
      }
      for (var i = 0; i < find.byType(TextField).evaluate().length; i++) {
        await _visible(tester, find.byType(TextField).at(i), scenario);
      }
    });

    testWidgets('Owner edit form with existing Plan $scenario', (tester) async {
      final service = _OfflineOwnerService();
      final transport = FakePlanTransport()..current = _plan;
      final vm = AddOwnersViewModel(
        mode: AddOwnersMode.edit,
        ownerId: _recordId,
        ownerData: _record(),
        ownerService: service,
        usesMediaQueue: true,
        mediaPicker: OfferMediaPicker(isAndroid: false),
        planTransport: transport,
      );
      await pumpResponsive(tester, scenario,
          home: AddOwnersView(
              mode: AddOwnersMode.edit, ownerData: _record(), viewModel: vm));
      expect(find.byType(AddOwnersView), findsOneWidget);
      expect(find.byKey(const Key('planAttachment.card')), findsWidgets);
      await _visible(
          tester, find.byKey(const Key('planAttachment.card')), scenario);
      expect(transport.calls.where((call) => call == 'fetch').length, 1);
      expect(transport.fetched.single, (PlanParent.owner, _recordId));
    });

    testWidgets('Populated Owner list $scenario', (tester) async {
      final listScenario = _withoutKeyboard(scenario);
      final records = List.generate(
          8,
          (i) => _record().copyWith(
              id: 'row-$i', uploadedFileName: i.isEven ? 'local fixture' : ''));
      final service = _OfflineOwnerService(list: Stream.value(records));
      final vm = OwnersListViewModel(ownerService: service);
      await pumpResponsive(tester, listScenario,
          home: OwnersListView(createViewModel: () => vm));
      expect(find.byType(OwnersListView), findsOneWidget);
      await _visible(tester, find.byType(FloatingActionButton), listScenario);
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -300));
      await tester.pump();
      for (final id in ['row-3', 'row-7']) {
        final tile = find.byWidgetPredicate(
            (w) => w is Dismissible && w.key == ValueKey('owner_$id'));
        await tester.scrollUntilVisible(tile, 250,
            scrollable: find.byType(Scrollable).first);
        final call =
            find.descendant(of: tile, matching: find.byIcon(Icons.phone));
        await tester.ensureVisible(call);
        await tester.pump();
        expect(call.hitTestable(), findsOneWidget);
        expectNoLayoutException(tester, listScenario);
      }
      expect(service.subscriptions, 1);
      expectNoLayoutException(tester, listScenario);
    });

    testWidgets('Owner details with separate Plan $scenario', (tester) async {
      final detailsScenario = _withoutKeyboard(scenario);
      final service = _OfflineOwnerService();
      final transport = FakePlanTransport()..current = _plan;
      await pumpResponsive(tester, detailsScenario,
          home: withR2ScreenProviders(OwnersDetailsView(
            owner: _record(),
            relatedItemsService: _OfflineRelated(),
            ownerService: service,
            planTransport: transport,
          )));
      expect(find.byType(OwnersDetailsView), findsOneWidget);
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
      expect(transport.fetched.single, (PlanParent.owner, _recordId));
    });
  }

  testWidgets('Owner list initial, empty and error', (tester) async {
    const scenario =
        ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.6);
    final pending = StreamController<List<OwnerModel>>();
    addTearDown(pending.close);
    final vm = OwnersListViewModel(
        ownerService: _OfflineOwnerService(list: pending.stream));
    await pumpResponsive(tester, scenario,
        home: OwnersListView(createViewModel: () => vm));
    expectNoLayoutException(tester, scenario);
    pending.add([]);
    await tester.pump();
    expectNoLayoutException(tester, scenario);
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpResponsive(tester, scenario,
        home: OwnersListView(
            createViewModel: () => OwnersListViewModel(
                  ownerService: _OfflineOwnerService(
                      list: Stream.error(StateError('offline'))),
                )));
    await tester.pump();
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Owner Plan status cards stay in bounds without external actions',
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
    for (final state in [
      ...states,
      const PlanAttachmentView(
          display: PlanDisplay.draft,
          kind: PlanAttachmentKind.word,
          displayName: 'Long selected Owner plan.docx'),
      const PlanAttachmentView(
          display: PlanDisplay.replacing,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Long replacement Owner plan.pdf',
          hasServerPlan: true),
    ]) {
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
    testWidgets('Owner media $phase remains visible without transport',
        (tester) async {
      const scenario =
          ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
      final item = OfferMediaRef(
        mediaObjectId: 'layout-${phase.name}',
        cacheKey: null,
        isVideo: true,
        uploadPhase: phase,
        displayName:
            'Very long selected Owner video filename for this layout test.mp4',
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

  testWidgets('Owner details loading media uses a local pending resolver',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(320, 568), locale: Locale('ar'), textScale: 1.6);
    final pending = Completer<OfferMediaResolution?>();
    final transport = FakePlanTransport();
    await pumpResponsive(tester, scenario,
        settle: false,
        home: withR2ScreenProviders(OwnersDetailsView(
          owner: _record(),
          relatedItemsService: _OfflineRelated(),
          ownerService: _OfflineOwnerService()..resolver = () => pending.future,
          planTransport: transport,
        )));
    await tester.pump();
    expect(find.byType(OwnersDetailsView), findsOneWidget);
    expectNoLayoutException(tester, scenario);
    pending.complete(const OfferMediaResolution(
        offerId: _recordId, ownerId: _owner, items: []));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Owner details media failure keeps its retry UI reachable',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    await pumpResponsive(tester, scenario,
        settle: false,
        home: withR2ScreenProviders(OwnersDetailsView(
          owner: _record(),
          relatedItemsService: _OfflineRelated(),
          ownerService: _OfflineOwnerService()
            ..resolver = () async => throw StateError('local fixture failure'),
          planTransport: FakePlanTransport(),
        )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(TextButton).hitTestable(), findsWidgets);
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Owner field, focus, and city survive portrait-landscape-portrait resize',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(393, 852), locale: Locale('ar'), textScale: 1.3);
    final vm = AddOwnersViewModel(
      ownerService: _OfflineOwnerService(),
      usesMediaQueue: true,
      mediaPicker: OfferMediaPicker(isAndroid: false),
      planTransport: FakePlanTransport(),
    )..selectLocationCity('Dubai', 'ar');
    await pumpResponsive(tester, scenario, home: AddOwnersView(viewModel: vm));
    final field = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.maxLines == 7);
    expect(field, findsOneWidget);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Owner notes text stays through resize');
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 8);
    final selection = controller.selection;
    final state = tester.element(find.byType(AddOwnersView));
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    expect(tester.element(find.byType(AddOwnersView)), same(state));
    expect(controller.selection, selection);
    expectNoLayoutException(tester, scenario);
    tester.view.physicalSize = const Size(786, 1704);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text,
        'Owner notes text stays through resize');
    expect(vm.notes, 'Owner notes text stays through resize');
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
    expect(vm.locationCity, 'Dubai');
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Owner list resize retains its one fake stream subscription',
      (tester) async {
    const scenario = ResponsiveCase(Size(393, 852));
    final service = _OfflineOwnerService(list: Stream.value([_record()]));
    await pumpResponsive(tester, scenario,
        home: OwnersListView(
            createViewModel: () => OwnersListViewModel(ownerService: service)));
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    tester.view.physicalSize = const Size(786, 1704);
    await tester.pump();
    await pumpResponsive(
        tester, const ResponsiveCase(Size(393, 852), locale: Locale('ar')),
        home: OwnersListView(
            createViewModel: () => OwnersListViewModel(ownerService: service)));
    expect(service.subscriptions, 1);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Owner swipe confirmation stays usable without deleting',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final service = _OfflineOwnerService(list: Stream.value([_record()]));
    await pumpResponsive(tester, scenario,
        home: OwnersListView(
            createViewModel: () => OwnersListViewModel(ownerService: service)));
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

  for (final scenario in const [
    ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2),
    ResponsiveCase(Size(640, 360), locale: Locale('ar'), textScale: 2),
  ]) {
    testWidgets('Owner details delete cancel $scenario', (tester) async {
      await pumpResponsive(tester, scenario,
          home: withR2ScreenProviders(OwnersDetailsView(
            owner: _record(),
            ownerService: _OfflineOwnerService(),
            planTransport: FakePlanTransport(),
            relatedItemsService: _OfflineRelated(),
          )));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expectNoLayoutException(tester, scenario);
      final cancel = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byIcon(Icons.close_rounded));
      await tester.ensureVisible(cancel);
      expect(cancel.hitTestable(), findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Owner list empty and error short window $scenario',
        (tester) async {
      for (final stream in [
        Stream<List<OwnerModel>>.value([]),
        Stream<List<OwnerModel>>.error(StateError('offline fixture'))
      ]) {
        await pumpResponsive(tester, scenario,
            home: OwnersListView(
                createViewModel: () => OwnersListViewModel(
                    ownerService: _OfflineOwnerService(list: stream))));
        expectNoLayoutException(tester, scenario);
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -200));
        await tester.pump();
        expectNoLayoutException(tester, scenario);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('Owner local invalid phone, chips and keyboard dismissal',
      (tester) async {
    const scenario = ResponsiveCase(Size(280, 600),
        locale: Locale('ar'), textScale: 2, keyboard: 240);
    final vm = AddOwnersViewModel(
        ownerService: _OfflineOwnerService(),
        usesMediaQueue: true,
        mediaPicker: OfferMediaPicker(isAndroid: false),
        planTransport: FakePlanTransport());
    await pumpResponsive(tester, scenario, home: AddOwnersView(viewModel: vm));
    final phone = find.byType(TextField).at(1);
    await tester.ensureVisible(phone);
    await tester.enterText(phone, '12');
    await tester.pump();
    expect(vm.phoneError, isNotNull);
    expectNoLayoutException(tester, scenario);
    final chip = find.byType(SelectableChip).first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    expect(vm.typeOfProperties, isNotEmpty);
    final retainedPhone = vm.phone;
    await pumpResponsive(tester, _withoutKeyboard(scenario),
        home: AddOwnersView(viewModel: vm));
    expect(vm.phone, retainedPhone);
    final actions = find.byType(SaveCancelButtons);
    expect(
        find
            .descendant(of: actions, matching: find.byType(OutlinedButton))
            .hitTestable(),
        findsOneWidget);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Owner pending media expands and survives resize with its Plan',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final service = _OfflineOwnerService()
      ..pending = List.generate(
          5,
          (i) => OfferMediaRef(
              mediaObjectId: 'pending-$i',
              cacheKey: null,
              isVideo: true,
              uploadPhase: OfferMediaUploadPhase.retryableFailure,
              displayName: 'Long pending Owner video $i.mp4'));
    final transport = FakePlanTransport()..current = _plan;
    final vm = AddOwnersViewModel(
        mode: AddOwnersMode.edit,
        ownerId: _recordId,
        ownerData: _record(),
        ownerService: service,
        usesMediaQueue: true,
        mediaPicker: OfferMediaPicker(isAndroid: false),
        planTransport: transport);
    await pumpResponsive(tester, scenario,
        home: AddOwnersView(mode: AddOwnersMode.edit, viewModel: vm));
    expect(vm.ownerMediaItems.length, 5);
    final more = find.text('+2 more');
    await tester.ensureVisible(more);
    await tester.pump();
    expect(more.hitTestable(), findsOneWidget);
    await tester.tap(more);
    await tester.pump();
    expect(vm.mediaDisplayCount, 5);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    expectNoLayoutException(tester, scenario);
    tester.view.physicalSize = const Size(560, 1200);
    await tester.pump();
    expect(vm.ownerMediaItems.length, 5);
    expect(vm.mediaDisplayCount, 5);
    expect(vm.planAttachment!.view.display, PlanDisplay.existing);
    expect(transport.fetched, [(PlanParent.owner, _recordId)]);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets(
      'Owner loaded local image and pending video preserve gallery and Plan separation',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final image = File('assets/images/whatsapp.png');
    // Reuse a bundled local image: no network, file picker, video playback or download.
    expect(image.existsSync(), isTrue);
    final service = _OfflineOwnerService()
      ..cached = [
        OfferMediaRef(
            mediaObjectId: 'photo',
            cacheKey: null,
            localFilePath: image.absolute.path),
        OfferMediaRef(
            mediaObjectId: 'video',
            cacheKey: null,
            isVideo: true,
            posterPath: image.absolute.path,
            uploadPhase: OfferMediaUploadPhase.queued),
      ];
    final transport = FakePlanTransport()..current = _plan;
    await pumpResponsive(tester, scenario,
        settle: false,
        home: withR2ScreenProviders(OwnersDetailsView(
            owner: _record(),
            ownerService: service,
            planTransport: transport,
            relatedItemsService: _OfflineRelated())));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final gallery = tester.widget<OptimizedMediaGalleryWidget>(
        find.byType(OptimizedMediaGalleryWidget));
    expect(gallery.mediaRefs!.length, 2);
    expect(
        gallery.mediaRefs!
            .any((item) => item.mediaObjectId == _plan.mediaObjectId),
        isFalse);
    await tester.drag(find.byType(PageView), const Offset(240, 0));
    await tester.pump(const Duration(seconds: 1));
    expectNoLayoutException(tester, scenario);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    expect(service.resolutions, 1);
    expect(transport.fetched, [(PlanParent.owner, _recordId)]);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets(
      'Offer consumer retains shared pickup controls at narrow Arabic 2x',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final vm = AddOffersViewModel(
        offerService: _LayoutOfferService(), usesMediaQueue: false);
    await pumpResponsive(tester, scenario, home: AddOffersView(viewModel: vm));
    final mapLabel = AppLocalizations.translateFor('ar', 'map')!;
    final map = find.widgetWithText(TextButton, mapLabel);
    await tester.ensureVisible(map);
    await tester.pump();
    expect(map.hitTestable(), findsOneWidget);
    final labelRect =
        tester.getRect(find.descendant(of: map, matching: find.text(mapLabel)));
    final buttonRect = tester.getRect(map);
    expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left));
    expect(labelRect.right, lessThanOrEqualTo(buttonRect.right));
    expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Offer pickup keeps its ordinary trailing alignment',
      (tester) async {
    const scenario = ResponsiveCase(Size(393, 852));
    final vm = AddOffersViewModel(
        offerService: _LayoutOfferService(), usesMediaQueue: false);
    await pumpResponsive(tester, scenario, home: AddOffersView(viewModel: vm));
    final mapLabel = AppLocalizations.translateFor('en', 'map')!;
    final map = find.widgetWithText(TextButton, mapLabel);
    await tester.ensureVisible(map);
    await tester.pump();
    expect(map.hitTestable(), findsOneWidget);
    final labelRect =
        tester.getRect(find.descendant(of: map, matching: find.text(mapLabel)));
    final buttonRect = tester.getRect(map);
    expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left));
    expect(labelRect.right, lessThanOrEqualTo(buttonRect.right));
    expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
    final row = find.ancestor(of: map, matching: find.byType(Row)).first;
    expect(buttonRect.right, closeTo(tester.getRect(row).right, 1));
    expectNoLayoutException(tester, scenario);
  });

  testWidgets(
      'Owner list keeps items on failed refresh and shows local deletion presentation',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final stream = StreamController<List<OwnerModel>>();
    addTearDown(stream.close);
    final service = _OfflineOwnerService(list: stream.stream);
    final vm = _DeletionPresentation(service);
    await pumpResponsive(tester, scenario,
        settle: false, home: OwnersListView(createViewModel: () => vm));
    stream.add([_record(), _record().copyWith(id: 'other')]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    expect(find.byType(EntityDeleteProgress), findsWidgets);
    expect(
        tester
            .widgetList<EntityDeleteProgress>(find.byType(EntityDeleteProgress))
            .where((w) => w.deleting)
            .length,
        1);
    stream.addError(StateError('local failed refresh'));
    await tester.pump();
    expect(vm.owners.length, 2);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    expect(vm.owners.length, 2);
    expect(service.subscriptions, 1);
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Owner Plan loading failure and absent states keep the separate card absent',
      (tester) async {
    const scenario =
        ResponsiveCase(Size(280, 600), locale: Locale('ar'), textScale: 2);
    final pending = _PendingPlan();
    await pumpResponsive(tester, scenario,
        home: withR2ScreenProviders(OwnersDetailsView(
            owner: _record(),
            ownerService: _OfflineOwnerService(),
            planTransport: pending,
            relatedItemsService: _OfflineRelated())));
    expect(find.byType(PlanAttachmentDetailsCard), findsNothing);
    pending.gate.completeError(StateError('local plan read failure'));
    await tester.pump();
    expect(find.byType(PlanAttachmentDetailsCard), findsNothing);
    expect(pending.fetched, [(PlanParent.owner, _recordId)]);
    expectNoLayoutException(tester, scenario);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpResponsive(tester, scenario,
        home: withR2ScreenProviders(OwnersDetailsView(
            owner: _record(),
            ownerService: _OfflineOwnerService(),
            planTransport: FakePlanTransport(),
            relatedItemsService: _OfflineRelated())));
    expect(find.byType(PlanAttachmentDetailsCard), findsNothing);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Owner detail resize does not recreate related data streams',
      (tester) async {
    const scenario = ResponsiveCase(Size(393, 852));
    final related = _OfflineRelated();
    await pumpResponsive(tester, scenario,
        home: withR2ScreenProviders(OwnersDetailsView(
            owner: _record(),
            ownerService: _OfflineOwnerService(),
            planTransport: FakePlanTransport(),
            relatedItemsService: related)));
    final offersBefore = related.offersReads;
    final requestsBefore = related.requestsReads;
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    tester.view.physicalSize = const Size(786, 1704);
    await tester.pump();
    expect(related.offersReads, offersBefore);
    expect(related.requestsReads, requestsBefore);
    expect(related.offersReads, 1);
    expectNoLayoutException(tester, scenario);
  });
}
