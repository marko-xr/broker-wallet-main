import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/enums/add_offers_mode.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_screening.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_offers_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_plan_transport.dart';
import 'plan_bytes.dart';

/// The Add/Edit Offer form with a land / plot plan (Supabase mode): the Offer is
/// saved first and the plan follows under the Offer's id; a plan that cannot be
/// sent never undoes the saved Offer and is retried under the same upload id;
/// the plan never counts toward the ten-item gallery; and a form without a plan
/// behaves exactly as before.
///
/// Local only: the Offer service and the Media Worker are fakes, and the file
/// work runs outside the test's fake clock (`runAsync`). Nothing here is device
/// or hosted verification.

const _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _offerId = 'o1111111-1111-4111-8111-111111111111';
const _planId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _oldPlanId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

class _Uploads extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// An Offer service that saves nothing anywhere and says what it was asked.
class _FakeOfferService extends OfferService {
  _FakeOfferService(this.events);

  final List<String> events;
  final uploads = _Uploads();
  final completions = StreamController<OfferMediaUploadCompleted>.broadcast();
  final saves = <({
    String offerId,
    List<String> newMedia,
    List<String> removed,
    List<String> cancelled,
  })>[];
  var generatedIds = 0;
  OfferModel? fetched;

  @override
  Listenable get offerMediaUploadChanges => uploads;

  @override
  Stream<OfferMediaUploadCompleted> get offerMediaUploadCompletions =>
      completions.stream;

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
      null;

  @override
  String? get currentOwnerId => _owner;

  @override
  String generateNewOfferId() {
    generatedIds += 1;
    return _offerId;
  }

  @override
  Future<OfferModel?> getOffer(String offerId) async => fetched;

  @override
  Future<OfferMediaSaveResult> saveOfferWithMedia({
    required OfferModel offer,
    required String offerId,
    List<OfferMediaDraft> newMedia = const <OfferMediaDraft>[],
    List<String> removedMediaIds = const <String>[],
    List<String> cancelledUploadIds = const <String>[],
  }) async {
    events.add('offer saved');
    saves.add((
      offerId: offerId,
      newMedia: [for (final d in newMedia) d.mediaObjectId],
      removed: List.of(removedMediaIds),
      cancelled: List.of(cancelledUploadIds),
    ));
    return OfferMediaSaveResult(offerId: offerId, queuedCount: newMedia.length);
  }
}

/// The Media Worker fake, writing each step into the same log as the service.
class _OrderedTransport extends FakePlanTransport {
  _OrderedTransport(this.events);

  final List<String> events;

  @override
  Future<PlanAuthorization> authorize({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) {
    events.add('plan authorize');
    return super.authorize(
      parent: parent,
      parentId: parentId,
      expectedMediaId: expectedMediaId,
      mediaObjectId: mediaObjectId,
      contentType: contentType,
      contentLength: contentLength,
      originalFileName: originalFileName,
    );
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  }) {
    events.add('plan upload');
    return super.uploadBytes(
      presignedUrl: presignedUrl,
      file: file,
      contentType: contentType,
    );
  }

  @override
  Future<PlanConfirmation> confirm({
    required PlanParent parent,
    required String parentId,
    required String mediaObjectId,
    required String? expectedMediaId,
  }) {
    events.add('plan confirm');
    return super.confirm(
      parent: parent,
      parentId: parentId,
      mediaObjectId: mediaObjectId,
      expectedMediaId: expectedMediaId,
    );
  }

  @override
  Future<PlanRemoval> remove({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    String? mediaObjectId,
  }) {
    events.add('plan remove');
    return super.remove(
      parent: parent,
      parentId: parentId,
      expectedMediaId: expectedMediaId,
      mediaObjectId: mediaObjectId,
    );
  }
}

OfferModel _offer({String? id = _offerId}) => OfferModel(
      id: id,
      userId: _owner,
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const ['Marina'],
      location: '',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: '',
      specificPropertyType: '',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      status: PropertyStatus.available,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      mediaUrls: const [],
      mediaObjectIds: const [],
    );

OfferMediaDraft _draft(String id) => OfferMediaDraft(
      mediaObjectId: id,
      path: '/tmp/$id.jpg',
      kind: OfferMediaKind.image,
      contentType: 'image/jpeg',
      byteLength: 10,
      displayName: '$id.jpg',
    );

class _Rig {
  _Rig() {
    service = _FakeOfferService(events);
    transport = _OrderedTransport(events);
  }

  final events = <String>[];
  late final _FakeOfferService service;
  late final _OrderedTransport transport;
  final Directory dir = Directory.systemTemp.createTempSync('plan_offer_form_');

  File get planFile {
    final file = File('${dir.path}${Platform.pathSeparator}Plot 14 plan.pdf');
    if (!file.existsSync()) file.writeAsBytesSync(planPdfBytes(900));
    return file;
  }

  /// The user choosing the plan file, from the Files picker (which names it).
  Future<PlanAttachmentRejection?> choosePlan(AddOffersViewModel vm) =>
      vm.planAttachment!.addPicked(planFile, displayName: 'Plot 14 plan.pdf');

  /// A new Offer form. It has chosen a city, as every Offer saved here has;
  /// [withCity] false leaves it holding nothing at all.
  AddOffersViewModel add({bool withCity = true}) {
    final vm = AddOffersViewModel(
      offerService: service,
      usesMediaQueue: true,
      planTransport: transport,
      planScreener: (file, {displayName}) => screenPlanFile(
        file,
        displayName: displayName,
        newMediaObjectId: () => _planId,
      ),
    );
    if (withCity) vm.selectCity('Dubai');
    return vm;
  }

  /// An existing Offer's form.
  AddOffersViewModel edit() => AddOffersViewModel(
        mode: AddOffersMode.edit,
        offerId: _offerId,
        offerData: _offer(),
        offerService: service,
        usesMediaQueue: true,
        planTransport: transport,
      );

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

PlanAttachmentRef _serverPlan() => const PlanAttachmentRef(
      mediaObjectId: _oldPlanId,
      kind: PlanAttachmentKind.pdf,
      contentType: PlanContentTypes.pdf,
      displayName: 'Old plan.pdf',
      byteLength: 4096,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];
  late Map<String, dynamic> en;

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async {
        if (call.method == 'showToast') {
          toasts.add((call.arguments as Map)['msg'] as String);
        }
        return true;
      },
    );
    await AppLocalizations.preloadAllLanguages();
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  late _Rig rig;
  setUp(() {
    toasts.clear();
    rig = _Rig();
  });
  tearDown(() => rig.dispose());

  group('the form', () {
    test('has a plan section in Supabase mode only', () {
      final supabase = rig.add();
      addTearDown(supabase.dispose);
      expect(supabase.planAttachment, isNotNull);

      final legacy = AddOffersViewModel(
        offerService: rig.service,
        usesMediaQueue: false,
      );
      addTearDown(legacy.dispose);
      expect(legacy.planAttachment, isNull,
          reason: 'the Firebase backend keeps its form as it was');
    });

    test('counts a plan as content, and keeps it out of the gallery', () async {
      // No city either: a chosen city is content by itself, so the plan alone
      // must be what turns an empty form into one with content.
      final vm = rig.add(withCity: false);
      addTearDown(vm.dispose);
      expect(vm.hasAnyContent, isFalse);

      expect(await rig.choosePlan(vm), isNull);
      expect(vm.hasAnyContent, isTrue);
      expect(vm.hasMediaFiles, isFalse,
          reason: 'the gallery\'s own test of its content ignores the plan');
      expect(vm.offerMediaItems, isEmpty,
          reason: 'a plan is not a photo or a video');
      expect(rig.transport.calls, isEmpty,
          reason: 'choosing a file sends nothing');
    });

    test('a record is edited with its plan shown as soon as it is read',
        () async {
      rig.transport.current = _serverPlan();
      final vm = rig.edit();
      addTearDown(vm.dispose);
      await pumpEventQueue();

      expect(vm.planAttachment!.view.display, PlanDisplay.existing);
      expect(vm.planAttachment!.view.displayName, 'Old plan.pdf');
      expect(rig.transport.calls, ['fetch']);
    });
  });

  group('Save', () {
    Future<List<Object?>> pumpFlow(
      WidgetTester tester,
      AddOffersViewModel vm,
    ) async {
      final popped = <Object?>[];
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
          GoRoute(
            path: '/start',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () async => popped.add(await context.push('/form')),
                child: const Text('OPEN'),
              ),
            ),
          ),
          GoRoute(
            path: '/form',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => vm.save(context),
                  child: const Text('SAVE'),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      return popped;
    }

    /// Save, with the file work done on the real clock.
    Future<void> save(WidgetTester tester, AddOffersViewModel vm) async {
      await tester.runAsync(() => vm.save(tester.element(find.text('SAVE'))));
      await tester.pumpAndSettle();
    }

    testWidgets('the Offer is saved first and the plan follows under its id',
        (tester) async {
      final vm = rig.add();
      addTearDown(vm.dispose);
      await tester.runAsync(() => rig.choosePlan(vm));
      await pumpFlow(tester, vm);

      await save(tester, vm);

      expect(rig.events,
          ['offer saved', 'plan authorize', 'plan upload', 'plan confirm']);
      final authorize = rig.transport.authorizeCalls.single;
      expect(authorize.parent, PlanParent.offer);
      expect(authorize.parentId, _offerId);
      expect(authorize.mediaObjectId, _planId);
      expect(authorize.contentType, PlanContentTypes.pdf);
      expect(authorize.originalFileName, 'Plot 14 plan.pdf');
      expect(rig.transport.current?.mediaObjectId, _planId);
      expect(rig.service.saves.single.newMedia, isEmpty,
          reason: 'the plan is not sent as a gallery item');
      expect(toasts, isNot(contains(en['planAttachmentSavedUploadFailed'])));
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'a plan that cannot be sent leaves the saved Offer saved and '
        'is retried under the same upload id', (tester) async {
      rig.transport.authorizeError =
          const PlanAttachmentException(PlanAttachmentFailure.unavailable);
      final vm = rig.add();
      addTearDown(vm.dispose);
      await tester.runAsync(() => rig.choosePlan(vm));
      await pumpFlow(tester, vm);

      await save(tester, vm);

      expect(rig.service.saves, hasLength(1), reason: 'the Offer was saved');
      expect(toasts.last, en['planAttachmentSavedUploadFailed']);
      expect(find.text('SAVE'), findsOneWidget, reason: 'the form stays open');
      expect(find.text('HOME'), findsNothing);
      expect(vm.planAttachment!.view.display, PlanDisplay.failed);
      expect(vm.planAttachment!.view.displayName, 'Plot 14 plan.pdf',
          reason: 'the chosen file is kept for the retry');
      expect(rig.transport.current, isNull);

      rig.transport.authorizeError = null;
      await save(tester, vm);

      expect(rig.service.saves, hasLength(2));
      expect(rig.service.saves.last.offerId, _offerId);
      expect(rig.service.generatedIds, 1, reason: 'one Offer, created once');
      expect(
        rig.transport.authorizeCalls.map((c) => c.mediaObjectId).toSet(),
        {_planId},
        reason: 'one upload id for the whole life of the choice',
      );
      expect(rig.transport.current?.mediaObjectId, _planId);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'ten gallery items and a plan: the plan is never counted, '
        'never sent as media', (tester) async {
      final vm = rig.add();
      addTearDown(vm.dispose);
      vm.addOfferMediaDraftsForTest(
          [for (var i = 1; i <= 10; i++) _draft('d$i')]);
      await tester.runAsync(() => rig.choosePlan(vm));
      expect(vm.offerMediaItems, hasLength(10));
      await pumpFlow(tester, vm);

      await save(tester, vm);

      expect(rig.service.saves.single.newMedia, hasLength(10));
      expect(rig.service.saves.single.newMedia, isNot(contains(_planId)));
      expect(rig.transport.authorizeCalls.single.mediaObjectId, _planId);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'an Offer with no plan never touches the Media Worker\'s plan '
        'routes', (tester) async {
      final vm = rig.add();
      addTearDown(vm.dispose);
      await pumpFlow(tester, vm);

      await save(tester, vm);

      expect(rig.transport.calls, isEmpty);
      expect(rig.events, ['offer saved']);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'editing: removing the plan removes it after the Offer is saved',
        (tester) async {
      rig.transport.current = _serverPlan();
      final vm = rig.edit();
      addTearDown(vm.dispose);
      await tester.pump();
      vm.planAttachment!.removeSelection();
      expect(vm.planAttachment!.view.display, PlanDisplay.removalPending);
      await pumpFlow(tester, vm);

      await save(tester, vm);

      expect(rig.events, ['offer saved', 'plan remove']);
      expect(rig.transport.removeCalls.single.expectedMediaId, _oldPlanId);
      expect(rig.transport.current, isNull);
      expect(find.text('SAVE'), findsNothing, reason: 'the form closed');
    });

    testWidgets('editing: an unchanged plan is left alone', (tester) async {
      rig.transport.current = _serverPlan();
      final vm = rig.edit();
      addTearDown(vm.dispose);
      await tester.pump();
      await pumpFlow(tester, vm);

      await save(tester, vm);

      expect(rig.transport.calls, ['fetch']);
      expect(rig.transport.current?.mediaObjectId, _oldPlanId);
    });
  });
}
