import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/scanner/scan_lifecycle_probe.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_engine.dart';

import 'scanner_harness.dart';

class FakeProbe implements ScanLifecycleProbe {
  final List<Completer<void>> watches = <Completer<void>>[];
  int begun = 0;
  int ended = 0;

  @override
  Future<ScanWatch> begin() async {
    begun++;
    final completer = Completer<void>();
    watches.add(completer);
    return ScanWatch(
      abandoned: completer.future,
      onEnd: () async => ended++,
    );
  }

  void abandonLatest() => watches.last.complete();
}

Future<ScannerFailure?> failureOf(Future<Object?> Function() action) async {
  try {
    await action();
  } on ScannerException catch (e) {
    return e.kind;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('the native listener channel', () {
    const channel = MethodChannel(PlatformScanLifecycleProbe.channelName);
    final calls = <String>[];

    Future<void> nativeSays(String method) async {
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method)),
        (_) {},
      );
    }

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
        'begin and end are passed to the native side; a loss completes '
        '"abandoned"', () async {
      final probe = PlatformScanLifecycleProbe();
      final watch = await probe.begin();
      var abandoned = false;
      unawaited(watch.abandoned.then((_) => abandoned = true));
      await Future<void>.delayed(Duration.zero);
      expect(abandoned, isFalse,
          reason: 'a scan that is merely open is not lost');

      await nativeSays('scanAbandoned');
      await Future<void>.delayed(Duration.zero);
      expect(abandoned, isTrue);
      await watch.end();
      expect(calls, <String>['begin', 'end']);
    });

    test('a loss reported after the scan ended does not touch the next scan',
        () async {
      final probe = PlatformScanLifecycleProbe();
      final first = await probe.begin();
      await first.end();
      await nativeSays('scanAbandoned');

      final second = await probe.begin();
      var abandoned = false;
      unawaited(second.abandoned.then((_) => abandoned = true));
      await Future<void>.delayed(Duration.zero);
      expect(abandoned, isFalse);
      await second.end();
    });

    test('a platform without the listener (iPhone) is tolerated', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final probe = PlatformScanLifecycleProbe();
      final watch = await probe.begin();
      await watch.end();
      var abandoned = false;
      unawaited(watch.abandoned.then((_) => abandoned = true));
      await Future<void>.delayed(Duration.zero);
      expect(abandoned, isFalse);
    });
  });

  group('the engine with a lost native result', () {
    const pluginChannel = MethodChannel('flutter_doc_scanner');
    late FakeProbe probe;
    late List<Completer<Object?>> pluginCalls;
    var answerNow = false;

    setUp(() {
      probe = FakeProbe();
      pluginCalls = <Completer<Object?>>[];
      answerNow = false;
      messenger.setMockMethodCallHandler(pluginChannel, (call) {
        if (answerNow) {
          return Future<Object?>.value(<String, Object?>{
            'pdfUri': '/files/a.pdf',
            'pageCount': 2,
          });
        }
        final pending = Completer<Object?>();
        pluginCalls.add(pending);
        return pending.future;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(pluginChannel, null));

    Future<Object?> scan() => FlutterDocScannerEngine(null, probe)
        .scan(format: ExportFormat.pdf, maxPages: 5);

    test(
        'a scan whose result was lost ends with scanAbandoned, not a '
        'permanent wait', () async {
      final running = failureOf(scan);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pluginCalls, hasLength(1), reason: 'the plugin never answered');
      probe.abandonLatest();
      expect(await running, ScannerFailure.scanAbandoned);
      expect(probe.ended, 1, reason: 'the watch is always ended');
    });

    test('a repeated attempt after a lost scan works', () async {
      final first = failureOf(scan);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      probe.abandonLatest();
      expect(await first, ScannerFailure.scanAbandoned);

      answerNow = true;
      final raw = await scan() as Map;
      expect(raw['pdfUri'], '/files/a.pdf');
      expect(probe.begun, 2);
      expect(probe.ended, 2);
    });

    test(
        'a result that arrived first is kept even if a loss is reported '
        'right after', () async {
      final running = scan();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pluginCalls.single.complete(<String, Object?>{
        'pdfUri': '/files/b.pdf',
        'pageCount': 1,
      });
      final raw = await running as Map;
      expect(raw['pdfUri'], '/files/b.pdf');
      probe.abandonLatest();
      await Future<void>.delayed(Duration.zero);
    });

    test('a slow scan is never ended by time alone', () async {
      final running = scan();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      var done = false;
      unawaited(running.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      pluginCalls.single.complete(<String, Object?>{'pdfUri': '/files/c.pdf'});
      expect((await running as Map)['pdfUri'], '/files/c.pdf');
    });

    test('cancel and errors still end the watch', () async {
      final cancelled = scan();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pluginCalls.last.complete(null);
      expect(await cancelled, isNull);

      final failing = failureOf(scan);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pluginCalls.last.completeError(PlatformException(code: 'SCAN_FAILED'));
      expect(await failing, ScannerFailure.engineFailed);
      expect(probe.ended, 2);
    });
  });

  group('the Scanner after a lost result', () {
    late Harness h;
    setUp(() => h = Harness());
    tearDown(() => h.close());

    test('no document, no usage, no draft; the screen is free to retry',
        () async {
      final vm = await h.started();
      h.engine.handler =
          (_) => throw const ScannerException(ScannerFailure.scanAbandoned);
      final result = await scanOnce(vm);
      expect(result.failure, ScannerFailure.scanAbandoned);
      expect(vm.isScanning, isFalse);
      expect(vm.draft, isNull);
      expect(vm.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);

      final path = await h.pdf(2);
      h.engine.handler = (_) => path;
      final retry = await scanOnce(vm);
      expect(retry.draft!.pageCount, 2);
    });

    test(
        'a loss that arrives after the account changed is still not a scan '
        'for the new account', () async {
      final vm = await h.started();
      h.engine.gate = Completer<void>();
      h.engine.handler =
          (_) => throw const ScannerException(ScannerFailure.scanAbandoned);
      final pending = scanOnce(vm);
      await settle(() => h.engine.calls == 1);
      await h.switchTo(vm, 'user-b');
      h.engine.gate!.complete();
      expect((await pending).failure, ScannerFailure.scanAbandoned);
      expect(vm.documents, isEmpty);
      expect(vm.isScanning, isFalse);
    });
  });

  group('backup exclusion', () {
    late Harness h;
    setUp(() => h = Harness());
    tearDown(() => h.close());

    test(
        'the Scanner folder is marked on start, and so is each scanner '
        'output it stages', () async {
      final vm = await h.started();
      expect(h.backup.excluded.any((p) => p.endsWith('scanner')), isTrue);
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      expect(h.backup.excluded.any((p) => p.endsWith('scan-1.pdf')), isTrue);
    });

    test('a backup failure never blocks scanning or saving', () async {
      h.backup.fail = true;
      final vm = await h.started();
      final path = await h.pdf(1);
      h.engine.handler = (_) => path;
      await scanOnce(vm);
      expect((await vm.saveDraft('Still saved')).isSaved, isTrue);
    });

    test(
        'the iPhone guard calls the native channel; Android relies on the '
        'rules and calls nothing', () async {
      const channel = MethodChannel(PlatformScannerBackupGuard.channelName);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      expect(
          await PlatformScannerBackupGuard(isIOS: true).exclude('/x/scanner'),
          isTrue);
      expect(calls.single.method, 'excludeFromBackup');
      expect(calls.single.arguments, '/x/scanner');

      calls.clear();
      expect(
          await PlatformScannerBackupGuard(isIOS: false).exclude('/x'), isTrue);
      expect(calls, isEmpty);

      messenger.setMockMethodCallHandler(channel, null);
      expect(
          await PlatformScannerBackupGuard(isIOS: true).exclude('/x'), isFalse,
          reason: 'a missing native side is reported, not thrown');
    });
  });
}
