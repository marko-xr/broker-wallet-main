import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/video_compression_service.dart';
import 'package:broker_wallet/src/services/regional_storage_config.dart';
import 'dart:developer' as developer;

/// Optimized video upload service with compression, resumable uploads, and progress tracking
class OptimizedVideoUploadService {
  static const String _logName = 'OptimizedVideoUpload';

  // Use lazy getter to avoid accessing Firebase before initialization
  static String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  /// Upload video with compression and resumable progress tracking
  static Future<VideoUploadResult> uploadVideo({
    required File videoFile,
    required String storagePath, // e.g., 'offers/$offerId/videos/original.mp4'
    bool immutable = true,
    VideoQualityPreset quality = VideoQualityPreset.medium,
    String? userCountry,
    Function(VideoUploadProgress)? onProgress,
    bool generateThumbnail = true,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final fullPath = 'users/$_currentUserId/$storagePath';
    final stopwatch = Stopwatch()..start();

    developer.log(
      '🎬 Starting optimized video upload: $storagePath',
      name: _logName,
    );

    try {
      // Stage 1: Compress video
      onProgress?.call(VideoUploadProgress(
        stage: UploadStage.compressing,
        progress: 0.0,
        message: 'Compressing video...',
      ));

      final compressionResult = await VideoCompressionService.compressVideo(
        inputFile: videoFile,
        quality: quality,
        onProgress: (progress) {
          onProgress?.call(VideoUploadProgress(
            stage: UploadStage.compressing,
            progress: progress / 100.0,
            message: 'Compressing video... ${progress.toInt()}%',
          ));
        },
      );

      developer.log(
        '✅ Video compression completed: ${compressionResult.summary}',
        name: _logName,
      );

      // Stage 2: Generate thumbnail (parallel with upload prep)
      File? thumbnailFile;
      if (generateThumbnail) {
        onProgress?.call(VideoUploadProgress(
          stage: UploadStage.generatingThumbnail,
          progress: 0.0,
          message: 'Generating thumbnail...',
        ));

        try {
          thumbnailFile = await VideoCompressionService.generateThumbnail(
            videoFile: compressionResult.compressedFile,
            maxWidth: 640,
            maxHeight: 480,
            quality: 85,
          );

          onProgress?.call(VideoUploadProgress(
            stage: UploadStage.generatingThumbnail,
            progress: 1.0,
            message: 'Thumbnail generated',
          ));
        } catch (e) {
          developer.log('⚠️ Thumbnail generation failed: $e', name: _logName);
          // Continue without thumbnail
        }
      }

      // Stage 3: Upload compressed video
      onProgress?.call(VideoUploadProgress(
        stage: UploadStage.uploadingVideo,
        progress: 0.0,
        message: 'Uploading video...',
      ));

      final storage = await RegionalStorageConfig.getBestStorageForUser(
        userCountry: userCountry,
      );

      final videoUrl = await _uploadVideoWithProgress(
        storage: storage,
        file: compressionResult.compressedFile,
        path: fullPath,
        immutable: immutable,
        compressionResult: compressionResult,
        onProgress: (progress) {
          onProgress?.call(VideoUploadProgress(
            stage: UploadStage.uploadingVideo,
            progress: progress,
            message: 'Uploading video... ${(progress * 100).toInt()}%',
          ));
        },
      );

      // Stage 4: Upload thumbnail (if available)
      String? thumbnailUrl;
      if (thumbnailFile != null) {
        onProgress?.call(VideoUploadProgress(
          stage: UploadStage.uploadingThumbnail,
          progress: 0.0,
          message: 'Uploading thumbnail...',
        ));

        try {
          final thumbnailPath = fullPath.replaceAll('.mp4', '_thumbnail.jpg');
          thumbnailUrl = await _uploadThumbnailWithProgress(
            storage: storage,
            file: thumbnailFile,
            path: thumbnailPath,
            onProgress: (progress) {
              onProgress?.call(VideoUploadProgress(
                stage: UploadStage.uploadingThumbnail,
                progress: progress,
                message: 'Uploading thumbnail... ${(progress * 100).toInt()}%',
              ));
            },
          );
        } catch (e) {
          developer.log('⚠️ Thumbnail upload failed: $e', name: _logName);
          // Continue without thumbnail URL
        }
      }

      // Stage 5: Complete
      stopwatch.stop();

      onProgress?.call(VideoUploadProgress(
        stage: UploadStage.completed,
        progress: 1.0,
        message: 'Upload completed successfully',
      ));

      final result = VideoUploadResult(
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        originalSize: await videoFile.length(),
        compressedSize: compressionResult.compressedSize,
        compressionRatio: compressionResult.compressionRatio,
        uploadDuration: stopwatch.elapsed,
        quality: quality,
        storagePath: fullPath,
      );

      developer.log(
        '✅ Video upload completed: ${result.summary}',
        name: _logName,
      );

      // Clean up temporary files
      await _cleanupTemporaryFiles([
        compressionResult.compressedFile,
        if (thumbnailFile != null) thumbnailFile,
      ]);

      return result;
    } catch (e) {
      stopwatch.stop();

      onProgress?.call(VideoUploadProgress(
        stage: UploadStage.failed,
        progress: 0.0,
        message: 'Upload failed: $e',
        error: e.toString(),
      ));

      developer.log('❌ Video upload failed: $e', name: _logName);
      rethrow;
    }
  }

  /// Upload video file with resumable progress tracking
  static Future<String> _uploadVideoWithProgress({
    required FirebaseStorage storage,
    required File file,
    required String path,
    required bool immutable,
    required VideoCompressionResult compressionResult,
    Function(double)? onProgress,
  }) async {
    final ref = storage.ref(path);

    // Set cache headers and metadata
    final metadata = SettableMetadata(
      contentType: 'video/mp4',
      cacheControl: immutable
          ? 'public, max-age=31536000, immutable'
          : 'public, max-age=3600',
      customMetadata: {
        'originalSize': compressionResult.originalSize.toString(),
        'compressedSize': compressionResult.compressedSize.toString(),
        'compressionRatio': compressionResult.compressionRatio.toString(),
        'quality': compressionResult.quality.name,
        'uploadedAt': DateTime.now().toIso8601String(),
        'userAgent': 'BrokerWallet/Flutter',
      },
    );

    // Create resumable upload task
    final uploadTask = ref.putFile(file, metadata);

    // Track progress
    uploadTask.snapshotEvents.listen((snapshot) {
      final progress = snapshot.bytesTransferred / snapshot.totalBytes;
      onProgress?.call(progress);

      if (snapshot.bytesTransferred % (1024 * 1024) == 0) {
        // Log every MB
        developer.log(
          '⬆️ Upload progress: ${(progress * 100).toInt()}% '
          '(${_formatBytes(snapshot.bytesTransferred)}/${_formatBytes(snapshot.totalBytes)})',
          name: _logName,
        );
      }
    });

    // Wait for completion and get URL
    await uploadTask;
    return await ref.getDownloadURL();
  }

  /// Upload thumbnail with progress tracking
  static Future<String> _uploadThumbnailWithProgress({
    required FirebaseStorage storage,
    required File file,
    required String path,
    Function(double)? onProgress,
  }) async {
    final ref = storage.ref(path);

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'public, max-age=31536000, immutable',
      customMetadata: {
        'type': 'video_thumbnail',
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );

    final uploadTask = ref.putFile(file, metadata);

    // Track progress
    uploadTask.snapshotEvents.listen((snapshot) {
      final progress = snapshot.bytesTransferred / snapshot.totalBytes;
      onProgress?.call(progress);
    });

    await uploadTask;
    return await ref.getDownloadURL();
  }

  /// Batch upload multiple videos with overall progress tracking
  static Future<List<VideoUploadResult>> uploadMultipleVideos({
    required List<File> videoFiles,
    required String baseStoragePath, // e.g., 'offers/$offerId/videos/'
    VideoQualityPreset quality = VideoQualityPreset.medium,
    String? userCountry,
    Function(BatchUploadProgress)? onProgress,
  }) async {
    final results = <VideoUploadResult>[];
    final totalVideos = videoFiles.length;

    for (int i = 0; i < videoFiles.length; i++) {
      final videoFile = videoFiles[i];
      final videoPath = '$baseStoragePath/video_$i.mp4';

      try {
        onProgress?.call(BatchUploadProgress(
          currentIndex: i,
          totalCount: totalVideos,
          currentVideoProgress: 0.0,
          overallProgress: i / totalVideos,
          message: 'Processing video ${i + 1}/$totalVideos',
        ));

        final result = await uploadVideo(
          videoFile: videoFile,
          storagePath: videoPath,
          quality: quality,
          userCountry: userCountry,
          onProgress: (videoProgress) {
            onProgress?.call(BatchUploadProgress(
              currentIndex: i,
              totalCount: totalVideos,
              currentVideoProgress: videoProgress.progress,
              overallProgress: (i + videoProgress.progress) / totalVideos,
              message: videoProgress.message,
              currentStage: videoProgress.stage,
            ));
          },
        );

        results.add(result);
      } catch (e) {
        developer.log('❌ Failed to upload video $i: $e', name: _logName);

        onProgress?.call(BatchUploadProgress(
          currentIndex: i,
          totalCount: totalVideos,
          currentVideoProgress: 0.0,
          overallProgress: i / totalVideos,
          message: 'Failed to upload video ${i + 1}: $e',
          hasError: true,
        ));

        // Continue with other videos
      }
    }

    onProgress?.call(BatchUploadProgress(
      currentIndex: totalVideos,
      totalCount: totalVideos,
      currentVideoProgress: 1.0,
      overallProgress: 1.0,
      message: 'All uploads completed',
    ));

    developer.log(
      '✅ Batch upload completed: ${results.length}/$totalVideos successful',
      name: _logName,
    );

    return results;
  }

  /// Cancel an ongoing upload task
  static Future<void> cancelUpload(UploadTask uploadTask) async {
    try {
      await uploadTask.cancel();
      developer.log('🛑 Upload cancelled', name: _logName);
    } catch (e) {
      developer.log('⚠️ Failed to cancel upload: $e', name: _logName);
    }
  }

  /// Pause an upload task (if supported)
  static Future<void> pauseUpload(UploadTask uploadTask) async {
    try {
      await uploadTask.pause();
      developer.log('⏸️ Upload paused', name: _logName);
    } catch (e) {
      developer.log('⚠️ Failed to pause upload: $e', name: _logName);
    }
  }

  /// Resume a paused upload task
  static Future<void> resumeUpload(UploadTask uploadTask) async {
    try {
      await uploadTask.resume();
      developer.log('▶️ Upload resumed', name: _logName);
    } catch (e) {
      developer.log('⚠️ Failed to resume upload: $e', name: _logName);
    }
  }

  /// Clean up temporary files
  static Future<void> _cleanupTemporaryFiles(List<File> files) async {
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

  /// Format bytes for logging
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

/// Upload stages for progress tracking
enum UploadStage {
  compressing,
  generatingThumbnail,
  uploadingVideo,
  uploadingThumbnail,
  completed,
  failed,
}

/// Extension for stage descriptions
extension UploadStageExt on UploadStage {
  String get description {
    switch (this) {
      case UploadStage.compressing:
        return 'Compressing video';
      case UploadStage.generatingThumbnail:
        return 'Generating thumbnail';
      case UploadStage.uploadingVideo:
        return 'Uploading video';
      case UploadStage.uploadingThumbnail:
        return 'Uploading thumbnail';
      case UploadStage.completed:
        return 'Upload completed';
      case UploadStage.failed:
        return 'Upload failed';
    }
  }
}

/// Progress information for single video upload
class VideoUploadProgress {
  final UploadStage stage;
  final double progress; // 0.0 to 1.0
  final String message;
  final String? error;

  const VideoUploadProgress({
    required this.stage,
    required this.progress,
    required this.message,
    this.error,
  });

  /// Get progress as percentage
  int get progressPercent => (progress * 100).round();

  /// Check if upload has error
  bool get hasError => error != null;

  /// Check if upload is completed
  bool get isCompleted => stage == UploadStage.completed;

  @override
  String toString() {
    return 'VideoUploadProgress(stage: $stage, progress: ${progressPercent}%, message: $message)';
  }
}

/// Progress information for batch video uploads
class BatchUploadProgress {
  final int currentIndex;
  final int totalCount;
  final double currentVideoProgress; // 0.0 to 1.0
  final double overallProgress; // 0.0 to 1.0
  final String message;
  final UploadStage? currentStage;
  final bool hasError;

  const BatchUploadProgress({
    required this.currentIndex,
    required this.totalCount,
    required this.currentVideoProgress,
    required this.overallProgress,
    required this.message,
    this.currentStage,
    this.hasError = false,
  });

  /// Get overall progress as percentage
  int get overallProgressPercent => (overallProgress * 100).round();

  /// Get current video progress as percentage
  int get currentVideoProgressPercent => (currentVideoProgress * 100).round();

  /// Check if all uploads are completed
  bool get isCompleted => currentIndex >= totalCount && overallProgress >= 1.0;

  @override
  String toString() {
    return 'BatchUploadProgress(${currentIndex + 1}/$totalCount, overall: ${overallProgressPercent}%, current: ${currentVideoProgressPercent}%)';
  }
}

/// Result of video upload operation
class VideoUploadResult {
  final String videoUrl;
  final String? thumbnailUrl;
  final int originalSize;
  final int compressedSize;
  final double compressionRatio;
  final Duration uploadDuration;
  final VideoQualityPreset quality;
  final String storagePath;

  const VideoUploadResult({
    required this.videoUrl,
    this.thumbnailUrl,
    required this.originalSize,
    required this.compressedSize,
    required this.compressionRatio,
    required this.uploadDuration,
    required this.quality,
    required this.storagePath,
  });

  /// Get human-readable summary
  String get summary {
    return 'Video uploaded successfully\n'
        'Original: ${OptimizedVideoUploadService._formatBytes(originalSize)}\n'
        'Compressed: ${OptimizedVideoUploadService._formatBytes(compressedSize)}\n'
        'Reduction: ${(compressionRatio * 100).toStringAsFixed(1)}%\n'
        'Upload time: ${uploadDuration.inSeconds}s\n'
        'Quality: ${quality.shortName}';
  }

  /// Check if upload was efficient
  bool get wasEfficient =>
      compressionRatio > 0.3 && uploadDuration.inSeconds < 30;

  /// Get upload speed in MB/s
  double get uploadSpeedMBps {
    if (uploadDuration.inSeconds == 0) return 0;
    return (compressedSize / (1024 * 1024)) / uploadDuration.inSeconds;
  }

  Map<String, dynamic> toJson() {
    return {
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'originalSize': originalSize,
      'compressedSize': compressedSize,
      'compressionRatio': compressionRatio,
      'uploadDurationMs': uploadDuration.inMilliseconds,
      'quality': quality.name,
      'storagePath': storagePath,
      'uploadSpeedMBps': uploadSpeedMBps,
    };
  }
}
