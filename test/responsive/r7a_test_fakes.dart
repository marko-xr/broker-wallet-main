import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scan_source_stager.dart';
import 'package:broker_wallet/src/services/scanner/scan_file_inspector.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';

final Uint8List r7aPreview = Uint8List.fromList(
    img.encodePng(img.Image(width: 24, height: 36, numChannels: 3)));
const r7aName = 'مستند تجريبي طويل Long document title for responsive layout';

/// Presentation state only: no constructor of a store, engine, account or cloud
/// service is run. Any unexpected operation fails and is counted.
class LocalScannerModel extends ChangeNotifier implements ScannerViewModel {
  int starts = 0;
  int retries = 0;
  int unexpectedCalls = 0;
  int saveRequests = 0;
  bool loading = false;
  bool waiting = false;
  bool failed = false;
  bool fetching = false;
  bool saving = false;
  final Set<String> selection = {};
  bool selecting = false;
  final Set<String> remoteOnly = {};
  final Set<String> missing = {};
  @override
  List<ScannerDocument> documents = [];
  @override
  ScanDraft? draft;
  @override
  String get suggestedName => r7aName;
  @override
  bool get isLoading => loading;
  @override
  bool get isWaitingForAccount => waiting;
  @override
  bool get loadFailed => failed;
  @override
  bool get isFetchingCloud => fetching;
  @override
  bool get isSaving => saving;
  @override
  bool get isBusy => saving;
  @override
  int get legacyDocumentCount => 2;
  @override
  int get maxPages => _maxPages;
  int _maxPages = 5;
  @override
  set maxPages(int value) {
    _maxPages = value;
    notifyListeners();
  }

  @override
  ScanMode scanMode = ScanMode.document;
  @override
  ExportFormat exportFormat = ExportFormat.pdf;
  @override
  void selectScanMode(ScanMode value) {
    scanMode = value;
    notifyListeners();
  }

  @override
  void selectExportFormat(ExportFormat value) {
    exportFormat = value;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    starts++;
    final ready = documents;
    documents = [];
    // Like an asynchronous library read: preferences settle before populated
    // cards are first laid out. This avoids exercising the protected default
    // grid in a test explicitly requesting the list preference.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      documents = ready;
      notifyListeners();
    });
  }

  @override
  Future<void> refresh({bool cloud = true}) async {
    retries++;
  }

  @override
  Future<ScanSaveResult> saveDraft(String? name) async {
    saveRequests++;
    return const ScanSaveResult.failed(ScannerFailure.storageFull);
  }

  @override
  bool isMissing(String id) => missing.contains(id);
  @override
  bool isCloudOnly(String id) => remoteOnly.contains(id);
  @override
  bool get isSelectionMode => selecting;
  @override
  bool isSelected(String id) => selection.contains(id);
  @override
  int get selectedCount => selection.length;
  @override
  List<ScannerDocument> get selectedDocuments =>
      documents.where((d) => selection.contains(d.id)).toList();
  @override
  void enterSelectionMode() {
    selecting = true;
    notifyListeners();
  }

  @override
  void exitSelectionMode() {
    selecting = false;
    selection.clear();
    notifyListeners();
  }

  @override
  void toggleSelection(String id) {
    if (!selection.remove(id)) selection.add(id);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected Scanner operation: ${invocation.memberName}');
  }
}

class LocalImagesModel extends ChangeNotifier implements ImagePdfViewModel {
  int starts = 0;
  int recoveries = 0;
  int retries = 0;
  int unexpectedCalls = 0;
  int settingsChanges = 0;
  bool waiting = false;
  bool failed = false;
  bool building = false;
  bool fetching = false;
  bool selecting = false;
  final Set<String> selection = {};
  final Set<String> remoteOnly = {};
  @override
  List<ImagePdfDocument> documents = [];
  @override
  List<ImagePdfItem> items = [];
  @override
  ImagePdfSettings settings = const ImagePdfSettings();
  @override
  String get suggestedName => r7aName;
  @override
  bool get isWaitingForAccount => waiting;
  @override
  bool get loadFailed => failed;
  @override
  bool get isFetchingCloud => fetching;
  @override
  bool get isBuilding => building;
  @override
  bool get isSaving => false;
  @override
  bool get isBusy => building;
  @override
  bool get isChecking => items.any((i) => i.status == ImageItemStatus.checking);
  @override
  bool get hasFailedItems =>
      items.any((i) => i.status == ImageItemStatus.failed);
  @override
  bool get hasPassword => false;
  @override
  int get legacyDocumentCount => 2;
  @override
  int? get plannedPageCount => items.isEmpty ? null : 999;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<AddImagesOutcome?> recoverLostPicks() async {
    recoveries++;
    return null;
  }

  @override
  Future<void> refresh({bool cloud = true}) async {
    retries++;
  }

  @override
  bool isMissing(String id) => false;
  @override
  bool isCloudOnly(String id) => remoteOnly.contains(id);
  @override
  bool get isSelectionMode => selecting;
  @override
  bool isSelected(String id) => selection.contains(id);
  @override
  int get selectedCount => selection.length;
  @override
  List<ImagePdfDocument> get selectedDocuments =>
      documents.where((d) => selection.contains(d.id)).toList();
  @override
  void enterSelectionMode() {
    selecting = true;
    notifyListeners();
  }

  @override
  void exitSelectionMode() {
    selecting = false;
    selection.clear();
    notifyListeners();
  }

  @override
  void toggleSelection(String id) {
    if (!selection.remove(id)) selection.add(id);
    notifyListeners();
  }

  @override
  void updateSettings(ImagePdfSettings value) {
    settings = value;
    settingsChanges++;
    notifyListeners();
  }

  @override
  void moveItem(int oldIndex, int newIndex) {
    items.insert(newIndex, items.removeAt(oldIndex));
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected Images operation: ${invocation.memberName}');
  }
}

List<ScannerDocument> scannerFixtures() => List.generate(
    6,
    (i) => ScannerDocument(
        id: 'fixture-$i',
        fileName: 'fixture-$i.pdf',
        name: '$r7aName $i',
        scanType: ScanMode.document,
        format: ExportFormat.pdf,
        mimeType: 'application/pdf',
        createdAt: DateTime(2026, 10, 30),
        fileSize: 987654321,
        pageCount: 999));

List<ImagePdfDocument> imageDocumentFixtures() => List.generate(
    6,
    (i) => ImagePdfDocument(
        id: 'fixture-$i',
        fileName: 'fixture-$i.pdf',
        name: '$r7aName $i',
        createdAt: DateTime(2026, 10, 30),
        fileSize: 987654321,
        pageCount: 999,
        imageCount: 100,
        encrypted: i.isOdd));

List<ImagePdfItem> imageFixtures() => List.generate(
    6,
    (i) => ImagePdfItem(
        id: 'image-$i',
        path: 'unused-local-preview-$i',
        displayName: '$r7aName-$i.png',
        size: 7654321)
      ..status = ImageItemStatus.ready
      ..possibleDuplicate = i == 1
      ..analysis = ImageAnalysis(
          size: 7654321,
          format: 'png',
          width: 2400,
          height: 3600,
          orientation: 1,
          hasAlpha: false,
          isBaselineJpeg: false,
          thumbnail: r7aPreview));

ScanDraft scanFixture() => ScanDraft(
    id: 'local-draft',
    userId: 'layout-only',
    epoch: 0,
    format: ExportFormat.images,
    scanType: ScanMode.document,
    pages: List.generate(
        12,
        (i) => DraftPage(
            StagedScanFile(
                file: File('unused-page-$i.png'),
                isTemporaryCopy: false,
                isScannerOutput: false),
            const InspectedScanFile(
                kind: ScanFileKind.png,
                size: 987654,
                pageCount: 1,
                width: 2400,
                height: 3600))));
