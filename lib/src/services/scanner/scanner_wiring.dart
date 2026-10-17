import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/scanner/scan_file_inspector.dart';
import 'package:broker_wallet/src/services/scanner/scan_lifecycle_probe.dart';
import 'package:broker_wallet/src/services/scanner/scan_source_stager.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_engine.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/scanner/scanner_share_preparer.dart';
import 'package:broker_wallet/src/services/scanner/scanner_usage_gate.dart';
import 'package:broker_wallet/src/services/scanner/syncfusion_pdf_page_counter.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';

/// The SharedPreferences key the first Scanner stored every account's
/// documents under, device-wide. It is only counted, never read into a list:
/// those entries carry no owner, so the Scanner cannot tell whose they are.
const String legacyScannerIndexKey = 'scanned_documents';

/// Connects the Scanner's logic to the real phone: the native scanner, the
/// app's folders, the signed-in account and the share and export routes.
class ScannerWiring {
  const ScannerWiring._();

  /// The plan-limit check. One instance serves both the screen's question
  /// ("may this account scan again?") and the view model's record ("it did").
  static const ScannerUsageGate usageGate = LegacyFirestoreScannerUsageGate();

  /// A view model for the signed-in session.
  static ScannerViewModel createViewModel() {
    final auth = RepositoryProvider.instance.authRepository;
    return ScannerViewModel(
      engine: FlutterDocScannerEngine(
        null,
        Platform.isAndroid
            ? PlatformScanLifecycleProbe()
            : const NoScanLifecycleProbe(),
      ),
      backup: PlatformScannerBackupGuard(),
      baseDirectory: getApplicationDocumentsDirectory,
      stager: ScanSourceStager(
        roots: _roots,
        contentReader: Platform.isAndroid ? PlatformContentUriReader() : null,
      ),
      inspector: const ScanFileInspector(pdfPages: SyncfusionPdfPageCounter()),
      usage: usageGate,
      sharePreparer: ScannerSharePreparer(tempRoot: getTemporaryDirectory),
      exporter: PlatformScannerExporter(
        isAndroid: Platform.isAndroid,
        androidSdk: () async =>
            (await DeviceInfoPlugin().androidInfo).version.sdkInt,
        requestLegacyStoragePermission: () async =>
            (await Permission.storage.request()).isGranted,
        saveToFiles: (name, bytes) =>
            FilePicker.platform.saveFile(fileName: name, bytes: bytes),
      ),
      currentUserId: () => auth.currentUserId,
      userIdChanges: auth.authStateChanges.map((user) => user?.uid),
      legacyDocumentCount: _legacyCount,
    );
  }

  static Future<int> _legacyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(legacyScannerIndexKey)?.length ?? 0;
  }

  static Future<ScannerRoots> _roots() async {
    final temp = await getTemporaryDirectory();
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final trusted = <Directory>[temp, support];
    // Only the iPhone scanner writes into Documents.
    if (Platform.isIOS) trusted.add(documents);
    try {
      trusted.add(await getApplicationCacheDirectory());
    } catch (_) {}
    if (Platform.isAndroid) {
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) trusted.add(external);
      } catch (_) {}
    }
    return ScannerRoots(
      stagingDir: Directory(p.join(temp.path, 'scanner_staging')),
      trusted: trusted,
      // The Scanner's own store lives in Documents and is never a scan source.
      denied: <Directory>[Directory(p.join(documents.path, 'scanner'))],
      // Google's scanner writes its pages under the app's files folder.
      scannerOutputDirs: <Directory>[
        Directory(p.join(support.path, 'mlkit_docscan_ui_client')),
      ],
      // The iPhone scanner writes date-named files straight into Documents.
      scannerOutputFlatDirs:
          Platform.isIOS ? <Directory>[documents] : const <Directory>[],
    );
  }
}
