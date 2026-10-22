import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_source_stager.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_document_store.dart';
import 'package:broker_wallet/src/services/scanner/scanner_engine.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/scanner/scanner_share_preparer.dart';
import 'package:broker_wallet/src/services/scanner/scanner_usage_recorder.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';

import 'scanner_fixtures.dart';

class FakeEngine implements ScannerEngine {
  Object? Function(ExportFormat format)? handler;
  Completer<void>? gate;
  int calls = 0;
  int? lastMaxPages;
  ExportFormat? lastFormat;

  @override
  Future<Object?> scan({
    required ExportFormat format,
    required int maxPages,
  }) async {
    calls++;
    lastFormat = format;
    lastMaxPages = maxPages;
    if (gate != null) await gate!.future;
    return handler!(format);
  }
}

class FakeUsage implements ScannerUsageRecorder {
  final List<String> recorded = <String>[];

  @override
  Future<void> recordScan(String userId) async => recorded.add(userId);
}

class FakeExporter implements ScannerExporter {
  final List<String> exportedNames = <String>[];
  final List<String> exportedPaths = <String>[];
  Object? failure;

  @override
  Future<ScannerExportResult> export(
      ScannerDocument document, File file) async {
    if (failure != null) throw failure!;
    exportedNames.add(document.exportFileName);
    exportedPaths.add(file.path);
    return ScannerExportResult.saved(
        ScannerExportDestination.downloads, document.exportFileName);
  }
}

class FakeBackupGuard implements ScannerBackupGuard {
  final List<String> excluded = <String>[];
  bool fail = false;

  @override
  Future<bool> exclude(String path) async {
    excluded.add(path);
    if (fail) throw StateError('backup marking failed');
    return true;
  }
}

class Harness {
  Harness() {
    root = makeTempDir('vm');
    base = Directory(p.join(root.path, 'docs'))..createSync();
    output = Directory(p.join(root.path, 'scanner_output'))..createSync();
    temp = Directory(p.join(root.path, 'tmp'))..createSync();
  }

  late final Directory root;
  late final Directory base;
  late final Directory output;
  late final Directory temp;
  final FakeEngine engine = FakeEngine();
  final FakeUsage usage = FakeUsage();
  final FakeExporter exporter = FakeExporter();
  final FakeBackupGuard backup = FakeBackupGuard();
  final StreamController<String?> auth = StreamController<String?>.broadcast();
  String? uid = 'user-a';
  int legacy = 0;
  final List<ScannerViewModel> built = <ScannerViewModel>[];

  Directory get staging => Directory(p.join(temp.path, 'staging'));

  ScannerViewModel build({
    ScannerFileCopier? copier,
    ScannerCloudFactory? cloudFactory,
  }) {
    final vm = ScannerViewModel(
      engine: engine,
      baseDirectory: () async => base,
      stager: ScanSourceStager(
        roots: () async => ScannerRoots(
          stagingDir: staging,
          trusted: <Directory>[output],
          scannerOutputDirs: <Directory>[output],
        ),
      ),
      inspector: testInspector(),
      usage: usage,
      sharePreparer: ScannerSharePreparer(tempRoot: () async => temp),
      exporter: exporter,
      backup: backup,
      currentUserId: () => uid,
      userIdChanges: auth.stream,
      legacyDocumentCount: () async => legacy,
      cloudFactory: cloudFactory,
      copier: copier,
    );
    built.add(vm);
    return vm;
  }

  Future<ScannerViewModel> started({
    ScannerFileCopier? copier,
    ScannerCloudFactory? cloudFactory,
  }) async {
    final vm = build(copier: copier, cloudFactory: cloudFactory);
    await vm.start();
    return vm;
  }

  Future<String> pdf(int pages, [String name = 'scan']) async =>
      (await writeFile(output, '$name-$pages.pdf', await pdfBytes(pages))).path;

  Future<String> jpeg(int seed) async =>
      (await writeFile(output, 'page-$seed.jpg', jpegBytes(seed: seed))).path;

  Future<void> switchTo(ScannerViewModel vm, String? next) async {
    uid = next;
    auth.add(next);
    await settle(() => vm.userId == next && !vm.isLoading);
  }

  List<String> outputFiles() => relativeFiles(output);

  Future<void> close() async {
    // Work the view model started in the background (a comparison with the
    // user's account, an upload) may still be reading a file: it finishes before
    // the folders are removed (Windows refuses to delete a folder with an open
    // file in it).
    for (final vm in built) {
      await vm.settle();
    }
    for (final vm in built) {
      if (!vm.isDisposedForTest) vm.dispose();
    }
    await auth.close();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // A widget test may still hold a decoded image file open on Windows.
    }
  }
}

extension on ScannerViewModel {
  // ChangeNotifier exposes no public flag; dispose is idempotent for tests by
  // catching the second call.
  bool get isDisposedForTest {
    try {
      addListener(() {});
      return false;
    } catch (_) {
      return true;
    }
  }
}

/// Waits (in real time: file work finishes on other threads) until [done].
Future<void> settle(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('condition was never reached');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<ScanStartResult> scanOnce(ScannerViewModel vm) =>
    vm.startScan(allowNewScan: (_) async => true);
