import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/media_pick_recovery.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/offer_media_selection.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_offers_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/offer_media_source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_android/image_picker_android.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Task B — the Offer media attachment sheet and its pickers: one native
/// Gallery selection of photos and videos together, capped at the places
/// left; the camera for a photo or a video; no app-made permission dialog
/// and no media-library permission request for the Gallery; every pick
/// screened exactly as before. Local widget/unit tests only.

const _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _offerRecord = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _ownerRecord = 'a0a0a0a0-a0a0-4a0a-8a0a-a0a0a0a0a0a0';
const _permissionsChannel = 'flutter.baseflow.com/permissions/methods';

List<int> _isoHeader(String major, [List<String> compatible = const []]) {
  final brands = '$major\u0000\u0000\u0000\u0000${compatible.join()}';
  final bytes = List<int>.filled(64, 0);
  bytes[3] = 8 + brands.length;
  bytes.setRange(4, 8, 'ftyp'.codeUnits);
  bytes.setRange(8, 8 + brands.length, brands.codeUnits);
  return bytes;
}

final _mp4 = _isoHeader('isom', ['isom', 'mp42']);
final _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(60, 0)];

late Directory _dir;
var _fileSeq = 0;

File _file(String name, List<int> bytes) {
  final file = File('${_dir.path}${Platform.pathSeparator}${_fileSeq++}_$name');
  file.writeAsBytesSync(bytes);
  return file;
}

/// image_picker's platform side: records each request and answers with the
/// files the test prepared.
class _FakePicker extends ImagePickerPlatform {
  final List<MediaOptions> mediaRequests = [];
  final List<ImageSource> imageRequests = [];
  final List<Duration?> videoRequests = [];
  List<XFile> gallery = [];
  XFile? camera;
  PlatformException? cameraError;
  LostDataResponse lost = LostDataResponse.empty();

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    mediaRequests.add(options);
    // The Android Photo Picker enforces the limit; this fake returns what it
    // was given, which proves the form re-checks anyway.
    return gallery;
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    imageRequests.add(source);
    if (cameraError != null) throw cameraError!;
    return camera;
  }

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    videoRequests.add(maxDuration);
    if (cameraError != null) throw cameraError!;
    return camera;
  }

  @override
  Future<LostDataResponse> getLostData() async => lost;
}

/// image_picker's Android implementation, to observe the Photo Picker
/// switch during a Gallery selection.
class _FakeAndroidPicker extends ImagePickerAndroid {
  bool? photoPickerDuringSelection;

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    photoPickerDuringSelection = useAndroidPhotoPicker;
    return const [];
  }
}

class _Uploads extends ChangeNotifier {}

class _FakeOfferService extends OfferService {
  final uploads = _Uploads();
  final completions = StreamController<OfferMediaUploadCompleted>.broadcast();
  List<OfferMediaRef> pending = [];

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
  List<OfferMediaRef> cachedOfferMedia(String offerId) => const [];

  @override
  String? get currentOwnerId => _owner;
}

AddOffersViewModel _vm({
  _FakeOfferService? service,
  OfferMediaSource? source,
  bool sheet = false,
}) =>
    AddOffersViewModel(
      offerService: service ?? _FakeOfferService(),
      usesMediaQueue: true,
      mediaPicker:
          OfferMediaPicker(isAndroid: true, recovery: MediaPickRecovery()),
      chooseMediaSource: sheet ? null : (context, remaining) async => source,
    );

Widget _app(Widget child,
        {Locale locale = const Locale('en'), ThemeData? theme}) =>
    MaterialApp(
      locale: locale,
      theme: theme,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePicker picker;
  late ImagePickerPlatform originalPicker;
  final permissionCalls = <String>[];
  final toasts = <String>[];
  late Map<String, dynamic> en;
  late Map<String, dynamic> ar;

  setUpAll(() async {
    _dir = await Directory.systemTemp.createTemp('offer_picker_test');
    originalPicker = ImagePickerPlatform.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(_permissionsChannel),
      (call) async {
        permissionCalls.add(call.method);
        return 1;
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
    await AppLocalizations.preloadAllLanguages();
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  setUp(() {
    picker = _FakePicker();
    ImagePickerPlatform.instance = picker;
    SharedPreferences.setMockInitialValues({});
    permissionCalls.clear();
    toasts.clear();
    VideoDurationProbe.read = (_) async => const Duration(seconds: 42);
    VideoPosterGenerator.generate = (_) async => null;
    HeifToJpegConverter.convert = (_) async => null;
  });

  tearDownAll(() async {
    ImagePickerPlatform.instance = originalPicker;
    try {
      await _dir.delete(recursive: true);
    } catch (_) {}
  });

  group('OfferMediaPicker', () {
    test(
        'Gallery is one selection of photos and videos together, capped at '
        'the places left, with no permission request', () async {
      picker.gallery = [
        XFile(_file('a.jpg', _jpeg).path),
        XFile(_file('b.mp4', _mp4).path),
      ];

      final files =
          await OfferMediaPicker().pickFromGallery(limit: 7, origin: null);

      expect(files, hasLength(2));
      expect(picker.mediaRequests, hasLength(1));
      expect(picker.mediaRequests.single.allowMultiple, isTrue);
      expect(picker.mediaRequests.single.limit, 7);
      expect(permissionCalls, isEmpty,
          reason: 'the system picker needs no media permission');
    });

    test(
        'Gallery switches Android to the system Photo Picker for that call '
        'only', () async {
      final android = _FakeAndroidPicker();
      ImagePickerPlatform.instance = android;

      await OfferMediaPicker().pickFromGallery(limit: 5, origin: null);

      expect(android.photoPickerDuringSelection, isTrue);
      expect(android.useAndroidPhotoPicker, isFalse,
          reason: 'other pickers in the app keep their behaviour');
    });

    test('a full Offer opens no picker', () async {
      expect(await OfferMediaPicker().pickFromGallery(limit: 0, origin: null),
          isEmpty);
      expect(picker.mediaRequests, isEmpty);
    });

    test('Camera takes a photo or records a video of at most three minutes',
        () async {
      picker.camera = XFile(_file('shot.jpg', _jpeg).path);
      final media = OfferMediaPicker();

      expect(await media.capturePhoto(origin: null), isNotNull);
      expect(picker.imageRequests, [ImageSource.camera]);

      picker.camera = XFile(_file('clip.mp4', _mp4).path);
      expect(
          await media.recordVideo(
              maxDuration: const Duration(minutes: 3), origin: null),
          isNotNull);
      expect(picker.videoRequests, [const Duration(minutes: 3)]);
      expect(permissionCalls, isEmpty,
          reason: 'the plugin asks for the camera itself, with the system '
              'dialog; the app shows none of its own');
    });

    test('a refused camera is reported, and refused for good when it is',
        () async {
      picker.cameraError = PlatformException(code: 'camera_access_denied');

      await expectLater(
        OfferMediaPicker(cameraPermanentlyDenied: () async => false)
            .capturePhoto(origin: null),
        throwsA(isA<OfferMediaPickerException>().having(
            (e) => e.failure, 'failure', OfferMediaPickerFailure.cameraDenied)),
      );
      await expectLater(
        OfferMediaPicker(cameraPermanentlyDenied: () async => true)
            .recordVideo(maxDuration: const Duration(minutes: 3), origin: null),
        throwsA(isA<OfferMediaPickerException>().having((e) => e.failure,
            'failure', OfferMediaPickerFailure.cameraPermanentlyDenied)),
      );
    });

    test(
        'media Android handed back after stopping the app is recovered for '
        'the form it was picked on, on Android only', () async {
      final origin = MediaPickOrigin.of(
        accountId: _owner,
        parent: MediaParent.offer,
        recordId: _offerRecord,
        formSessionId: 'form',
      )!;
      // The previous run opened the picker for [origin], then Android
      // stopped the app.
      SharedPreferences.setMockInitialValues({
        MediaPickRecovery.pendingOriginKey: jsonEncode(origin.toJson()),
      });
      picker.lost = LostDataResponse(
        files: [XFile(_file('lost.mp4', _mp4).path)],
      );
      final recovery = MediaPickRecovery();

      expect(
          await OfferMediaPicker(isAndroid: false, recovery: recovery)
              .recoverLostSelection(origin: origin),
          isEmpty);
      expect(
          await OfferMediaPicker(isAndroid: true, recovery: recovery)
              .recoverLostSelection(origin: origin),
          hasLength(1));
    });
  });

  group('the Offer form', () {
    test('five videos chosen in one selection all enter the form', () async {
      final vm = _vm();
      addTearDown(vm.dispose);

      final outcome = await vm.addPickedOfferMedia([
        for (var i = 0; i < 5; i++) _file('video$i.mp4', _mp4),
      ]);

      expect(outcome.added, 5);
      expect(outcome.rejections, isEmpty);
      final items = vm.offerMediaItems;
      expect(items, hasLength(5));
      expect(items.every((ref) => ref.isVideo), isTrue);
    });

    test('photos and videos chosen together keep their kinds', () async {
      final vm = _vm();
      addTearDown(vm.dispose);

      await vm.addPickedOfferMedia([
        _file('p1.jpg', _jpeg),
        _file('v1.mp4', _mp4),
        _file('p2.jpg', _jpeg),
      ]);

      expect([for (final ref in vm.offerMediaItems) ref.isVideo],
          [false, true, false]);
    });

    test('the places left cap what enters, whatever the picker returned',
        () async {
      final vm = _vm();
      addTearDown(vm.dispose);
      await vm.addPickedOfferMedia([
        for (var i = 0; i < 7; i++) _file('held$i.jpg', _jpeg),
      ]);
      expect(vm.remainingMediaSlots, 3);

      final outcome = await vm.addPickedOfferMedia([
        for (var i = 0; i < 5; i++) _file('extra$i.mp4', _mp4),
      ]);

      expect(outcome.added, 3);
      expect(outcome.trimmedByLimit, isTrue);
      expect(vm.remainingMediaSlots, 0);
    });

    test('a file picked again is skipped; an invalid one is refused', () async {
      final vm = _vm();
      addTearDown(vm.dispose);
      final clip = _file('same.mp4', _mp4);

      await vm.addPickedOfferMedia([clip]);
      final again = await vm.addPickedOfferMedia([
        clip,
        _file('notes.txt', utf8.encode('plain text, not media')),
      ]);

      expect(again.added, 0);
      expect(again.duplicates, 1);
      expect(again.rejections, [OfferMediaRejection.unsupportedType]);
      expect(vm.offerMediaItems, hasLength(1));
    });

    test('picked media goes to the upload queue on Save with its ids',
        () async {
      final vm = _vm();
      addTearDown(vm.dispose);

      await vm.addPickedOfferMedia([
        _file('q1.jpg', _jpeg),
        _file('q2.mp4', _mp4),
      ]);

      final ids = [for (final ref in vm.offerMediaItems) ref.mediaObjectId];
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2),
          reason: 'each file gets its own lasting id, handed to the queue');
    });

    test(
        'a new Offer form never adopts what Android handed back for another '
        'form; it stays kept for that form', () async {
      final ownerForm = MediaPickOrigin.of(
        accountId: _owner,
        parent: MediaParent.owner,
        recordId: _ownerRecord,
        formSessionId: 'owner-form',
      )!;
      SharedPreferences.setMockInitialValues({
        MediaPickRecovery.pendingOriginKey: jsonEncode(ownerForm.toJson()),
      });
      picker.lost = LostDataResponse(
        files: [XFile(_file('owner-photo.jpg', _jpeg).path)],
      );
      final recovery = MediaPickRecovery();

      final vm = AddOffersViewModel(
        offerService: _FakeOfferService(),
        usesMediaQueue: true,
        mediaPicker: OfferMediaPicker(isAndroid: true, recovery: recovery),
        chooseMediaSource: (context, remaining) async => null,
      );
      addTearDown(vm.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(vm.offerMediaItems, isEmpty);
      expect(await recovery.take(ownerForm), hasLength(1),
          reason: 'still there for the Owner it was picked on');
    });
  });

  group('selectMedia', () {
    Future<BuildContext> host(WidgetTester tester,
        {Locale locale = const Locale('en')}) async {
      late BuildContext captured;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
        locale: locale,
      ));
      await tester.pump();
      return captured;
    }

    testWidgets('dismissing the sheet changes nothing and opens no picker',
        (tester) async {
      final vm = _vm(source: null);
      addTearDown(vm.dispose);
      final context = await host(tester);

      await tester.runAsync(() => vm.selectMedia(context));

      expect(picker.mediaRequests, isEmpty);
      expect(vm.offerMediaItems, isEmpty);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final vm = _vm(source: OfferMediaSource.gallery);
      addTearDown(vm.dispose);
      final context = await host(tester);

      await tester.runAsync(() => vm.selectMedia(context));

      expect(picker.mediaRequests.single.limit, 10);
      expect(vm.offerMediaItems, isEmpty);
      expect(toasts, isEmpty);
    });

    testWidgets(
        'Gallery: five videos in one selection, one short confirmation, no '
        'permission dialog', (tester) async {
      picker.gallery = [
        for (var i = 0; i < 5; i++) XFile(_file('g$i.mp4', _mp4).path),
      ];
      final vm = _vm(source: OfferMediaSource.gallery);
      addTearDown(vm.dispose);
      final context = await host(tester);

      await tester.runAsync(() => vm.selectMedia(context));
      await tester.pump();

      expect(vm.offerMediaItems, hasLength(5));
      expect(picker.mediaRequests, hasLength(1));
      expect(permissionCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'no app-made permission explanation');
      expect(toasts,
          [(en['offerMediaAdded'] as String).replaceAll('{count}', '5')]);
    });

    testWidgets('Camera: a photo, then a video, each added', (tester) async {
      final vm = _vm(source: OfferMediaSource.cameraPhoto);
      addTearDown(vm.dispose);
      final context = await host(tester);
      picker.camera = XFile(_file('cam.jpg', _jpeg).path);

      await tester.runAsync(() => vm.selectMedia(context));
      expect(vm.offerMediaItems.single.isVideo, isFalse);
      expect(picker.imageRequests, [ImageSource.camera]);

      final vmVideo = _vm(source: OfferMediaSource.cameraVideo);
      addTearDown(vmVideo.dispose);
      picker.camera = XFile(_file('cam.mp4', _mp4).path);
      await tester.runAsync(() => vmVideo.selectMedia(context));
      expect(vmVideo.offerMediaItems.single.isVideo, isTrue);
      expect(picker.videoRequests, [OfferMediaPolicy.maxVideoDuration]);
      expect(picker.mediaRequests, isEmpty, reason: 'no gallery involved');
      expect(permissionCalls, isEmpty);
    });

    testWidgets('leaving the system camera without a shot changes nothing',
        (tester) async {
      final vm = _vm(source: OfferMediaSource.cameraVideo);
      addTearDown(vm.dispose);
      final context = await host(tester);
      picker.camera = null;

      await tester.runAsync(() => vm.selectMedia(context));

      expect(picker.videoRequests, hasLength(1));
      expect(vm.offerMediaItems, isEmpty);
      expect(toasts, isEmpty);
    });

    testWidgets(
        'what the camera returns is screened like a Gallery pick: an invalid '
        'file is refused with its message', (tester) async {
      final vm = _vm(source: OfferMediaSource.cameraPhoto);
      addTearDown(vm.dispose);
      final context = await host(tester);
      picker.camera =
          XFile(_file('cam.jpg', utf8.encode('plain text, not a photo')).path);

      await tester.runAsync(() => vm.selectMedia(context));

      expect(vm.offerMediaItems, isEmpty);
      expect(toasts, [en['offerMediaUnsupportedType']]);
    });

    testWidgets(
        'a camera refused for good explains itself and offers Settings; '
        'nothing is added', (tester) async {
      picker.cameraError = PlatformException(code: 'camera_access_denied');
      final vm = AddOffersViewModel(
        offerService: _FakeOfferService(),
        usesMediaQueue: true,
        mediaPicker:
            OfferMediaPicker(cameraPermanentlyDenied: () async => true),
        chooseMediaSource: (context, remaining) async =>
            OfferMediaSource.cameraPhoto,
      );
      addTearDown(vm.dispose);
      final context = await host(tester);

      await tester.runAsync(() => vm.selectMedia(context));
      await tester.pump();

      expect(find.text(en['cameraPermissionPermanentlyDenied'] as String),
          findsOneWidget);
      expect(find.text(en['openSettings'] as String), findsOneWidget);
      expect(vm.offerMediaItems, isEmpty);
    });

    testWidgets('a full Offer says so and opens nothing', (tester) async {
      final vm = _vm(source: OfferMediaSource.gallery);
      addTearDown(vm.dispose);
      // Real file I/O: outside the widget test's fake clock.
      await tester.runAsync(() => vm.addPickedOfferMedia([
            for (var i = 0; i < 10; i++) _file('full$i.jpg', _jpeg),
          ]));
      final context = await host(tester);

      await tester.runAsync(() => vm.selectMedia(context));

      expect(picker.mediaRequests, isEmpty);
      expect(toasts, [en['offerMediaLimitReached']]);
    });
  });

  group('the attachment sheet', () {
    OfferMediaSource? lastChoice;

    Future<void> open(WidgetTester tester,
        {Locale locale = const Locale('en'),
        ThemeData? theme,
        Size size = const Size(390, 844)}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      var closed = false;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              lastChoice =
                  await showOfferMediaSourceSheet(context, remaining: 4);
              closed = true;
            },
            child: const Text('open'),
          );
        }),
        locale: locale,
        theme: theme,
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(closed, isFalse);
    }

    testWidgets('three sections; Gallery closes it with one choice',
        (tester) async {
      await open(tester);

      expect(find.text(en['offerMediaSheetTitle'] as String), findsOneWidget);
      expect(
          find.text((en['offerMediaSheetRemaining'] as String)
              .replaceAll('{count}', '4')),
          findsOneWidget);
      expect(find.byKey(const Key('offerMediaSource.camera')), findsOneWidget);
      expect(
          find.text(en['offerMediaCameraTakePhoto'] as String), findsOneWidget);
      expect(find.text(en['offerMediaCameraRecordVideo'] as String),
          findsOneWidget);
      expect(find.byKey(const Key('offerMediaSource.gallery')), findsOneWidget);
      expect(
          find.byKey(const Key('offerMediaSource.documents')), findsOneWidget);
      // No list of separate photo/video camera and gallery rows any more.
      expect(find.byType(ListTile), findsNothing);

      await tester.tap(find.byKey(const Key('offerMediaSource.gallery')));
      await tester.pumpAndSettle();
      expect(find.byType(OfferMediaSourceSheet), findsNothing);
    });

    testWidgets(
        'Take photo and Record video are direct: each closes the sheet with '
        'its choice, with no second Photo/Video step', (tester) async {
      await open(tester);
      expect(
        tester.getSemantics(
            find.byKey(const Key('offerMediaSource.cameraPhoto'))),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: en['offerMediaCameraTakePhoto'] as String,
        ),
      );

      await tester.tap(find.byKey(const Key('offerMediaSource.cameraPhoto')));
      await tester.pumpAndSettle();
      expect(find.byType(OfferMediaSourceSheet), findsNothing);
      expect(lastChoice, OfferMediaSource.cameraPhoto);

      await open(tester);
      await tester.tap(find.byKey(const Key('offerMediaSource.cameraVideo')));
      await tester.pumpAndSettle();
      expect(find.byType(OfferMediaSourceSheet), findsNothing);
      expect(lastChoice, OfferMediaSource.cameraVideo);
    });

    testWidgets('Documents is shown as unavailable for Offers and does nothing',
        (tester) async {
      await open(tester);

      expect(find.text(en['offerMediaSourceDocumentsUnavailable'] as String),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('offerMediaSource.documents')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(OfferMediaSourceSheet), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const Key('offerMediaSource.documents'))),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
    });

    testWidgets('Arabic reads right to left; dark theme and a narrow phone fit',
        (tester) async {
      await open(tester,
          locale: const Locale('ar'),
          theme: ThemeData.dark(),
          size: const Size(320, 640));

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(
          find.text(ar['offerMediaSourceGallery'] as String), findsOneWidget);
      expect(find.text(ar['offerMediaCameraRecordVideo'] as String),
          findsOneWidget);
      final camera =
          tester.getCenter(find.byKey(const Key('offerMediaSource.camera')));
      final gallery =
          tester.getCenter(find.byKey(const Key('offerMediaSource.gallery')));
      expect(camera.dx, greaterThan(gallery.dx),
          reason: 'the first action is on the right in Arabic');
    });
  });
}
