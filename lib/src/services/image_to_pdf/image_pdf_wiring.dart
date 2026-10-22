import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_executor.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_platform.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_usage_gate.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_wiring.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart';

/// The SharedPreferences key the first Images to PDF tool stored every account's
/// documents under, device-wide. It is only counted, never read into a list:
/// those entries carry no owner, so the tool cannot tell whose they are. Their
/// files stay where they were and are neither shown, moved nor deleted.
const String legacyConvertedPdfIndexKey = 'converted_pdf_documents';

/// The Arabic font bundled with the app (also declared in `pubspec.yaml`),
/// embedded in a PDF only when a text on it is not plain Latin.
const String imagePdfUnicodeFontAsset =
    'assets/fonts/Noto_Naskh_Arabic/NotoNaskhArabic-VariableFont_wght.ttf';

/// Connects the Images to PDF tool's logic to the real phone: the system
/// pickers and camera, the app's folders, the signed-in account and the share
/// and export routes.
class ImagePdfWiring {
  const ImagePdfWiring._();

  /// The plan-limit check. One instance serves both the screen's question ("may
  /// this account convert again?") and the view model's record ("it did").
  static const ImagePdfUsageGate usageGate = LegacyFirestoreImagePdfUsageGate();

  /// A view model for the signed-in session.
  static ImagePdfViewModel createViewModel() {
    final auth = RepositoryProvider.instance.authRepository;
    return ImagePdfViewModel(
      executor: const IsolateImagePdfExecutor(),
      baseDirectory: getApplicationDocumentsDirectory,
      picker: SystemImagePdfPicker(accountId: () => auth.currentUserId),
      normalizer: const PlatformImagePdfImageNormalizer(),
      usage: usageGate,
      sharePreparer: ImagePdfSharePreparer(tempRoot: getTemporaryDirectory),
      exporter: PlatformImagePdfExporter(
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
      loadUnicodeFont: _loadFont,
      tempRoot: getTemporaryDirectory,
      legacyDocumentCount: _legacyCount,
      // The account copy: null (so the tool stays local) when this build has it
      // switched off.
      cloudFactory: (accountId, files) => ToolkitCloudWiring.create(
        accountId: accountId,
        type: ToolkitDocumentType.imageToPdf,
        directory: files.journalDirectory,
        files: files,
        currentAccountId: () => auth.currentUserId,
      ),
    );
  }

  static Future<Uint8List?> _loadFont() async {
    try {
      final data = await rootBundle.load(imagePdfUnicodeFontAsset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<int> _legacyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(legacyConvertedPdfIndexKey)?.length ?? 0;
  }
}
