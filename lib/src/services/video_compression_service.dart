import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

/// Video compression service with thumbnail generation for fast uploads
/// Note: Actual video compression is handled by backend for AGP compatibility
class VideoCompressionService {
  static const String _logName = 'VideoCompression';

  /// Generate video compression result - compression handled by backend
  static Future<VideoCompressionResult> compressVideo({
    required File inputFile,
    required VideoQualityPreset quality,
    Function(double progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      developer.log(
        '🎬 Preparing video for upload: ${inputFile.path}',
        name: _logName,
      );

      // Get input file info
      final inputSize = await inputFile.length();
      developer.log(
        '📹 Input video: ${_formatFileSize(inputSize)}',
        name: _logName,
      );

      // For AGP compatibility, we skip on-device compression
      // and let the backend handle it through Cloud Functions
      onProgress?.call(0.5);

      // Create a temporary copy if needed for consistency
      final tempDir = await getTemporaryDirectory();
      final outputName =
          '${path.basenameWithoutExtension(inputFile.path)}_processed.mp4';
      final outputPath = '${tempDir.path}/$outputName';

      // Just copy the file to a temp location for consistency
      final outputFile = await inputFile.copy(outputPath);

      onProgress?.call(1.0);

      stopwatch.stop();

      final result = VideoCompressionResult(
        compressedFile: outputFile,
        originalSize: inputSize,
        compressedSize: inputSize, // Same size since no compression on device
        compressionRatio: 0.0, // No compression performed on device
        compressionTime: stopwatch.elapsed,
        quality: quality,
      );

      developer.log(
        '✅ Video prepared: ${result.summary}',
        name: _logName,
      );

      return result;
      // frameRate: config.frameRate,
    } catch (e) {
      stopwatch.stop();
      developer.log('❌ Video processing failed: $e', name: _logName);
      rethrow;
    }
  }

  /// Generate video thumbnail for poster display
  static Future<File> generateThumbnail({
    required File videoFile,
    int timeMs = 1000, // 1 second into video
    int maxWidth = 640,
    int maxHeight = 480,
    int quality = 85,
  }) async {
    try {
      developer.log(
        '🖼️ Generating video thumbnail: ${videoFile.path}',
        name: _logName,
      );

      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        timeMs: timeMs,
        quality: quality,
      );

      if (thumbnailBytes == null) {
        throw Exception('Failed to generate video thumbnail');
      }

      // Save thumbnail to temporary file
      final tempDir = await getTemporaryDirectory();
      final thumbnailName =
          '${path.basenameWithoutExtension(videoFile.path)}_thumb.jpg';
      final thumbnailFile = File('${tempDir.path}/$thumbnailName');

      await thumbnailFile.writeAsBytes(thumbnailBytes);

      developer.log(
        '✅ Video thumbnail generated: ${thumbnailFile.path} (${thumbnailBytes.length} bytes)',
        name: _logName,
      );

      return thumbnailFile;
    } catch (e) {
      developer.log('❌ Thumbnail generation failed: $e', name: _logName);
      rethrow;
    }
  }

  /// Generate multiple thumbnails at different time positions
  static Future<List<File>> generateMultipleThumbnails({
    required File videoFile,
    List<int> timePositionsMs = const [1000, 5000, 10000], // 1s, 5s, 10s
    int maxWidth = 320,
    int maxHeight = 240,
    int quality = 80,
  }) async {
    final thumbnails = <File>[];

    for (int i = 0; i < timePositionsMs.length; i++) {
      try {
        final timeMs = timePositionsMs[i];
        final thumbnailBytes = await VideoThumbnail.thumbnailData(
          video: videoFile.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          timeMs: timeMs,
          quality: quality,
        );

        if (thumbnailBytes != null) {
          final tempDir = await getTemporaryDirectory();
          final thumbnailName =
              '${path.basenameWithoutExtension(videoFile.path)}_thumb_$i.jpg';
          final thumbnailFile = File('${tempDir.path}/$thumbnailName');

          await thumbnailFile.writeAsBytes(thumbnailBytes);
          thumbnails.add(thumbnailFile);
        }
      } catch (e) {
        developer.log(
            '⚠️ Failed to generate thumbnail at ${timePositionsMs[i]}ms: $e',
            name: _logName);
      }
    }

    developer.log(
      '✅ Generated ${thumbnails.length}/${timePositionsMs.length} thumbnails',
      name: _logName,
    );

    return thumbnails;
  }

  /// Get video metadata without compression
  static Future<VideoMetadata> getVideoMetadata(File videoFile) async {
    try {
      // For now, we'll use basic file info
      // In a full implementation, you might use ffmpeg_kit_flutter for detailed metadata
      final fileSize = await videoFile.length();
      final fileName = path.basename(videoFile.path);
      final extension = path.extension(videoFile.path).toLowerCase();

      return VideoMetadata(
        fileName: fileName,
        filePath: videoFile.path,
        fileSize: fileSize,
        extension: extension,
        // These would come from actual video analysis
        durationMs: null,
        width: null,
        height: null,
        frameRate: null,
        bitrate: null,
      );
    } catch (e) {
      developer.log('❌ Failed to get video metadata: $e', name: _logName);
      rethrow;
    }
  }

  /// Batch compress multiple videos with progress tracking
  static Future<List<VideoCompressionResult>> compressMultipleVideos({
    required List<File> videoFiles,
    required VideoQualityPreset quality,
    Function(int completed, int total, double currentProgress)? onProgress,
  }) async {
    final results = <VideoCompressionResult>[];

    for (int i = 0; i < videoFiles.length; i++) {
      final videoFile = videoFiles[i];

      developer.log(
        '🎬 Compressing video ${i + 1}/${videoFiles.length}: ${videoFile.path}',
        name: _logName,
      );

      try {
        final result = await compressVideo(
          inputFile: videoFile,
          quality: quality,
          onProgress: (progress) {
            onProgress?.call(i, videoFiles.length, progress);
          },
        );

        results.add(result);
      } catch (e) {
        developer.log('❌ Failed to compress ${videoFile.path}: $e',
            name: _logName);
        // Continue with other videos
      }
    }

    developer.log(
      '✅ Batch compression completed: ${results.length}/${videoFiles.length} successful',
      name: _logName,
    );

    return results;
  }

  /// Clean up temporary compressed files
  static Future<void> cleanupTemporaryFiles(List<File> files) async {
    for (final file in files) {
      try {
        if (await file.exists()) {
          await file.delete();
          developer.log('🗑️ Cleaned up: ${file.path}', name: _logName);
        }
      } catch (e) {
        developer.log('⚠️ Failed to cleanup ${file.path}: $e', name: _logName);
      }
    }
  }

  /// Format file size for logging
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

/// Video quality presets optimized for different use cases
enum VideoQualityPreset {
  veryLow, // For thumbnails/previews (240p, low bitrate)
  low, // For social feeds (480p, moderate bitrate)
  medium, // For standard viewing (720p, good bitrate)
  high, // For detail views (1080p, high bitrate)
  veryHigh, // For professional content (1080p+, very high bitrate)
}

/// Extension to get quality descriptions
extension VideoQualityPresetExt on VideoQualityPreset {
  String get description {
    switch (this) {
      case VideoQualityPreset.veryLow:
        return 'Very Low (240p) - Fast upload, small size';
      case VideoQualityPreset.low:
        return 'Low (480p) - Quick sharing';
      case VideoQualityPreset.medium:
        return 'Medium (720p) - Good quality';
      case VideoQualityPreset.high:
        return 'High (1080p) - Best quality';
      case VideoQualityPreset.veryHigh:
        return 'Very High (1080p+) - Professional';
    }
  }

  String get shortName {
    switch (this) {
      case VideoQualityPreset.veryLow:
        return 'Very Low';
      case VideoQualityPreset.low:
        return 'Low';
      case VideoQualityPreset.medium:
        return 'Medium';
      case VideoQualityPreset.high:
        return 'High';
      case VideoQualityPreset.veryHigh:
        return 'Very High';
    }
  }

  /// Recommended use cases
  String get useCase {
    switch (this) {
      case VideoQualityPreset.veryLow:
        return 'Preview thumbnails, very slow connections';
      case VideoQualityPreset.low:
        return 'Social media posts, mobile data';
      case VideoQualityPreset.medium:
        return 'Property tours, general viewing';
      case VideoQualityPreset.high:
        return 'Professional listings, detail views';
      case VideoQualityPreset.veryHigh:
        return 'High-end properties, marketing videos';
    }
  }
}

/// Result of video compression operation
class VideoCompressionResult {
  final File compressedFile;
  final int originalSize;
  final int compressedSize;
  final double compressionRatio;
  final Duration compressionTime;
  final VideoQualityPreset quality;

  const VideoCompressionResult({
    required this.compressedFile,
    required this.originalSize,
    required this.compressedSize,
    required this.compressionRatio,
    required this.compressionTime,
    required this.quality,
  });

  /// Get human-readable compression summary
  String get summary {
    return 'Compressed ${VideoCompressionService._formatFileSize(originalSize)} → '
        '${VideoCompressionService._formatFileSize(compressedSize)} '
        '(${(compressionRatio * 100).toStringAsFixed(1)}% reduction) '
        'in ${compressionTime.inSeconds}s';
  }

  /// Check if compression was effective
  bool get wasEffective => compressionRatio > 0.1; // At least 10% reduction

  /// Get compression efficiency score (0-100)
  double get efficiencyScore {
    if (compressionTime.inSeconds == 0) return 0;
    return (compressionRatio * 100) / compressionTime.inSeconds;
  }
}

/// Video metadata information
class VideoMetadata {
  final String fileName;
  final String filePath;
  final int fileSize;
  final String extension;
  final int? durationMs;
  final int? width;
  final int? height;
  final double? frameRate;
  final int? bitrate;

  const VideoMetadata({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.extension,
    this.durationMs,
    this.width,
    this.height,
    this.frameRate,
    this.bitrate,
  });

  /// Get aspect ratio if dimensions are available
  double? get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }

  /// Get resolution string
  String? get resolution {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return null;
  }

  /// Get duration string
  String? get durationString {
    if (durationMs != null) {
      final duration = Duration(milliseconds: durationMs!);
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'filePath': filePath,
      'fileSize': fileSize,
      'extension': extension,
      'durationMs': durationMs,
      'width': width,
      'height': height,
      'frameRate': frameRate,
      'bitrate': bitrate,
    };
  }
}
