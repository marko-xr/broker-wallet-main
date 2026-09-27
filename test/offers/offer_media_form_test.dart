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
import 'package:broker_wallet/src/viewmodels/AddScreens/add_offers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The Add/Edit Offer form's media (Supabase mode): what it shows, what it
/// counts toward the ten-item limit, and what Save sends — by identity,
/// never by URL, and never reporting an item as uploaded.
///
/// Local only: the Offer service is a fake. Nothing here is device or
/// hosted verification.

const _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _offerId = 'o1111111-1111-4111-8111-111111111111';

class _Uploads extends ChangeNotifier {
  void changed() => notifyListeners();
}

class _FakeOfferService extends OfferService {
  _FakeOfferService();

  final uploads = _Uploads();
  final completions = StreamController<OfferMediaUploadCompleted>.broadcast();
  List<OfferMediaRef> pending = [];
  List<OfferMediaRef> held = [];
  Future<OfferMediaResolution?> Function()? resolve;
  final saves = <({
    String offerId,
    List<String> newMedia,
    List<String> removed,
    List<String> cancelled,
  })>[];
  OfferMediaSaveResult Function(int call, String offerId)? onSave;
  final retried = <String>[];
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
  List<OfferMediaRef> pendingOfferMedia(String offerId) => pending;

  @override
  List<OfferMediaRef> cachedOfferMedia(String offerId) => held;

  @override
  Future<OfferMediaResolution?> resolveOfferMedia({
    required String offerId,
    required String ownerId,
  }) async =>
      resolve == null ? null : await resolve!();

  @override
  String? get currentOwnerId => _owner;

  @override
  Future<void> retryOfferMediaUpload(String mediaObjectId) async =>
      retried.add(mediaObjectId);

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
    saves.add((
      offerId: offerId,
      newMedia: [for (final d in newMedia) d.mediaObjectId],
      removed: List.of(removedMediaIds),
      cancelled: List.of(cancelledUploadIds),
    ));
    return onSave?.call(saves.length, offerId) ??
        OfferMediaSaveResult(offerId: offerId, queuedCount: newMedia.length);
  }
}

OfferModel _offer({
  String? id = _offerId,
  List<String> ids = const [],
}) =>
    OfferModel(
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
      mediaUrls: [for (final id in ids) 'https://r2.example.test/$id.jpg?sig'],
      mediaObjectIds: ids,
    );

OfferMediaRef _server(String id) => OfferMediaRef(
      mediaObjectId: id,
      cacheKey: offerMediaCacheKey(ownerId: _owner, mediaObjectId: id),
      signedUrl: 'https://r2.example.test/$id.jpg?fresh',
    );

OfferMediaRef _queued(String id,
        {OfferMediaUploadPhase phase = OfferMediaUploadPhase.uploading}) =>
    OfferMediaRef(
      mediaObjectId: id,
      cacheKey: offerMediaCacheKey(ownerId: _owner, mediaObjectId: id),
      localFilePath: '/docs/offer_media/$id.jpg',
      uploadPhase: phase,
      progress: phase == OfferMediaUploadPhase.uploading ? 0.5 : null,
    );

OfferMediaDraft _draft(String id) => OfferMediaDraft(
      mediaObjectId: id,
      path: '/tmp/$id.jpg',
      kind: OfferMediaKind.image,
      contentType: 'image/jpeg',
      byteLength: 10,
      displayName: '$id.jpg',
    );

List<String> _ids(AddOffersViewModel vm) =>
    [for (final ref in vm.offerMediaItems) ref.mediaObjectId];

AddOffersViewModel _edit(_FakeOfferService service, List<String> ids) =>
    AddOffersViewModel(
      mode: AddOffersMode.edit,
      offerId: _offerId,
      offerData: _offer(ids: ids),
      offerService: service,
      usesMediaQueue: true,
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

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

  setUp(toasts.clear);

  group('what the form shows', () {
    test(
        'server items by identity, then queued uploads, then new picks — '
        'each once, the server copy winning', () async {
      final service = _FakeOfferService()
        ..pending = [_queued('p1'), _queued('e2')];
      final vm = _edit(service, ['e1', 'e2']);
      addTearDown(vm.dispose);
      vm.addOfferMediaDraftsForTest([_draft('d1')]);

      expect(_ids(vm), ['e1', 'e2', 'p1', 'd1']);
      expect(vm.offerMediaItems[1].uploadPhase, isNull);
      expect(
          vm.offerMediaItems[2].uploadPhase, OfferMediaUploadPhase.uploading);
      expect(vm.uploadedFileUrls, isEmpty,
          reason: 'a signed URL is never what the form edits');
    });

    test('the Worker list replaces what the Offer model gave', () async {
      final service = _FakeOfferService()
        ..resolve = () async => OfferMediaResolution(
              offerId: _offerId,
              ownerId: _owner,
              items: [_server('e1'), _server('e3')],
            );
      final vm = _edit(service, ['e1', 'e2']);
      addTearDown(vm.dispose);
      await _flush();

      expect(_ids(vm), ['e1', 'e3']);
    });

    test('an answer that predates a finished upload never hides it', () async {
      final first = Completer<OfferMediaResolution?>();
      var calls = 0;
      final service = _FakeOfferService();
      service.resolve = () {
        calls += 1;
        if (calls == 1) return first.future;
        return Future.value(OfferMediaResolution(
          offerId: _offerId,
          ownerId: _owner,
          items: [_server('e1'), _server('p1')],
        ));
      };
      service.pending = [_queued('p1')];
      final vm = _edit(service, ['e1']);
      addTearDown(vm.dispose);

      service.pending = [];
      service.completions.add(const OfferMediaUploadCompleted(
          ownerId: _owner, offerId: _offerId, mediaObjectId: 'p1'));
      await _flush();
      await _flush();
      expect(_ids(vm), ['e1', 'p1']);
      expect(vm.offerMediaItems.last.uploadPhase, isNull);

      first.complete(OfferMediaResolution(
          offerId: _offerId, ownerId: _owner, items: [_server('e1')]));
      await _flush();

      expect(_ids(vm), ['e1', 'p1']);
    });

    test('a finished video is shown as a video at once', () async {
      final service = _FakeOfferService()
        ..pending = [
          _queued('v1'),
        ];
      final vm = _edit(service, const []);
      addTearDown(vm.dispose);

      service.pending = [];
      service.completions.add(const OfferMediaUploadCompleted(
        ownerId: _owner,
        offerId: _offerId,
        mediaObjectId: 'v1',
        isVideo: true,
        durationMs: 5000,
      ));
      await _flush();

      final ref = vm.offerMediaItems.single;
      expect(ref.isVideo, isTrue);
      expect(ref.durationMs, 5000);
      expect(ref.uploadPhase, isNull);
    });

    test('"+N more" opens every item, so all ten can be reached and removed',
        () {
      final service = _FakeOfferService();
      final vm = _edit(service, [for (var i = 0; i < 10; i++) 'e$i']);
      addTearDown(vm.dispose);

      expect(vm.mediaDisplayCount, 3);
      vm.showAllMedia();
      expect(vm.mediaDisplayCount, 10);
      vm.removeOfferMediaAt(9);
      expect(_ids(vm), isNot(contains('e9')));
    });
  });

  group('the ten-item limit', () {
    test(
        'counts server items, queued uploads and new picks, but not a '
        'refused upload', () {
      final service = _FakeOfferService()
        ..pending = [
          _queued('p1'),
          _queued('p2', phase: OfferMediaUploadPhase.retryableFailure),
          _queued('p3', phase: OfferMediaUploadPhase.permanentFailure),
        ];
      final vm = _edit(service, ['e1', 'e2', 'e3', 'e4', 'e5']);
      addTearDown(vm.dispose);
      vm.addOfferMediaDraftsForTest([_draft('d1'), _draft('d2')]);

      expect(vm.currentMediaCount, 9);
      expect(vm.remainingMediaSlots, 1);
    });

    test('removing frees a place at once', () {
      final service = _FakeOfferService();
      final vm = _edit(service, [for (var i = 0; i < 10; i++) 'e$i']);
      addTearDown(vm.dispose);
      expect(vm.remainingMediaSlots, 0);

      vm.removeOfferMediaAt(0);

      expect(vm.remainingMediaSlots, 1);
    });
  });

  group('Remove and Retry in the form', () {
    test(
        'a new pick goes at once; a server item and an upload are hidden '
        'and go on Save', () {
      final service = _FakeOfferService()..pending = [_queued('p1')];
      final vm = _edit(service, ['e1']);
      addTearDown(vm.dispose);
      vm.addOfferMediaDraftsForTest([_draft('d1')]);

      vm.removeOfferMediaAt(2); // d1
      vm.removeOfferMediaAt(1); // p1
      vm.removeOfferMediaAt(0); // e1

      expect(_ids(vm), isEmpty);
      expect(service.saves, isEmpty, reason: 'nothing is sent before Save');
    });

    test('Retry applies only to an upload that failed for a passing reason',
        () {
      final service = _FakeOfferService()
        ..pending = [
          _queued('busy'),
          _queued('flaky', phase: OfferMediaUploadPhase.retryableFailure),
          _queued('refused', phase: OfferMediaUploadPhase.permanentFailure),
        ];
      final vm = _edit(service, const []);
      addTearDown(vm.dispose);

      for (var i = 0; i < 3; i++) {
        vm.retryOfferMediaAt(i);
      }

      expect(service.retried, ['flaky']);
    });

    test('the form redraws as uploads progress, and stops when closed',
        () async {
      final service = _FakeOfferService();
      final vm = _edit(service, const []);
      var redraws = 0;
      vm.addListener(() => redraws += 1);

      service.uploads.changed();
      expect(redraws, 1);

      vm.dispose();
      service.uploads.changed();
      expect(service.completions.hasListener, isFalse);
    });
  });

  test('the Firebase backend keeps its URL-based media form untouched', () {
    final service = _FakeOfferService();
    final vm = AddOffersViewModel(
      mode: AddOffersMode.edit,
      offerId: _offerId,
      offerData: _offer(ids: ['e1']),
      offerService: service,
      usesMediaQueue: false,
    );
    addTearDown(vm.dispose);

    expect(vm.usesOfferMediaItems, isFalse);
    expect(vm.offerMediaItems, isEmpty);
    expect(vm.uploadedFileUrls, hasLength(1));
    expect(service.completions.hasListener, isFalse);
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

    testWidgets(
        'edit sends exactly the removals, withdrawals and new picks, then '
        'says the new media is uploading — not uploaded', (tester) async {
      final service = _FakeOfferService()
        ..pending = [_queued('p1')]
        ..fetched = _offer(ids: ['e2']);
      final vm = _edit(service, ['e1', 'e2']);
      addTearDown(vm.dispose);
      vm.addOfferMediaDraftsForTest([_draft('d1'), _draft('d2')]);
      vm.removeOfferMediaAt(0); // e1
      vm.removeOfferMediaAt(1); // p1 (now at index 1)
      vm.removeOfferMediaAt(2); // d2 (now at index 2)
      final popped = await pumpFlow(tester, vm);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      final save = service.saves.single;
      expect(save.offerId, _offerId);
      expect(save.removed, ['e1']);
      expect(save.cancelled, ['p1']);
      expect(save.newMedia, ['d1']);
      expect(toasts.single, en['offerUpdatedMediaUploading']);
      expect(popped.single, same(service.fetched));
    });

    testWidgets(
        'add: an item that could not be queued keeps the form open with it, '
        'and Save again updates the same Offer', (tester) async {
      final service = _FakeOfferService()
        ..onSave = (call, offerId) => call == 1
            ? OfferMediaSaveResult(
                offerId: offerId,
                queuedCount: 1,
                failedToQueueIds: const ['d2'],
              )
            : OfferMediaSaveResult(offerId: offerId, queuedCount: 1);
      final vm = AddOffersViewModel(
        offerService: service,
        usesMediaQueue: true,
      );
      addTearDown(vm.dispose);
      vm.selectCity('Dubai');
      vm.addOfferMediaDraftsForTest([_draft('d1'), _draft('d2')]);
      await pumpFlow(tester, vm);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(service.saves.single.newMedia, ['d1', 'd2']);
      expect(toasts, [en['offerMediaPrepareFailed']]);
      expect(find.text('SAVE'), findsOneWidget, reason: 'the form stays open');
      expect(_ids(vm), ['d2']);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(service.saves, hasLength(2));
      expect(service.saves.last.offerId, _offerId);
      expect(service.saves.last.newMedia, ['d2']);
      expect(service.generatedIds, 1, reason: 'one Offer, created once');
      expect(toasts.last, en['offerSavedMediaUploading']);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'a removal that failed stays marked, the form stays open, and Save '
        'retries it', (tester) async {
      final service = _FakeOfferService()
        ..onSave = (call, offerId) => call == 1
            ? OfferMediaSaveResult(
                offerId: offerId,
                queuedCount: 0,
                failedRemovalIds: const ['e1'],
              )
            : OfferMediaSaveResult(offerId: offerId, queuedCount: 0);
      final vm = _edit(service, ['e1', 'e2']);
      addTearDown(vm.dispose);
      vm.removeOfferMediaAt(0);
      await pumpFlow(tester, vm);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(toasts, [en['offerMediaRemoveFailed']]);
      expect(_ids(vm), ['e2'], reason: 'still marked for removal');

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(service.saves.last.removed, ['e1']);
    });

    testWidgets('an Offer without new media says nothing about uploading',
        (tester) async {
      final service = _FakeOfferService();
      final vm = AddOffersViewModel(
        offerService: service,
        usesMediaQueue: true,
      );
      addTearDown(vm.dispose);
      vm.selectCity('Dubai');
      await pumpFlow(tester, vm);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(toasts.single, isNot(en['offerSavedMediaUploading']));
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
