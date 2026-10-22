import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_page_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_stamp_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_wiring.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_library_viewmodel.dart';

/// The SharedPreferences key the first Signature tool stored every account's
/// signed documents under, device-wide. It is only counted, never read into a
/// list: those entries carry no owner, so the tool cannot tell whose they are.
/// Their files (in `signed_documents/`) stay where they were and are neither
/// shown, moved nor deleted.
const String legacySignedDocumentIndexKey = 'signed_documents_list';

/// Connects the Signature tool's logic to the real phone: the system file picker,
/// the app's folders, the signed-in account, the page renderer and the share and
/// export routes.
class SignatureWiring {
  const SignatureWiring._();

  /// The plan-limit check. One instance serves both the screen's question ("may
  /// this account save another signed document?") and the view model's record
  /// ("it did").
  static const SignatureUsageGate usageGate =
      LegacyFirestoreSignatureUsageGate();

  /// Turns drawings and typed text into the images that are placed.
  static const StampRenderer stampRenderer = FlutterStampRenderer();

  /// A page renderer for one editing session. The session's screen owns it.
  static SignaturePageRenderer createPageRenderer() =>
      PdfrxSignaturePageRenderer();

  /// A view model for the signed-in session.
  static SignatureLibraryViewModel createViewModel() {
    final auth = RepositoryProvider.instance.authRepository;
    return SignatureLibraryViewModel(
      executor: const IsolateSignatureExecutor(),
      baseDirectory: getApplicationDocumentsDirectory,
      picker: const SystemSignaturePdfPicker(),
      usage: usageGate,
      sharePreparer: SignatureSharePreparer(tempRoot: getTemporaryDirectory),
      exporter: PlatformSignaturePdfExporter(
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
      stampRenderer: stampRenderer,
      currentUserId: () => auth.currentUserId,
      userIdChanges: auth.authStateChanges.map((user) => user?.uid),
      legacyDocumentCount: _legacyCount,
      // The account copy: null (so the tool stays local) when this build has it
      // switched off.
      cloudFactory: (accountId, files) => ToolkitCloudWiring.create(
        accountId: accountId,
        type: ToolkitDocumentType.signature,
        directory: files.journalDirectory,
        files: files,
        currentAccountId: () => auth.currentUserId,
      ),
    );
  }

  static Future<int> _legacyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(legacySignedDocumentIndexKey)?.length ?? 0;
  }
}
