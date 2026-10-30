import 'dart:io';

import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_store.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_library_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../signature/signature_fixtures.dart';
import 'responsive_harness.dart';

/// Representative R7B viewports crossed with locale, theme, text scale and
/// intrusions. Sampled, not the full cross product.
List<ResponsiveCase> r7bCases() {
  const portrait = <Size>[
    Size(280, 600),
    Size(320, 568),
    Size(360, 640),
    Size(393, 852),
    Size(430, 932),
    Size(600, 800),
    Size(800, 1280),
  ];
  const scales = <double>[1.0, 1.3, 1.6, 2.0];
  final cases = <ResponsiveCase>[];
  for (var i = 0; i < portrait.length; i++) {
    for (var s = 0; s < scales.length; s++) {
      cases.add(ResponsiveCase(
        portrait[i],
        locale: (i + s).isEven ? const Locale('en') : const Locale('ar'),
        dark: s.isOdd,
        textScale: scales[s],
        safeArea: const EdgeInsets.only(top: 24, bottom: 16),
      ));
    }
  }
  for (var s = 0; s < scales.length; s++) {
    cases.add(ResponsiveCase(
      const Size(640, 360),
      locale: s.isEven ? const Locale('ar') : const Locale('en'),
      dark: s.isEven,
      textScale: scales[s],
      safeArea: const EdgeInsets.only(left: 24, right: 24, bottom: 8),
    ));
  }
  return cases;
}

/// The control must be fully inside the window, so it can be reached.
void expectOnScreen(WidgetTester tester, Finder finder, ResponsiveCase c) {
  expect(finder, findsWidgets, reason: c.toString());
  final rect = tester.getRect(finder.first);
  final window = Offset.zero & c.size;
  expect(
    window.inflate(0.5).contains(rect.topLeft) &&
        window.inflate(0.5).contains(rect.bottomRight),
    isTrue,
    reason: '$finder at $rect is outside $window; $c',
  );
}

SignedDocument r7bDocument(
  int n, {
  String? name,
  int pages = 3,
  int size = 482133,
}) =>
    SignedDocument(
      id: 'doc$n',
      fileName: 'doc$n.pdf',
      name: name ?? 'Signed lease $n',
      createdAt: DateTime.utc(2026, 10, 18, 9, 30),
      fileSize: size,
      pageCount: pages,
      signatureCount: 2,
      itemCount: 4,
    );

const longEnglishName =
    'Annual tenancy contract renewal for Marina Heights tower apartment 2104 signed copy';
const longArabicName =
    'عقد إيجار سنوي مجدد لشقة رقم ٢١٠٤ في برج مرسى الارتفاعات مع الملاحق الموقعة';

/// A library view model that serves what the test says, with no store, cloud,
/// disk or picker behind it. Only what the screen reads is overridden.
class FakeSignatureLibrary extends SignatureLibraryViewModel {
  FakeSignatureLibrary({
    List<SignedDocument> documents = const <SignedDocument>[],
    this.loading = false,
    this.waiting = false,
    this.failed = false,
    this.fetching = false,
    Set<String> missing = const <String>{},
  })  : docs = documents,
        _missing = missing,
        super(
          executor: const InlineSignatureExecutor(),
          baseDirectory: () async => Directory.systemTemp,
          picker: FakeSignaturePicker(),
          usage: RecordingSignatureUsage(),
          sharePreparer: SignatureSharePreparer(
              tempRoot: () async => Directory.systemTemp),
          exporter: FakeSignatureExporter(),
          backup: RecordingBackup(),
          stampRenderer: FakeStampRenderer(),
          currentUserId: () => 'user-a',
          userIdChanges: const Stream<String?>.empty(),
        );

  List<SignedDocument> docs;
  bool loading;
  bool waiting;
  bool failed;
  bool fetching;
  final Set<String> _missing;
  final Set<String> _picked = <String>{};
  bool _selecting = false;

  @override
  List<SignedDocument> get documents => docs;
  @override
  bool get isLoading => loading;
  @override
  bool get isWaitingForAccount => waiting;
  @override
  bool get loadFailed => failed;
  @override
  bool get isFetchingCloud => fetching;
  @override
  bool get isBusy => false;
  @override
  bool isMissing(String id) => _missing.contains(id);
  @override
  bool isSelected(String id) => _picked.contains(id);
  @override
  bool get isSelectionMode => _selecting;
  @override
  int get selectedCount => _picked.length;
  @override
  List<SignedDocument> get selectedDocuments => [
        for (final d in docs)
          if (_picked.contains(d.id)) d
      ];

  @override
  Future<void> start() async {}
  @override
  Future<void> refresh({bool cloud = true}) async {}

  @override
  void enterSelectionMode() {
    _selecting = true;
    notifyListeners();
  }

  @override
  void exitSelectionMode() {
    _selecting = false;
    _picked.clear();
    notifyListeners();
  }

  @override
  void toggleSelection(String id) {
    if (!_picked.remove(id)) _picked.add(id);
    notifyListeners();
  }
}

/// An editing session over a synthetic [pageCount]-page A4 file: nothing is
/// read from or written to disk.
SignatureEditorViewModel r7bEditor({int pageCount = 3}) {
  final pages = <PageGeometry>[
    for (var i = 0; i < pageCount; i++)
      const PageGeometry(mediaBox: PdfBox(0, 0, 595, 842)),
  ];
  return SignatureEditorViewModel(
    sourcePath: 'r7b-synthetic.pdf',
    sourceName: 'r7b-synthetic.pdf',
    analysis: SignatureAnalysis(
      size: 1024,
      pageCount: pageCount,
      pages: pages,
      features: const SignatureFeatures(),
    ),
    executor: const InlineSignatureExecutor(),
    store: SignatureStore(
      accountDir: Directory.systemTemp,
      userId: 'user-a',
      verify: (_) => throw UnimplementedError('no disk in R7B tests'),
    ),
    userId: 'user-a',
    currentUserId: () => 'user-a',
    userIdChanges: const Stream<String?>.empty(),
    usage: RecordingSignatureUsage(),
    renderer: FakeStampRenderer(),
    idGenerator: _ids(),
  );
}

String Function() _ids() {
  var n = 0;
  return () => 'r7b${n++}';
}

FakePageRenderer r7bRenderer({int pageCount = 3}) => FakePageRenderer(sizes: [
      for (var i = 0; i < pageCount; i++) const RenderedPageSize(595, 842),
    ]);
