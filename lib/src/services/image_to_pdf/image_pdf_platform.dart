import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    show ImagePickerPlatform;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/media_pick_recovery.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';

/// One picture the user chose: the picker's private copy, and the name it had.
class PickedImage {
  const PickedImage({required this.path, required this.name});

  final String path;
  final String name;
}

/// Lets the user choose pictures. The Android Photo Picker, the iOS photo
/// picker and the system camera hand the app only what the user chose, so no
/// storage permission is requested here. Nothing is resized or recompressed on
/// the way in: the original bytes arrive.
abstract interface class ImagePdfImagePicker {
  /// The chosen pictures, or null when the picker was closed without a choice.
  /// Throws an [ImagePdfException] (`pickerFailed`).
  Future<List<PickedImage>?> pickFromGallery();

  /// A photo taken with the phone's own camera app, or null when it was
  /// cancelled. Throws an [ImagePdfException] (`permissionDenied`,
  /// `pickerFailed`).
  Future<PickedImage?> capturePhoto();

  /// Pictures a picker of this tool had returned just before Android stopped the
  /// app, which Android hands back after the restart: only for the signed-in
  /// account that opened the picker, once, in the order picked. Empty on every
  /// other platform and whenever the picker, the account or the tool cannot be
  /// established.
  Future<List<PickedImage>> recoverLostPicks();
}

class SystemImagePdfPicker implements ImagePdfImagePicker {
  SystemImagePdfPicker({
    ImagePicker? picker,
    MediaPickRecovery? recovery,
    bool? isAndroid,
    String? Function()? accountId,
  })  : _picker = picker ?? ImagePicker(),
        _recovery = recovery ?? MediaPickRecovery.instance,
        _isAndroid = isAndroid ?? Platform.isAndroid,
        _accountId = accountId ?? (() => null);

  /// The name this tool's pending pick is recorded under.
  static const String toolName = 'image_to_pdf';

  final ImagePicker _picker;
  final MediaPickRecovery _recovery;
  final bool _isAndroid;
  final String? Function() _accountId;

  ToolPickOrigin? get _origin =>
      ToolPickOrigin.of(accountId: _accountId(), tool: toolName);

  /// Runs [pick] with this tool and the signed-in account recorded as the
  /// picker's owner, so that a result Android hands back after stopping the app
  /// can come back to it alone. The record is cleared when [pick] returns here:
  /// a pick, a cancel or an error.
  Future<T> _tracked<T>(Future<T> Function() pick) async {
    if (!_isAndroid) return pick();
    await _recovery.beginToolPick(_origin);
    try {
      return await pick();
    } finally {
      await _recovery.endPick();
    }
  }

  /// The system Photo Picker (the plugin otherwise opens the older document
  /// chooser), for this one call.
  Future<T> _withPhotoPicker<T>(Future<T> Function() pick) async {
    final platform = ImagePickerPlatform.instance;
    if (platform is! ImagePickerAndroid) return pick();
    final previous = platform.useAndroidPhotoPicker;
    platform.useAndroidPhotoPicker = true;
    try {
      return await pick();
    } finally {
      platform.useAndroidPhotoPicker = previous;
    }
  }

  @override
  Future<List<PickedImage>?> pickFromGallery() async {
    try {
      final files = await _tracked(
          () => _withPhotoPicker(() => _picker.pickMultiImage()));
      if (files.isEmpty) return null;
      return <PickedImage>[
        for (final file in files) PickedImage(path: file.path, name: file.name),
      ];
    } on PlatformException catch (error) {
      throw ImagePdfException(ImagePdfFailure.pickerFailed, detail: error.code);
    }
  }

  @override
  Future<PickedImage?> capturePhoto() async {
    try {
      final file =
          await _tracked(() => _picker.pickImage(source: ImageSource.camera));
      if (file == null) return null;
      return PickedImage(path: file.path, name: file.name);
    } on PlatformException catch (error) {
      if (error.code == 'camera_access_denied') {
        throw const ImagePdfException(ImagePdfFailure.permissionDenied);
      }
      throw ImagePdfException(ImagePdfFailure.pickerFailed, detail: error.code);
    }
  }

  @override
  Future<List<PickedImage>> recoverLostPicks() async {
    if (!_isAndroid) return const <PickedImage>[];
    try {
      final files = await _recovery.takeTool(_origin);
      return <PickedImage>[
        for (final file in files)
          PickedImage(path: file.path, name: p.basename(file.path)),
      ];
    } catch (_) {
      return const <PickedImage>[];
    }
  }
}

/// Turns a HEIC/HEIF photo into a JPEG with the phone's own decoder. The PDF
/// libraries cannot read HEIC, so this is the only way such a photo can be
/// used; a phone without a HEIC decoder (Android before 9) reports failure and
/// the photo is refused by name.
abstract interface class ImagePdfImageNormalizer {
  /// Writes an upright, metadata-free JPEG of [source] to [target] and returns
  /// it; null when the phone cannot decode it.
  Future<File?> heicToJpeg(File source, File target);
}

class PlatformImagePdfImageNormalizer implements ImagePdfImageNormalizer {
  const PlatformImagePdfImageNormalizer();

  @override
  Future<File?> heicToJpeg(File source, File target) async {
    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        source.path,
        target.path,
        format: CompressFormat.jpeg,
        quality: 95,
        // Never scaled: these minimums are above any photo.
        minWidth: 20000,
        minHeight: 20000,
        autoCorrectionAngle: true,
        keepExif: false,
      );
      if (result == null) return null;
      final file = File(result.path);
      return await file.exists() && await file.length() > 0 ? file : null;
    } catch (_) {
      return null;
    }
  }
}

/// Where an exported copy of a PDF goes.
abstract interface class ImagePdfExporter {
  /// Exports [file] under [fileName]. Throws an [ImagePdfException]
  /// (`permissionDenied`, `storageFull`, `exportFailed`).
  Future<ScannerExportResult> export(String fileName, File file);
}

/// Reuses the Scanner's route: MediaStore Downloads (no storage permission on
/// Android 10 and later, never All Files Access), the Files save sheet on
/// iPhone. Nothing is reported as saved unless the platform said so.
class PlatformImagePdfExporter implements ImagePdfExporter {
  const PlatformImagePdfExporter(this._exporter);

  final PlatformScannerExporter _exporter;

  @override
  Future<ScannerExportResult> export(String fileName, File file) async {
    try {
      return await _exporter.exportFile(
          file: file, fileName: fileName, mimeType: 'application/pdf');
    } on ScannerException catch (error) {
      switch (error.kind) {
        case ScannerFailure.permissionDenied:
          throw const ImagePdfException(ImagePdfFailure.permissionDenied);
        case ScannerFailure.storageFull:
          throw const ImagePdfException(ImagePdfFailure.storageFull);
        default:
          throw ImagePdfException(ImagePdfFailure.exportFailed,
              detail: error.detail);
      }
    }
  }
}

/// Prepares the files of a share. A stored document is named by an internal id,
/// which must never reach another app, so a share carries copies named by the
/// document's title in a folder of their own inside the app's temporary
/// directory. They are not deleted the moment the share sheet opens (the
/// receiving app may still be reading them); [sweepStale] removes old ones.
class ImagePdfSharePreparer {
  ImagePdfSharePreparer({required Future<Directory> Function() tempRoot})
      : _tempRoot = tempRoot;

  final Future<Directory> Function() _tempRoot;

  Future<Directory> _root() async =>
      Directory(p.join((await _tempRoot()).path, 'image_pdf_share'));

  /// Copies each of [files] to a title-named file and returns the new paths in
  /// the same order.
  Future<List<String>> prepare(
      List<({ImagePdfDocument document, File file})> files) async {
    final folder = Directory(p.join((await _root()).path, const Uuid().v4()));
    await folder.create(recursive: true);
    final used = <String>{};
    final paths = <String>[];
    try {
      for (final item in files) {
        var name = item.document.exportFileName;
        var counter = 2;
        while (!used.add(name.toLowerCase())) {
          name = '${item.document.name} ($counter).pdf';
          counter++;
        }
        final target = File(p.join(folder.path, name));
        await item.file.copy(target.path);
        paths.add(target.path);
      }
    } catch (_) {
      try {
        await folder.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
    return paths;
  }

  Future<void> sweepStale({
    Duration olderThan = const Duration(hours: 1),
    DateTime? now,
  }) async {
    try {
      final root = await _root();
      if (!await root.exists()) return;
      final cutoff = (now ?? DateTime.now()).subtract(olderThan);
      await for (final item in root.list(followLinks: false)) {
        if (item is! Directory) continue;
        final stat = await item.stat();
        if (stat.modified.isBefore(cutoff)) {
          try {
            await item.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
