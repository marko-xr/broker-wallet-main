import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

/// Comprehensive permission handling service for Broker Wallet
/// Handles all device permissions with user-friendly UI flows
class PermissionService {
  // Singleton pattern
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Request camera permission with proper UI flow
  /// Shows rationale dialog if needed and handles all permission states
  Future<PermissionStatus> requestCameraPermission(BuildContext context) async {
    PermissionStatus status = await Permission.camera.status;

    // Already granted
    if (status.isGranted) {
      return status;
    }

    // Check if we should show rationale
    if (status.isDenied) {
      bool shouldRequest = true;

      if (await Permission.camera.shouldShowRequestRationale) {
        // Show custom rationale dialog
        shouldRequest = await _showRationaleDialog(
              context: context,
              title: 'Camera Access Required',
              message:
                  'Broker Wallet needs camera access to take photos and videos of properties, documents, and create visual content for your listings.',
              icon: Icons.camera_alt,
            ) ??
            false;
      }

      if (shouldRequest) {
        status = await Permission.camera.request();
        return status;
      } else {
        return status;
      }
    }

    // Permanently denied - guide to settings
    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Camera Permission Required',
        message:
            'Camera access was permanently denied. Please enable it in app settings to take photos and videos.',
        icon: Icons.camera_alt,
      );
      return status;
    }

    // First time - direct request
    status = await Permission.camera.request();
    return status;
  }

  /// Request photo library permission with proper UI flow
  Future<PermissionStatus> requestPhotosPermission(BuildContext context) async {
    PermissionStatus status = await Permission.photos.status;

    if (status.isGranted || status.isLimited) {
      return status;
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Photo Library Permission Required',
        message:
            'Photo library access was permanently denied. Please enable it in app settings to select images.',
        icon: Icons.photo_library,
      );
      return status;
    }

    bool shouldRequest = true;

    if (status.isDenied && await Permission.photos.shouldShowRequestRationale) {
      shouldRequest = await _showRationaleDialog(
            context: context,
            title: 'Photo Library Access Required',
            message:
                'Broker Wallet needs access to your photo library to select property images, documents, and media for your listings.',
            icon: Icons.photo_library,
          ) ??
          false;
    }

    if (!shouldRequest) {
      return status;
    }

    if (!status.isGranted && !status.isLimited) {
      status = await Permission.photos.request();
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Photo Library Permission Required',
        message:
            'Photo library access was permanently denied. Please enable it in app settings to select images.',
        icon: Icons.photo_library,
      );
      return status;
    }

    if (status.isGranted || status.isLimited) {
      return status;
    }

    if (Platform.isAndroid) {
      final fallbackStatus = await requestStoragePermission(context);
      return fallbackStatus;
    }

    return status;
  }

  /// Request storage/media permissions (Android 13+ specific handling)
  Future<Map<Permission, PermissionStatus>> requestStoragePermissions(
    BuildContext context, {
    bool includePhotos = true,
    bool includeVideos = true,
    bool includeLegacyStorage = true,
  }) async {
    Map<Permission, PermissionStatus> statuses = {};

    // Determine which permissions to request based on platform support
    final Set<Permission> mediaPermissions = <Permission>{};

    if (includePhotos) {
      mediaPermissions.add(Permission.photos);
    }

    if (includeVideos) {
      mediaPermissions.add(Permission.videos);
    }

    if (includeLegacyStorage && Platform.isAndroid) {
      mediaPermissions.add(Permission.storage);
    }

    // Check current status
    bool allGranted = true;
    for (var permission in mediaPermissions) {
      final status = await permission.status;
      statuses[permission] = status;
      if (!status.isGranted && !status.isLimited) {
        allGranted = false;
      }
    }

    if (allGranted) {
      return statuses;
    }

    // Show rationale if needed
    bool shouldRequest = true;
    bool needsRationale = false;

    for (var permission in mediaPermissions) {
      if (await permission.shouldShowRequestRationale) {
        needsRationale = true;
        break;
      }
    }

    if (needsRationale) {
      shouldRequest = await _showRationaleDialog(
            context: context,
            title: 'Media Access Required',
            message:
                'Broker Wallet needs access to your media files to manage property photos, videos, and documents. This helps you organize and share your real estate content.',
            icon: Icons.perm_media,
          ) ??
          false;
    }

    if (shouldRequest && mediaPermissions.isNotEmpty) {
      statuses = await mediaPermissions.toList().request();

      // Check if any are permanently denied
      bool hasPermDenied =
          statuses.values.any((status) => status.isPermanentlyDenied);
      if (hasPermDenied) {
        await _showSettingsDialog(
          context: context,
          title: 'Media Access Required',
          message:
              'Media or file access permissions were denied. Please enable them in app settings to manage your property content.',
          icon: Icons.perm_media,
        );
      }
    }

    return statuses;
  }

  /// Request location permission (when in use)
  Future<PermissionStatus> requestLocationWhenInUse(
      BuildContext context) async {
    PermissionStatus status = await Permission.locationWhenInUse.status;

    if (status.isGranted) {
      return status;
    }

    if (status.isDenied) {
      bool shouldRequest = true;

      if (await Permission.locationWhenInUse.shouldShowRequestRationale) {
        shouldRequest = await _showRationaleDialog(
              context: context,
              title: 'Location Access Required',
              message:
                  'Broker Wallet needs your location to show property locations on the map, find nearby properties, and help you navigate to listings.',
              icon: Icons.location_on,
            ) ??
            false;
      }

      if (shouldRequest) {
        status = await Permission.locationWhenInUse.request();
        return status;
      } else {
        return status;
      }
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Location Permission Required',
        message:
            'Location access was permanently denied. Please enable it in app settings to use map features.',
        icon: Icons.location_on,
      );
      return status;
    }

    status = await Permission.locationWhenInUse.request();
    return status;
  }

  /// Request phone permission for making calls
  Future<PermissionStatus> requestPhonePermission(BuildContext context) async {
    PermissionStatus status = await Permission.phone.status;

    if (status.isGranted) {
      return status;
    }

    if (status.isDenied) {
      bool shouldRequest = true;

      if (await Permission.phone.shouldShowRequestRationale) {
        shouldRequest = await _showRationaleDialog(
              context: context,
              title: 'Phone Access Required',
              message:
                  'Broker Wallet needs phone access to make calls to your contacts, clients, and property owners directly from the app.',
              icon: Icons.phone,
            ) ??
            false;
      }

      if (shouldRequest) {
        status = await Permission.phone.request();
        return status;
      } else {
        return status;
      }
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Phone Permission Required',
        message:
            'Phone access was permanently denied. Please enable it in app settings to make calls.',
        icon: Icons.phone,
      );
      return status;
    }

    status = await Permission.phone.request();
    return status;
  }

  /// Request microphone permission for video recording
  Future<PermissionStatus> requestMicrophonePermission(
      BuildContext context) async {
    PermissionStatus status = await Permission.microphone.status;

    if (status.isGranted) {
      return status;
    }

    if (status.isDenied) {
      bool shouldRequest = true;

      if (await Permission.microphone.shouldShowRequestRationale) {
        shouldRequest = await _showRationaleDialog(
              context: context,
              title: 'Microphone Access Required',
              message:
                  'Broker Wallet needs microphone access to record videos with audio for property tours and presentations.',
              icon: Icons.mic,
            ) ??
            false;
      }

      if (shouldRequest) {
        status = await Permission.microphone.request();
        return status;
      } else {
        return status;
      }
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Microphone Permission Required',
        message:
            'Microphone access was permanently denied. Please enable it in app settings to record videos with audio.',
        icon: Icons.mic,
      );
      return status;
    }

    status = await Permission.microphone.request();
    return status;
  }

  /// Request storage permission (for Android 10 and below, or specific file access)
  Future<PermissionStatus> requestStoragePermission(
      BuildContext context) async {
    PermissionStatus status = await Permission.storage.status;

    if (status.isGranted) {
      return status;
    }

    if (status.isDenied) {
      bool shouldRequest = true;

      if (await Permission.storage.shouldShowRequestRationale) {
        shouldRequest = await _showRationaleDialog(
              context: context,
              title: 'Storage Access Required',
              message:
                  'Broker Wallet needs storage access to save and access your property documents, PDFs, and media files.',
              icon: Icons.folder,
            ) ??
            false;
      }

      if (shouldRequest) {
        status = await Permission.storage.request();
        return status;
      } else {
        return status;
      }
    }

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Storage Permission Required',
        message:
            'Storage access was permanently denied. Please enable it in app settings to save and access files.',
        icon: Icons.folder,
      );
      return status;
    }

    status = await Permission.storage.request();
    return status;
  }

  /// Request multiple permissions at once for camera + media workflows
  Future<Map<Permission, PermissionStatus>> requestCameraAndMediaPermissions(
    BuildContext context,
  ) async {
    List<Permission> permissions = [
      Permission.camera,
      Permission.microphone,
      Permission.photos,
    ];

    // Check current status
    Map<Permission, PermissionStatus> currentStatuses = {};
    bool allGranted = true;

    for (var permission in permissions) {
      final status = await permission.status;
      currentStatuses[permission] = status;
      if (!status.isGranted && !status.isLimited) {
        allGranted = false;
      }
    }

    if (allGranted) {
      return currentStatuses;
    }

    // Show rationale
    bool shouldRequest = await _showRationaleDialog(
          context: context,
          title: 'Camera & Media Access Required',
          message:
              'Broker Wallet needs access to your camera, microphone, and media library to capture and manage property photos and videos.',
          icon: Icons.photo_camera,
        ) ??
        false;

    if (!shouldRequest) {
      return currentStatuses;
    }

    // Request all permissions
    final statuses = await permissions.request();

    // Check for permanently denied permissions
    bool hasPermDenied =
        statuses.values.any((status) => status.isPermanentlyDenied);
    if (hasPermDenied) {
      await _showSettingsDialog(
        context: context,
        title: 'Permissions Required',
        message:
            'Some permissions were denied. Please enable camera, microphone, and media access in app settings.',
        icon: Icons.photo_camera,
      );
    }

    return statuses;
  }

  /// Check if a permission is granted (simple utility)
  Future<bool> isPermissionGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted || status.isLimited;
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Permission.location.serviceStatus.isEnabled;
  }

  /// Show rationale dialog before requesting permission
  Future<bool?> _showRationaleDialog({
    required BuildContext context,
    required String title,
    required String message,
    required IconData icon,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor, size: 28),
              const SizedBox(width: 12),
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
          content: Text(
            message,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not Now',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 15,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 15),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Show settings dialog when permission is permanently denied
  Future<void> _showSettingsDialog({
    required BuildContext context,
    required String title,
    required String message,
    required IconData icon,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(icon, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
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
                  fontSize: 15,
                  color: Colors.grey[700],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can change this in Settings > Broker Wallet > Permissions',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
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
                'Cancel',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 15,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'Open Settings',
                style: TextStyle(fontSize: 15),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Show snackbar for permission status feedback
  void showPermissionStatusSnackBar(
    BuildContext context,
    String permissionName,
    PermissionStatus status,
  ) {
    String message;
    Color backgroundColor;
    IconData icon;

    if (status.isGranted) {
      message = '$permissionName permission granted!';
      backgroundColor = Colors.green;
      icon = Icons.check_circle;
    } else if (status.isLimited) {
      message = '$permissionName permission granted with limited access.';
      backgroundColor = Colors.orange;
      icon = Icons.warning;
    } else if (status.isDenied) {
      message = '$permissionName permission denied.';
      backgroundColor = Colors.red;
      icon = Icons.cancel;
    } else if (status.isPermanentlyDenied) {
      message =
          '$permissionName permission permanently denied. Open settings to enable.';
      backgroundColor = Colors.deepOrange;
      icon = Icons.block;
    } else if (status.isRestricted) {
      message = '$permissionName permission is restricted.';
      backgroundColor = Colors.grey;
      icon = Icons.lock;
    } else {
      message = '$permissionName permission status: ${status.name}';
      backgroundColor = Colors.grey;
      icon = Icons.info;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
