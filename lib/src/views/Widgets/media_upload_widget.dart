import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/Views/Widgets/unified_media_preview_grid.dart';

class MediaUploadWidget extends StatelessWidget {
  final List<PlatformFile> selectedFiles;
  final List<String> existingFileUrls; // Add this for existing uploaded files
  final VoidCallback onSelectMedia;
  final VoidCallback? onUpload;
  final Function(int) onRemoveFile;
  final Function(int)?
      onRemoveExistingFile; // Add this for removing existing files
  final VoidCallback onClearAll;
  final bool isUploading;
  final bool showUploadButton;
  final int maxDisplayFiles;
  final String? hintText;
  final String? uploadButtonText;
  final List<String>? allowedExtensions;
  final AppLocalizations localization;
  final bool showImagePreview; // New parameter for image preview

  const MediaUploadWidget({
    super.key,
    required this.selectedFiles,
    this.existingFileUrls = const [],
    required this.onSelectMedia,
    this.onUpload,
    required this.onRemoveFile,
    this.onRemoveExistingFile,
    required this.onClearAll,
    required this.localization,
    this.isUploading = false,
    this.showUploadButton = true,
    this.maxDisplayFiles = 4,
    this.hintText,
    this.uploadButtonText,
    this.allowedExtensions,
    this.showImagePreview =
        false, // Default to false for backward compatibility
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveHintText =
        hintText ?? localization.translate('uploadMediaHint');

    // Convert files to unified media items
    final mediaItems = <MediaPreviewItem>[
      // Existing URLs first
      ...existingFileUrls.map((url) => MediaPreviewItem.fromUrl(url)),
      // Selected files second
      ...selectedFiles.map((file) => MediaPreviewItem.fromFile(file)),
    ];

    final hasAnyFiles = mediaItems.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Upload Container
        _buildUploadContainer(context, colors, effectiveHintText, hasAnyFiles),

        // Unified Media Preview Grid
        if (hasAnyFiles) ...[
          const SizedBox(height: 12),
          UnifiedMediaPreviewGrid(
            mediaItems: mediaItems,
            onRemove: (index) {
              // Determine if this is an existing file or selected file
              if (index < existingFileUrls.length) {
                // Remove existing file
                onRemoveExistingFile?.call(index);
              } else {
                // Remove selected file
                final selectedFileIndex = index - existingFileUrls.length;
                onRemoveFile(selectedFileIndex);
              }
            },
            onAddMore: showUploadButton ? onSelectMedia : null,
            showAddButton: !isUploading,
            maxDisplayFiles: maxDisplayFiles,
            localization: localization,
          ),
        ],

        // Upload button if no files and we want to show it
        if (!hasAnyFiles && showUploadButton) ...[
          const SizedBox(height: 12),
          UnifiedMediaPreviewGrid(
            mediaItems: const [],
            onRemove: (_) {},
            onAddMore: onSelectMedia,
            showAddButton: true,
            localization: localization,
          ),
        ],
      ],
    );
  }

  Widget _buildUploadContainer(BuildContext context, ColorScheme colors,
      String hintText, bool hasFiles) {
    return GestureDetector(
      onTap: isUploading ? null : onSelectMedia,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: hasFiles
              ? Border.all(color: colors.primary.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              Icons.attach_file,
              size: 22,
              color: hasFiles ? colors.primary : const Color(0xFF8B959A),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                !hasFiles
                    ? hintText
                    : showImagePreview && maxDisplayFiles == 1
                        ? 'Logo selected: '
                        : '${selectedFiles.length + existingFileUrls.length} file(s) selected',
                style: AppTextStyles.hintText.copyWith(
                  color: hasFiles ? colors.onSurface : null,
                ),
              ),
            ),
            // Show replace button for single image preview
            if (hasFiles && showImagePreview && maxDisplayFiles == 1)
              _buildReplaceButton(colors),
            // Show add more button for multiple files (show when files exist and not in single preview mode)
            if (hasFiles && !showImagePreview) _buildAddMoreButton(colors),
            _buildMainUploadButton(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildReplaceButton(ColorScheme colors) {
    return GestureDetector(
      onTap: onSelectMedia,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary),
        ),
        child: Text(
          'Replace',
          style: TextStyle(
            color: colors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildAddMoreButton(ColorScheme colors) {
    return GestureDetector(
      onTap: onSelectMedia,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary),
        ),
        child: Icon(
          Icons.add,
          color: colors.primary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildMainUploadButton(ColorScheme colors) {
    return Container(
        margin: const EdgeInsets.all(7),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: isUploading
              ? colors.primary.withValues(alpha: 0.6)
              : colors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SvgPicture.asset(
          SvgIcon.uploadMedia,
          width: 24,
          height: 24,
        ));
  }

  // Utility methods remain the same...
  String getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
      return 'image';
    } else if (['mp4', 'mov', 'avi', 'mkv'].contains(extension)) {
      return 'video';
    } else {
      return 'document';
    }
  }

  IconData getFileIcon(String fileName) {
    final type = getFileType(fileName);
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      default:
        return Icons.description;
    }
  }

  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Helper methods for URL-based files
  String getFileTypeFromUrl(String url) {
    final extension = url.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
      return 'image';
    } else if (['mp4', 'mov', 'avi', 'mkv'].contains(extension)) {
      return 'video';
    } else {
      return 'document';
    }
  }

  IconData getFileIconFromUrl(String url) {
    final type = getFileTypeFromUrl(url);
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      default:
        return Icons.description;
    }
  }
}
