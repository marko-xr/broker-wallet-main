import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_executor.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_platform.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_wiring.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart';

/// The SharedPreferences key the first Combine tool stored every account's
/// documents under, device-wide. It is only counted, never read into a list:
/// those entries carry no owner, so the tool cannot tell whose they are. Their
/// files stay where they were and are neither shown, moved nor deleted.
const String legacyCombinedPdfIndexKey = 'combined_pdf_documents';

/// Connects the Combine tool's logic to the real phone: the system file picker,
/// the app's folders, the signed-in account and the share and export routes.
class CombinePdfWiring {
  const CombinePdfWiring._();

  /// The plan-limit check. One instance serves both the screen's question
  /// ("may this account combine again?") and the view model's record ("it did").
  static const CombineUsageGate usageGate = LegacyFirestoreCombineUsageGate();

  /// A view model for the signed-in session.
  static CombinePdfViewModel createViewModel() {
    final auth = RepositoryProvider.instance.authRepository;
    return CombinePdfViewModel(
      executor: const IsolateCombineExecutor(),
      baseDirectory: getApplicationDocumentsDirectory,
      picker: const SystemCombinePdfPicker(),
      usage: usageGate,
      sharePreparer: CombineSharePreparer(tempRoot: getTemporaryDirectory),
      exporter: PlatformCombinePdfExporter(
        PlatformScannerExporter(
          isAndroid: Platform.isAndroid,
          androidSdk: () async =>
              (await DeviceInfoPlugin().androidInfo).version.sdkInt,
          requestLegacyStoragePermission: () async =>
              (await Permission.storage.request()).isGranted,
          saveToFiles: (name, bytes) =>
              FilePicker.platform.saveFile(fileName: name, bytes: bytes),
        ),
      ),
      backup: PlatformScannerBackupGuard(),
      currentUserId: () => auth.currentUserId,
      userIdChanges: auth.authStateChanges.map((user) => user?.uid),
      legacyDocumentCount: _legacyCount,
      // The account's cloud copy: null (so the tool stays local) only when the
      // build sets the kill switch TOOLKIT_CLOUD_DOCUMENTS=false.
      cloudFactory: (accountId, store, files) => ToolkitCloudWiring.create(
        accountId: accountId,
        type: ToolkitDocumentType.combinePdfs,
        directory: store.cloudDir,
        files: files,
        currentAccountId: () => auth.currentUserId,
      ),
    );
  }

  static Future<int> _legacyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(legacyCombinedPdfIndexKey)?.length ?? 0;
  }
}
