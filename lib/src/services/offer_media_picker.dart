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

import 'package:broker_wallet/src/services/media_pick_recovery.dart';

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
///
/// Every picker is opened for an `origin` — the form asking (see
/// [MediaPickOrigin]). On Android, what the system hands back after it
/// stopped the app mid-pick goes back to that form alone
/// ([recoverLostSelection]); never to another record, kind of record or
/// account.
class OfferMediaPicker {
  OfferMediaPicker({
    ImagePicker? picker,
    Future<bool> Function()? cameraPermanentlyDenied,
    bool? isAndroid,
    MediaPickRecovery? recovery,
  })  : _picker = picker ?? ImagePicker(),
        _cameraPermanentlyDenied =
            cameraPermanentlyDenied ?? _cameraIsPermanentlyDenied,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
        _recovery = recovery ?? MediaPickRecovery.instance;

  final ImagePicker _picker;
  final Future<bool> Function() _cameraPermanentlyDenied;
  final bool _isAndroid;
  final MediaPickRecovery _recovery;

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
  /// [limit], for the form [origin]. Empty when the user cancels.
  Future<List<File>> pickFromGallery({
    required int limit,
    required MediaPickOrigin? origin,
  }) async {
    if (limit < 1) return const <File>[];
    final picked = await _forOrigin(
        origin,
        () => _withPhotoPicker(() => _picker.pickMultipleMedia(
              limit: limit,
              imageQuality: _imageQuality,
              maxWidth: _maxImageDimension,
              maxHeight: _maxImageDimension,
            )));
    return [for (final file in picked) File(file.path)];
  }

  /// A photo taken with the camera for the form [origin], or null when the
  /// user cancels.
  Future<File?> capturePhoto({required MediaPickOrigin? origin}) => _camera(
      origin,
      () => _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: _imageQuality,
            maxWidth: _maxImageDimension,
            maxHeight: _maxImageDimension,
          ));

  /// A video recorded with the camera for the form [origin], or null when the
  /// user cancels.
  Future<File?> recordVideo({
    required Duration maxDuration,
    required MediaPickOrigin? origin,
  }) =>
      _camera(
          origin,
          () => _picker.pickVideo(
              source: ImageSource.camera, maxDuration: maxDuration));

  /// Media picked on the form [origin] just before Android stopped the app
  /// while its picker was open, which Android hands back after the restart.
  /// Empty when there is none for exactly this form (and on every other
  /// platform): another form's result is never handed out here.
  Future<List<File>> recoverLostSelection({
    required MediaPickOrigin? origin,
  }) async {
    if (!_isAndroid) return const <File>[];
    try {
      return await _recovery.take(origin);
    } catch (_) {
      return const <File>[];
    }
  }

  /// Runs [pick] with [origin] recorded as the form waiting for it, so that a
  /// result Android hands back after stopping the app can go back to it alone.
  /// The record is cleared when [pick] returns here: a pick, a cancel or an
  /// error.
  Future<T> _forOrigin<T>(
    MediaPickOrigin? origin,
    Future<T> Function() pick,
  ) async {
    if (!_isAndroid) return pick();
    await _recovery.beginPick(origin);
    try {
      return await pick();
    } finally {
      await _recovery.endPick();
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

  Future<File?> _camera(
    MediaPickOrigin? origin,
    Future<XFile?> Function() pick,
  ) async {
    try {
      final picked = await _forOrigin(origin, pick);
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
