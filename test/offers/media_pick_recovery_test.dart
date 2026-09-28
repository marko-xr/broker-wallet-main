import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/media_pick_recovery.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart'
    show OfferMediaUploadCompleted;
import 'package:broker_wallet/src/services/private_media_store.dart';
import 'package:broker_wallet/src/viewmodels/private_media_form.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A photo or video Android hands back after it stopped the app mid-pick
/// goes back to the form it was picked on — the same account, kind of record
/// and record — and to no other; a result nobody can claim is not adopted.
/// Local unit tests against fakes of image_picker's platform side and of
/// SharedPreferences; "a restart" is a fresh [MediaPickRecovery] over what the
/// previous run left in storage.

const _alice = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _bob = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _ownerX = 'a0a0a0a0-a0a0-4a0a-8a0a-a0a0a0a0a0a0';
const _ownerY = 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1';

final _jpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(60, 0)];

late Directory _dir;
var _seq = 0;

File _jpeg(String name) =>
    File('${_dir.path}${Platform.pathSeparator}${_seq++}_$name')
      ..writeAsBytesSync(_jpegBytes);

/// image_picker's platform side. Android hands a lost result back once, so
/// [getLostData] answers with it once; [onPick] observes a Gallery pick while
/// the picker is "open".
class _FakePicker extends ImagePickerPlatform {
  LostDataResponse lost = LostDataResponse.empty();
  int lostRequests = 0;
  List<XFile> gallery = [];
  Future<void> Function()? onPick;

  @override
  Future<LostDataResponse> getLostData() async {
    lostRequests += 1;
    final answer = lost;
    lost = LostDataResponse.empty();
    return answer;
  }

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    await onPick?.call();
    return gallery;
  }
}

/// An Owner media store for [_alice] with nothing on the server or queued.
class _Store implements PrivateMediaStore {
  final _changes = ChangeNotifier();
  final _completions = StreamController<OfferMediaUploadCompleted>.broadcast();

  @override
  MediaParent get parent => MediaParent.owner;

  @override
  String? get currentOwnerId => _alice;

  @override
  List<OfferMediaRef> cachedMedia(String recordId) => const [];

  @override
  Future<OfferMediaResolution?> resolveMedia({
    required String recordId,
    required String ownerId,
  }) async =>
      null;

  @override
  List<OfferMediaRef> pendingMedia(String recordId) => const [];

  @override
  Listenable get uploadChanges => _changes;

  @override
  Stream<OfferMediaUploadCompleted> get uploadCompletions =>
      _completions.stream;

  @override
  Future<void> loadUploads() async {}

  @override
  Future<void> retryUpload(String mediaObjectId) async {}

  @override
  Future<void> cancelUpload(String mediaObjectId) async {}
}

MediaPickOrigin _origin({
  String account = _alice,
  MediaParent parent = MediaParent.owner,
  String? record = _ownerX,
  String session = 'form-1',
}) =>
    MediaPickOrigin.of(
      accountId: account,
      parent: parent,
      recordId: record,
      formSessionId: session,
    )!;

Future<String?> _stored(String key) async =>
    (await SharedPreferences.getInstance()).getString(key);

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePicker picker;
  late ImagePickerPlatform originalPicker;

  setUpAll(() async {
    _dir = await Directory.systemTemp.createTemp('media_pick_recovery_test');
    originalPicker = ImagePickerPlatform.instance;
  });

  setUp(() {
    picker = _FakePicker();
    ImagePickerPlatform.instance = picker;
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    ImagePickerPlatform.instance = originalPicker;
    try {
      await _dir.delete(recursive: true);
    } catch (_) {}
  });

  /// A new run of the app after Android stopped the previous one: [pending]
  /// was waiting for its picker (none: no Offer/Owner picker was open), and
  /// Android hands back [files].
  MediaPickRecovery restart({
    MediaPickOrigin? pending,
    List<File> files = const [],
  }) {
    SharedPreferences.setMockInitialValues({
      if (pending != null)
        MediaPickRecovery.pendingOriginKey: jsonEncode(pending.toJson()),
    });
    picker.lost = files.isEmpty
        ? LostDataResponse.empty()
        : LostDataResponse(files: [for (final f in files) XFile(f.path)]);
    return MediaPickRecovery();
  }

  group('MediaPickOrigin', () {
    test(
        'names the account, the kind of record and the record — or the form '
        'while the record has no id; nothing without an account', () {
      final edit = _origin();
      expect(edit.recordId, _ownerX);
      expect(edit.formSessionId, isNull);

      final fresh = _origin(record: null);
      expect(fresh.recordId, isNull);
      expect(fresh.formSessionId, 'form-1');

      for (final account in [null, '', '  ']) {
        expect(
          MediaPickOrigin.of(
            accountId: account,
            parent: MediaParent.owner,
            recordId: _ownerX,
            formSessionId: 'form-1',
          ),
          isNull,
        );
      }
      expect(MediaPickOrigin.fromJson(edit.toJson()), edit);
      expect(MediaPickOrigin.fromJson(fresh.toJson()), fresh);
      expect(MediaPickOrigin.fromJson({'account': _alice}), isNull);
      expect(
        MediaPickOrigin.fromJson({
          'account': _alice,
          'parent': 'owner',
          'record': _ownerX,
          'session': 'form-1',
        }),
        isNull,
        reason: 'a record or a form, never both',
      );
    });
  });

  group('MediaPickRecovery', () {
    test('a lost pick goes back to the form it was picked on, once', () async {
      final photo = _jpeg('lost.jpg');
      final recovery = restart(pending: _origin(), files: [photo]);

      final taken = await recovery.take(_origin());

      expect(taken.map((f) => f.path), [photo.path]);
      expect(await recovery.take(_origin()), isEmpty,
          reason: 'handed out once: a second open adopts nothing');
    });

    test(
        'another record, another kind of record, another account or a new '
        'form neither receives it nor uses it up', () async {
      final photo = _jpeg('owner-x.jpg');
      final recovery = restart(pending: _origin(), files: [photo]);

      final others = {
        'another Owner record': _origin(record: _ownerY),
        'an Offer with the same id': _origin(parent: MediaParent.offer),
        'another account': _origin(account: _bob),
        'a new-Owner form': _origin(record: null),
      };
      for (final entry in others.entries) {
        expect(await recovery.take(entry.value), isEmpty, reason: entry.key);
      }
      expect(await recovery.take(null), isEmpty,
          reason: 'a form with no account');

      expect((await recovery.take(_origin())).map((f) => f.path), [photo.path],
          reason: 'still kept for the form it was picked on');
    });

    test(
        'a result no Offer/Owner picker was waiting for — another picker in '
        'the app — is not adopted', () async {
      final recovery = restart(files: [_jpeg('avatar.jpg')]);

      expect(await recovery.take(_origin()), isEmpty);
      expect(await recovery.take(_origin(parent: MediaParent.offer)), isEmpty);
      expect(await _stored(MediaPickRecovery.keptResultKey), isNull);
    });

    test(
        'a pick on a form for a record not yet saved is not adopted after the '
        'restart: that form is gone', () async {
      final fresh = _origin(record: null);
      final recovery = restart(pending: fresh, files: [_jpeg('new.jpg')]);

      expect(await recovery.take(fresh), isEmpty);
      expect(await recovery.take(_origin(record: null, session: 'form-2')),
          isEmpty);
      expect(await _stored(MediaPickRecovery.keptResultKey), isNull);
      expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull);
    });

    test('Android is asked once per run of the app', () async {
      final recovery = restart(pending: _origin(), files: [_jpeg('once.jpg')]);

      await recovery.reconcile();
      await recovery.reconcile();
      await recovery.take(_origin(record: _ownerY));
      await recovery.take(_origin());

      expect(picker.lostRequests, 1);
    });

    test(
        'a picker opened before start-up routing finished cannot claim the '
        'earlier result', () async {
      final photo = _jpeg('earlier.jpg');
      final recovery = restart(pending: _origin(), files: [photo]);
      final media = OfferMediaPicker(isAndroid: true, recovery: recovery);

      // Opened for Owner Y at once, before anything awaited the routing.
      await media.pickFromGallery(limit: 3, origin: _origin(record: _ownerY));

      expect(await recovery.take(_origin(record: _ownerY)), isEmpty);
      expect((await recovery.take(_origin())).map((f) => f.path), [photo.path]);
    });
  });

  group('OfferMediaPicker', () {
    test(
        'records the form before the picker opens and clears it when the '
        'picker returns, also on cancel', () async {
      final media =
          OfferMediaPicker(isAndroid: true, recovery: MediaPickRecovery());
      String? pendingWhileOpen;
      picker.onPick = () async {
        pendingWhileOpen = await _stored(MediaPickRecovery.pendingOriginKey);
      };

      final files =
          await media.pickFromGallery(limit: 3, origin: _origin()); // cancel

      expect(files, isEmpty);
      expect(jsonDecode(pendingWhileOpen!), _origin().toJson());
      expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull,
          reason: 'nothing is pending once the picker returned');
    });

    test('a picker opened with no account records nothing to recover into',
        () async {
      final media =
          OfferMediaPicker(isAndroid: true, recovery: MediaPickRecovery());
      var checked = false;
      picker.onPick = () async {
        expect(await _stored(MediaPickRecovery.pendingOriginKey), isNull);
        checked = true;
      };

      await media.pickFromGallery(limit: 3, origin: null);

      expect(checked, isTrue);
    });

    test('recovers on Android only, and only for the asking form', () async {
      final recovery = restart(pending: _origin(), files: [_jpeg('a.jpg')]);

      expect(
          await OfferMediaPicker(isAndroid: false, recovery: recovery)
              .recoverLostSelection(origin: _origin()),
          isEmpty);
      expect(picker.lostRequests, 0, reason: 'nothing asked off Android');

      final android = OfferMediaPicker(isAndroid: true, recovery: recovery);
      expect(
          await android.recoverLostSelection(origin: _origin(record: _ownerY)),
          isEmpty);
      expect(
          await android.recoverLostSelection(origin: _origin()), hasLength(1));
    });
  });

  group('the Owner form', () {
    PrivateMediaForm form(MediaPickRecovery recovery) {
      final created = PrivateMediaForm(
        store: _Store(),
        onChanged: () {},
        picker: OfferMediaPicker(isAndroid: true, recovery: recovery),
      );
      addTearDown(created.dispose);
      return created;
    }

    test(
        'opening another Owner or a new Owner adopts nothing; the Owner it was '
        'picked on gets it', () async {
      final recovery = restart(pending: _origin(), files: [_jpeg('x.jpg')]);

      final other = form(recovery)..start(editRecordId: _ownerY);
      final fresh = form(recovery)..start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(other.items, isEmpty);
      expect(fresh.items, isEmpty);

      final own = form(recovery)..start(editRecordId: _ownerX);
      await _until(() => own.items.isNotEmpty);
      expect(own.items, hasLength(1));
      expect(own.drafts, hasLength(1));

      final again = form(recovery)..start(editRecordId: _ownerX);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(again.items, isEmpty, reason: 'recovered once, not twice');
    });
  });
}
