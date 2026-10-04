import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart'
    show SharePlatform;

import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';
import 'package:broker_wallet/src/services/share/share_plus_sink.dart';

import 'share_fixtures.dart';

const PreparedShareFile _photo = PreparedShareFile(
  path: '/share/Offer-01.jpg',
  name: 'Offer-01.jpg',
  mimeType: 'image/jpeg',
);
const PreparedShareFile _video = PreparedShareFile(
  path: '/share/Offer-02.mp4',
  name: 'Offer-02.mp4',
  mimeType: 'video/mp4',
);
const PreparedShareFile _photo2 = PreparedShareFile(
  path: '/share/Offer-02.png',
  name: 'Offer-02.png',
  mimeType: 'image/png',
);
const PreparedShareFile _video2 = PreparedShareFile(
  path: '/share/Offer-02.mov',
  name: 'Offer-02.mov',
  mimeType: 'video/quicktime',
);
const PreparedShareFile _pdf = PreparedShareFile(
  path: '/share/Broker-Wallet-Quotation-1.pdf',
  name: 'Broker-Wallet-Quotation-1.pdf',
  mimeType: 'application/pdf',
);

/// The platform end of share_plus, replaced by a recording one.
class RecordingPlatform extends SharePlatform {
  ShareResult result =
      const ShareResult('chosen-app', ShareResultStatus.success);
  final List<ShareParams> calls = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    return result;
  }
}

void main() {
  group('the launcher', () {
    test('hands the request to the share sheet and reports how it ended',
        () async {
      final sink = FakeShareSink(outcome: ShareOutcome.dismissed);
      final launcher = ShareLauncher(sink);
      const request = ShareRequest(text: 'hello', subject: 's');
      expect(await launcher.launch(request), ShareOutcome.dismissed);
      expect(sink.requests.single, same(request));
      expect(launcher.isOpen, isFalse);
    });

    test('never opens a share sheet with nothing in it', () async {
      final sink = FakeShareSink();
      final launcher = ShareLauncher(sink);
      for (final empty in const <ShareRequest>[
        ShareRequest(),
        ShareRequest(text: ''),
        ShareRequest(text: '   \n'),
        ShareRequest(subject: 'only a subject'),
      ]) {
        ShareFailure? failure;
        try {
          await launcher.launch(empty);
        } on ShareFailure catch (error) {
          failure = error;
        }
        expect(failure, isNotNull);
        expect(failure!.kind, ShareFailureKind.generic);
      }
      expect(sink.requests, isEmpty);
    });

    test('opens one sheet at a time', () async {
      final sink = FakeShareSink();
      final gate = Completer<ShareOutcome>();
      sink.hold = gate;
      final launcher = ShareLauncher(sink);

      final first = launcher.launch(const ShareRequest(text: 'one'));
      await Future<void>.delayed(Duration.zero);
      expect(launcher.isOpen, isTrue);
      expect(await launcher.launch(const ShareRequest(text: 'two')), isNull);
      expect(await launcher.launch(const ShareRequest(text: 'three')), isNull);
      expect(sink.requests, hasLength(1));

      gate.complete(ShareOutcome.shared);
      expect(await first, ShareOutcome.shared);
      expect(launcher.isOpen, isFalse);

      sink.hold = null;
      expect(await launcher.launch(const ShareRequest(text: 'four')),
          ShareOutcome.shared);
      expect(sink.requests, hasLength(2));
    });

    test('whatever the platform throws becomes a short failure', () async {
      final sink = FakeShareSink()
        ..error =
            StateError('PlatformException(error, sharePositionOrigin: ...)');
      final launcher = ShareLauncher(sink);
      ShareFailure? failure;
      try {
        await launcher.launch(const ShareRequest(text: 'x'));
      } on ShareFailure catch (error) {
        failure = error;
      }
      expect(failure!.kind, ShareFailureKind.generic);
      expect(failure.toString(), 'ShareFailure(generic)');

      // The lock was released: the next share can open.
      sink.error = null;
      expect(await launcher.launch(const ShareRequest(text: 'y')),
          ShareOutcome.shared);
    });

    test('a failure the sink already classified keeps its kind', () async {
      final sink = FakeShareSink()
        ..error = const ShareFailure(ShareFailureKind.session);
      ShareFailure? failure;
      try {
        await ShareLauncher(sink).launch(const ShareRequest(text: 'x'));
      } on ShareFailure catch (error) {
        failure = error;
      }
      expect(failure!.kind, ShareFailureKind.session);
    });
  });

  group('the share_plus end', () {
    late RecordingPlatform platform;
    late SharePlusSink sink;

    setUp(() {
      platform = RecordingPlatform();
      sink = SharePlusSink(invoke: SharePlus.custom(platform).share);
    });

    test('text only', () async {
      final outcome = await sink.send(const ShareRequest(
          text: 'Offer Details\n====\n', subject: 'Offer Details'));
      expect(outcome, ShareOutcome.shared);
      final params = platform.calls.single;
      expect(params.text, 'Offer Details\n====\n');
      expect(params.subject, 'Offer Details');
      expect(params.files, isNull);
      expect(params.uri, isNull);
      expect(params.sharePositionOrigin, isNull);
    });

    test('text with one file', () async {
      await sink.send(const ShareRequest(
          text: 'message', subject: 's', files: <PreparedShareFile>[_photo]));
      final params = platform.calls.single;
      expect(params.text, 'message');
      expect(params.files, hasLength(1));
      expect(params.files!.single.path, _photo.path);
      expect(params.files!.single.mimeType, 'image/jpeg');
    });

    test('several files keep their order and their types', () async {
      await sink.send(
          const ShareRequest(files: <PreparedShareFile>[_photo, _video, _pdf]));
      final params = platform.calls.single;
      expect(params.files!.map((f) => f.path).toList(),
          <String>[_photo.path, _video.path, _pdf.path]);
      expect(params.files!.map((f) => f.mimeType).toList(),
          <String?>['image/jpeg', 'video/mp4', 'application/pdf']);
    });

    test(
        'a whole selection goes to the plugin whole, message included, in one '
        'call, each file with its own proven type', () async {
      final selection = SharePayload.plan(
        delivery: ShareDelivery.wholeSelection,
        files: const <PreparedShareFile>[_photo, _video, _photo2, _video2],
        text: 'Offer Details\n====\n',
        subject: 'Offer Details',
      );
      expect(selection.kind, SharePayloadKind.filesWithText);

      final outcome = await sink.send(selection.toRequest(null));

      expect(outcome, ShareOutcome.shared);
      expect(platform.calls, hasLength(1), reason: 'one native request');
      final params = platform.calls.single;
      expect(params.text, 'Offer Details\n====\n');
      expect(params.subject, 'Offer Details');
      expect(params.uri, isNull);
      expect(params.files!.map((f) => f.path).toList(),
          <String>[_photo.path, _video.path, _photo2.path, _video2.path],
          reason: 'the order they were chosen in');
      expect(params.files!.map((f) => f.mimeType).toList(), <String?>[
        'image/jpeg',
        'video/mp4',
        'image/png',
        'video/quicktime',
      ]);
    });

    test('files alone carry no text', () async {
      await sink.send(const ShareRequest(
          text: '', subject: '  ', files: <PreparedShareFile>[_video]));
      final params = platform.calls.single;
      expect(params.text, isNull);
      expect(params.subject, isNull);
      expect(params.files, hasLength(1));
    });

    test('a link is never passed as the thing being shared', () async {
      await sink.send(const ShareRequest(text: 'message'));
      expect(platform.calls.single.uri, isNull);
    });

    test('an iPad is told where the sheet comes from', () async {
      await sink.send(
          const ShareRequest(text: 'x', origin: ShareOrigin(10, 20, 30, 40)));
      expect(platform.calls.single.sharePositionOrigin,
          const Rect.fromLTWH(10, 20, 30, 40));
    });

    test('an origin with no area is not passed on', () async {
      await sink.send(
          const ShareRequest(text: 'x', origin: ShareOrigin(10, 20, 0, 0)));
      expect(platform.calls.single.sharePositionOrigin, isNull);
    });

    test('closing the sheet is a dismissal, not a failure', () async {
      platform.result = const ShareResult('', ShareResultStatus.dismissed);
      expect(await sink.send(const ShareRequest(text: 'x')),
          ShareOutcome.dismissed);
    });

    test('a platform that cannot say how it ended is unknown, not an error',
        () async {
      platform.result = ShareResult.unavailable;
      expect(
          await sink.send(const ShareRequest(text: 'x')), ShareOutcome.unknown);
    });

    test('the plugin accepts everything the sink builds', () async {
      // share_plus rejects empty text, empty file lists and text with a link:
      // none of the shapes above tripped it.
      for (final request in const <ShareRequest>[
        ShareRequest(text: 'a'),
        ShareRequest(text: 'a', files: <PreparedShareFile>[_photo]),
        ShareRequest(files: <PreparedShareFile>[_photo, _pdf]),
      ]) {
        await sink.send(request);
      }
      expect(platform.calls, hasLength(3));
    });
  });
}
