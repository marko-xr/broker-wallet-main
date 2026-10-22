import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_page_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';
import 'package:broker_wallet/src/services/signature/signature_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_stamp_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_store.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_library_viewmodel.dart';

import '../combine_pdf/combine_fixtures.dart'
    show PageSpec, buildPdf, makeTempDir, writeFile;

// The real PDFs the Signature tests use are the ones Combine PDF's tests
// already build with the same PDF library the app uses (links, form fields,
// markup, encryption, a genuine digital signature, a hand-written CropBox).
export '../combine_pdf/combine_fixtures.dart'
    show
        PageSpec,
        PdfFacts,
        a4,
        a4Landscape,
        buildPdf,
        cropBoxPdf,
        makeTempDir,
        readPdf,
        relativeFiles,
        writeFile;

const int testMaxBytes = SignatureLimits.maxSourceBytes;

/// The analysis of [file], as the app reads it.
SignatureAnalysis analysisOf(File file) =>
    analyzeSignaturePdf(file.path, maxBytes: testMaxBytes);

/// A one-page PDF written by hand, so its boxes and rotation are exactly what the
/// test says: [media] and [crop] are PDF arrays such as `[0 0 612 792]`
/// (null leaves the entry out), [rotate] is `/Rotate`, and [inherit] puts all
/// three on the page tree node instead of the page.
Uint8List pdfWithBoxes({
  String? media = '[0 0 612 792]',
  String? crop,
  int? rotate,
  bool inherit = false,
}) {
  const content = 'BT /F1 24 Tf 150 500 Td (Boxes) Tj ET';
  final entries = <String>[
    if (media != null) '/MediaBox $media',
    if (crop != null) '/CropBox $crop',
    if (rotate != null) '/Rotate $rotate',
  ].join(' ');
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 ${inherit ? entries : ''} >>',
    '<< /Type /Page /Parent 2 0 R ${inherit ? '' : entries} '
        '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(out.toString()));
}

// --------------------------------------------------------------------- images

/// A transparent PNG with an opaque filled box inside it (so the aspect ratio
/// and the transparent margin are both checkable).
Uint8List stampPng({int width = 240, int height = 80, int color = 0xFF1B1B1B}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fillRect(
    image,
    x1: 6,
    y1: 6,
    x2: width - 7,
    y2: height - 7,
    color: img.ColorRgba8((color >> 16) & 0xFF, (color >> 8) & 0xFF,
        color & 0xFF, (color >> 24) & 0xFF),
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// A 4 x 2 PNG whose only opaque pixel is the top-left one, to tell how an image
/// was turned.
Uint8List markedPng() {
  final image = img.Image(width: 4, height: 2, numChannels: 4);
  image.setPixelRgba(0, 0, 255, 0, 0, 255);
  return Uint8List.fromList(img.encodePng(image));
}

/// Where the only opaque pixel of [png] is, and the image's size.
({int x, int y, int width, int height}) markOf(Uint8List png) {
  final image = img.decodePng(png)!;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a > 0) {
        return (x: x, y: y, width: image.width, height: image.height);
      }
    }
  }
  throw StateError('no opaque pixel');
}

/// A drawing of a stroke across a pad, the way the pad would hand it over.
SignatureDrawing drawingOf({
  double width = 300,
  double height = 120,
  int colorValue = 0xFF000000,
  double strokeWidth = 3.5,
  bool twoStrokes = false,
}) {
  final points = <InkPoint>[
    const InkPoint(20, 80, isStrokeStart: true),
    const InkPoint(60, 40),
    const InkPoint(110, 90),
    const InkPoint(170, 30),
    const InkPoint(250, 70),
    if (twoStrokes) ...const [
      InkPoint(30, 100, isStrokeStart: true),
      InkPoint(240, 105),
    ],
  ];
  return SignatureDrawing(
    points: points,
    colorValue: colorValue,
    strokeWidth: strokeWidth,
    canvasWidth: width,
    canvasHeight: height,
  );
}

/// Waits (in real time, up to [timeout]) until [condition] holds and says
/// whether it did. For work the code under test starts and does not await, such
/// as the removal of a discarded draft.
Future<bool> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return condition();
}

class FakeStampRenderer implements StampRenderer {
  int drawings = 0;
  int texts = 0;
  Object? failWith;

  @override
  Future<StampAsset> renderDrawing({
    required String id,
    required StampKind kind,
    required SignatureDrawing drawing,
  }) async {
    final error = failWith;
    if (error != null) throw error;
    drawings++;
    final width = kind == StampKind.initials ? 120 : 240;
    return StampAsset(
      id: id,
      kind: kind,
      png: stampPng(width: width, height: 80, color: drawing.colorValue),
      pixelWidth: width,
      pixelHeight: 80,
      drawing: drawing,
      colorValue: drawing.colorValue,
    );
  }

  @override
  Future<StampAsset> renderText({
    required String id,
    required StampKind kind,
    required String text,
    required int colorValue,
  }) async {
    final error = failWith;
    if (error != null) throw error;
    texts++;
    final width = 20 + 10 * text.runes.length;
    return StampAsset(
      id: id,
      kind: kind,
      png: stampPng(width: width, height: 40, color: colorValue),
      pixelWidth: width,
      pixelHeight: 40,
      label: text,
      colorValue: colorValue,
    );
  }
}

// --------------------------------------------------------- exported geometry

/// An image the signed copy draws, as the page's user space sees it.
class DrawnImage {
  const DrawnImage(this.rect, this.axisAligned);

  final UserRect rect;

  /// The matrix has no rotation or skew, so the image is upright in user space.
  final bool axisAligned;
}

/// The streams of an incremental update: the bytes after [originalLength],
/// inflated where they are compressed.
List<String> appendedStreams(Uint8List output, int originalLength) {
  final tail = output.sublist(originalLength);
  final text = latin1.decode(tail);
  final result = <String>[];
  for (final match in RegExp(r'(?<!end)stream\r?\n').allMatches(text)) {
    final start = match.end;
    final end = text.indexOf('endstream', start);
    if (end < 0) continue;
    final data = tail.sublist(start, end);
    String? decoded;
    for (var trim = 0; trim <= 2 && decoded == null; trim++) {
      if (data.length - trim <= 0) break;
      try {
        decoded =
            latin1.decode(zlib.decode(data.sublist(0, data.length - trim)));
      } catch (_) {
        decoded = null;
      }
    }
    result.add(decoded ?? latin1.decode(data));
  }
  return result;
}

List<double> _mul(List<double> m, List<double> n) => <double>[
      m[0] * n[0] + m[1] * n[2],
      m[0] * n[1] + m[1] * n[3],
      m[2] * n[0] + m[3] * n[2],
      m[2] * n[1] + m[3] * n[3],
      m[4] * n[0] + m[5] * n[2] + n[4],
      m[4] * n[1] + m[5] * n[3] + n[5],
    ];

/// Every image the content streams of the appended update draw, with the place it
/// lands in user space. A small content-stream reader (`q`, `Q`, `cm`, `Do`):
/// it is how the tests prove where a stamp really is in the saved file, without
/// trusting the engine's own arithmetic.
List<DrawnImage> imagesDrawnByUpdate(Uint8List output, int originalLength) {
  final drawn = <DrawnImage>[];
  for (final stream in appendedStreams(output, originalLength)) {
    if (!stream.contains(' Do') && !stream.contains('\nDo')) continue;
    final cleaned = stream.replaceAll(RegExp(r'%[^\r\n]*'), ' ');
    final tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    var ctm = <double>[1, 0, 0, 1, 0, 0];
    final saved = <List<double>>[];
    final operands = <double>[];
    for (final token in tokens) {
      final number = double.tryParse(token);
      if (number != null) {
        operands.add(number);
        continue;
      }
      switch (token) {
        case 'q':
          saved.add(List<double>.of(ctm));
        case 'Q':
          if (saved.isNotEmpty) ctm = saved.removeLast();
        case 'cm':
          if (operands.length >= 6) {
            final m = operands.sublist(operands.length - 6);
            ctm = _mul(m, ctm);
          }
        case 'Do':
          final xs = <double>[];
          final ys = <double>[];
          for (final corner in const [
            [0.0, 0.0],
            [1.0, 0.0],
            [0.0, 1.0],
            [1.0, 1.0],
          ]) {
            xs.add(corner[0] * ctm[0] + corner[1] * ctm[2] + ctm[4]);
            ys.add(corner[0] * ctm[1] + corner[1] * ctm[3] + ctm[5]);
          }
          final left = xs.reduce((a, b) => a < b ? a : b);
          final right = xs.reduce((a, b) => a > b ? a : b);
          final bottom = ys.reduce((a, b) => a < b ? a : b);
          final top = ys.reduce((a, b) => a > b ? a : b);
          drawn.add(DrawnImage(
            UserRect(left, bottom, right - left, top - bottom),
            ctm[1].abs() < 1e-6 && ctm[2].abs() < 1e-6,
          ));
      }
      operands.clear();
    }
  }
  return drawn;
}

/// A job that writes [placements] (page index, rectangle in visible points) of
/// [source] to [output], using one [png] for all of them.
SignatureWriteJob jobFor(
  File source,
  String outputPath,
  List<({int page, PageRect rect})> placements, {
  Uint8List? png,
  SignatureAnalysis? analysis,
}) {
  return SignatureWriteJob(
    sourcePath: source.path,
    source: analysis ?? analysisOf(source),
    images: <Uint8List>[png ?? stampPng()],
    placements: <SignatureWritePlacement>[
      for (final item in placements)
        SignatureWritePlacement(
            pageIndex: item.page, imageIndex: 0, rect: item.rect),
    ],
    outputPath: outputPath,
  );
}

// ------------------------------------------------------------------- doubles

class FakeSignaturePicker implements SignaturePdfPicker {
  PickedSignaturePdf? next;
  Completer<void>? gate;
  int clears = 0;
  int picks = 0;

  @override
  Future<PickedSignaturePdf?> pick() async {
    picks++;
    if (gate != null) await gate!.future;
    return next;
  }

  @override
  Future<void> clearPickedCopies() async {
    clears++;
  }
}

class RecordingSignatureUsage implements SignatureUsageRecorder {
  final List<String> recorded = <String>[];

  @override
  Future<void> recordSignedDocument(String userId) async {
    recorded.add(userId);
  }
}

class FakeSignatureExporter implements SignaturePdfExporter {
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

/// Reports the geometry of the file's own pages (what a faithful renderer
/// would) and draws nothing.
class FakePageRenderer implements SignaturePageRenderer {
  FakePageRenderer({this.sizes, this.failOpenWith});

  /// Overrides what [open] reports; by default the file's own geometry.
  final List<RenderedPageSize>? sizes;
  final SignatureFailure? failOpenWith;
  String? openedPath;
  bool disposed = false;

  @override
  Future<List<RenderedPageSize>> open(String path) async {
    openedPath = path;
    final failure = failOpenWith;
    if (failure != null) throw SignatureException(failure);
    final reported = sizes;
    if (reported != null) return reported;
    final analysis = analyzeSignaturePdf(path, maxBytes: testMaxBytes);
    return <RenderedPageSize>[
      for (final page in analysis.pages)
        RenderedPageSize(page.width, page.height),
    ];
  }

  @override
  Future<ui.Image?> render(int pageIndex, {required int pixelWidth}) async =>
      null;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// An executor that blocks a write until released, to test cancellation, double
/// taps and account switches while work is running.
class GatedSignatureExecutor implements SignatureExecutor {
  GatedSignatureExecutor(this.inner);

  final SignatureExecutor inner;
  final Completer<void> started = Completer<void>();
  Completer<void>? release;
  int writes = 0;

  @override
  Future<SignatureAnalysis> analyze(String path, {int? maxBytes}) =>
      inner.analyze(path, maxBytes: maxBytes);

  @override
  Future<SignatureWriteResult> write(
      SignatureWriteJob job, SignatureCancelToken token) async {
    writes++;
    if (!started.isCompleted) started.complete();
    final gate = release;
    if (gate != null) {
      await gate.future;
      if (token.isCancelled) {
        throw const SignatureException(SignatureFailure.cancelled);
      }
    }
    return inner.write(job, token);
  }
}

/// A library view model wired to temporary folders and doubles.
class SignatureHarness {
  SignatureHarness({
    SignatureExecutor? executor,
    String? Function()? userId,
    String initialUser = 'user-a',
    FakeSignaturePicker? picker,
    DateTime Function()? clock,
    SignatureFileCopier? copier,
    Future<int> Function()? legacyCount,
    bool singleSubscriptionAuth = true,
    Stream<String?>? authStream,
    SignatureCloudFactory? cloudFactory,
  })  : base = makeTempDir('sig_base'),
        temp = makeTempDir('sig_temp'),
        inputs = makeTempDir('sig_in'),
        picker = picker ?? FakeSignaturePicker(),
        usage = RecordingSignatureUsage(),
        exporter = FakeSignatureExporter(),
        backup = RecordingBackup(),
        stamps = FakeStampRenderer(),
        // The real auth repository hands out a stream that can be listened to
        // once, so that is the default here: a test that listens twice must fail.
        _users = singleSubscriptionAuth
            ? StreamController<String?>()
            : StreamController<String?>.broadcast(),
        _user = initialUser {
    var counter = 0;
    viewModel = SignatureLibraryViewModel(
      executor: executor ?? const InlineSignatureExecutor(),
      baseDirectory: () async => base,
      picker: this.picker,
      usage: usage,
      sharePreparer: SignatureSharePreparer(tempRoot: () async => temp),
      exporter: exporter,
      backup: backup,
      stampRenderer: stamps,
      currentUserId: userId ?? () => _user,
      userIdChanges: authStream ?? _users.stream,
      clock: clock ?? () => DateTime.utc(2026, 10, 18, 9, 30),
      idGenerator: () => 'id${counter++}',
      copier: copier,
      legacyDocumentCount: legacyCount,
      cloudFactory: cloudFactory,
    );
  }

  final Directory base;
  final Directory temp;
  final Directory inputs;
  final FakeSignaturePicker picker;
  final RecordingSignatureUsage usage;
  final FakeSignatureExporter exporter;
  final RecordingBackup backup;
  final FakeStampRenderer stamps;
  final StreamController<String?> _users;
  String? _user;
  late final SignatureLibraryViewModel viewModel;
  final List<SignatureEditorViewModel> _sessions = <SignatureEditorViewModel>[];

  String? get user => _user;

  /// Switches the signed-in account, as the auth stream would report it.
  Future<void> switchTo(String? uid) async {
    _user = uid;
    _users.add(uid);
    await pumpFutures();
    // The account's folder is read from disk: wait for that to finish.
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

  Future<File> pdf(String name, String tag,
      {int count = 3, List<PageSpec>? pages}) {
    return writeFile(inputs, name, buildPdf(tag, count: count, pages: pages));
  }

  /// Opens [file] for signing, as a pick would.
  Future<SignatureOpenOutcome> open(File file, {String? name}) {
    return viewModel.openPicked(PickedSignaturePdf(
        path: file.path, name: name ?? p.basename(file.path)));
  }

  /// Opens [file] and expects an editing session.
  Future<SignatureEditorViewModel> session(File file, {String? name}) async {
    final outcome = await open(file, name: name);
    final session = outcome.session;
    if (session == null) {
      throw StateError('not opened: ${outcome.failure}');
    }
    _sessions.add(session);
    return session;
  }

  /// A signature drawn and placed on [page] of [session].
  Future<PlacedStamp> place(SignatureEditorViewModel session,
      {int page = 0, StampKind kind = StampKind.signature}) async {
    final asset = kind == StampKind.signature || kind == StampKind.initials
        ? await session.createDrawnAsset(kind, drawingOf())
        : await session.createTextAsset(kind, 'Text', 0xFF000000);
    return session.place(asset, page);
  }

  Future<SignatureSaveOutcome> save(SignatureEditorViewModel session,
      {String name = 'Lease signed', bool allow = true}) async {
    final failure = await session.buildDraft();
    if (failure != null) throw StateError('draft failed: $failure');
    return session.save(name: name, allowNew: (uid) async => allow);
  }

  Future<void> dispose() async {
    for (final session in _sessions) {
      session.dispose();
    }
    viewModel.dispose();
    // A single-subscription controller that nobody listened to completes its
    // close only when somebody does, so it is not waited for.
    if (_users.hasListener) {
      await _users.close();
    } else {
      unawaited(_users.close());
    }
    for (final d in [base, temp, inputs]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  }
}
