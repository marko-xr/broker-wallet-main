import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:broker_wallet/src/services/media_type_service.dart';
import 'package:broker_wallet/src/services/optimized_video_upload_service.dart';
import 'package:broker_wallet/src/services/video_compression_service.dart';
import 'dart:developer' as developer;

/// Enhanced media upload service that routes video files to optimized upload
/// and regular files to standard upload, preventing upload failures
class EnhancedMediaUploadService {
  static const String _logName = 'EnhancedMediaUpload';

  final MediaUploadService _standardUploadService = MediaUploadService();

  /// Upload media with automatic routing based on file type
  Future<String> uploadMedia({
    required File file,
    required String documentType, // 'offers' or 'owners'
    required String documentId,
    Function(double)? onProgress,
    String? userCountry,
  }) async {
    final extension = file.path.split('.').last.toLowerCase();

    developer.log(
      '📁 Processing media upload: ${file.path} (${extension})',
      name: _logName,
    );

    // Check if it's a video file
    if (_isVideoFile(extension)) {
      return await _uploadVideoFile(
        file: file,
        documentType: documentType,
        documentId: documentId,
        onProgress: onProgress,
        userCountry: userCountry,
      );
    } else {
      // Use standard upload for images and documents
      return await _standardUploadService.uploadPropertyMedia(
        file,
        documentType,
        documentId,
        onProgress: onProgress,
      );
    }
  }

  /// Upload multiple media files with proper routing
  Future<List<String>> uploadMultipleMedia({
    required List<PlatformFile> files,
    required String documentType,
    required String documentId,
    Function(double)? onOverallProgress,
    Function(int, double)? onIndividualProgress,
    String? userCountry,
  }) async {
    final List<String> uploadedUrls = [];
    final totalFiles = files.length;

    developer.log(
      '📁 Starting batch media upload: $totalFiles files',
      name: _logName,
    );

    for (int i = 0; i < files.length; i++) {
      final platformFile = files[i];
      final file = File(platformFile.path!);

      try {
        developer.log(
          '📁 Uploading file ${i + 1}/$totalFiles: ${platformFile.name}',
          name: _logName,
        );

        final url = await uploadMedia(
          file: file,
          documentType: documentType,
          documentId: documentId,
          onProgress: (progress) {
            onIndividualProgress?.call(i, progress);

            // Calculate overall progress
            final completedFiles = i;
            final currentFileProgress = progress;
            final overallProgress =
                (completedFiles + currentFileProgress) / totalFiles;
            onOverallProgress?.call(overallProgress);
          },
          userCountry: userCountry,
        );

        uploadedUrls.add(url);

        developer.log(
          '✅ File ${i + 1}/$totalFiles uploaded successfully',
          name: _logName,
        );
      } catch (e) {
        developer.log(
          '❌ Failed to upload file ${i + 1}/$totalFiles: ${platformFile.name} - $e',
          name: _logName,
        );

        // Continue with other files instead of failing completely
        // You can choose to throw here if you want all-or-nothing behavior
        developer.log(
          '⚠️ Continuing with remaining files after failure',
          name: _logName,
        );
      }
    }

    final successfulUploads = uploadedUrls.length;
    developer.log(
      '📁 Batch upload completed: $successfulUploads/$totalFiles successful',
      name: _logName,
    );

    return uploadedUrls;
  }

  /// Upload video file using optimized video upload service
  Future<String> _uploadVideoFile({
    required File file,
    required String documentType,
    required String documentId,
    Function(double)? onProgress,
    String? userCountry,
  }) async {
    try {
      developer.log(
        '🎬 Routing video file to optimized upload service: ${file.path}',
        name: _logName,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = file.path.split('.').last.toLowerCase();
      final fileName = 'video_$timestamp.$extension';

      // Create storage path that matches the expected structure
      final storagePath = 'property_media/$documentType/$documentId/$fileName';

      final result = await OptimizedVideoUploadService.uploadVideo(
        videoFile: file,
        storagePath: storagePath,
        quality: VideoQualityPreset.medium, // Balance between quality and size
        userCountry: userCountry,
        onProgress: (progress) {
          onProgress?.call(progress.progress);
        },
        generateThumbnail: true,
      );

      developer.log(
        '✅ Video upload completed: ${result.videoUrl}',
        name: _logName,
      );

      return result.videoUrl;
    } catch (e) {
      developer.log(
        '❌ Video upload failed, falling back to standard upload: $e',
        name: _logName,
      );

      // Fallback to standard upload if optimized upload fails
      return await _standardUploadService.uploadPropertyMedia(
        file,
        documentType,
        documentId,
        onProgress: onProgress,
      );
    }
  }

  /// Check if file extension represents a video file
  bool _isVideoFile(String extension) {
    const videoExtensions = [
      'mp4',
      'mov',
      'avi',
      'mkv',
      'm4v',
      'webm',
      '3gp',
      'flv',
      'wmv'
    ];
    return videoExtensions.contains(extension.toLowerCase());
  }

  /// Get recommended video formats for the platform
  static List<String> getSupportedVideoFormats() {
    return [
      'mp4', // Most compatible, H.264/H.265
      'm4v', // iOS compatible
      'webm', // Web optimized
      '3gp', // Mobile optimized
      'mov', // Apple format (may need conversion)
      'avi', // Legacy format (may need conversion)
      'mkv', // High quality (may need conversion)
    ];
  }

  /// Get codec recommendations for different scenarios
  static Map<String, String> getCodecRecommendations() {
    return {
      'best_compatibility': 'H.264/AVC in MP4 container',
      'best_quality': 'H.265/HEVC in MP4 container',
      'web_optimized': 'VP9 in WebM container',
      'mobile_optimized': 'H.264/AVC in 3GP container',
    };
  }

  /// Validate video file before upload
  static Future<VideoFileValidationResult> validateVideoFile(File file) async {
    final extension = file.path.split('.').last.toLowerCase();
    final fileSize = await file.length();

    final result = VideoFileValidationResult();

    // Check file size (limit to 100MB for performance)
    if (fileSize > 100 * 1024 * 1024) {
      result.isValid = false;
      result.errors.add(
          'Video file too large (max 100MB). Current size: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');
    }

    // Check if format is supported
    if (!getSupportedVideoFormats().contains(extension)) {
      result.isValid = false;
      result.errors.add(
          'Unsupported video format: $extension. Supported: ${getSupportedVideoFormats().join(', ')}');
    }

    // Check if file exists
    if (!await file.exists()) {
      result.isValid = false;
      result.errors.add('Video file does not exist');
    }

    if (result.errors.isEmpty) {
      result.isValid = true;
      result.recommendations.add('Video file appears valid for upload');

      // Add codec recommendations
      if (extension == 'mov' || extension == 'avi' || extension == 'mkv') {
        result.recommendations
            .add('Consider converting to MP4 for better compatibility');
      }

      if (fileSize > 50 * 1024 * 1024) {
        result.recommendations.add(
            'Large file detected - compression will be applied automatically');
      }
    }

    return result;
  }
}

class VideoFileValidationResult {
  bool isValid = true;
  List<String> errors = [];
  List<String> recommendations = [];

  @override
  String toString() {
    return 'VideoFileValidationResult(isValid: $isValid, errors: ${errors.length}, recommendations: ${recommendations.length})';
  }
}
