import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_executor.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_platform.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_store.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_usage_gate.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart';

import 'image_pdf_fixtures.dart';

Directory makeTempDir(String prefix) =>
    Directory.systemTemp.createTempSync('bw_i2p_$prefix');

/// Every file under [dir] as paths relative to it, sorted.
List<String> relativeFiles(Directory dir) {
  if (!dir.existsSync()) return <String>[];
  final names = <String>[
    for (final item in dir.listSync(recursive: true, followLinks: false))
      if (item is File)
        p.relative(item.path, from: dir.path).replaceAll(r'\', '/'),
  ];
  names.sort();
  return names;
}

class FakeImagePicker implements ImagePdfImagePicker {
  List<PickedImage>? gallery;
  PickedImage? photo;
  Object? failWith;
  Completer<void>? gate;
  int picks = 0;

  /// What Android would hand back after the app was stopped mid-pick.
  List<PickedImage> lost = const <PickedImage>[];
  int recoveries = 0;

  @override
  Future<List<PickedImage>> recoverLostPicks() async {
    recoveries++;
    final answer = lost;
    lost = const <PickedImage>[];
    return answer;
  }

  @override
  Future<List<PickedImage>?> pickFromGallery() async {
    picks++;
    if (gate != null) await gate!.future;
    final error = failWith;
    if (error != null) throw error;
    return gallery;
  }

  @override
  Future<PickedImage?> capturePhoto() async {
    picks++;
    if (gate != null) await gate!.future;
    final error = failWith;
    if (error != null) throw error;
    return photo;
  }
}

class FakeNormalizer implements ImagePdfImageNormalizer {
  bool succeed = true;
  int calls = 0;

  @override
  Future<File?> heicToJpeg(File source, File target) async {
    calls++;
    if (!succeed) return null;
    await target.writeAsBytes(jpeg(marked(120, 90)));
    return target;
  }
}

class RecordingUsage implements ImagePdfUsageRecorder {
  final List<String> recorded = <String>[];

  @override
  Future<void> recordConversion(String userId) async {
    recorded.add(userId);
  }
}

class FakeExporter implements ImagePdfExporter {
  final List<String> names = <String>[];
  Object? failWith;
  ScannerExportResult result = const ScannerExportResult.saved(
      ScannerExportDestination.downloads, 'x.pdf');

  @override
  Future<ScannerExportResult> export(String fileName, File file) async {
    final error = failWith;
    if (error != null) throw error;
    if (!file.existsSync()) throw const FileSystemException('gone');
    names.add(fileName);
    return result;
  }
}

class RecordingBackup implements ScannerBackupGuard {
  final List<String> excluded = <String>[];

  @override
  Future<bool> exclude(String path) async {
    excluded.add(path);
    return true;
  }
}

/// An executor that can hold a conversion (or a picture check) until released,
/// to test cancellation, double taps and account switches while work runs.
class GatedExecutor implements ImagePdfExecutor {
  GatedExecutor(this.inner);

  final ImagePdfExecutor inner;
  Completer<void> buildStarted = Completer<void>();
  Completer<void>? releaseBuild;
  Completer<void>? releaseAnalysis;
  int builds = 0;
  int analyses = 0;
  ImagePdfBuildJob? lastJob;

  @override
  Future<ImageAnalysis> analyzeImage(String path) async {
    analyses++;
    final gate = releaseAnalysis;
    if (gate != null) await gate.future;
    return inner.analyzeImage(path);
  }

  @override
  Future<ImagePdfFileInfo> analyzePdf(String path, {String? password}) =>
      inner.analyzePdf(path, password: password);

  @override
  Future<ImagePdfBuildResult> build(
      ImagePdfBuildJob job, ImagePdfCancelToken token) async {
    builds++;
    lastJob = job;
    if (!buildStarted.isCompleted) buildStarted.complete();
    final gate = releaseBuild;
    if (gate != null) {
      await gate.future;
      if (token.isCancelled) {
        throw const ImagePdfException(ImagePdfFailure.cancelled);
      }
    }
    return inner.build(job, token);
  }
}

/// A view model wired to temporary folders and doubles.
class ImagePdfHarness {
  ImagePdfHarness({
    ImagePdfExecutor? executor,
    String? Function()? userId,
    String initialUser = 'user-a',
    FakeImagePicker? picker,
    DateTime Function()? clock,
    ImagePdfFileCopier? copier,
    Future<int> Function()? legacyCount,
    bool pickerCopiesInTemp = false,
    ImagePdfCloudFactory? cloudFactory,
  })  : base = makeTempDir('base'),
        temp = makeTempDir('temp'),
        inputs = makeTempDir('in'),
        picker = picker ?? FakeImagePicker(),
        normalizer = FakeNormalizer(),
        usage = RecordingUsage(),
        exporter = FakeExporter(),
        backup = RecordingBackup(),
        _user = initialUser {
    var counter = 0;
    viewModel = ImagePdfViewModel(
      executor: executor ?? const InlineImagePdfExecutor(),
      baseDirectory: () async => base,
      picker: this.picker,
      normalizer: normalizer,
      usage: usage,
      sharePreparer: ImagePdfSharePreparer(tempRoot: () async => temp),
      exporter: exporter,
      backup: backup,
      currentUserId: userId ?? () => _user,
      userIdChanges: _users.stream,
      loadUnicodeFont: () async => arabicFontBytes(),
      tempRoot: pickerCopiesInTemp ? () async => inputs : () async => temp,
      legacyDocumentCount: legacyCount,
      clock: clock ?? () => DateTime(2026, 10, 18, 9, 30),
      idGenerator: () => 'id${counter++}',
      copier: copier,
      cloudFactory: cloudFactory,
    );
  }

  final Directory base;
  final Directory temp;
  final Directory inputs;
  final FakeImagePicker picker;
  final FakeNormalizer normalizer;
  final RecordingUsage usage;
  final FakeExporter exporter;
  final RecordingBackup backup;
  final StreamController<String?> _users =
      StreamController<String?>.broadcast();
  String? _user;
  late final ImagePdfViewModel viewModel;

  String? get user => _user;

  /// Switches the signed-in account, as the auth stream would report it.
  Future<void> switchTo(String? uid) async {
    _user = uid;
    _users.add(uid);
    await pumpFutures();
    for (var i = 0; i < 300; i++) {
      if (viewModel.userId == uid && !viewModel.isLoading) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void addAuthError() => _users.addError(StateError('auth stream error'));

  Future<void> pumpFutures() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// A JPEG picture file in the pretend gallery.
  File jpegFile(String name,
      {int w = 400,
      int h = 300,
      int r = 40,
      int g = 120,
      int b = 200,
      int? orientation}) {
    final image = img.Image(width: w, height: h)..clear(img.ColorRgb8(r, g, b));
    final file = File(p.join(inputs.path, name));
    file.writeAsBytesSync(jpeg(image, quality: 92, orientation: orientation));
    return file;
  }

  File rawFile(String name, List<int> bytes) {
    final file = File(p.join(inputs.path, name));
    file.writeAsBytesSync(bytes);
    return file;
  }

  /// Adds the given files through the view model, as a pick would.
  Future<AddImagesOutcome> add(List<File> files) {
    return viewModel.addPickedImages([
      for (final f in files) PickedImage(path: f.path, name: p.basename(f.path))
    ]);
  }

  /// Waits until every selected picture has been read and checked.
  Future<void> waitChecked() async {
    for (var i = 0; i < 1000 && viewModel.isChecking; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (viewModel.isChecking) throw StateError('pictures were never checked');
  }

  Future<AddImagesOutcome> addAndCheck(List<File> files) async {
    final outcome = await add(files);
    await waitChecked();
    return outcome;
  }

  Future<DraftOutcome> prepare({
    String title = 'Villa',
    ImagePdfTexts texts = const ImagePdfTexts(),
    bool allow = true,
    List<String>? asked,
  }) {
    return viewModel.prepareDraft(
      title: title,
      coverTexts: texts,
      allowNewConversion: (uid) async {
        asked?.add(uid);
        return allow;
      },
    );
  }

  Directory accountDir([String? uid]) =>
      ImagePdfStore.accountDirectory(base, uid ?? _user!);

  Future<void> dispose() async {
    viewModel.dispose();
    await _users.close();
    for (final d in [base, temp, inputs]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  }
}

Uint8List noBytes() => Uint8List(0);
