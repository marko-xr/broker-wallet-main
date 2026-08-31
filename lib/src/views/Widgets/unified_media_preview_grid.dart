import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

enum MediaSourceType { file, url }

class MediaPreviewItem {
  final String identifier; // file path or URL
  final MediaSourceType sourceType;
  final String? displayName;
  final String? contentType;
  final int? size;
  final PlatformFile? platformFile; // Only for file type

  MediaPreviewItem({
    required this.identifier,
    required this.sourceType,
    this.displayName,
    this.contentType,
    this.size,
    this.platformFile,
  });

  // Create from PlatformFile (Save mode)
  factory MediaPreviewItem.fromFile(PlatformFile file) {
    return MediaPreviewItem(
      identifier: file.path ?? '',
      sourceType: MediaSourceType.file,
      displayName: file.name,
      contentType: _getContentTypeFromExtension(file.extension),
      size: file.size,
      platformFile: file,
    );
  }

  // Create from URL (Edit mode)
  factory MediaPreviewItem.fromUrl(String url, {String? contentType}) {
    return MediaPreviewItem(
      identifier: url,
      sourceType: MediaSourceType.url,
      displayName: _getFileNameFromUrl(url),
      contentType: contentType ?? _getContentTypeFromUrl(url),
    );
  }

  static String? _getContentTypeFromExtension(String? extension) {
    if (extension == null) return null;

    final ext = extension.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif']
        .contains(ext)) {
      return 'image/$ext';
    } else if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
      return 'video/$ext';
    } else if (ext == 'pdf') {
      return 'application/pdf';
    } else if (['doc', 'docx'].contains(ext)) {
      return 'application/msword';
    }
    return null;
  }

  static String? _getContentTypeFromUrl(String url) {
    // Try to extract extension from URL
    String cleanUrl = url.split('?').first; // Remove query parameters

    // Handle Firebase Storage URLs with encoded paths
    if (cleanUrl.contains('%2F')) {
      cleanUrl = Uri.decodeFull(cleanUrl);
    }

    final parts = cleanUrl.split('.');
    if (parts.length > 1) {
      return _getContentTypeFromExtension(parts.last);
    }

    // Fallback: try to detect from URL path patterns
    if (url.contains('image') || url.contains('img')) {
      return 'image/jpeg';
    } else if (url.contains('video') || url.contains('vid')) {
      return 'video/mp4';
    } else if (url.contains('pdf')) {
      return 'application/pdf';
    }

    return null;
  }

  static String _getFileNameFromUrl(String url) {
    String cleanUrl = url.split('?').first; // Remove query parameters

    // Handle Firebase Storage URLs with encoded paths
    if (cleanUrl.contains('%2F')) {
      cleanUrl = Uri.decodeFull(cleanUrl);
    }

    final parts = cleanUrl.split('/');
    if (parts.isNotEmpty) {
      String fileName = parts.last;
      // If filename is still encoded or too long, create a shorter name
      if (fileName.length > 30 || fileName.contains('%')) {
        final extension = _extractExtensionFromUrl(url);
        return 'media_file${extension.isNotEmpty ? '.$extension' : ''}';
      }
      return fileName;
    }

    return 'media_file';
  }

  static String _extractExtensionFromUrl(String url) {
    // Try multiple approaches to extract extension
    String cleanUrl = url.split('?').first;
    if (cleanUrl.contains('%2F')) {
      cleanUrl = Uri.decodeFull(cleanUrl);
    }

    final parts = cleanUrl.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }

    return '';
  }

  String get mediaType {
    final content = contentType?.toLowerCase() ?? '';

    if (content.startsWith('image/')) {
      return 'image';
    } else if (content.startsWith('video/')) {
      return 'video';
    } else if (content.contains('pdf')) {
      return 'pdf';
    } else if (content.contains('word') || content.contains('doc')) {
      return 'document';
    }

    return 'document'; // Default fallback
  }

  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isPdf => mediaType == 'pdf';
  bool get isDocument => mediaType == 'document';
}

class UnifiedMediaPreviewGrid extends StatelessWidget {
  final List<MediaPreviewItem> mediaItems;
  final Function(int) onRemove;
  final VoidCallback? onAddMore;
  final bool showAddButton;
  final int maxDisplayFiles;
  final AppLocalizations localization;

  const UnifiedMediaPreviewGrid({
    super.key,
    required this.mediaItems,
    required this.onRemove,
    this.onAddMore,
    this.showAddButton = true,
    this.maxDisplayFiles = 8,
    required this.localization,
  });

  /// Helper method to validate if URL is suitable for CachedNetworkImage
  bool _isValidNetworkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (mediaItems.isEmpty && !showAddButton) {
      return const SizedBox.shrink();
    }

    final displayItems = mediaItems.take(maxDisplayFiles).toList();
    final hasMore = mediaItems.length > maxDisplayFiles;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, colors),
          if (mediaItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildMediaGrid(context, colors, displayItems, hasMore),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mediaItems.isEmpty
                    ? 'No Media Files'
                    : '${mediaItems.length} Media File${mediaItems.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
              ),
              if (mediaItems.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Tap to view details or remove files',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (showAddButton && onAddMore != null)
          GestureDetector(
            onTap: onAddMore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Add Media',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMediaGrid(BuildContext context, ColorScheme colors,
      List<MediaPreviewItem> items, bool hasMore) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < items.length) {
          return _buildMediaTile(context, colors, items[index], index);
        } else {
          return _buildMoreTile(context, colors);
        }
      },
    );
  }

  Widget _buildMediaTile(BuildContext context, ColorScheme colors,
      MediaPreviewItem item, int index) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          // Preview content
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildPreviewContent(item, colors),
            ),
          ),
          // File info overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getTruncatedFileName(item.displayName ?? 'Unknown file'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.size != null)
                    Text(
                      _formatFileSize(item.size!),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Remove button
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => onRemove(index),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent(MediaPreviewItem item, ColorScheme colors) {
    switch (item.mediaType) {
      case 'image':
        if (item.sourceType == MediaSourceType.file &&
            item.platformFile?.path != null) {
          // Use HeicAwareImage widget that handles HEIC conversion automatically
          return HeicAwareImage(filePath: item.platformFile!.path!);
        } else if (item.sourceType == MediaSourceType.file &&
            item.platformFile?.bytes != null) {
          return Image.memory(
            item.platformFile!.bytes!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildErrorPreview('Failed to load image', colors);
            },
          );
        } else if (item.sourceType == MediaSourceType.url) {
          if (_isValidNetworkUrl(item.identifier)) {
            return CachedNetworkImage(
              imageUrl: item.identifier,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: colors.surfaceContainerHighest,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: (context, url, error) {
                return _buildErrorPreview('Failed to load image', colors);
              },
            );
          } else {
            return _buildErrorPreview('Unsupported image URL', colors);
          }
        }
        return _buildErrorPreview('No image data', colors);

      case 'video':
        // ... الكود الخاص بالفيديو كما هو
        return Container(
          color: Colors.black87,
          child: Stack(
            children: [
              Center(
                child: Icon(
                  Icons.videocam_rounded,
                  size: 48,
                  color: colors.primary,
                ),
              ),
              const Positioned(
                bottom: 8,
                right: 8,
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        );

      case 'pdf':
        // ... الكود الخاص بملفات PDF كما هو
        return Container(
          color: Colors.red.withValues(alpha: 0.1),
          child: Center(
            child: Icon(
              Icons.picture_as_pdf,
              size: 48,
              color: Colors.red,
            ),
          ),
        );

      default:
        // ... الكود الافتراضي كما هو
        return Container(
          color: colors.primary.withValues(alpha: 0.1),
          child: Center(
            child: Icon(
              Icons.description,
              size: 48,
              color: colors.primary,
            ),
          ),
        );
    }
  }

  Widget _buildErrorPreview(String message, ColorScheme colors) {
    return Container(
      color: colors.errorContainer,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: colors.error,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: colors.error,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreTile(BuildContext context, ColorScheme colors) {
    final remaining = mediaItems.length - maxDisplayFiles;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.more_horiz,
              size: 32,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '+$remaining more',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTruncatedFileName(String fileName) {
    if (fileName.length <= 15) return fileName;

    final parts = fileName.split('.');
    if (parts.length > 1) {
      final nameWithoutExt = parts.take(parts.length - 1).join('.');
      final extension = parts.last;
      final availableLength = 15 - extension.length - 1; // -1 for the dot

      if (nameWithoutExt.length > availableLength) {
        return '${nameWithoutExt.substring(0, availableLength)}...$extension';
      }
    }

    return '${fileName.substring(0, 15)}...';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Widget that handles HEIC/HEIF images by converting them to JPEG on-the-fly for preview
class HeicAwareImage extends StatefulWidget {
  final String filePath;

  const HeicAwareImage({super.key, required this.filePath});

  @override
  State<HeicAwareImage> createState() => _HeicAwareImageState();
}

class _HeicAwareImageState extends State<HeicAwareImage> {
  Future<Uint8List?>? _imageDataFuture;

  @override
  void initState() {
    super.initState();
    _imageDataFuture = _loadImageData();
  }

  Future<Uint8List?> _loadImageData() async {
    final file = File(widget.filePath);
    if (!await file.exists()) {
      return null;
    }

    final extension = widget.filePath.split('.').last.toLowerCase();
    final isHeic = extension == 'heic' || extension == 'heif';

    if (isHeic) {
      // Convert HEIC to JPEG in memory for display
      try {
        final result = await FlutterImageCompress.compressWithFile(
          widget.filePath,
          format: CompressFormat.jpeg,
          quality: 85, // Good quality for preview
        );
        return result;
      } catch (e) {
        return null;
      }
    } else {
      // For regular images, just read the bytes
      return await file.readAsBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _imageDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show loading indicator while converting
          return Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Converting HEIC...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (snapshot.hasError || snapshot.data == null) {
          // Show error if conversion failed
          return Container(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image,
                    color: Theme.of(context).colorScheme.error,
                    size: 40,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Failed to load',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Display the converted image from memory
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
      },
    );
  }
}
