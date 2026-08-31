import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:broker_wallet/src/services/clean_permission_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Clean media service that handles all media picking with proper permission flows
/// Replaces direct ImagePicker usage and MediaPermissionWrapper
class CleanMediaService {
  static final CleanMediaService _instance = CleanMediaService._internal();
  factory CleanMediaService() => _instance;
  CleanMediaService._internal();

  final ImagePicker _picker = ImagePicker();
  final CleanPermissionService _permissionService = CleanPermissionService();

  // ============================================================================
  // 📸 IMAGE CAPTURE AND SELECTION
  // ============================================================================

  /// Pick image from camera with permission handling
  Future<File?> pickImageFromCamera(BuildContext context) async {
    try {
      // Request camera permission
      final permission =
          await _permissionService.requestCameraPermission(context);

      if (!permission.isGranted) {
        return null;
      }

      // Pick image from camera
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        return File(image.path);
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to capture image: ${e.toString()}');
      return null;
    }
  }

  /// Pick image from gallery with permission handling
  Future<File?> pickImageFromGallery(BuildContext context) async {
    try {
      // Request storage permission
      final permissions =
          await _permissionService.requestStoragePermissions(context);

      final hasPermission = permissions.values.any(
        (status) => status.isGranted || status.isLimited,
      );

      if (!hasPermission) {
        return null;
      }

      // Pick image from gallery
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        return File(image.path);
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to select image: ${e.toString()}');
      return null;
    }
  }

  /// Pick multiple images from gallery
  Future<List<File>?> pickMultipleImagesFromGallery(
      BuildContext context) async {
    try {
      // Request storage permission
      final permissions =
          await _permissionService.requestStoragePermissions(context);

      final hasPermission = permissions.values.any(
        (status) => status.isGranted || status.isLimited,
      );

      if (!hasPermission) {
        return null;
      }

      // Pick multiple images
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (images.isNotEmpty) {
        return images.map((image) => File(image.path)).toList();
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to select images: ${e.toString()}');
      return null;
    }
  }

  // ============================================================================
  // 🎥 VIDEO CAPTURE AND SELECTION
  // ============================================================================

  /// Pick video from camera with permission handling
  Future<File?> pickVideoFromCamera(BuildContext context) async {
    try {
      // Request camera and microphone permissions
      final permissions = await _permissionService
          .requestCameraAndMicrophonePermissions(context);

      final cameraGranted = permissions[Permission.camera]?.isGranted ?? false;
      final micGranted = permissions[Permission.microphone]?.isGranted ?? false;

      if (!cameraGranted) {
        return null;
      }

      // Show warning if microphone not granted
      if (!micGranted) {
        _showWarningSnackBar(context, 'Video will be recorded without audio');
      }

      // Pick video from camera
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        return File(video.path);
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to record video: ${e.toString()}');
      return null;
    }
  }

  /// Pick video from gallery with permission handling
  Future<File?> pickVideoFromGallery(BuildContext context) async {
    try {
      // Request storage permission
      final permissions =
          await _permissionService.requestStoragePermissions(context);

      final hasPermission = permissions.values.any(
        (status) => status.isGranted || status.isLimited,
      );

      if (!hasPermission) {
        return null;
      }

      // Pick video from gallery
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (video != null) {
        return File(video.path);
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to select video: ${e.toString()}');
      return null;
    }
  }

  // ============================================================================
  // 📄 DOCUMENT AND FILE SELECTION
  // ============================================================================

  /// Pick documents with permission handling
  Future<List<PlatformFile>?> pickDocuments(BuildContext context) async {
    try {
      // Request storage permission
      final permissions =
          await _permissionService.requestStoragePermissions(context);

      final hasPermission = permissions.values.any(
        (status) => status.isGranted || status.isLimited,
      );

      if (!hasPermission) {
        return null;
      }

      // Pick documents
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files;
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(
          context, 'Failed to select documents: ${e.toString()}');
      return null;
    }
  }

  // ============================================================================
  // 🎭 USER CHOICE DIALOGS
  // ============================================================================

  /// Show comprehensive media selection dialog with all options
  Future<List<PlatformFile>?> showMediaSelectionDialog(
      BuildContext context) async {
    final loc = AppLocalizations.of(context);

    final String? selectedOption = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Colors.blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.translate('selectMediaType'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            loc.translate('chooseMediaSource'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Options
              _buildMediaOption(
                context: context,
                icon: Icons.camera_alt,
                title: loc.translate('camera'),
                subtitle: loc.translate('takePhoto'),
                color: Colors.blue,
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              _buildMediaOption(
                context: context,
                icon: Icons.videocam,
                title: loc.translate('videoCamera'),
                subtitle: loc.translate('recordVideo'),
                color: Colors.red,
                onTap: () => Navigator.pop(context, 'video_camera'),
              ),
              _buildMediaOption(
                context: context,
                icon: Icons.photo_library,
                title: loc.translate('gallery'),
                subtitle: loc.translate('selectFromGallery'),
                color: Colors.green,
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              _buildMediaOption(
                context: context,
                icon: Icons.video_library,
                title: loc.translate('videoGallery'),
                subtitle: loc.translate('selectVideoFromGallery'),
                color: Colors.purple,
                onTap: () => Navigator.pop(context, 'video_gallery'),
              ),
              _buildMediaOption(
                context: context,
                icon: Icons.description,
                title: loc.translate('documents'),
                subtitle: loc.translate('selectDocuments'),
                color: Colors.orange,
                onTap: () => Navigator.pop(context, 'documents'),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );

    if (selectedOption == null) return null;

    // Handle the selected option
    switch (selectedOption) {
      case 'camera':
        final file = await pickImageFromCamera(context);
        if (file != null) {
          final bytes = await file.readAsBytes();
          return [
            PlatformFile(
              name: file.path.split(Platform.pathSeparator).last,
              path: file.path,
              size: bytes.length,
              bytes: bytes,
            )
          ];
        }
        break;

      case 'video_camera':
        final file = await pickVideoFromCamera(context);
        if (file != null) {
          final bytes = await file.readAsBytes();
          return [
            PlatformFile(
              name: file.path.split(Platform.pathSeparator).last,
              path: file.path,
              size: bytes.length,
              bytes: bytes,
            )
          ];
        }
        break;

      case 'gallery':
        final files = await pickMultipleImagesFromGallery(context);
        if (files != null && files.isNotEmpty) {
          final platformFiles = <PlatformFile>[];
          for (final file in files) {
            final bytes = await file.readAsBytes();
            platformFiles.add(
              PlatformFile(
                name: file.path.split(Platform.pathSeparator).last,
                path: file.path,
                size: bytes.length,
                bytes: bytes,
              ),
            );
          }
          return platformFiles;
        }
        break;

      case 'video_gallery':
        final file = await pickVideoFromGallery(context);
        if (file != null) {
          final bytes = await file.readAsBytes();
          return [
            PlatformFile(
              name: file.path.split(Platform.pathSeparator).last,
              path: file.path,
              size: bytes.length,
              bytes: bytes,
            )
          ];
        }
        break;

      case 'documents':
        final files = await pickDocuments(context);
        return files;
    }

    return null;
  }

  /// Show image source selection dialog
  Future<File?> showImageSourceDialog(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    return await showDialog<File?>(
      context: context,
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
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_camera,
                  color: Colors.blue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                loc.translate('selectImageSource'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSourceOption(
                context: context,
                title: loc.translate('camera'),
                subtitle: loc.translate('takeNewPhoto'),
                icon: Icons.camera_alt,
                color: Colors.blue,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await pickImageFromCamera(context);
                  if (context.mounted) {
                    Navigator.pop(context, file);
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildSourceOption(
                context: context,
                title: loc.translate('gallery'),
                subtitle: loc.translate('chooseFromGallery'),
                icon: Icons.photo_library,
                color: Colors.green,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await pickImageFromGallery(context);
                  if (context.mounted) {
                    Navigator.pop(context, file);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                loc.translate('cancel'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Show video source selection dialog
  Future<File?> showVideoSourceDialog(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    return await showDialog<File?>(
      context: context,
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
                  Icons.videocam,
                  color: Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                loc.translate('selectVideoSource'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSourceOption(
                context: context,
                title: loc.translate('camera'),
                subtitle: loc.translate('recordNewVideo'),
                icon: Icons.videocam,
                color: Colors.orange,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await pickVideoFromCamera(context);
                  if (context.mounted) {
                    Navigator.pop(context, file);
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildSourceOption(
                context: context,
                title: loc.translate('gallery'),
                subtitle: loc.translate('chooseFromGallery'),
                icon: Icons.video_library,
                color: Colors.purple,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await pickVideoFromGallery(context);
                  if (context.mounted) {
                    Navigator.pop(context, file);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                loc.translate('cancel'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Show media type selection dialog (image, video, or document)
  Future<File?> showMediaTypeDialog(BuildContext context) async {
    final loc = AppLocalizations.of(context);

    return await showDialog<File?>(
      context: context,
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
                  color: Colors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.attachment,
                  color: Colors.indigo,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                loc.translate('selectMediaType'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSourceOption(
                context: context,
                title: loc.translate('photo'),
                subtitle: loc.translate('takeOrSelectPhoto'),
                icon: Icons.photo_camera,
                color: Colors.blue,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await showImageSourceDialog(context);
                  if (context.mounted) {
                    Navigator.pop(context, file);
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildSourceOption(
                context: context,
                title: loc.translate('video'),
                subtitle: loc.translate('recordOrSelectVideo'),
                icon: Icons.videocam,
                color: Colors.orange,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await showVideoSourceDialog(context);
                  if (context.mounted) {
                    Navigator.pop(context, file);
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildSourceOption(
                context: context,
                title: loc.translate('document'),
                subtitle: loc.translate('selectDocument'),
                icon: Icons.description,
                color: Colors.green,
                onTap: () async {
                  Navigator.pop(context);
                  final files = await pickDocuments(context);
                  if (context.mounted && files != null && files.isNotEmpty) {
                    // Return first file as File object
                    final firstFile = files.first;
                    if (firstFile.path != null) {
                      Navigator.pop(context, File(firstFile.path!));
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                loc.translate('cancel'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // 🛠 HELPER METHODS
  // ============================================================================

  Widget _buildSourceOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    // Use Fluttertoast for lightweight feedback so this can be called from
    // non-widget contexts as well.
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  void _showWarningSnackBar(BuildContext context, String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.orange,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  Widget _buildMediaOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Color.fromARGB(
                    (0.1 * 255).round(), color.red, color.green, color.blue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}
