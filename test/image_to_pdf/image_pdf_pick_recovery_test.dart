import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_platform.dart';
import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/media_pick_recovery.dart';

import 'image_pdf_fixtures.dart';
import 'image_pdf_harness.dart';

/// What Android hands back after it stopped the app while a picture picker was
/// open goes back to Images to PDF for the account that opened it, in the order
/// picked, once, and to nothing else. Local tests against fakes of
/// image_picker's platform side and of SharedPreferences; "a restart" is a
/// fresh [MediaPickRecovery] over what the previous run left in storage.

const _alice = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _bob = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

class _FakePicker extends ImagePickerPlatform {
  LostDataResponse lost = LostDataResponse.empty();
  int lostRequests = 0;
  List<XFile> gallery = <XFile>[];
  XFile? photo;
  Object? error;

  /// Observes the pending record while the picker is "open".
  Future<void> Function()? onPick;

  @override
  Future<LostDataResponse> getLostData() async {
    lostRequests += 1;
    final answer = lost;
    lost = LostDataResponse.empty();
    return answer;
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    await onPick?.call();
    if (error != null) throw error!;
    return gallery;
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    await onPick?.call();
    if (error != null) throw error!;
    return photo;
  }
}

late Directory _dir;
var _seq = 0;

File _jpg(String name) =>
    File('${_dir.path}${Platform.pathSeparator}${_seq++}_$name')
      ..writeAsBytesSync(jpeg(marked(40, 30)));

Future<String?> _stored(String key) async =>
    (await SharedPreferences.getInstance()).getString(key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePicker platform;
  late ImagePickerPlatform original;

  setUpAll(() async {
    _dir = await Directory.systemTemp.createTemp('i2p_recovery_test');
    original = ImagePickerPlatform.instance;
  });
  setUp(() {
    platform = _FakePicker();
    ImagePickerPlatform.instance = platform;
    SharedPreferences.setMockInitialValues({});
  });
  tearDownAll(() async {
    ImagePickerPlatform.instance = original;
    try {
      await _dir.delete(recursive: true);
    } catch (_) {}
  });

  ToolPickOrigin tool([String account = _alice]) =>
      ToolPickOrigin.of(accountId: account, tool: 'image_to_pdf')!;

  /// A new run of the app after Android stopped the previous one.
  MediaPickRecovery restart({String? pendingRaw, List<File> files = const []}) {
    SharedPreferences.setMockInitialValues({
      if (pendingRaw != null) MediaPickRecovery.pendingOriginKey: pendingRaw,
    });
    platform.lost = files.isEmpty
        ? LostDataResponse.empty()
        : LostDataResponse(files: [for (final f in files) XFile(f.path)]);
    return MediaPickRecovery();
  }

  String raw(ToolPickOrigin origin) => jsonEncode(origin.toJson());

  group('the shared recovery, for a tool that has no record', () {
    test('a lost pick goes back to its account and tool, in order, once',
        () async {
      final files = [_jpg('1.jpg'), _jpg('2.jpg'), _jpg('3.jpg')];
      final recovery = restart(pendingRaw: raw(tool()), files: files);
      final taken = await recovery.takeTool(tool());
      expect(taken.map((f) => f.path), files.map((f) => f.path).toList());
      expect(await recovery.takeTool(tool()), isEmpty,
          reason: 'handed out once');
      expect(await _stored(MediaPickRecovery.keptResultKey), isNull);
    });

    test('another account neither receives it nor uses it up', () async {
      final photo = _jpg('a.jpg');
      final recovery = restart(pendingRaw: raw(tool()), files: [photo]);
      expect(await recovery.takeTool(tool(_bob)), isEmpty);
      expect(await recovery.takeTool(null), isEmpty,
          reason: 'nobody signed in');
      expect(
          await recovery.takeTool(
              ToolPickOrigin.of(accountId: _alice, tool: 'another_tool')),
          isEmpty,
          reason: 'another tool');
      expect((await recovery.takeTool(tool())).map((f) => f.path), [photo.path],
          reason: 'still kept for the account that opened the picker');
    });

    test('an Offer or Owner form can neither take it nor use it up', () async {
      final photo = _jpg('t.jpg');
      final recovery = restart(pendingRaw: raw(tool()), files: [photo]);
      final offer = MediaPickOrigin.of(
          accountId: _alice,
          parent: MediaParent.offer,
          recordId: 'r1',
          formSessionId: 's')!;
      expect(await recovery.take(offer), isEmpty);
      expect(
          (await recovery.takeTool(tool())).map((f) => f.path), [photo.path]);
    });

    test('an Offer pick is never handed to the tool', () async {
      final photo = _jpg('o.jpg');
      final offer = MediaPickOrigin.of(
          accountId: _alice,
          parent: MediaParent.offer,
          recordId: 'r1',
          formSessionId: 's')!;
      final recovery =
          restart(pendingRaw: jsonEncode(offer.toJson()), files: [photo]);
      expect(await recovery.takeTool(tool()), isEmpty);
      expect((await recovery.take(offer)).map((f) => f.path), [photo.path]);
    });

    test(
        'a result with no pending pick, or an unreadable record, is not adopted',
        () async {
      final photo = _jpg('x.jpg');
      var recovery = restart(files: [photo]);
      expect(await recovery.takeTool(tool()), isEmpty);
      recovery = restart(pendingRaw: '{ not json', files: [photo]);
      expect(await recovery.takeTool(tool()), isEmpty);
      recovery = restart(
          pendingRaw: jsonEncode({'account': _alice, 'tool': ''}),
          files: [photo]);
      expect(await recovery.takeTool(tool()), isEmpty);
      // A pick opened with nobody signed in recorded nothing.
      recovery = restart(pendingRaw: raw(tool()), files: const []);
      expect(await recovery.takeTool(tool()), isEmpty,
          reason: 'Android returned nothing');
    });

    test('origins: malformed and Offer-shaped records are refused', () {
      expect(ToolPickOrigin.fromJson(null), isNull);
      expect(ToolPickOrigin.fromJson({'account': _alice}), isNull);
      expect(ToolPickOrigin.fromJson({'tool': 'image_to_pdf'}), isNull);
      expect(
          ToolPickOrigin.fromJson(
              {'account': _alice, 'tool': 't', 'parent': 'offer'}),
          isNull);
      expect(ToolPickOrigin.of(accountId: ' ', tool: 'image_to_pdf'), isNull);
      expect(ToolPickOrigin.of(accountId: _alice, tool: ''), isNull);
      expect(ToolPickOrigin.fromJson(tool().toJson()), tool());
      expect(MediaPickOrigin.fromJson(tool().toJson()), isNull);
    });
  });

  group('the Images to PDF picker', () {
    SystemImagePdfPicker picker(MediaPickRecovery recovery,
            {bool android = true, String? account = _alice}) =>
        SystemImagePdfPicker(
          picker: ImagePicker(),
          recovery: recovery,
          isAndroid: android,
          accountId: () => account,
        );

    test(
        'the pending pick is recorded while the picker is open and cleared after',
        () async {
      final recovery = MediaPickRecovery();
      String? whileOpen;
      platform.gallery = [XFile(_jpg('a.jpg').path)];
      platform.onPick = () async {
        whileOpen = await _stored(MediaPickRecovery.pendingOriginKey);
      };
      final result = await picker(recovery).pickFromGallery();
      expect(result, hasLength(1));
      expect(
          jsonDecode(whileOpen!), {'account': _alice, 'tool': 'image_to_pdf'});
      expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull);
    });

    test(
        'a cancel, an error and the camera also clear it: nothing stale remains',
        () async {
      final recovery = MediaPickRecovery();
      final subject = picker(recovery);
      platform.gallery = [];
      expect(await subject.pickFromGallery(), isNull);
      expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull);
      platform.error = PlatformException(code: 'boom');
      await expectLater(
          subject.pickFromGallery(), throwsA(isA<ImagePdfException>()));
      expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull);
      platform.error = PlatformException(code: 'camera_access_denied');
      await expectLater(
          subject.capturePhoto(),
          throwsA(isA<ImagePdfException>().having(
              (e) => e.kind, 'kind', ImagePdfFailure.permissionDenied)));
      expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull);
      platform.error = null;
      platform.photo = XFile(_jpg('cam.jpg').path);
      String? whileOpen;
      platform.onPick = () async {
        whileOpen = await _stored(MediaPickRecovery.pendingOriginKey);
      };
      expect(await subject.capturePhoto(), isNotNull);
      expect(whileOpen, isNotNull);
      expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull);
    });

    test('with nobody signed in nothing is recorded and nothing is recovered',
        () async {
      final recovery = MediaPickRecovery();
      String? whileOpen = 'unset';
      platform.gallery = [XFile(_jpg('a.jpg').path)];
      platform.onPick = () async {
        whileOpen = await _stored(MediaPickRecovery.pendingOriginKey);
      };
      await picker(recovery, account: null).pickFromGallery();
      expect(whileOpen, isNull);
      // A restart with a pick Android returns: no account, nothing adopted.
      final again = restart(pendingRaw: null, files: [_jpg('lost.jpg')]);
      expect(await picker(again, account: null).recoverLostPicks(), isEmpty);
      expect(await picker(again).recoverLostPicks(), isEmpty);
    });

    test('after a restart the same account gets its pictures back in order',
        () async {
      final files = [_jpg('1.jpg'), _jpg('2.jpg'), _jpg('3.jpg')];
      final recovery = restart(pendingRaw: raw(tool()), files: files);
      final back = await picker(recovery).recoverLostPicks();
      expect(back.map((e) => e.path), files.map((f) => f.path).toList());
      expect(back.map((e) => e.name),
          files.map((f) => p.basename(f.path)).toList());
      expect(await picker(recovery).recoverLostPicks(), isEmpty);
    });

    test(
        'another account on the same phone gets nothing, and the owner still can',
        () async {
      final photo = _jpg('mine.jpg');
      final recovery = restart(pendingRaw: raw(tool()), files: [photo]);
      expect(await picker(recovery, account: _bob).recoverLostPicks(), isEmpty);
      expect(await picker(recovery).recoverLostPicks(), hasLength(1));
    });

    test('off Android there is nothing to recover and nothing is recorded',
        () async {
      final recovery = MediaPickRecovery();
      platform.gallery = [XFile(_jpg('a.jpg').path)];
      String? whileOpen = 'unset';
      platform.onPick = () async {
        whileOpen = await _stored(MediaPickRecovery.pendingOriginKey);
      };
      final subject = picker(recovery, android: false);
      await subject.pickFromGallery();
      expect(whileOpen, isNull);
      expect(await subject.recoverLostPicks(), isEmpty);
      expect(platform.lostRequests, 0, reason: 'Android is never asked');
    });
  });

  group('the screen\'s logic takes them back as an ordinary add', () {
    late ImagePdfHarness h;
    setUp(() async {
      h = ImagePdfHarness();
      await h.viewModel.start();
    });
    tearDown(() async => h.dispose());

    test(
        'recovered pictures are added in order, checked, and nothing is made or counted',
        () async {
      final files = [
        h.jpegFile('r1.jpg', w: 101, h: 80),
        h.jpegFile('r2.jpg', w: 102, h: 80),
        h.jpegFile('r3.jpg', w: 103, h: 80),
      ];
      h.picker.lost = [
        for (final f in files)
          PickedImage(path: f.path, name: p.basename(f.path))
      ];
      final outcome = await h.viewModel.recoverLostPicks();
      expect(outcome!.added, 3);
      await h.waitChecked();
      expect([for (final i in h.viewModel.items) i.analysis!.width],
          [101, 102, 103]);
      // The private copies are the account's own; no PDF, no document, no usage.
      expect(h.viewModel.draft, isNull);
      expect(h.viewModel.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.isBuilding, isFalse);
      expect(relativeFiles(Directory(p.join(h.accountDir().path, 'work'))),
          isEmpty);
    });

    test(
        'asking again, or being handed the same file again, adds nothing twice',
        () async {
      final file = h.jpegFile('once.jpg');
      final lost = PickedImage(path: file.path, name: 'once.jpg');
      h.picker.lost = [lost];
      expect((await h.viewModel.recoverLostPicks())!.added, 1);
      expect(await h.viewModel.recoverLostPicks(), isNull);
      h.picker.lost = [lost];
      expect(await h.viewModel.recoverLostPicks(), isNull);
      await h.waitChecked();
      expect(h.viewModel.items, hasLength(1));
    });

    test('nothing recovered means nothing changes', () async {
      expect(await h.viewModel.recoverLostPicks(), isNull);
      expect(h.viewModel.items, isEmpty);
      expect(h.viewModel.isAdding, isFalse);
    });

    test('signed out, or busy with another action, it asks for nothing',
        () async {
      final file = h.jpegFile('kept.jpg');
      h.picker.lost = [PickedImage(path: file.path, name: 'kept.jpg')];
      await h.switchTo(null);
      expect(await h.viewModel.recoverLostPicks(), isNull);
      expect(h.picker.recoveries, 0, reason: 'never taken, so never lost');
      await h.switchTo('user-a');
      final gate = Completer<void>();
      h.picker.gate = gate;
      h.picker.gallery = [];
      final running = h.viewModel.pickFromGallery();
      await h.pumpFutures();
      expect(await h.viewModel.recoverLostPicks(), isNull);
      expect(h.picker.recoveries, 0);
      gate.complete();
      await running;
      h.picker.gate = null;
      expect((await h.viewModel.recoverLostPicks())!.added, 1);
    });

    test(
        'a recovered file that is gone is reported by name, the others are kept',
        () async {
      final good = h.jpegFile('good.jpg');
      h.picker.lost = [
        PickedImage(path: p.join(h.inputs.path, 'gone.jpg'), name: 'gone.jpg'),
        PickedImage(path: good.path, name: 'good.jpg'),
      ];
      final outcome = await h.viewModel.recoverLostPicks();
      expect(outcome!.added, 1);
      expect(outcome.rejected.single.failure, ImagePdfFailure.missingSource);
    });

    test('the picker\'s temporary copy is removed once the private copy exists',
        () async {
      await h.dispose();
      h = ImagePdfHarness(pickerCopiesInTemp: true);
      await h.viewModel.start();
      final copy = h.jpegFile('picker_temp.jpg');
      h.picker.lost = [PickedImage(path: copy.path, name: 'picker_temp.jpg')];
      await h.viewModel.recoverLostPicks();
      await h.waitChecked();
      expect(copy.existsSync(), isFalse);
      expect(h.viewModel.items.single.isReady, isTrue);
    });
  });
}
