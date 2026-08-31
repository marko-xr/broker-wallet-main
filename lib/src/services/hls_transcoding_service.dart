import 'dart:async';
import 'dart:developer' as developer;

/// Service for managing HLS video transcoding using Google Cloud Transcoder API
/// Converts uploaded videos into adaptive streaming formats for optimal playback
class HLSTranscodingService {
  static const String _baseFunctionUrl =
      'https://australia-southeast1-broker-wallet-app.cloudfunctions.net';

  /// Request HLS transcoding for an uploaded video
  static Future<TranscodingResult> requestTranscoding({
    required String videoPath,
    required String outputBucket,
    String region = 'australia-southeast1',
    List<VideoQuality> qualities = const [
      VideoQuality.low,
      VideoQuality.medium,
      VideoQuality.high,
    ],
    Map<String, dynamic>? metadata,
  }) async {
    try {
      developer.log(
        '🎬 Starting HLS transcoding for: $videoPath',
        name: 'HLSTranscodingService',
      );

      // Call Cloud Function to initiate transcoding
      final response = await _callTranscodingFunction(
        videoPath: videoPath,
        outputBucket: outputBucket,
        region: region,
        qualities: qualities,
        metadata: metadata,
      );

      final result = TranscodingResult.fromJson(response);

      developer.log(
        '✅ Transcoding job created: ${result.jobId}',
        name: 'HLSTranscodingService',
      );

      return result;
    } catch (e) {
      developer.log(
        '❌ Transcoding request failed: $e',
        name: 'HLSTranscodingService',
      );

      throw TranscodingException('Failed to request transcoding: $e');
    }
  }

  /// Get transcoding job status
  static Future<TranscodingStatus> getJobStatus(String jobId) async {
    try {
      final response = await _callStatusFunction(jobId);
      return TranscodingStatus.fromJson(response);
    } catch (e) {
      throw TranscodingException('Failed to get job status: $e');
    }
  }

  /// Wait for transcoding completion with progress updates
  static Stream<TranscodingProgress> watchTranscodingProgress(
      String jobId) async* {
    const maxWaitTime = Duration(minutes: 30);
    const pollInterval = Duration(seconds: 10);

    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      try {
        final status = await getJobStatus(jobId);

        yield TranscodingProgress(
          jobId: jobId,
          status: status.state,
          progressPercent: status.progressPercent,
          currentStep: status.currentStep,
          estimatedTimeRemaining: status.estimatedTimeRemaining,
          hlsUrl: status.hlsUrl,
          thumbnailUrl: status.thumbnailUrl,
        );

        if (status.state == TranscodingState.succeeded ||
            status.state == TranscodingState.failed) {
          break;
        }

        await Future.delayed(pollInterval);
      } catch (e) {
        yield TranscodingProgress(
          jobId: jobId,
          status: TranscodingState.failed,
          progressPercent: 0,
          currentStep: 'Error: $e',
          estimatedTimeRemaining: null,
          hlsUrl: null,
          thumbnailUrl: null,
        );
        break;
      }
    }
  }

  /// Get adaptive streaming URLs for different quality levels
  static Map<VideoQuality, String> getAdaptiveUrls(String baseHlsUrl) {
    final urls = <VideoQuality, String>{};

    for (final quality in VideoQuality.values) {
      final qualityPath = quality.path;
      final adaptiveUrl =
          baseHlsUrl.replaceAll('/master.m3u8', '/$qualityPath/index.m3u8');
      urls[quality] = adaptiveUrl;
    }

    return urls;
  }

  /// Generate thumbnail URLs from transcoded video
  static List<String> generateThumbnailUrls(String baseUrl, {int count = 5}) {
    final thumbnails = <String>[];

    for (int i = 0; i < count; i++) {
      final thumbnailUrl =
          baseUrl.replaceAll('/master.m3u8', '/thumbnails/thumbnail_$i.jpg');
      thumbnails.add(thumbnailUrl);
    }

    return thumbnails;
  }

  /// Batch transcode multiple videos
  static Future<Map<String, TranscodingResult>> batchTranscode(
    Map<String, TranscodingRequest> requests,
  ) async {
    final results = <String, TranscodingResult>{};
    const maxConcurrent = 3; // Limit concurrent transcoding jobs

    final entries = requests.entries.toList();

    for (int i = 0; i < entries.length; i += maxConcurrent) {
      final batch = entries.skip(i).take(maxConcurrent);
      final futures = batch.map((entry) async {
        try {
          final result = await requestTranscoding(
            videoPath: entry.value.videoPath,
            outputBucket: entry.value.outputBucket,
            region: entry.value.region,
            qualities: entry.value.qualities,
            metadata: entry.value.metadata,
          );
          return MapEntry(entry.key, result);
        } catch (e) {
          developer.log(
            '⚠️ Batch transcoding failed for ${entry.key}: $e',
            name: 'HLSTranscodingService',
          );
          rethrow;
        }
      });

      final batchResults = await Future.wait(futures);
      for (final entry in batchResults) {
        results[entry.key] = entry.value;
      }
    }

    return results;
  }

  /// Clean up transcoding artifacts
  static Future<void> cleanupTranscodingArtifacts(String jobId) async {
    try {
      await _callCleanupFunction(jobId);
      developer.log(
        '🗑️ Cleaned up transcoding artifacts for job: $jobId',
        name: 'HLSTranscodingService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to cleanup transcoding artifacts: $e',
        name: 'HLSTranscodingService',
      );
    }
  }

  // Private helper methods for Cloud Function calls
  static Future<Map<String, dynamic>> _callTranscodingFunction({
    required String videoPath,
    required String outputBucket,
    required String region,
    required List<VideoQuality> qualities,
    Map<String, dynamic>? metadata,
  }) async {
    // Simulate Cloud Function call
    // In real implementation, this would make HTTP request to your Cloud Function
    await Future.delayed(const Duration(milliseconds: 500));

    return {
      'jobId': 'transcode_${DateTime.now().millisecondsSinceEpoch}',
      'status': 'created',
      'videoPath': videoPath,
      'outputBucket': outputBucket,
      'region': region,
      'qualities': qualities.map((q) => q.name).toList(),
      'estimatedDuration': 300, // 5 minutes
    };
  }

  static Future<Map<String, dynamic>> _callStatusFunction(String jobId) async {
    // Simulate job status check
    await Future.delayed(const Duration(milliseconds: 200));

    // Simulate different job states based on time
    final createdTime = int.tryParse(jobId.split('_').last) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - createdTime;

    if (elapsed < 30000) {
      // First 30 seconds: processing
      return {
        'jobId': jobId,
        'state': 'processing',
        'progressPercent': (elapsed / 30000 * 100).round(),
        'currentStep': 'Transcoding video segments',
        'estimatedTimeRemaining': 30000 - elapsed,
      };
    } else {
      // After 30 seconds: completed
      return {
        'jobId': jobId,
        'state': 'succeeded',
        'progressPercent': 100,
        'currentStep': 'Transcoding completed',
        'estimatedTimeRemaining': 0,
        'hlsUrl':
            'https://storage.googleapis.com/broker-wallet-videos-au/hls/$jobId/master.m3u8',
        'thumbnailUrl':
            'https://storage.googleapis.com/broker-wallet-videos-au/hls/$jobId/thumbnails/thumbnail_0.jpg',
      };
    }
  }

  static Future<void> _callCleanupFunction(String jobId) async {
    // Simulate cleanup operation
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

/// Video quality levels for adaptive streaming
enum VideoQuality {
  low(height: 360, bitrate: 800, path: '360p'),
  medium(height: 720, bitrate: 2500, path: '720p'),
  high(height: 1080, bitrate: 5000, path: '1080p'),
  ultra(height: 1440, bitrate: 8000, path: '1440p');

  const VideoQuality({
    required this.height,
    required this.bitrate,
    required this.path,
  });

  final int height;
  final int bitrate; // kbps
  final String path;
}

/// Transcoding request parameters
class TranscodingRequest {
  final String videoPath;
  final String outputBucket;
  final String region;
  final List<VideoQuality> qualities;
  final Map<String, dynamic>? metadata;

  const TranscodingRequest({
    required this.videoPath,
    required this.outputBucket,
    this.region = 'australia-southeast1',
    this.qualities = const [
      VideoQuality.low,
      VideoQuality.medium,
      VideoQuality.high
    ],
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'videoPath': videoPath,
        'outputBucket': outputBucket,
        'region': region,
        'qualities': qualities.map((q) => q.name).toList(),
        'metadata': metadata,
      };
}

/// Transcoding job result
class TranscodingResult {
  final String jobId;
  final String status;
  final String videoPath;
  final String outputBucket;
  final int estimatedDurationSeconds;
  final DateTime createdAt;

  const TranscodingResult({
    required this.jobId,
    required this.status,
    required this.videoPath,
    required this.outputBucket,
    required this.estimatedDurationSeconds,
    required this.createdAt,
  });

  factory TranscodingResult.fromJson(Map<String, dynamic> json) {
    return TranscodingResult(
      jobId: json['jobId'] as String,
      status: json['status'] as String,
      videoPath: json['videoPath'] as String,
      outputBucket: json['outputBucket'] as String,
      estimatedDurationSeconds: json['estimatedDuration'] as int? ?? 300,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'status': status,
        'videoPath': videoPath,
        'outputBucket': outputBucket,
        'estimatedDurationSeconds': estimatedDurationSeconds,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Transcoding job status
class TranscodingStatus {
  final String jobId;
  final TranscodingState state;
  final int progressPercent;
  final String currentStep;
  final int? estimatedTimeRemaining;
  final String? hlsUrl;
  final String? thumbnailUrl;
  final String? errorMessage;

  const TranscodingStatus({
    required this.jobId,
    required this.state,
    required this.progressPercent,
    required this.currentStep,
    this.estimatedTimeRemaining,
    this.hlsUrl,
    this.thumbnailUrl,
    this.errorMessage,
  });

  factory TranscodingStatus.fromJson(Map<String, dynamic> json) {
    return TranscodingStatus(
      jobId: json['jobId'] as String,
      state: TranscodingState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => TranscodingState.unknown,
      ),
      progressPercent: json['progressPercent'] as int? ?? 0,
      currentStep: json['currentStep'] as String? ?? '',
      estimatedTimeRemaining: json['estimatedTimeRemaining'] as int?,
      hlsUrl: json['hlsUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  bool get isCompleted => state == TranscodingState.succeeded;
  bool get isFailed => state == TranscodingState.failed;
  bool get isProcessing => state == TranscodingState.processing;
}

/// Transcoding progress information
class TranscodingProgress {
  final String jobId;
  final TranscodingState status;
  final int progressPercent;
  final String currentStep;
  final int? estimatedTimeRemaining;
  final String? hlsUrl;
  final String? thumbnailUrl;

  const TranscodingProgress({
    required this.jobId,
    required this.status,
    required this.progressPercent,
    required this.currentStep,
    this.estimatedTimeRemaining,
    this.hlsUrl,
    this.thumbnailUrl,
  });

  String get readableTimeRemaining {
    if (estimatedTimeRemaining == null) return 'Unknown';

    final minutes = estimatedTimeRemaining! ~/ 60000;
    final seconds = (estimatedTimeRemaining! % 60000) ~/ 1000;

    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

/// Transcoding job states
enum TranscodingState {
  pending,
  processing,
  succeeded,
  failed,
  cancelled,
  unknown,
}

/// Transcoding service exceptions
class TranscodingException implements Exception {
  final String message;
  const TranscodingException(this.message);

  @override
  String toString() => 'TranscodingException: $message';
}

/// HLS helper utilities
class HLSUtils {
  /// Check if a URL is an HLS manifest
  static bool isHLSUrl(String url) {
    return url.toLowerCase().contains('.m3u8');
  }

  /// Extract base URL from HLS manifest URL
  static String getBaseHLSUrl(String manifestUrl) {
    final uri = Uri.parse(manifestUrl);
    final pathSegments = uri.pathSegments.toList();

    if (pathSegments.isNotEmpty && pathSegments.last.endsWith('.m3u8')) {
      pathSegments.removeLast();
    }

    return uri.replace(pathSegments: pathSegments).toString();
  }

  /// Generate quality-specific manifest URLs
  static Map<VideoQuality, String> generateQualityUrls(String baseHlsUrl) {
    final urls = <VideoQuality, String>{};

    for (final quality in VideoQuality.values) {
      final qualityUrl = '$baseHlsUrl/${quality.path}/index.m3u8';
      urls[quality] = qualityUrl;
    }

    return urls;
  }

  /// Validate HLS URL accessibility
  static Future<bool> validateHLSUrl(String hlsUrl) async {
    try {
      // In a real implementation, this would make a HEAD request
      // to check if the manifest is accessible
      await Future.delayed(const Duration(milliseconds: 100));
      return hlsUrl.isNotEmpty && isHLSUrl(hlsUrl);
    } catch (e) {
      return false;
    }
  }
}

/// Configuration for HLS transcoding
class HLSTranscodingConfig {
  final List<VideoQuality> defaultQualities;
  final Duration maxTranscodingTime;
  final int maxConcurrentJobs;
  final String defaultRegion;
  final Map<String, String> outputBuckets;

  const HLSTranscodingConfig({
    this.defaultQualities = const [
      VideoQuality.low,
      VideoQuality.medium,
      VideoQuality.high,
    ],
    this.maxTranscodingTime = const Duration(minutes: 30),
    this.maxConcurrentJobs = 3,
    this.defaultRegion = 'australia-southeast1',
    this.outputBuckets = const {
      'australia-southeast1': 'broker-wallet-videos-au',
      'asia-southeast1': 'broker-wallet-videos-sg',
      'us-central1': 'broker-wallet-videos-us',
    },
  });

  String getOutputBucket(String region) {
    return outputBuckets[region] ?? outputBuckets[defaultRegion]!;
  }

  /// Get optimal quality levels based on original video resolution
  List<VideoQuality> getOptimalQualities(int originalHeight) {
    final qualities = <VideoQuality>[];

    // Always include low quality for compatibility
    qualities.add(VideoQuality.low);

    // Add higher qualities based on original resolution
    if (originalHeight >= 720) {
      qualities.add(VideoQuality.medium);
    }
    if (originalHeight >= 1080) {
      qualities.add(VideoQuality.high);
    }
    if (originalHeight >= 1440) {
      qualities.add(VideoQuality.ultra);
    }

    return qualities;
  }
}
