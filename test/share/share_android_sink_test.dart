// The Android transport for a homogeneous batch of photos, or of videos: what is
// routed to the native adapter, exactly what it is sent over the method channel,
// and what happens when it fails.
//
// Local tests with a recording channel. The Kotlin side (the intent it builds)
// cannot run here; its structure is pinned by the source guards and its behavior
// is a device check.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/share/share_android_sink.dart';
import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';

const PreparedShareFile _photo = PreparedShareFile(
  path: '/cache/broker_wallet_share/1-0/Offer-01.jpg',
  name: 'Offer-01.jpg',
  mimeType: 'image/jpeg',
);
const PreparedShareFile _photo2 = PreparedShareFile(
  path: '/cache/broker_wallet_share/1-0/Offer-02.png',
  name: 'Offer-02.png',
  mimeType: 'image/png',
);
const PreparedShareFile _photo3 = PreparedShareFile(
  path: '/cache/broker_wallet_share/1-0/Offer-03.jpg',
  name: 'Offer-03.jpg',
  mimeType: 'image/jpeg',
);
const PreparedShareFile _video = PreparedShareFile(
  path: '/cache/broker_wallet_share/2-0/Offer-01.mp4',
  name: 'Offer-01.mp4',
  mimeType: 'video/mp4',
);
const PreparedShareFile _video2 = PreparedShareFile(
  path: '/cache/broker_wallet_share/2-0/Offer-02.mov',
  name: 'Offer-02.mov',
  mimeType: 'video/quicktime',
);
const PreparedShareFile _pdf = PreparedShareFile(
  path: '/cache/broker_wallet_share/1-0/Doc-01.pdf',
  name: 'Doc-01.pdf',
  mimeType: 'application/pdf',
);

const String _message = 'Offer Details\n====\nVilla\n====';

/// The system share, standing in for share_plus.
class _SystemSink implements ShareSink {
  final List<ShareRequest> requests = <ShareRequest>[];
  ShareOutcome outcome = ShareOutcome.shared;

  @override
  Future<ShareOutcome> send(ShareRequest request) async {
    requests.add(request);
    return outcome;
  }
}

/// The request the share flow makes for [files] on Android.
ShareRequest _request(List<PreparedShareFile> files,
        {String? text = _message}) =>
    SharePayload.plan(
      delivery: ShareDelivery.familyBatches,
      files: files,
      text: text,
      subject: 'Offer Details',
    ).toRequest(null);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidMediaBatchSink.channelName);

  late List<MethodCall> calls;
  late _SystemSink system;
  late AndroidMediaBatchSink sink;
  Object? Function(MethodCall call)? answer;

  setUp(() {
    calls = <MethodCall>[];
    system = _SystemSink();
    answer = null;
    sink = AndroidMediaBatchSink(system: system);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      final reply = answer;
      return reply == null ? null : reply(call);
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('what goes to the native adapter', () {
    test('the channel and the method are the ones the Kotlin side answers', () {
      expect(AndroidMediaBatchSink.channelName,
          'com.example.broker_wallet/multi_media_share');
      expect(AndroidMediaBatchSink.shareMethod, 'shareMultipleMedia');
    });

    test('a homogeneous batch of photos, or of videos', () {
      expect(
          AndroidMediaBatchSink.takes(
              _request(<PreparedShareFile>[_photo, _photo2, _photo3])),
          isTrue);
      expect(
          AndroidMediaBatchSink.takes(
              _request(<PreparedShareFile>[_video, _video2])),
          isTrue);
    });

    test(
        'nothing else: no file, one file, documents, a mix, or an unmarked one',
        () {
      expect(AndroidMediaBatchSink.takes(_request(const <PreparedShareFile>[])),
          isFalse);
      expect(AndroidMediaBatchSink.takes(_request(<PreparedShareFile>[_photo])),
          isFalse);
      expect(
          AndroidMediaBatchSink.takes(
              _request(<PreparedShareFile>[_pdf, _pdf])),
          isFalse);
      // A mix is never a batch, so it is never handed to the native adapter.
      expect(
          AndroidMediaBatchSink.takes(
              _request(<PreparedShareFile>[_photo, _video])),
          isFalse);
      // Two files nobody marked as a media batch (the Toolkit's own files) keep
      // the system share.
      expect(
          AndroidMediaBatchSink.takes(const ShareRequest(
              text: 'x', files: <PreparedShareFile>[_photo, _photo2])),
          isFalse);
    });
  });

  group('what the native adapter is sent', () {
    test('every path in the order chosen and the type each proved, no message',
        () {
      final request = _request(<PreparedShareFile>[_photo, _photo2, _photo3]);
      final arguments = AndroidMediaBatchSink.arguments(request);

      expect(arguments.keys.toSet(), <String>{'paths', 'mimeTypes'},
          reason: 'files and types only: no text, subject or link');
      expect(arguments['paths'], <String>[
        _photo.path,
        _photo2.path,
        _photo3.path,
      ]);
      expect(arguments['mimeTypes'], <String>[
        'image/jpeg',
        'image/png',
        'image/jpeg',
      ]);
    });

    test('videos keep their own types', () {
      final arguments = AndroidMediaBatchSink.arguments(
          _request(<PreparedShareFile>[_video, _video2]));
      expect(arguments['mimeTypes'], <String>['video/mp4', 'video/quicktime']);
    });

    test('only local paths: never a link', () {
      final arguments = AndroidMediaBatchSink.arguments(
          _request(<PreparedShareFile>[_photo, _photo2]));
      for (final path in arguments['paths']! as List<Object?>) {
        expect(path, startsWith('/'));
        expect('$path'.contains('://'), isFalse);
        expect('$path'.contains('?'), isFalse);
      }
    });
  });

  group('sending', () {
    test('a batch is one call to the channel, and the system share is not used',
        () async {
      final outcome = await sink
          .send(_request(<PreparedShareFile>[_photo, _photo2, _photo3]));

      expect(outcome, ShareOutcome.unknown,
          reason: 'a started chooser reports nothing back');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'shareMultipleMedia');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['paths'], hasLength(3));
      expect(arguments['mimeTypes'], hasLength(3));
      expect(arguments.containsKey('text'), isFalse);
      expect(system.requests, isEmpty);
    });

    test('one file, no file and documents take the system share, untouched',
        () async {
      await sink.send(_request(<PreparedShareFile>[_photo]));
      await sink.send(_request(const <PreparedShareFile>[]));
      await sink.send(_request(<PreparedShareFile>[_pdf, _pdf]));

      expect(calls, isEmpty);
      expect(system.requests, hasLength(3));
      expect(system.requests.first.files.single.path, _photo.path);
      expect(system.requests.first.text, _message);
    });

    test('the system share keeps its own outcome', () async {
      system.outcome = ShareOutcome.dismissed;
      expect(await sink.send(_request(<PreparedShareFile>[_photo])),
          ShareOutcome.dismissed);
    });

    test('a refusal of the native side is thrown, and the launcher reduces it',
        () async {
      answer = (call) => throw PlatformException(
            code: 'share-failed',
            message: 'The share sheet could not be opened.',
          );
      final launcher = ShareLauncher(sink);

      await expectLater(
        launcher.launch(_request(<PreparedShareFile>[_photo, _photo2])),
        throwsA(isA<ShareFailure>()
            .having((f) => f.kind, 'kind', ShareFailureKind.generic)),
      );
      expect(launcher.isOpen, isFalse);
      expect(system.requests, isEmpty,
          reason: 'a failed batch is never retried through the system share');
    });

    test('an adapter that is missing is a failure too, not a silent fallback',
        () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      final launcher = ShareLauncher(sink);

      await expectLater(
        launcher.launch(_request(<PreparedShareFile>[_photo, _photo2])),
        throwsA(isA<ShareFailure>()),
      );
      expect(system.requests, isEmpty);
    });

    test('two batches are never open at once', () async {
      final gate = Completer<Object?>();
      answer = (call) => gate.future;
      final launcher = ShareLauncher(sink);

      final first =
          launcher.launch(_request(<PreparedShareFile>[_photo, _photo2]));
      await Future<void>.delayed(Duration.zero);
      final second =
          await launcher.launch(_request(<PreparedShareFile>[_video, _video2]));

      expect(second, isNull, reason: 'one share sheet only');
      expect(calls, hasLength(1));
      gate.complete(null);
      expect(await first, ShareOutcome.unknown);
    });
  });
}
