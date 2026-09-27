import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
// The Android implementation of image_picker, always present with it; used
// only to switch that plugin to the system Photo Picker for one call.
// ignore: depend_on_referenced_packages
import 'package:image_picker_android/image_picker_android.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:permission_handler/permission_handler.dart';

/// Where new Offer media comes from.
enum OfferMediaSource { cameraPhoto, cameraVideo, gallery }

/// Why a picker could not be used.
enum OfferMediaPickerFailure {
  /// The camera permission was refused this time.
  cameraDenied,

  /// The camera permission is refused for good: only Settings can change it.
  cameraPermanentlyDenied,
}

class OfferMediaPickerException implements Exception {
  const OfferMediaPickerException(this.failure);

  final OfferMediaPickerFailure failure;

  @override
  String toString() => 'OfferMediaPickerException(${failure.name})';
}

/// The pickers behind the Offer media attachment sheet.
///
/// **Gallery** is one native selection of photos and videos together
/// (`pickMultipleMedia`), capped at the places the Offer has left. On Android
/// it uses the system Photo Picker, which grants access to exactly the items
/// the user picks and needs no media-library permission: no app-made
/// explanation dialog, no "allow access to photos and videos" screen. The
/// Photo Picker is switched on for that call only, so every other picker in
/// the app behaves as before.
///
/// **Camera** is the phone's own camera app, opened for a photo or for a
/// video (a system capture returns one kind, so the sheet offers both
/// directly). Android requires the camera permission because the app
/// declares it; the plugin asks for it with the system dialog at that moment,
/// once, with no app-made dialog before it. The camera app records sound
/// itself, so no microphone permission is involved.
///
/// Every picked file is only a candidate: the caller screens it against the
/// Offer media rules (count, size, real type, duration, HEIC conversion)
/// before it enters the form, and the upload queue copies it into the app's
/// own storage when the Offer is saved.
class OfferMediaPicker {
  OfferMediaPicker({
    ImagePicker? picker,
    Future<bool> Function()? cameraPermanentlyDenied,
    bool? isAndroid,
  })  : _picker = picker ?? ImagePicker(),
        _cameraPermanentlyDenied =
            cameraPermanentlyDenied ?? _cameraIsPermanentlyDenied,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  final ImagePicker _picker;
  final Future<bool> Function() _cameraPermanentlyDenied;
  final bool _isAndroid;

  /// Photos keep the scale and quality the app's pickers already use.
  static const double _maxImageDimension = 1920;
  static const int _imageQuality = 85;

  static Future<bool> _cameraIsPermanentlyDenied() async {
    try {
      return await Permission.camera.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Photos and videos chosen together in one native selection, at most
  /// [limit]. Empty when the user cancels.
  Future<List<File>> pickFromGallery({required int limit}) async {
    if (limit < 1) return const <File>[];
    final picked = await _withPhotoPicker(() => _picker.pickMultipleMedia(
          limit: limit,
          imageQuality: _imageQuality,
          maxWidth: _maxImageDimension,
          maxHeight: _maxImageDimension,
        ));
    return [for (final file in picked) File(file.path)];
  }

  /// A photo taken with the camera, or null when the user cancels.
  Future<File?> capturePhoto() => _camera(() => _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: _imageQuality,
        maxWidth: _maxImageDimension,
        maxHeight: _maxImageDimension,
      ));

  /// A video recorded with the camera, or null when the user cancels.
  Future<File?> recordVideo({required Duration maxDuration}) => _camera(() =>
      _picker.pickVideo(source: ImageSource.camera, maxDuration: maxDuration));

  /// Media picked just before Android stopped the app while the picker was
  /// open, which Android hands back at the next opportunity. Empty when there
  /// is none (and on every other platform).
  Future<List<File>> recoverLostSelection() async {
    if (!_isAndroid) return const <File>[];
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty) return const <File>[];
      final files =
          response.files ?? [if (response.file != null) response.file!];
      return [for (final file in files) File(file.path)];
    } catch (_) {
      return const <File>[];
    }
  }

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

  Future<File?> _camera(Future<XFile?> Function() pick) async {
    try {
      final picked = await pick();
      return picked == null ? null : File(picked.path);
    } on PlatformException catch (error) {
      if (error.code == 'camera_access_denied') {
        throw OfferMediaPickerException(await _cameraPermanentlyDenied()
            ? OfferMediaPickerFailure.cameraPermanentlyDenied
            : OfferMediaPickerFailure.cameraDenied);
      }
      rethrow;
    }
  }
}
