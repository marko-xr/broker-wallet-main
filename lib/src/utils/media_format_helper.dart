import 'package:flutter/material.dart';

/// Helper class for handling various media formats and conversions
class MediaFormatHelper {
  /// Modern image formats that might need special handling
  static const Set<String> modernImageFormats = {
    'heic',
    'heif',
    'avif',
    'webp',
    'raw',
    'dng',
    'cr2',
    'nef',
    'arw'
  };

  /// High-end video formats
  static const Set<String> modernVideoFormats = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'flv',
    'wmv',
    'mpg',
    'mpeg',
    '3gp',
    'ogv',
    'ts',
    'm2ts',
    'mts'
  };

  /// Audio formats
  static const Set<String> audioFormats = {
    'mp3',
    'wav',
    'aac',
    'flac',
    'ogg',
    'm4a',
    'wma',
    'opus'
  };

  /// Traditional image formats that are well-supported
  static const Set<String> traditionalImageFormats = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'tiff',
    'tif'
  };

  /// All supported image formats
  static Set<String> get allImageFormats =>
      {...traditionalImageFormats, ...modernImageFormats};

  /// All supported video formats
  static Set<String> get allVideoFormats => modernVideoFormats;

  /// All supported audio formats
  static Set<String> get allAudioFormats => audioFormats;

  /// All supported formats
  static Set<String> get allSupportedFormats => {
        ...allImageFormats,
        ...allVideoFormats,
        ...allAudioFormats,
        'pdf',
        'doc',
        'docx',
        'txt',
        'rtf',
        'xls',
        'xlsx',
        'ppt',
        'pptx'
      };

  /// Get the media type for a file extension
  static String getMediaType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    if (allImageFormats.contains(extension)) {
      return 'image';
    } else if (allVideoFormats.contains(extension)) {
      return 'video';
    } else if (allAudioFormats.contains(extension)) {
      return 'audio';
    } else if (extension == 'pdf') {
      return 'pdf';
    } else if (['doc', 'docx', 'txt', 'rtf', 'xls', 'xlsx', 'ppt', 'pptx']
        .contains(extension)) {
      return 'document';
    }
    return 'unknown';
  }

  /// Check if a format is a modern image format that might need conversion
  static bool isModernImageFormat(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return modernImageFormats.contains(extension);
  }

  /// Check if a format is traditionally supported by Flutter
  static bool isTraditionalImageFormat(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return traditionalImageFormats.contains(extension);
  }

  /// Get file type icon
  static IconData getFileIcon(String fileName) {
    final type = getMediaType(fileName);
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'document':
        return Icons.description;
      default:
        return Icons.attach_file;
    }
  }

  /// Format file size in a human-readable way
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get user-friendly error message for unsupported formats
  static String getUnsupportedFormatMessage(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    if (modernImageFormats.contains(extension)) {
      switch (extension) {
        case 'heic':
        case 'heif':
          return 'HEIC/HEIF format detected. Some devices may not support preview, but upload will work.';
        case 'avif':
          return 'AVIF format detected. Limited preview support, but upload will work.';
        case 'raw':
        case 'dng':
        case 'cr2':
        case 'nef':
        case 'arw':
          return 'RAW format detected. Preview not available, but upload will work.';
        default:
          return 'Modern image format. Preview may not be available on all devices.';
      }
    }

    return 'Format not supported for preview, but upload may still work.';
  }

  /// Check if file should show a warning about preview limitations
  static bool shouldShowPreviewWarning(String fileName) {
    return isModernImageFormat(fileName);
  }

  /// Get recommended alternative formats for problematic ones
  static String getRecommendedFormat(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    if (['heic', 'heif'].contains(extension)) {
      return 'Consider converting to JPEG for better compatibility';
    }
    if (extension == 'avif') {
      return 'Consider converting to WebP or JPEG for better compatibility';
    }
    if (['raw', 'dng', 'cr2', 'nef', 'arw'].contains(extension)) {
      return 'Consider converting to JPEG or PNG for preview and smaller file size';
    }

    return '';
  }

  /// Validate if file type is allowed for upload
  static bool isFileTypeAllowed(
      String fileName, List<String>? allowedExtensions) {
    if (allowedExtensions == null || allowedExtensions.isEmpty) {
      return allSupportedFormats
          .contains(fileName.split('.').last.toLowerCase());
    }

    final extension = fileName.split('.').last.toLowerCase();
    return allowedExtensions.map((e) => e.toLowerCase()).contains(extension);
  }

  /// Get MIME type for a file
  static String? getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    // Image MIME types
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'avif':
        return 'image/avif';
      case 'bmp':
        return 'image/bmp';
      case 'tiff':
      case 'tif':
        return 'image/tiff';
      case 'svg':
        return 'image/svg+xml';

      // Video MIME types
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      case 'flv':
        return 'video/x-flv';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'mpg':
      case 'mpeg':
        return 'video/mpeg';
      case '3gp':
        return 'video/3gpp';

      // Audio MIME types
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'opus':
        return 'audio/opus';

      // Document MIME types
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      case 'rtf':
        return 'application/rtf';

      default:
        return null;
    }
  }
}
