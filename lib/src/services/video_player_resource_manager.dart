import 'dart:io';
import 'package:video_player/video_player.dart';
import 'dart:developer' as developer;

/// Manages video player controllers to prevent memory exhaustion
/// Limits concurrent video players and provides resource pooling
class VideoPlayerResourceManager {
  static const String _logName = 'VideoPlayerManager';
  static const int _maxConcurrentPlayers = 2; // Limit to 2 concurrent players
  static const Duration _controllerTimeout =
      Duration(seconds: 30); // Increased timeout for better reliability

  static final VideoPlayerResourceManager _instance =
      VideoPlayerResourceManager._internal();
  factory VideoPlayerResourceManager() => _instance;
  VideoPlayerResourceManager._internal();

  final Map<String, VideoPlayerController> _activeControllers = {};
  final Map<String, DateTime> _controllerLastUsed = {};
  final List<String> _initializationQueue = [];
  bool _isCleanupRunning = false;

  /// Get or create a video controller with resource management and HEVC fallback
  Future<VideoPlayerController?> getController(String videoUrl) async {
    try {
      // Check if we already have this controller
      if (_activeControllers.containsKey(videoUrl)) {
        final controller = _activeControllers[videoUrl]!;
        _controllerLastUsed[videoUrl] = DateTime.now();

        if (controller.value.isInitialized) {
          developer.log('♻️ Reusing existing controller for: $videoUrl',
              name: _logName);
          return controller;
        } else {
          // Controller exists but not initialized, remove it
          developer.log('🗑️ Removing uninitialized controller for: $videoUrl',
              name: _logName);
          await _disposeController(videoUrl);
        }
      }

      // Pre-check video format support and warn about HEVC
      if (!isVideoFormatSupported(videoUrl)) {
        developer.log(
            '⚠️ Unsupported video format detected: $videoUrl (${getVideoCodecInfo(videoUrl)})',
            name: _logName);
      }

      if (isLikelyHEVCVideo(videoUrl)) {
        developer.log(
            '🔍 HEVC video detected: $videoUrl - will attempt playback with fallback options',
            name: _logName);
      }

      // Check if we're at the limit of concurrent players
      if (_activeControllers.length >= _maxConcurrentPlayers) {
        developer.log('⚠️ Max concurrent players reached, cleaning up oldest',
            name: _logName);
        await _cleanupOldestController();
      }

      // Attempt controller creation with retry logic and HEVC handling
      VideoPlayerController? controller;
      String? lastError;
      bool isHEVCError = false;

      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          developer.log(
              '🎬 Creating video controller (attempt $attempt) for: $videoUrl',
              name: _logName);

          if (videoUrl.startsWith('http')) {
            // Enhanced network video configuration for better compatibility
            controller = VideoPlayerController.networkUrl(
              Uri.parse(videoUrl),
              httpHeaders: {
                'Accept': 'video/mp4,video/webm,video/x-msvideo,video/*',
                'User-Agent': 'BrokerWallet-Android/1.0',
                'Connection': 'keep-alive',
                'Range':
                    'bytes=0-', // Support partial content for better streaming
                'Cache-Control': attempt > 1
                    ? 'no-cache'
                    : 'max-age=3600', // Avoid cache on retry
              },
            );
          } else {
            controller = VideoPlayerController.file(File(videoUrl));
          }

          // Initialize with enhanced error handling and progressive timeout
          final timeoutDuration =
              Duration(seconds: 20 + (attempt * 10)); // 30s, 40s, 50s
          final initializationFuture = controller.initialize();
          final timeoutFuture = Future.delayed(timeoutDuration, () {
            throw TimeoutException(
                'Video controller initialization timed out', timeoutDuration);
          });

          await Future.any([initializationFuture, timeoutFuture]);

          if (controller.value.isInitialized &&
              controller.value.duration > Duration.zero) {
            _activeControllers[videoUrl] = controller;
            _controllerLastUsed[videoUrl] = DateTime.now();
            developer.log(
                '✅ Video controller initialized successfully (attempt $attempt) for: $videoUrl (${controller.value.size.width}x${controller.value.size.height})',
                name: _logName);
            return controller;
          } else {
            throw Exception(
                'Controller initialized but has invalid video data');
          }
        } catch (e) {
          lastError = e.toString();
          developer.log(
              '❌ Video initialization attempt $attempt failed: $lastError for: $videoUrl',
              name: _logName);

          // Clean up failed controller
          if (controller != null) {
            try {
              await controller.dispose();
            } catch (disposeError) {
              developer.log(
                  '❌ Error disposing failed controller: $disposeError',
                  name: _logName);
            }
            controller = null;
          }

          // Check for specific MediaCodec HEVC errors
          if (lastError.contains('MediaCodecVideoRenderer') ||
              lastError.contains('ExoPlaybackException') ||
              lastError.contains('video/hevc') ||
              lastError.contains('hvc1')) {
            isHEVCError = true;
            developer.log(
                '🔧 MediaCodec HEVC compatibility issue detected. Device may not support H.265/HEVC codec.',
                name: _logName);

            // For HEVC errors, break early since retries won't help with codec issues
            developer.log(
                '⚠️ HEVC codec not supported on this device. Video cannot be played natively.',
                name: _logName);
            break;
          } else {
            // For other errors, wait progressively longer before retry
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }

      if (isHEVCError) {
        developer.log(
            '❌ HEVC video cannot be played on this device. MediaCodec does not support H.265/HEVC format.',
            name: _logName);
        return null; // Return null with specific HEVC error context
      }

      developer.log(
          '❌ Failed to create video controller after 3 attempts. Last error: $lastError',
          name: _logName);
      return null;
    } catch (e) {
      developer.log('❌ Error creating video controller: $e', name: _logName);
      return null;
    }
  }

  /// Pause a specific controller if it's currently playing
  Future<void> pauseController(String videoUrl) async {
    final controller = _activeControllers[videoUrl];
    if (controller == null) {
      return;
    }

    if (!controller.value.isInitialized) {
      return;
    }

    if (!controller.value.isPlaying) {
      return;
    }

    try {
      await controller.pause();
      developer.log('⏸️ Paused controller for: $videoUrl', name: _logName);
    } catch (e) {
      developer.log('⚠️ Failed to pause controller for $videoUrl: $e',
          name: _logName);
    }
  }

  /// Pause all controllers except the provided URL (if any)
  Future<void> pauseAllExcept(String? activeVideoUrl) async {
    await _pauseControllers(exceptUrl: activeVideoUrl);
  }

  /// Pause all controllers
  Future<void> pauseAll() async {
    await _pauseControllers();
  }

  /// Release a specific controller
  Future<void> releaseController(String videoUrl) async {
    if (_activeControllers.containsKey(videoUrl)) {
      developer.log('🗑️ Releasing controller for: $videoUrl', name: _logName);
      await _disposeController(videoUrl);
    }
  }

  Future<void> _pauseControllers({String? exceptUrl}) async {
    for (final entry in _activeControllers.entries) {
      if (exceptUrl != null && entry.key == exceptUrl) {
        continue;
      }

      final controller = entry.value;
      if (!controller.value.isInitialized) {
        continue;
      }

      if (!controller.value.isPlaying) {
        continue;
      }

      try {
        await controller.pause();
        developer.log('⏸️ Paused controller during bulk pause: ${entry.key}',
            name: _logName);
      } catch (e) {
        developer.log(
            '⚠️ Failed to pause controller during bulk pause: $e (url: ${entry.key})',
            name: _logName);
      }
    }
  }

  /// Clean up old controllers to free memory
  Future<void> _cleanupOldestController() async {
    if (_isCleanupRunning || _activeControllers.isEmpty) return;

    _isCleanupRunning = true;

    try {
      // Find the oldest used controller that's not currently playing
      String? oldestKey;
      DateTime? oldestTime;

      for (final entry in _controllerLastUsed.entries) {
        final controller = _activeControllers[entry.key];

        // Skip controllers that are currently playing to avoid interruption
        if (controller != null && controller.value.isPlaying) {
          continue;
        }

        if (oldestTime == null || entry.value.isBefore(oldestTime)) {
          oldestTime = entry.value;
          oldestKey = entry.key;
        }
      }

      if (oldestKey != null) {
        developer.log('🗑️ Cleaning up oldest controller: $oldestKey',
            name: _logName);
        await _disposeController(oldestKey);
      } else {
        // If all controllers are playing, wait a bit longer
        developer.log('⏳ All controllers are active, delaying cleanup',
            name: _logName);
      }
    } finally {
      _isCleanupRunning = false;
    }
  }

  /// Dispose a specific controller
  Future<void> _disposeController(String videoUrl) async {
    final controller = _activeControllers.remove(videoUrl);
    _controllerLastUsed.remove(videoUrl);

    if (controller != null) {
      try {
        await controller.dispose();
        developer.log('✅ Controller disposed for: $videoUrl', name: _logName);
      } catch (e) {
        developer.log('⚠️ Error disposing controller: $e', name: _logName);
      }
    }
  }

  /// Clean up all controllers (call when app is disposing)
  Future<void> disposeAll() async {
    developer.log('🗑️ Disposing all video controllers', name: _logName);

    final controllers =
        List<VideoPlayerController>.from(_activeControllers.values);
    _activeControllers.clear();
    _controllerLastUsed.clear();

    for (final controller in controllers) {
      try {
        await controller.dispose();
      } catch (e) {
        developer.log('⚠️ Error disposing controller during cleanup: $e',
            name: _logName);
      }
    }

    developer.log('✅ All video controllers disposed', name: _logName);
  }

  /// Get current resource usage stats
  Map<String, dynamic> getResourceStats() {
    return {
      'activeControllers': _activeControllers.length,
      'maxConcurrentPlayers': _maxConcurrentPlayers,
      'controllerUrls': _activeControllers.keys.toList(),
    };
  }

  /// Check if a video format is supported to prevent codec issues
  static bool isVideoFormatSupported(String url) {
    final extension = url.split('.').last.toLowerCase().split('?').first;

    // Supported formats for most Android devices
    const supportedFormats = [
      'mp4', // H.264/AVC, H.265/HEVC (but HEVC may cause issues)
      'm4v', // H.264/AVC
      'webm', // VP8/VP9
      '3gp', // H.263, H.264
      'mkv', // Various codecs
      'avi', // Various codecs
      'mov', // QuickTime formats
    ];

    return supportedFormats.contains(extension);
  }

  /// Check if video likely uses HEVC codec which can cause MediaCodec issues
  static bool isLikelyHEVCVideo(String url) {
    // HEVC videos often have these characteristics in their path/name
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('hevc') ||
        lowerUrl.contains('h265') ||
        lowerUrl.contains('x265') ||
        lowerUrl.contains('hvc1');
  }

  /// Check if an error is specifically related to HEVC codec incompatibility
  static bool isHEVCCompatibilityError(String error) {
    final lowerError = error.toLowerCase();
    return lowerError.contains('mediacodecvideorenderer') &&
        (lowerError.contains('video/hevc') ||
            lowerError.contains('hvc1') ||
            lowerError.contains('h.265') ||
            lowerError.contains('hevc'));
  }

  /// Get video codec information for debugging
  static String getVideoCodecInfo(String url) {
    final extension = url.split('.').last.toLowerCase().split('?').first;

    String baseCodec;
    switch (extension) {
      case 'mp4':
      case 'm4v':
        baseCodec = 'H.264/AVC or H.265/HEVC';
        break;
      case 'webm':
        baseCodec = 'VP8/VP9';
        break;
      case '3gp':
        baseCodec = 'H.263/H.264';
        break;
      case 'mkv':
        baseCodec = 'Various (H.264/H.265/VP9)';
        break;
      case 'avi':
        baseCodec = 'Various (H.264/DivX/Xvid)';
        break;
      case 'mov':
        baseCodec = 'QuickTime (H.264/HEVC)';
        break;
      default:
        baseCodec = 'Unknown codec';
    }

    // Add HEVC warning if detected
    if (isLikelyHEVCVideo(url)) {
      baseCodec += ' ⚠️ HEVC detected - may cause compatibility issues';
    }

    return baseCodec;
  }
}

class TimeoutException implements Exception {
  final String message;
  final Duration timeout;

  TimeoutException(this.message, this.timeout);

  @override
  String toString() => 'TimeoutException: $message (${timeout.inSeconds}s)';
}
