import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Service to handle video conversion from HEVC to H.264 format for compatibility
class VideoConverterService {
  static const String _logName = 'VideoConverter';
  static final VideoConverterService _instance =
      VideoConverterService._internal();
  factory VideoConverterService() => _instance;
  VideoConverterService._internal();

  final Map<String, String> _conversionCache = {};
  final Set<String> _convertingVideos = {};

  /// Check if a video needs conversion (is HEVC format)
  bool needsConversion(String videoPath) {
    final fileName = path.basename(videoPath).toLowerCase();

    // Check for HEVC indicators
    return fileName.contains('hevc') ||
        fileName.contains('h265') ||
        fileName.contains('x265') ||
        _isHEVCFile(videoPath);
  }

  /// Check file metadata for HEVC codec (simplified check)
  bool _isHEVCFile(String videoPath) {
    try {
      final file = File(videoPath);
      if (!file.existsSync()) return false;

      // Simple heuristic: HEVC files often have specific patterns
      // In a real implementation, you'd use FFmpeg or similar to check codec
      return false; // Placeholder - would need proper codec detection
    } catch (e) {
      developer.log('Error checking file format: $e', name: _logName);
      return false;
    }
  }

  /// Convert HEVC video to H.264 format for compatibility
  Future<String?> convertToH264(String hevcVideoPath) async {
    try {
      // Check if already converted
      if (_conversionCache.containsKey(hevcVideoPath)) {
        final convertedPath = _conversionCache[hevcVideoPath]!;
        if (File(convertedPath).existsSync()) {
          developer.log('Using cached converted video: $convertedPath',
              name: _logName);
          return convertedPath;
        } else {
          // Cache is stale, remove entry
          _conversionCache.remove(hevcVideoPath);
        }
      }

      // Check if conversion is already in progress
      if (_convertingVideos.contains(hevcVideoPath)) {
        developer.log('Video conversion already in progress: $hevcVideoPath',
            name: _logName);
        return null;
      }

      _convertingVideos.add(hevcVideoPath);

      try {
        developer.log('Starting HEVC to H.264 conversion: $hevcVideoPath',
            name: _logName);

        // Get app's temporary directory
        final tempDir = await getTemporaryDirectory();
        final convertedDir =
            Directory(path.join(tempDir.path, 'converted_videos'));

        if (!convertedDir.existsSync()) {
          await convertedDir.create(recursive: true);
        }

        // Generate output filename
        final originalName = path.basenameWithoutExtension(hevcVideoPath);
        final outputPath =
            path.join(convertedDir.path, '${originalName}_h264.mp4');

        // In a real implementation, you would use FFmpeg here
        // For now, we'll simulate the process and provide user guidance
        developer.log(
            '⚠️ HEVC conversion not implemented. Would convert to: $outputPath',
            name: _logName);
        developer.log('💡 FFmpeg integration required for actual conversion.',
            name: _logName);

        // Placeholder: In production, use FFmpeg command like:
        // ffmpeg -i input.mp4 -c:v libx264 -c:a aac -preset fast output.mp4

        return null; // Return null to indicate conversion not available
      } finally {
        _convertingVideos.remove(hevcVideoPath);
      }
    } catch (e) {
      developer.log('Error converting HEVC video: $e', name: _logName);
      _convertingVideos.remove(hevcVideoPath);
      return null;
    }
  }

  /// Get user-friendly message about HEVC compatibility
  String getHEVCCompatibilityMessage() {
    return '''
HEVC/H.265 Video Format Not Supported

Your device's video player doesn't support HEVC (H.265) codec. 

Solutions:
• Convert videos to H.264 format before uploading
• Use apps like HandBrake or VLC for conversion
• Record videos in H.264 format when possible

H.264 is more widely supported across Android devices.
    ''';
  }

  /// Get conversion progress for a video (placeholder)
  double? getConversionProgress(String videoPath) {
    if (_convertingVideos.contains(videoPath)) {
      return 0.0; // Placeholder - would track actual progress
    }
    return null;
  }

  /// Clear conversion cache
  void clearCache() {
    _conversionCache.clear();
    developer.log('Conversion cache cleared', name: _logName);
  }

  /// Get statistics about conversions
  Map<String, dynamic> getStats() {
    return {
      'cachedConversions': _conversionCache.length,
      'activeConversions': _convertingVideos.length,
      'cacheEntries': _conversionCache.keys.toList(),
    };
  }
}
