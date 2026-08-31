import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:broker_wallet/src/services/clean_media_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class MediaSelectionService {
  static final ImagePicker _imagePicker = ImagePicker();
  static final CleanMediaService _cleanMediaService = CleanMediaService();

  /// Show media type selection bottom sheet
  static Future<String?> showMediaSelectionDialog(BuildContext context) async {
    // Showing media selection bottom sheet (log removed)
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final colors = Theme.of(context).colorScheme;
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(
                        (0.4 * 255).round(),
                        colors.onSurfaceVariant.red,
                        colors.onSurfaceVariant.green,
                        colors.onSurfaceVariant.blue),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    AppLocalizations.of(context).translate('selectMediaType'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                // Camera options
                _buildMediaOption(
                  context,
                  icon: Icons.camera_alt_rounded,
                  color: Colors.blue,
                  title: AppLocalizations.of(context).translate('takePhoto'),
                  subtitle: AppLocalizations.of(context)
                      .translate('useCameraToCapture'),
                  value: 'camera_photo',
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.videocam_rounded,
                  color: Colors.red,
                  title: AppLocalizations.of(context).translate('recordVideo'),
                  subtitle: AppLocalizations.of(context)
                      .translate('useCameraToRecord'),
                  value: 'camera_video',
                ),
                const Divider(height: 1),
                // Gallery options
                _buildMediaOption(
                  context,
                  icon: Icons.photo_library_rounded,
                  color: Colors.green,
                  title: AppLocalizations.of(context).translate('gallery'),
                  subtitle: AppLocalizations.of(context)
                      .translate('chooseFromGallery'),
                  value: 'gallery_photo',
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.video_library_rounded,
                  color: Colors.orange,
                  title: AppLocalizations.of(context).translate('videoGallery'),
                  subtitle: AppLocalizations.of(context)
                      .translate('selectVideoFromGallery'),
                  value: 'gallery_video',
                ),
                const Divider(height: 1),
                // File options
                _buildMediaOption(
                  context,
                  icon: Icons.description_rounded,
                  color: Colors.purple,
                  title: AppLocalizations.of(context).translate('documents'),
                  subtitle:
                      AppLocalizations.of(context).translate('selectDocuments'),
                  value: 'documents',
                ),
                _buildMediaOption(
                  context,
                  icon: Icons.folder_rounded,
                  color: Colors.teal,
                  title: AppLocalizations.of(context).translate('allFiles'),
                  subtitle: AppLocalizations.of(context)
                      .translate('selectAnyFileType'),
                  value: 'all_files',
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildMediaOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Media option selected (log removed): $value
          Navigator.pop(context, value);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick files based on type with improved handling
  static Future<List<PlatformFile>> pickFiles(String type) async {
    // Picking files for type (log removed): $type

    try {
      switch (type) {
        case 'camera_photo':
          return await _pickImageFromCamera();
        case 'camera_video':
          return await _pickVideoFromCamera();
        case 'gallery_photo':
          return await _pickImagesFromGallery();
        case 'gallery_video':
          return await _pickVideosFromGallery();
        case 'documents':
          return await _pickDocuments();
        case 'all_files':
          return await _pickAllFiles();
        default:
          // Unknown file type (log removed): $type
          return [];
      }
    } catch (e) {
      // Error picking files (log removed): $e
      rethrow;
    }
  }

  static Future<List<PlatformFile>> _pickImageFromCamera() async {
    // Picking image from camera (log removed)
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      return [
        PlatformFile(
          name: image.name,
          path: image.path,
          size: bytes.length,
          bytes: bytes,
        )
      ];
    }
    return [];
  }

  static Future<List<PlatformFile>> _pickVideoFromCamera() async {
    // Picking video from camera (log removed)
    final XFile? video = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 5),
    );

    if (video != null) {
      final bytes = await video.readAsBytes();
      return [
        PlatformFile(
          name: video.name,
          path: video.path,
          size: bytes.length,
          bytes: bytes,
        )
      ];
    }
    return [];
  }

  static Future<List<PlatformFile>> _pickImagesFromGallery() async {
    // Picking images from gallery (log removed)
    final List<XFile> images = await _imagePicker.pickMultipleMedia(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );

    List<PlatformFile> files = [];
    for (final image in images) {
      final bytes = await image.readAsBytes();
      files.add(PlatformFile(
        name: image.name,
        path: image.path,
        size: bytes.length,
        bytes: bytes,
      ));
    }
    return files;
  }

  static Future<List<PlatformFile>> _pickVideosFromGallery() async {
    // Picking videos from gallery (log removed)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    return result?.files ?? [];
  }

  static Future<List<PlatformFile>> _pickDocuments() async {
    // Picking documents (log removed)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'],
      allowMultiple: true,
    );
    return result?.files ?? [];
  }

  static Future<List<PlatformFile>> _pickAllFiles() async {
    // Picking all files (log removed)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    return result?.files ?? [];
  }

  /// Show success message
  static void showSuccessMessage(BuildContext context, int fileCount) {
    final loc = AppLocalizations.of(context);
    _showToast(
        '${loc.translate('filesSelectedSuccessfully').replaceAll('{count}', fileCount.toString())}',
        Colors.green);
  }

  /// Show error message
  static void showErrorMessage(BuildContext context, String error) {
    final loc = AppLocalizations.of(context);
    _showToast('${loc.translate('errorSelectingFiles')}: $error', Colors.red);
  }

  static void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }
}
