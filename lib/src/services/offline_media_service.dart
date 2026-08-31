import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Service to handle offline media loading for images and videos
/// Maps Firebase Storage URLs to local file paths when offline
class OfflineMediaService {
  static const String _localMediaBoxName = 'local_media';
  static const String _urlMappingBoxName = 'url_mapping';

  static OfflineMediaService? _instance;
  static OfflineMediaService get instance =>
      _instance ??= OfflineMediaService._();
  OfflineMediaService._();

  late Box _localMediaBox;
  late Box _urlMappingBox;
  bool _isInitialized = false;

  /// Initialize the offline media service
  Future<void> initialize() async {
    try {
      _localMediaBox = await Hive.openBox(_localMediaBoxName);
      _urlMappingBox = await Hive.openBox(_urlMappingBoxName);
      _isInitialized = true;
      // ✅ OfflineMediaService initialized (log removed)
    } catch (e) {
      // ⚠️ OfflineMediaService init failed: $e (log removed)
    }
  }

  /// Map Firebase URL to local file path
  Future<void> mapUrlToLocalFile(String firebaseUrl, String localPath) async {
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }

    try {
      await _urlMappingBox.put(firebaseUrl, localPath);
      // 📁 Mapped URL to local file: $firebaseUrl -> $localPath (log removed)
    } catch (e) {
      // ⚠️ Failed to map URL: $e (log removed)
    }
  }

  /// Get local file path for Firebase URL
  String? getLocalFilePath(String firebaseUrl) {
    if (!_isInitialized) return null;

    try {
      return _urlMappingBox.get(firebaseUrl);
    } catch (e) {
      return null;
    }
  }

  /// Check if local file exists for given Firebase URL
  Future<bool> hasLocalFile(String firebaseUrl) async {
    final localPath = getLocalFilePath(firebaseUrl);
    if (localPath == null) return false;

    final file = File(localPath);
    return await file.exists();
  }

  /// Get ImageProvider that checks local files first
  ImageProvider getImageProvider(String imageUrl) {
    // Handle local:// URLs first
    if (imageUrl.startsWith('local://')) {
      final localPath = getLocalFilePath(imageUrl);
      if (localPath != null) {
        final file = File(localPath);
        if (file.existsSync()) {
          // 📱 Using local image: $localPath (log removed)
          return FileImage(file);
        }
      }
      // For local:// URLs that don't have a local file, return a broken image provider
      // instead of trying to use CachedNetworkImageProvider which doesn't support local:// scheme
      return const AssetImage('assets/icons/placeholder.png');
    }

    // Check if we have a local file for this URL (Firebase URLs)
    final localPath = getLocalFilePath(imageUrl);
    if (localPath != null) {
      final file = File(localPath);
      if (file.existsSync()) {
        // 📱 Using local image: $localPath (log removed)
        return FileImage(file);
      }
    }

    // Only use CachedNetworkImageProvider for valid network URLs
    if (!_isValidNetworkUrl(imageUrl)) {
      // For invalid URLs, return a placeholder
      return const AssetImage('assets/icons/placeholder.png');
    }

    // Fallback to network image
    return CachedNetworkImageProvider(
      imageUrl,
      cacheKey: imageUrl,
      maxWidth: 800,
      maxHeight: 600,
    );
  }

  /// Helper method to validate if URL is suitable for CachedNetworkImage
  bool _isValidNetworkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  /// Get file for video player that checks local files first
  Future<File?> getVideoFile(String videoUrl) async {
    // Handle local:// URLs first
    if (videoUrl.startsWith('local://')) {
      final localPath = getLocalFilePath(videoUrl);
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          // 📱 Using local video: $localPath (log removed)
          return file;
        }
      }
    }

    // Check if we have a local file for this URL (Firebase URLs)
    final localPath = getLocalFilePath(videoUrl);
    if (localPath != null) {
      final file = File(localPath);
      if (await file.exists()) {
        return file;
      }
    }

    // No local file available
    return null;
  }

  /// Store local media data when saving with FastMediaUploadService
  Future<void> storeLocalMediaData(
      String documentId, Map<String, dynamic> data) async {
    if (!_isInitialized) return;

    try {
      await _localMediaBox.put(documentId, data);
      // 📦 Stored local media data for: $documentId (log removed)
    } catch (e) {
      // ⚠️ Failed to store local media data: $e (log removed)
    }
  }

  /// Get local media data for document
  Map<String, dynamic>? getLocalMediaData(String documentId) {
    if (!_isInitialized) return null;

    try {
      final data = _localMediaBox.get(documentId);
      return data != null ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      // ⚠️ Failed to get local media data: $e (log removed)
      return null;
    }
  }

  /// Clean up old local files to save space
  Future<void> cleanupOldFiles({int maxAgeInDays = 30}) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final localMediaDir = Directory('${appDir.path}/local_media');

      if (!await localMediaDir.exists()) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: maxAgeInDays));
      final entities = await localMediaDir.list(recursive: true).toList();

      for (final entity in entities) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
            // 🗑️ Cleaned up old file: ${entity.path} (log removed)
          }
        }
      }
    } catch (e) {
      // ⚠️ Cleanup failed: $e (log removed)
    }
  }

  /// Check if device is currently offline
  bool get isOfflineMode {
    // This is a simple check - in a real app you'd want to ping a server
    // For now, we'll assume offline if we can't reach Firebase
    return !_canReachFirebase();
  }

  bool _canReachFirebase() {
    // Simplified check - you could implement actual connectivity check here
    // For now, return false to enable offline mode for testing
    return false; // TODO: Implement proper connectivity check
  }

  /// Create offline-aware widget for images
  Widget buildOfflineAwareImage({
    required String imageUrl,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    // ALWAYS check for local file first (for both local:// and Firebase URLs)
    // This prevents loading indicators when switching from local:// to Firebase URLs
    final localPath = getLocalFilePath(imageUrl);
    if (localPath != null) {
      final file = File(localPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) {
            return errorWidget ?? _buildDefaultErrorWidget();
          },
        );
      }
    }

    // Handle local:// URLs - if no local file exists, show placeholder immediately
    if (imageUrl.startsWith('local://')) {
      return placeholder ?? _buildDefaultPlaceholder();
    }

    // For Firebase URLs, use CachedNetworkImage with preloading strategy
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder: (context, url) {
        if (placeholder != null) {
          return placeholder;
        }

        // For profile images that were previously saved locally,
        // avoid showing loading placeholders to prevent flicker
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(
              Icons.person,
              size: (width != null && height != null)
                  ? (width * height < 2500 ? 24 : 48)
                  : 32,
              color: Colors.grey[400],
            ),
          ),
        );
      },
      errorWidget: (context, url, error) {
        // Check if it's a network error and show appropriate fallback
        final errorString = error.toString().toLowerCase();
        if (errorString.contains('socketexception') ||
            errorString.contains('failed host lookup') ||
            errorString.contains('firebasestorage')) {
          return _buildOfflineIndicator();
        }
        return errorWidget ?? _buildDefaultErrorWidget();
      },
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 50),
    );
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Icon(
          Icons.person,
          size: 32,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildDefaultErrorWidget() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(
          Icons.broken_image,
          size: 48,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildOfflineIndicator() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              'Offline Mode',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Image unavailable',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
