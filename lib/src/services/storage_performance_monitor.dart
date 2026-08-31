import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Performance measurement utilities for Firebase Storage operations
class StoragePerformanceMonitor {
  static const String _logName = 'StoragePerformance';
  static bool _isEnabled = true;

  /// Enable or disable performance monitoring
  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Monitor a Firebase Storage upload operation
  static Future<T> monitorUpload<T>(
    String operationName,
    Future<T> Function() operation, {
    String? additionalInfo,
  }) async {
    if (!_isEnabled) return await operation();

    final stopwatch = Stopwatch()..start();

    try {
      final result = await operation();
      stopwatch.stop();

      _logPerformance(
        operation: '$operationName (Success)',
        duration: stopwatch.elapsed,
        additionalInfo: additionalInfo,
      );

      return result;
    } catch (e) {
      stopwatch.stop();

      _logPerformance(
        operation: '$operationName (Failed)',
        duration: stopwatch.elapsed,
        additionalInfo:
            'Error: $e${additionalInfo != null ? ' | $additionalInfo' : ''}',
      );

      rethrow;
    }
  }

  /// Monitor image loading and decode performance
  static Future<void> monitorImageLoad({
    required String url,
    required BuildContext context,
    String? operationName,
    double? targetWidth,
    double? targetHeight,
  }) async {
    if (!_isEnabled) return;

    final operation = operationName ?? 'Image Load';
    final stopwatch = Stopwatch()..start();

    try {
      await precacheImage(
        CachedNetworkImageProvider(
          url,
          cacheKey: url,
          maxWidth: targetWidth?.toInt(),
          maxHeight: targetHeight?.toInt(),
        ),
        context,
      );

      stopwatch.stop();

      _logPerformance(
        operation: '$operation (Success)',
        duration: stopwatch.elapsed,
        additionalInfo:
            'URL: ${_truncateUrl(url)}${targetWidth != null ? ' | Target: ${targetWidth}x${targetHeight}' : ''}',
      );
    } catch (e) {
      stopwatch.stop();

      _logPerformance(
        operation: '$operation (Failed)',
        duration: stopwatch.elapsed,
        additionalInfo: 'Error: $e | URL: ${_truncateUrl(url)}',
      );
    }
  }

  /// Monitor getDownloadURL operation
  static Future<String> monitorGetDownloadURL(
    String operation,
    Future<String> Function() getUrl, {
    String? filePath,
  }) async {
    if (!_isEnabled) return await getUrl();

    final stopwatch = Stopwatch()..start();

    try {
      final url = await getUrl();
      stopwatch.stop();

      _logPerformance(
        operation: '$operation (Success)',
        duration: stopwatch.elapsed,
        additionalInfo: filePath != null ? 'Path: $filePath' : null,
      );

      return url;
    } catch (e) {
      stopwatch.stop();

      _logPerformance(
        operation: '$operation (Failed)',
        duration: stopwatch.elapsed,
        additionalInfo:
            'Error: $e${filePath != null ? ' | Path: $filePath' : ''}',
      );

      rethrow;
    }
  }

  /// Create a comprehensive performance test for a complete upload flow
  static Future<UploadPerformanceResult> measureCompleteUploadFlow({
    required Future<void> Function() uploadOperation,
    required Future<String> Function() getUrlOperation,
    required String url,
    required BuildContext context,
    double? targetWidth,
    double? targetHeight,
    String? operationName,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    final result = UploadPerformanceResult();

    try {
      // 1. Measure upload time
      final uploadStopwatch = Stopwatch()..start();
      await uploadOperation();
      uploadStopwatch.stop();
      result.uploadDuration = uploadStopwatch.elapsed;

      // 2. Measure getDownloadURL time
      final urlStopwatch = Stopwatch()..start();
      final downloadUrl = await getUrlOperation();
      urlStopwatch.stop();
      result.getUrlDuration = urlStopwatch.elapsed;

      // 3. Measure image load time
      final imageStopwatch = Stopwatch()..start();
      await precacheImage(
        CachedNetworkImageProvider(
          downloadUrl,
          maxWidth: targetWidth?.toInt(),
          maxHeight: targetHeight?.toInt(),
        ),
        context,
      );
      imageStopwatch.stop();
      result.imageDuration = imageStopwatch.elapsed;

      totalStopwatch.stop();
      result.totalDuration = totalStopwatch.elapsed;
      result.success = true;

      // Log comprehensive results
      _logCompleteFlow(result, operationName ?? 'Complete Upload Flow');

      return result;
    } catch (e) {
      totalStopwatch.stop();
      result.totalDuration = totalStopwatch.elapsed;
      result.success = false;
      result.error = e.toString();

      _logCompleteFlow(result, operationName ?? 'Complete Upload Flow');
      return result;
    }
  }

  /// Log performance data
  static void _logPerformance({
    required String operation,
    required Duration duration,
    String? additionalInfo,
  }) {
    final durationMs = duration.inMilliseconds;
    final emoji = _getPerformanceEmoji(durationMs);

    final message = '$emoji $operation: ${durationMs}ms'
        '${additionalInfo != null ? ' | $additionalInfo' : ''}';

    developer.log(
      message,
      name: _logName,
      level: durationMs > 3000 ? 900 : 800, // Warning for slow operations
    );
  }

  /// Log complete upload flow results
  static void _logCompleteFlow(
      UploadPerformanceResult result, String operation) {
    final emoji = result.success ? '✅' : '❌';
    final message = '$emoji $operation Results:\n'
        '  Upload: ${result.uploadDuration?.inMilliseconds ?? 0}ms\n'
        '  GetURL: ${result.getUrlDuration?.inMilliseconds ?? 0}ms\n'
        '  Image:  ${result.imageDuration?.inMilliseconds ?? 0}ms\n'
        '  Total:  ${result.totalDuration.inMilliseconds}ms'
        '${result.error != null ? '\n  Error: ${result.error}' : ''}';

    developer.log(
      message,
      name: _logName,
      level: result.success && result.totalDuration.inMilliseconds < 5000
          ? 800
          : 900,
    );
  }

  /// Get emoji based on performance
  static String _getPerformanceEmoji(int milliseconds) {
    if (milliseconds < 500) return '⚡'; // Very fast
    if (milliseconds < 1000) return '🚀'; // Fast
    if (milliseconds < 3000) return '⏱️'; // Acceptable
    if (milliseconds < 10000) return '🐌'; // Slow
    return '🚨'; // Very slow
  }

  /// Truncate URL for logging
  static String _truncateUrl(String url, {int maxLength = 60}) {
    if (url.length <= maxLength) return url;
    return '${url.substring(0, maxLength - 3)}...';
  }
}

/// Result object for complete upload flow performance measurement
class UploadPerformanceResult {
  Duration? uploadDuration;
  Duration? getUrlDuration;
  Duration? imageDuration;
  Duration totalDuration = Duration.zero;
  bool success = false;
  String? error;

  /// Get a human-readable summary
  String get summary {
    if (!success) {
      return 'Failed after ${totalDuration.inMilliseconds}ms: $error';
    }

    return 'Total: ${totalDuration.inMilliseconds}ms '
        '(Upload: ${uploadDuration?.inMilliseconds ?? 0}ms, '
        'URL: ${getUrlDuration?.inMilliseconds ?? 0}ms, '
        'Image: ${imageDuration?.inMilliseconds ?? 0}ms)';
  }

  /// Check if performance is acceptable (under 5 seconds total)
  bool get isAcceptablePerformance =>
      success && totalDuration.inMilliseconds < 5000;

  /// Get performance rating
  String get performanceRating {
    if (!success) return 'Failed';

    final ms = totalDuration.inMilliseconds;
    if (ms < 1000) return 'Excellent';
    if (ms < 3000) return 'Good';
    if (ms < 5000) return 'Acceptable';
    if (ms < 10000) return 'Slow';
    return 'Very Slow';
  }
}
