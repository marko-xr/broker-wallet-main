import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:broker_wallet/src/services/combine_pdf/combine_executor.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_platform.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_store.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart';

import 'test_certificate.dart';

/// One page of a generated PDF.
class PageSpec {
  const PageSpec(this.width, this.height,
      {this.rotate = PdfPageRotateAngle.rotateAngle0});

  final double width;
  final double height;
  final PdfPageRotateAngle rotate;
}

const PageSpec a4 = PageSpec(595, 842);
const PageSpec a4Landscape = PageSpec(842, 595);

/// A real PDF made by the same library the app uses. Every page carries the
/// text "[tag] page N", so order is checkable by reading the output back.
///
/// The optional features are real PDF structures: a link, a filled text field,
/// a markup annotation (with an appearance), a bookmark, an embedded TrueType
/// font, encryption and a genuine digital signature.
Uint8List buildPdf(
  String tag, {
  List<PageSpec>? pages,
  int count = 3,
  bool link = false,
  bool form = false,
  bool markup = false,
  bool bookmark = false,
  Uint8List? fontBytes,
  String? userPassword,
  String? ownerPassword,
  bool sign = false,
}) {
  final specs = pages ?? List<PageSpec>.filled(count, a4);
  final document = PdfDocument();
  final font = fontBytes == null
      ? PdfStandardFont(PdfFontFamily.helvetica, 20)
      : PdfTrueTypeFont(fontBytes, 20);
  PdfPage? firstPage;
  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    final section = document.sections!.add();
    section.pageSettings.margins.all = 0;
    section.pageSettings.orientation = spec.width > spec.height
        ? PdfPageOrientation.landscape
        : PdfPageOrientation.portrait;
    section.pageSettings.size = Size(spec.width, spec.height);
    section.pageSettings.rotate = spec.rotate;
    final page = section.pages.add();
    firstPage ??= page;
    page.graphics.drawString('$tag page ${i + 1}', font,
        bounds: const Rect.fromLTWH(40, 40, 300, 40));
  }
  final first = firstPage!;
  if (link) {
    first.annotations.add(PdfUriAnnotation(
        bounds: const Rect.fromLTWH(40, 100, 100, 20),
        uri: 'https://example.com'));
  }
  if (markup) {
    first.annotations.add(PdfRectangleAnnotation(
        const Rect.fromLTWH(40, 140, 120, 30), 'Marked',
        color: PdfColor(255, 0, 0), setAppearance: true));
  }
  if (form) {
    document.form.fields.add(PdfTextBoxField(
        first, 'name', const Rect.fromLTWH(40, 200, 220, 30),
        text: 'filled value'));
  }
  if (bookmark) document.bookmarks.add('Bookmark $tag');
  if (sign) {
    document.form.fields.add(PdfSignatureField(
      first,
      'sig',
      bounds: const Rect.fromLTWH(40, 260, 200, 60),
      signature: PdfSignature(
        certificate:
            PdfCertificate(testCertificateBytes(), testCertificatePassword),
        reason: 'test',
      ),
    ));
  }
  if (userPassword != null || ownerPassword != null) {
    document.security.algorithm = PdfEncryptionAlgorithm.aesx128Bit;
    if (userPassword != null) document.security.userPassword = userPassword;
    if (ownerPassword != null) document.security.ownerPassword = ownerPassword;
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

/// A PDF whose page has a CropBox that does not start at the origin and a
/// /Rotate entry, written by hand so the structure is exactly known.
Uint8List cropBoxPdf({int rotate = 0}) {
  const content = 'BT /F1 24 Tf 150 500 Td (Crop page) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/CropBox [100 100 500 600] /Rotate $rotate '
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

/// What a PDF holds, read back with the library.
class PdfFacts {
  PdfFacts(this.pageCount, this.sizes, this.rotations, this.texts,
      this.annotationCount, this.formFieldCount, this.bookmarkCount);

  final int pageCount;
  final List<Size> sizes;
  final List<int> rotations;
  final List<String> texts;
  final int annotationCount;
  final int formFieldCount;
  final int bookmarkCount;
}

PdfFacts readPdf(List<int> bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    final extractor = PdfTextExtractor(document);
    final sizes = <Size>[];
    final rotations = <int>[];
    final texts = <String>[];
    var annotations = 0;
    for (var i = 0; i < document.pages.count; i++) {
      final page = document.pages[i];
      sizes.add(page.size);
      rotations.add(page.rotation.index);
      annotations += page.annotations.count;
      texts.add(extractor
          .extractText(startPageIndex: i, endPageIndex: i)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim());
    }
    return PdfFacts(document.pages.count, sizes, rotations, texts, annotations,
        document.form.fields.count, document.bookmarks.count);
  } finally {
    document.dispose();
  }
}

Future<File> writeFile(Directory dir, String name, List<int> bytes) async {
  final file = File(p.join(dir.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Directory makeTempDir(String prefix) =>
    Directory.systemTemp.createTempSync('bw_combine_$prefix');

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

/// A [CombineSource] for an existing PDF file, as the app would build it.
Future<CombineSource> sourceOf(File file,
    {String? id, String? name, CombineExecutor? executor}) async {
  final analysis =
      await (executor ?? const InlineCombineExecutor()).analyze(file.path);
  return CombineSource(
    id: id ?? p.basenameWithoutExtension(file.path),
    path: file.path,
    displayName: name ?? p.basename(file.path),
    size: analysis.size,
    pageCount: analysis.pageCount,
    features: analysis.features,
  );
}

// ------------------------------------------------------------------ doubles

class FakePicker implements CombinePdfPicker {
  FakePicker();

  List<PickedPdf>? next;
  Completer<void>? gate;
  int clears = 0;
  int picks = 0;

  @override
  Future<List<PickedPdf>?> pick() async {
    picks++;
    if (gate != null) await gate!.future;
    return next;
  }

  @override
  Future<void> clearPickedCopies() async {
    clears++;
  }
}

class RecordingUsage implements CombineUsageRecorder {
  final List<String> recorded = <String>[];

  @override
  Future<void> recordCombine(String userId) async {
    recorded.add(userId);
  }
}

class FakeCombineExporter implements CombinePdfExporter {
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

/// An executor that blocks a combine until released, to test cancellation,
/// double taps and account switches while work is running.
class GatedExecutor implements CombineExecutor {
  GatedExecutor(this.inner);

  final CombineExecutor inner;
  final Completer<void> started = Completer<void>();
  Completer<void>? release;
  int merges = 0;

  @override
  Future<CombineAnalysis> analyze(String path, {int? maxBytes}) =>
      inner.analyze(path, maxBytes: maxBytes);

  @override
  Future<CombineMergeResult> merge(
      CombineMergeJob job, CombineCancelToken token) async {
    merges++;
    if (!started.isCompleted) started.complete();
    final gate = release;
    if (gate != null) {
      await gate.future;
      if (token.isCancelled) {
        throw const CombinePdfException(CombinePdfFailure.cancelled);
      }
    }
    return inner.merge(job, token);
  }
}

/// A view model wired to temporary folders and doubles.
class CombineHarness {
  CombineHarness({
    CombineExecutor? executor,
    String? Function()? userId,
    String initialUser = 'user-a',
    FakePicker? picker,
    DateTime Function()? clock,
    CombineFileCopier? copier,
  })  : base = makeTempDir('base'),
        temp = makeTempDir('temp'),
        inputs = makeTempDir('in'),
        picker = picker ?? FakePicker(),
        usage = RecordingUsage(),
        exporter = FakeCombineExporter(),
        backup = RecordingBackup(),
        _user = initialUser {
    var counter = 0;
    viewModel = CombinePdfViewModel(
      executor: executor ?? const InlineCombineExecutor(),
      baseDirectory: () async => base,
      picker: this.picker,
      usage: usage,
      sharePreparer: CombineSharePreparer(tempRoot: () async => temp),
      exporter: exporter,
      backup: backup,
      currentUserId: userId ?? () => _user,
      userIdChanges: _users.stream,
      clock: clock ?? () => DateTime.utc(2026, 10, 18, 9, 30),
      idGenerator: () => 'id${counter++}',
      copier: copier,
    );
  }

  final Directory base;
  final Directory temp;
  final Directory inputs;
  final FakePicker picker;
  final RecordingUsage usage;
  final FakeCombineExporter exporter;
  final RecordingBackup backup;
  final StreamController<String?> _users =
      StreamController<String?>.broadcast();
  String? _user;
  late final CombinePdfViewModel viewModel;

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

  /// Adds the given files through the view model, as a pick would.
  Future<AddFilesOutcome> add(List<File> files) {
    return viewModel.addPickedFiles([
      for (final f in files) PickedPdf(path: f.path, name: p.basename(f.path))
    ]);
  }

  Future<CombineOutcome> combine({String? name, bool allow = true}) {
    return viewModel.combine(name: name, allowNewCombine: (uid) async => allow);
  }

  Future<void> dispose() async {
    viewModel.dispose();
    await _users.close();
    for (final d in [base, temp, inputs]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  }
}
