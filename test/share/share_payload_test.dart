// The payload rule: what the native share sheet is handed for a prepared batch.
//
// Pure logic, no phone. The rule: no file is the message alone; one file is the
// file with its message; two or more photos, or two or more videos, are ONE
// homogeneous batch of exactly those files with NO message in the request (the
// message is copied once by the flow instead); a mix of photos and videos is
// never a batch; a platform that takes the whole selection in one system share
// gets every file and the message. A batch is never declared to be anything it is
// not. These tests do not exercise any receiving app.

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';

const String _message = 'Offer Details\n====\nVilla in Dubai Marina\n====';
const String _subject = 'Offer Details';

PreparedShareFile _file(String name, String mime) => PreparedShareFile(
      path: '/share/$name',
      name: name,
      mimeType: mime,
    );

PreparedShareFile _jpg(int n) => _file('Offer-0$n.jpg', 'image/jpeg');
PreparedShareFile _png(int n) => _file('Offer-0$n.png', 'image/png');
PreparedShareFile _mp4(int n) => _file('Offer-0$n.mp4', 'video/mp4');
PreparedShareFile _mov(int n) => _file('Offer-0$n.mov', 'video/quicktime');
PreparedShareFile _pdf(int n) => _file('Doc-0$n.pdf', 'application/pdf');

SharePayload _plan(
  List<PreparedShareFile> files, {
  ShareDelivery delivery = ShareDelivery.familyBatches,
  String? text = _message,
}) =>
    SharePayload.plan(
      delivery: delivery,
      files: files,
      text: text,
      subject: _subject,
    );

void main() {
  group('no file or one file', () {
    test('no file is the message alone', () {
      final payload = _plan(const <PreparedShareFile>[]);
      expect(payload.kind, SharePayloadKind.textOnly);
      expect(payload.isMediaBatch, isFalse);
      expect(payload.isLaunchable, isTrue);
      final request = payload.toRequest(null);
      expect(request.text, _message);
      expect(request.subject, _subject);
      expect(request.files, isEmpty);
      expect(request.mediaBatch, isFalse);
    });

    test('one image goes with its message', () {
      final payload = _plan(<PreparedShareFile>[_jpg(1)]);
      expect(payload.kind, SharePayloadKind.fileWithText);
      final request = payload.toRequest(null);
      expect(request.files, hasLength(1));
      expect(request.text, _message);
      expect(request.subject, _subject);
      expect(request.mediaBatch, isFalse,
          reason: 'one file keeps the existing system share');
    });

    test('one video goes with its message', () {
      final payload = _plan(<PreparedShareFile>[_mp4(1)]);
      expect(payload.kind, SharePayloadKind.fileWithText);
      final request = payload.toRequest(null);
      expect(request.files.single.mimeType, 'video/mp4');
      expect(request.text, _message);
      expect(request.mediaBatch, isFalse);
    });
  });

  group('several photos, or several videos: one homogeneous batch', () {
    test('several images are files only, in the order prepared', () {
      final payload = _plan(<PreparedShareFile>[_jpg(1), _png(2), _jpg(3)]);
      expect(payload.kind, SharePayloadKind.mediaBatch);
      expect(payload.isMediaBatch, isTrue);
      expect(payload.isLaunchable, isTrue);
      final request = payload.toRequest(null);
      expect(request.mediaBatch, isTrue);
      expect(request.text, isNull,
          reason: 'a message sent with several files is repeated or dropped by '
              'the receiving app; the flow copies it instead');
      expect(request.subject, isNull);
      expect(request.files.map((f) => f.name).toList(),
          <String>['Offer-01.jpg', 'Offer-02.png', 'Offer-03.jpg']);
    });

    test('several videos are files only, each with its own type', () {
      final payload = _plan(<PreparedShareFile>[_mp4(1), _mov(2), _mp4(3)]);
      expect(payload.kind, SharePayloadKind.mediaBatch);
      final request = payload.toRequest(null);
      expect(request.files.map((f) => f.mimeType).toList(),
          <String>['video/mp4', 'video/quicktime', 'video/mp4']);
      expect(request.text, isNull);
      expect(request.subject, isNull);
    });

    test('two files are already a batch', () {
      expect(_plan(<PreparedShareFile>[_jpg(1), _jpg(2)]).kind,
          SharePayloadKind.mediaBatch);
      expect(_plan(<PreparedShareFile>[_mp4(1), _mp4(2)]).kind,
          SharePayloadKind.mediaBatch);
      expect(SharePayload.severalFiles, 2);
    });

    test('a batch carries no message even when there is none to carry', () {
      for (final text in <String?>[null, '', '  \n']) {
        final payload =
            _plan(<PreparedShareFile>[_jpg(1), _jpg(2)], text: text);
        expect(payload.kind, SharePayloadKind.mediaBatch);
        expect(payload.toRequest(null).text, isNull);
        expect(payload.toRequest(null).files, hasLength(2));
      }
    });

    test('the origin the sheet is anchored to is carried through', () {
      const origin = ShareOrigin(10, 20, 30, 40);
      final request =
          _plan(<PreparedShareFile>[_jpg(1), _jpg(2)]).toRequest(origin);
      expect(request.origin, same(origin));
    });
  });

  group('photos and videos in one batch are refused, never relabelled', () {
    test('a mix is an inconsistent batch that is not launchable', () {
      for (final files in <List<PreparedShareFile>>[
        <PreparedShareFile>[_jpg(1), _mp4(2)],
        <PreparedShareFile>[_jpg(1), _jpg(2), _mp4(3)],
        <PreparedShareFile>[_mp4(1), _mp4(2), _jpg(3)],
        <PreparedShareFile>[_jpg(1), _mp4(2), _png(3), _mov(4)],
      ]) {
        final payload = _plan(files);
        expect(payload.kind, SharePayloadKind.inconsistentBatch);
        expect(payload.isLaunchable, isFalse);
        expect(payload.isMediaBatch, isFalse,
            reason: 'never handed to the batch transport');
        expect(payload.toRequest(null).text, isNull);
        expect(payload.toRequest(null).mediaBatch, isFalse);
      }
    });
  });

  group('files that are not all photos and videos', () {
    test('several documents take the system share with the message', () {
      final payload = _plan(<PreparedShareFile>[_pdf(1), _pdf(2)]);
      expect(payload.kind, SharePayloadKind.filesWithText);
      expect(payload.isMediaBatch, isFalse);
      expect(payload.toRequest(null).mediaBatch, isFalse);
      expect(payload.toRequest(null).text, _message);
    });

    test('a photo with a document is not a media batch', () {
      final payload = _plan(<PreparedShareFile>[_jpg(1), _pdf(2)]);
      expect(payload.kind, SharePayloadKind.filesWithText);
      expect(payload.toRequest(null).mediaBatch, isFalse);
      expect(payload.isLaunchable, isTrue);
    });
  });

  group('a platform that takes the whole selection', () {
    test('every file and the message go in one system share, mixed or not', () {
      for (final files in <List<PreparedShareFile>>[
        <PreparedShareFile>[_jpg(1), _mp4(2), _jpg(3)],
        <PreparedShareFile>[_jpg(1), _jpg(2), _jpg(3)],
        <PreparedShareFile>[_mp4(1), _mp4(2)],
      ]) {
        final payload = _plan(files, delivery: ShareDelivery.wholeSelection);
        expect(payload.kind, SharePayloadKind.filesWithText);
        expect(payload.isLaunchable, isTrue);
        final request = payload.toRequest(null);
        expect(request.text, _message);
        expect(request.mediaBatch, isFalse,
            reason: 'never the Android batch transport');
        expect(request.files, hasLength(files.length));
      }
    });

    test('one file and no file are the same on every platform', () {
      for (final delivery in ShareDelivery.values) {
        expect(_plan(<PreparedShareFile>[_jpg(1)], delivery: delivery).kind,
            SharePayloadKind.fileWithText);
        expect(_plan(const <PreparedShareFile>[], delivery: delivery).kind,
            SharePayloadKind.textOnly);
      }
    });
  });

  group('a file is a photo, a video or neither by the type its bytes proved',
      () {
    test('family and kind', () {
      expect(_jpg(1).family, 'image');
      expect(_jpg(1).isImage, isTrue);
      expect(_mov(1).family, 'video');
      expect(_mov(1).isVideo, isTrue);
      expect(_mp4(1).isMedia, isTrue);
      expect(_pdf(1).family, 'application');
      expect(_pdf(1).isMedia, isFalse);
      expect(_file('x', 'odd').family, 'odd');
    });
  });
}
