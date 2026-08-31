import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:broker_wallet/src/services/permission_service.dart';
import 'package:broker_wallet/src/services/media_selection_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:broker_wallet/src/common/utils/app_notifier.dart';
import 'dart:io' show Platform;

/// Wrapper service that combines permission handling with media selection
/// Ensures permissions are properly requested before allowing media access
class MediaPermissionWrapper {
  static final PermissionService _permissionService = PermissionService();

  /// Pick media with automatic permission handling
  /// Returns null if permission is denied, otherwise returns the selected files
  static Future<List<PlatformFile>?> pickMediaWithPermission(
    BuildContext context,
    String mediaType,
  ) async {
    try {
      // Determine which permissions are needed based on media type
      bool permissionGranted = false;

      switch (mediaType) {
        case 'camera_photo':
          permissionGranted = await _requestCameraPermissions(context);
          break;
        case 'camera_video':
          permissionGranted =
              await _requestCameraAndMicrophonePermissions(context);
          break;
        case 'gallery_photo':
          permissionGranted =
              await _requestGalleryPermissions(context, includeVideo: false);
          break;
        case 'gallery_video':
          permissionGranted =
              await _requestGalleryPermissions(context, includeVideo: true);
          break;
        case 'documents':
        case 'all_files':
          permissionGranted = await _requestStoragePermissions(context);
          break;
        default:
          permissionGranted = true; // For unknown types, try anyway
      }

      if (!permissionGranted) {
        _showPermissionDeniedMessage(context, mediaType);
        return null;
      }

      // Permission granted, proceed with media selection
      return await MediaSelectionService.pickFiles(mediaType);
    } on PlatformException catch (e) {
      if (_isPermissionException(e)) {
        _showPermissionDeniedMessage(context, mediaType);
      } else {
        _showErrorMessage(
          context,
          'Failed to access media: ${e.message ?? e.code}',
        );
      }
      return null;
    } catch (e) {
      _showErrorMessage(context, 'Failed to access media: $e');
      return null;
    }
  }

  /// Show media selection dialog with automatic permission handling
  static Future<List<PlatformFile>?> showMediaDialogWithPermission(
    BuildContext context,
  ) async {
    // First show the selection dialog
    final String? selectedType =
        await MediaSelectionService.showMediaSelectionDialog(context);

    if (selectedType == null) {
      return null; // User cancelled
    }

    // Then handle permissions and pick media
    return await pickMediaWithPermission(context, selectedType);
  }

  /// Request camera permissions
  static Future<bool> _requestCameraPermissions(BuildContext context) async {
    final status = await _permissionService.requestCameraPermission(context);
    return status.isGranted;
  }

  /// Request camera + microphone permissions for video recording
  static Future<bool> _requestCameraAndMicrophonePermissions(
      BuildContext context) async {
    final cameraStatus =
        await _permissionService.requestCameraPermission(context);
    if (!cameraStatus.isGranted) {
      return false;
    }

    final micStatus =
        await _permissionService.requestMicrophonePermission(context);
    return micStatus.isGranted;
  }

  /// Request photo gallery permissions
  static Future<bool> _requestGalleryPermissions(
    BuildContext context, {
    required bool includeVideo,
  }) async {
    if (Platform.isIOS) {
      final photoStatus =
          await _permissionService.requestPhotosPermission(context);
      if (photoStatus.isGranted || photoStatus.isLimited) {
        if (photoStatus.isLimited) {
          _showLimitedAccessBanner(context);
        }
        return true;
      }

      if (photoStatus.isDenied) {
        _permissionService.showPermissionStatusSnackBar(
          context,
          'Photos',
          photoStatus,
        );
      }
      return false;
    }

    final statuses = await _permissionService.requestStoragePermissions(
      context,
      includePhotos: true,
      includeVideos: includeVideo,
      includeLegacyStorage: true,
    );

    final hasAccess = statuses.values.any(
      (status) => status.isGranted || status.isLimited,
    );

    if (hasAccess) {
      if (statuses.values.any((status) => status.isLimited)) {
        _showLimitedAccessBanner(context);
      }
      return true;
    }

    final legacyStatus =
        await _permissionService.requestStoragePermission(context);
    if (legacyStatus.isGranted || legacyStatus.isLimited) {
      if (legacyStatus.isLimited) {
        _showLimitedAccessBanner(context);
      }
      return true;
    }

    return false;
  }

  /// Request storage permissions for documents/files
  static Future<bool> _requestStoragePermissions(BuildContext context) async {
    final statuses = await _permissionService.requestStoragePermissions(
      context,
      includePhotos: true,
      includeVideos: true,
      includeLegacyStorage: true,
    );

    // Check if at least one permission is granted
    return statuses.values
        .any((status) => status.isGranted || status.isLimited);
  }

  /// Request location permission for map features
  static Future<bool> requestLocationPermission(BuildContext context) async {
    final status = await _permissionService.requestLocationWhenInUse(context);
    return status.isGranted;
  }

  /// Request phone permission for calling
  static Future<bool> requestPhonePermission(BuildContext context) async {
    final status = await _permissionService.requestPhonePermission(context);
    return status.isGranted;
  }

  /// Check if camera permission is granted
  static Future<bool> hasCameraPermission() async {
    return await _permissionService.isPermissionGranted(Permission.camera);
  }

  /// Check if location permission is granted
  static Future<bool> hasLocationPermission() async {
    return await _permissionService
        .isPermissionGranted(Permission.locationWhenInUse);
  }

  /// Check if storage/media permissions are granted
  static Future<bool> hasStoragePermission() async {
    // Check for Android 13+ granular permissions
    final photosGranted =
        await _permissionService.isPermissionGranted(Permission.photos);
    final videosGranted =
        await _permissionService.isPermissionGranted(Permission.videos);

    return photosGranted || videosGranted;
  }

  /// Show permission denied message
  static void _showPermissionDeniedMessage(
      BuildContext context, String mediaType) {
    String message = 'Permission denied for accessing ';

    switch (mediaType) {
      case 'camera_photo':
        message += 'camera. Please enable camera permission in settings.';
        break;
      case 'camera_video':
        message +=
            'camera and microphone. Please enable these permissions in settings.';
        break;
      case 'gallery_photo':
      case 'gallery_video':
        message +=
            'photo library. Please enable photo library permission in settings.';
        break;
      case 'documents':
      case 'all_files':
        message += 'storage. Please enable storage permission in settings.';
        break;
      default:
        message += 'media. Please enable required permissions in settings.';
    }

    // Prefer a SnackBar when available, otherwise fallback to toast.
    AppNotifier.show(
      context,
      message,
      isError: false,
      actionLabel: 'Settings',
      onAction: () => openAppSettings(),
      duration: const Duration(seconds: 4),
    );
  }

  /// Show generic error message
  static void _showErrorMessage(BuildContext context, String message) {
    AppNotifier.show(context, message, isError: true);
  }

  static bool _isPermissionException(PlatformException exception) {
    const permissionErrorCodes = {
      'camera_access_denied',
      'camera_access_restricted',
      'photo_access_denied',
      'photo_access_restricted',
      'storage_permission_denied',
    };

    if (permissionErrorCodes.contains(exception.code)) {
      return true;
    }

    final message = exception.message?.toLowerCase() ?? '';
    return message.contains('denied') || message.contains('restricted');
  }

  static void _showLimitedAccessBanner(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();

    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.blueGrey.shade50,
        leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
        content: const Text(
          'You allowed limited photo access. To use all images and videos, upgrade access in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  /// Request all necessary permissions at app startup (optional)
  /// Returns a map of permission statuses
  static Future<Map<String, bool>> requestEssentialPermissions(
      BuildContext context) async {
    Map<String, bool> results = {};

    // Request location permission
    final locationStatus =
        await _permissionService.requestLocationWhenInUse(context);
    results['location'] = locationStatus.isGranted;

    // Request storage/media permissions
    final storageStatuses =
        await _permissionService.requestStoragePermissions(context);
    results['storage'] =
        storageStatuses.values.any((s) => s.isGranted || s.isLimited);

    return results;
  }

  /// Check all permissions status
  static Future<Map<String, PermissionStatus>> checkAllPermissions() async {
    return {
      'camera': await Permission.camera.status,
      'microphone': await Permission.microphone.status,
      'photos': await Permission.photos.status,
      'videos': await Permission.videos.status,
      'location': await Permission.locationWhenInUse.status,
      'phone': await Permission.phone.status,
      'storage': await Permission.storage.status,
    };
  }

  /// Show permissions status screen
  static Future<void> showPermissionsStatus(BuildContext context) async {
    final statuses = await checkAllPermissions();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('App Permissions'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: statuses.entries.map((entry) {
                final IconData icon;
                final Color color;

                if (entry.value.isGranted) {
                  icon = Icons.check_circle;
                  color = Colors.green;
                } else if (entry.value.isLimited) {
                  icon = Icons.warning;
                  color = Colors.orange;
                } else if (entry.value.isDenied) {
                  icon = Icons.cancel;
                  color = Colors.red;
                } else {
                  icon = Icons.help;
                  color = Colors.grey;
                }

                return ListTile(
                  dense: true,
                  leading: Icon(icon, color: color, size: 20),
                  title: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    entry.value.name,
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }
}
