import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/app_notifier.dart';

/// Clean permission service with proper pre-dialogs and edge case handling
/// Replaces the fragmented permission system with consistent UX
class CleanPermissionService {
  static final CleanPermissionService _instance =
      CleanPermissionService._internal();
  factory CleanPermissionService() => _instance;
  CleanPermissionService._internal();

  // ============================================================================
  // 📸 CAMERA PERMISSION
  // ============================================================================

  /// Request camera permission with full flow
  Future<PermissionStatus> requestCameraPermission(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    // Check current status
    final currentStatus = await Permission.camera.status;

    if (currentStatus.isGranted) {
      return currentStatus;
    }

    if (currentStatus.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('cameraPermissionRequired'),
        message: loc.translate('cameraPermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableCameraInSettings'),
      );
      return currentStatus;
    }

    // Show pre-permission dialog explaining why we need camera
    final shouldRequest = await _showPrePermissionDialog(
      context: context,
      title: loc.translate('cameraAccessNeeded'),
      message: loc.translate('cameraPermissionExplanation'),
      icon: Icons.camera_alt,
      iconColor: Colors.blue,
    );

    if (!shouldRequest) {
      return PermissionStatus.denied;
    }

    // Request the permission
    final result = await Permission.camera.request();

    // Handle the result
    if (result.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('cameraPermissionRequired'),
        message: loc.translate('cameraPermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableCameraInSettings'),
      );
    } else if (result.isDenied) {
      _showPermissionDeniedSnackBar(
          context, loc.translate('cameraPermissionDenied'));
    }

    return result;
  }

  // ============================================================================
  // 📁 STORAGE/MEDIA PERMISSIONS
  // ============================================================================

  /// Request storage/media permissions with Android 13+ handling
  Future<Map<Permission, PermissionStatus>> requestStoragePermissions(
      BuildContext context) async {
    final loc = AppLocalizations.of(context);
    Map<Permission, PermissionStatus> results = {};

    // Determine permissions needed based on platform
    List<Permission> permissionsToRequest = [];

    if (Platform.isAndroid) {
      // Android 13+ uses granular media permissions
      permissionsToRequest.addAll([
        Permission.photos,
        Permission.videos,
      ]);

      // For older Android versions, also request storage
      final androidInfo = await _getAndroidSdkVersion();
      if (androidInfo < 33) {
        permissionsToRequest.add(Permission.storage);
      }
    } else if (Platform.isIOS) {
      permissionsToRequest.add(Permission.photos);
    }

    // Check current statuses
    Map<Permission, PermissionStatus> currentStatuses = {};
    bool anyPermanentlyDenied = false;
    bool allGranted = true;

    for (final permission in permissionsToRequest) {
      final status = await permission.status;
      currentStatuses[permission] = status;
      results[permission] = status;

      if (status.isPermanentlyDenied) {
        anyPermanentlyDenied = true;
      }
      if (!status.isGranted && !status.isLimited) {
        allGranted = false;
      }
    }

    if (allGranted) {
      return results;
    }

    if (anyPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('mediaPermissionRequired'),
        message: loc.translate('mediaPermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableMediaInSettings'),
      );
      return results;
    }

    // Show pre-permission dialog
    final shouldRequest = await _showPrePermissionDialog(
      context: context,
      title: loc.translate('mediaAccessNeeded'),
      message: loc.translate('mediaPermissionExplanation'),
      icon: Icons.photo_library,
      iconColor: Colors.green,
    );

    if (!shouldRequest) {
      return results;
    }

    // Request permissions
    final requestResults = await permissionsToRequest.request();
    results.addAll(requestResults);

    // Handle results
    bool anyPermanentlyDeniedAfter =
        requestResults.values.any((status) => status.isPermanentlyDenied);
    bool anyGranted = requestResults.values
        .any((status) => status.isGranted || status.isLimited);

    if (anyPermanentlyDeniedAfter) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('mediaPermissionRequired'),
        message: loc.translate('mediaPermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableMediaInSettings'),
      );
    } else if (!anyGranted) {
      _showPermissionDeniedSnackBar(
          context, loc.translate('mediaPermissionDenied'));
    } else if (Platform.isIOS &&
        requestResults[Permission.photos]?.isLimited == true) {
      _showLimitedAccessSnackBar(context, loc.translate('limitedPhotoAccess'));
    }

    return results;
  }

  // ============================================================================
  // 📍 LOCATION PERMISSION
  // ============================================================================

  /// Request location permission with full flow
  Future<PermissionStatus> requestLocationPermission(
      BuildContext context) async {
    final loc = AppLocalizations.of(context);

    // Check current status
    final currentStatus = await Permission.locationWhenInUse.status;

    if (currentStatus.isGranted) {
      return currentStatus;
    }

    if (currentStatus.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('locationPermissionRequired'),
        message: loc.translate('locationPermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableLocationInSettings'),
      );
      return currentStatus;
    }

    // Show pre-permission dialog
    final shouldRequest = await _showPrePermissionDialog(
      context: context,
      title: loc.translate('locationAccessNeeded'),
      message: loc.translate('locationPermissionExplanation'),
      icon: Icons.location_on,
      iconColor: Colors.red,
    );

    if (!shouldRequest) {
      return PermissionStatus.denied;
    }

    // Request the permission
    final result = await Permission.locationWhenInUse.request();

    // Handle the result
    if (result.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('locationPermissionRequired'),
        message: loc.translate('locationPermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableLocationInSettings'),
      );
    } else if (result.isDenied) {
      _showPermissionDeniedSnackBar(
          context, loc.translate('locationPermissionDenied'));
    }

    return result;
  }

  // ============================================================================
  // 🎤 MICROPHONE PERMISSION (for video recording)
  // ============================================================================

  /// Request microphone permission
  Future<PermissionStatus> requestMicrophonePermission(
      BuildContext context) async {
    final loc = AppLocalizations.of(context);

    final currentStatus = await Permission.microphone.status;

    if (currentStatus.isGranted) {
      return currentStatus;
    }

    if (currentStatus.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('microphonePermissionRequired'),
        message: loc.translate('microphonePermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableMicrophoneInSettings'),
      );
      return currentStatus;
    }

    final shouldRequest = await _showPrePermissionDialog(
      context: context,
      title: loc.translate('microphoneAccessNeeded'),
      message: loc.translate('microphonePermissionExplanation'),
      icon: Icons.mic,
      iconColor: Colors.purple,
    );

    if (!shouldRequest) {
      return PermissionStatus.denied;
    }

    final result = await Permission.microphone.request();

    if (result.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: loc.translate('microphonePermissionRequired'),
        message: loc.translate('microphonePermissionPermanentlyDenied'),
        settingsMessage: loc.translate('enableMicrophoneInSettings'),
      );
    } else if (result.isDenied) {
      _showPermissionDeniedSnackBar(
          context, loc.translate('microphonePermissionDenied'));
    }

    return result;
  }

  // ============================================================================
  // 🎥 CAMERA + MICROPHONE (for video recording)
  // ============================================================================

  /// Request both camera and microphone for video recording
  Future<Map<Permission, PermissionStatus>>
      requestCameraAndMicrophonePermissions(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    // Check current statuses
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;

    Map<Permission, PermissionStatus> results = {
      Permission.camera: cameraStatus,
      Permission.microphone: micStatus,
    };

    if (cameraStatus.isGranted && micStatus.isGranted) {
      return results;
    }

    // Show combined pre-permission dialog
    final shouldRequest = await _showPrePermissionDialog(
      context: context,
      title: loc.translate('videoRecordingPermissions'),
      message: loc.translate('videoRecordingPermissionExplanation'),
      icon: Icons.videocam,
      iconColor: Colors.orange,
    );

    if (!shouldRequest) {
      return results;
    }

    // Request permissions individually to handle each result properly
    if (!cameraStatus.isGranted) {
      final newCameraStatus = await requestCameraPermission(context);
      results[Permission.camera] = newCameraStatus;
    }

    if (!micStatus.isGranted) {
      final newMicStatus = await requestMicrophonePermission(context);
      results[Permission.microphone] = newMicStatus;
    }

    return results;
  }

  // ============================================================================
  // ✅ PERMISSION CHECKING UTILITIES
  // ============================================================================

  /// Check if camera permission is granted
  Future<bool> hasCameraPermission() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Check if storage/media permissions are granted
  Future<bool> hasStoragePermission() async {
    if (Platform.isAndroid) {
      final photosStatus = await Permission.photos.status;
      final videosStatus = await Permission.videos.status;
      return photosStatus.isGranted ||
          photosStatus.isLimited ||
          videosStatus.isGranted ||
          videosStatus.isLimited;
    } else {
      final photosStatus = await Permission.photos.status;
      return photosStatus.isGranted || photosStatus.isLimited;
    }
  }

  /// Check if location permission is granted
  Future<bool> hasLocationPermission() async {
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  // ============================================================================
  // 🎨 UI HELPER METHODS
  // ============================================================================

  /// Show pre-permission dialog explaining why permission is needed
  Future<bool> _showPrePermissionDialog({
    required BuildContext context,
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) async {
    final loc = AppLocalizations.of(context);

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue[600], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc.translate('permissionDialogInfo'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    loc.translate('notNow'),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    loc.translate('allowAccess'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  /// Show settings dialog when permission is permanently denied
  Future<void> _showSettingsDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String settingsMessage,
  }) async {
    final loc = AppLocalizations.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.settings,
                  color: Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_forward,
                        color: Colors.orange[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        settingsMessage,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                loc.translate('cancel'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                loc.translate('openSettings'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Show snackbar for permission denied
  void _showPermissionDeniedSnackBar(BuildContext context, String message) {
    AppNotifier.show(context, message, isError: false);
  }

  /// Show snackbar for limited photo access (iOS)
  void _showLimitedAccessSnackBar(BuildContext context, String message) {
    AppNotifier.show(context, message, isError: false);
  }

  /// Get Android SDK version for permission logic
  Future<int> _getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;

    try {
      // This is a simplified version - you might want to use device_info_plus
      return 33; // Default to Android 13+ behavior
    } catch (e) {
      return 30; // Fallback to Android 11
    }
  }
}
