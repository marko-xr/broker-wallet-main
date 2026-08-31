import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:broker_wallet/src/services/media_upload_service.dart';
import 'package:broker_wallet/src/services/video_player_resource_manager.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'dart:developer' as developer;

/// Comprehensive video system integration that handles upload, validation, and display
/// Prevents memory issues and upload failures through proper resource management
class VideoSystemIntegration {
  static const String _logName = 'VideoSystemIntegration';

  static final VideoPlayerResourceManager _resourceManager =
      VideoPlayerResourceManager();
  static final EnhancedMediaUploadService _uploadService =
      EnhancedMediaUploadService();

  /// Upload videos with proper validation and progress tracking
  static Future<List<String>> uploadVideos({
    required List<PlatformFile> videoFiles,
    required String documentType,
    required String documentId,
    String? userCountry,
    Function(double)? onOverallProgress,
    Function(int, String)? onFileProgress,
    Function(String)? onError,
  }) async {
    try {
      developer.log(
        '🎬 Starting video system upload: ${videoFiles.length} files',
        name: _logName,
      );

      // Validate all video files first
      final validationResults = <VideoFileValidationResult>[];
      for (int i = 0; i < videoFiles.length; i++) {
        final file = File(videoFiles[i].path!);
        final validation =
            await EnhancedMediaUploadService.validateVideoFile(file);
        validationResults.add(validation);

        if (!validation.isValid) {
          final errorMsg =
              'File ${videoFiles[i].name}: ${validation.errors.join(', ')}';
          developer.log('❌ Validation failed: $errorMsg', name: _logName);
          onError?.call(errorMsg);
        }
      }

      // Filter out invalid files
      final validFiles = <PlatformFile>[];
      for (int i = 0; i < videoFiles.length; i++) {
        if (validationResults[i].isValid) {
          validFiles.add(videoFiles[i]);
        }
      }

      if (validFiles.isEmpty) {
        throw Exception('No valid video files to upload');
      }

      // Upload valid files
      final uploadedUrls = await _uploadService.uploadMultipleMedia(
        files: validFiles,
        documentType: documentType,
        documentId: documentId,
        userCountry: userCountry,
        onOverallProgress: onOverallProgress,
        onIndividualProgress: (index, progress) {
          final fileName = validFiles[index].name;
          onFileProgress?.call(
              index, 'Uploading $fileName: ${(progress * 100).toInt()}%');
        },
      );

      developer.log(
        '✅ Video system upload completed: ${uploadedUrls.length}/${validFiles.length} successful',
        name: _logName,
      );

      return uploadedUrls;
    } catch (e) {
      developer.log('❌ Video system upload failed: $e', name: _logName);
      onError?.call('Upload failed: $e');
      rethrow;
    }
  }

  /// Create a video gallery widget with memory management
  static Widget createVideoGallery({
    required List<String> videoUrls,
    required List<String> imageUrls,
    bool autoPlay = false,
    double? height,
    PageController? pageController,
    Function(int)? onPageChanged,
    required AppLocalizations localization,
  }) {
    // Combine all media items
    final allMediaItems = <MediaItem>[];

    // Add images first
    for (final imageUrl in imageUrls) {
      allMediaItems.add(MediaItem(
        url: imageUrl,
        type: MediaType.image,
      ));
    }

    // Add videos
    for (final videoUrl in videoUrls) {
      allMediaItems.add(MediaItem(
        url: videoUrl,
        type: MediaType.video,
      ));
    }

    if (allMediaItems.isEmpty) {
      return Container(
        height: height ?? 300,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                localization.translate('noMediaAvailable'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: height ?? 300,
      child: OptimizedMediaGalleryWidget(
        mediaUrls: allMediaItems.map((item) => item.url).toList(),
        autoPlay: autoPlay,
        pageController: pageController,
        onPageChanged: onPageChanged,
      ),
    );
  }

  /// Validate if device can handle video playback
  static Future<VideoSystemCapabilities> checkSystemCapabilities() async {
    final capabilities = VideoSystemCapabilities();

    try {
      developer.log('🔍 Checking video system capabilities', name: _logName);

      // Check memory stats
      final resourceStats = _resourceManager.getResourceStats();
      capabilities.maxConcurrentPlayers =
          resourceStats['maxConcurrentPlayers'] as int;
      capabilities.currentActivePlayers =
          resourceStats['activeControllers'] as int;

      // Check supported formats
      capabilities.supportedFormats =
          EnhancedMediaUploadService.getSupportedVideoFormats();
      capabilities.codecRecommendations =
          EnhancedMediaUploadService.getCodecRecommendations();

      // Estimate available resources
      capabilities.canPlayVideo =
          capabilities.currentActivePlayers < capabilities.maxConcurrentPlayers;
      capabilities.memoryPressure = capabilities.currentActivePlayers >=
          (capabilities.maxConcurrentPlayers * 0.8);

      developer.log(
        '✅ System capabilities: ${capabilities.toString()}',
        name: _logName,
      );
    } catch (e) {
      developer.log('❌ Failed to check system capabilities: $e',
          name: _logName);
      capabilities.hasError = true;
      capabilities.errorMessage = e.toString();
    }

    return capabilities;
  }

  /// Clean up video resources
  static Future<void> cleanup() async {
    developer.log('🗑️ Cleaning up video system resources', name: _logName);
    await _resourceManager.disposeAll();
  }

  /// Get debug information for troubleshooting
  static Map<String, dynamic> getDebugInfo() {
    return {
      'resourceManager': _resourceManager.getResourceStats(),
      'supportedFormats': EnhancedMediaUploadService.getSupportedVideoFormats(),
      'codecRecommendations':
          EnhancedMediaUploadService.getCodecRecommendations(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

class VideoSystemCapabilities {
  bool canPlayVideo = true;
  bool memoryPressure = false;
  bool hasError = false;
  String? errorMessage;
  int maxConcurrentPlayers = 2;
  int currentActivePlayers = 0;
  List<String> supportedFormats = [];
  Map<String, String> codecRecommendations = {};

  @override
  String toString() {
    return 'VideoSystemCapabilities('
        'canPlay: $canPlayVideo, '
        'memoryPressure: $memoryPressure, '
        'players: $currentActivePlayers/$maxConcurrentPlayers, '
        'formats: ${supportedFormats.length}, '
        'hasError: $hasError'
        ')';
  }
}

/// Widget for displaying video system status
class VideoSystemStatusWidget extends StatefulWidget {
  final bool showDebugInfo;

  const VideoSystemStatusWidget({
    super.key,
    this.showDebugInfo = false,
  });

  @override
  State<VideoSystemStatusWidget> createState() =>
      _VideoSystemStatusWidgetState();
}

class _VideoSystemStatusWidgetState extends State<VideoSystemStatusWidget> {
  VideoSystemCapabilities? _capabilities;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    final capabilities = await VideoSystemIntegration.checkSystemCapabilities();
    if (mounted) {
      setState(() {
        _capabilities = capabilities;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_capabilities == null) {
      return const Center(child: Text('Failed to load video system status'));
    }

    final capabilities = _capabilities!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  capabilities.canPlayVideo
                      ? Icons.check_circle
                      : Icons.warning,
                  color:
                      capabilities.canPlayVideo ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  'Video System Status',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatusRow('Can Play Video', capabilities.canPlayVideo),
            _buildStatusRow('Memory Pressure', capabilities.memoryPressure),
            _buildStatusRow('Active Players',
                '${capabilities.currentActivePlayers}/${capabilities.maxConcurrentPlayers}'),
            _buildStatusRow(
                'Supported Formats', '${capabilities.supportedFormats.length}'),
            if (capabilities.hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Error: ${capabilities.errorMessage}',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
            if (widget.showDebugInfo) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Debug Information',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                VideoSystemIntegration.getDebugInfo().toString(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, dynamic value) {
    Color? valueColor;
    if (value is bool) {
      valueColor = value ? Colors.green : Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
