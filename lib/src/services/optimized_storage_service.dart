import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:broker_wallet/src/services/storage_performance_monitor.dart';
import 'dart:developer' as developer;

/// Optimized Firebase Storage upload service with compression and caching
class OptimizedStorageService {
  static const String _logName = 'OptimizedStorage';

  // Use lazy getters to avoid accessing Firebase before initialization
  static FirebaseStorage get _storage => FirebaseStorage.instance;
  static String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  /// Upload image with compression, resizing, and optimal cache headers
  static Future<String> uploadImageFast({
    required Uint8List originalBytes,
    required String path, // e.g. 'offers/$offerId/cover.jpg'
    bool isMutable = false, // avatars -> true, listing photos -> false
    int quality = 75,
    int maxWidth = 1600,
    int maxHeight = 1600,
    CompressFormat format = CompressFormat.jpeg,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final fullPath = 'users/$_currentUserId/$path';

    return await StoragePerformanceMonitor.monitorUpload(
      'Optimized Image Upload',
      () async => _performOptimizedUpload(
        originalBytes: originalBytes,
        path: fullPath,
        isMutable: isMutable,
        quality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        format: format,
      ),
      additionalInfo: 'Path: $path, Size: ${originalBytes.length} bytes',
    );
  }

  /// Internal method to perform the optimized upload
  static Future<String> _performOptimizedUpload({
    required Uint8List originalBytes,
    required String path,
    required bool isMutable,
    required int quality,
    required int maxWidth,
    required int maxHeight,
    required CompressFormat format,
  }) async {
    // 1) Compress using native iOS/Android compression for speed
    developer.log(
      '🔄 Compressing image: ${originalBytes.length} bytes -> quality $quality, max ${maxWidth}x${maxHeight}',
      name: _logName,
    );

    final compressed = await FlutterImageCompress.compressWithList(
      originalBytes,
      quality: quality,
      minWidth: maxWidth,
      minHeight: maxHeight,
      format: format,
    );

    final compressionRatio =
        (originalBytes.length - compressed.length) / originalBytes.length;
    developer.log(
      '✅ Compression completed: ${compressed.length} bytes (${(compressionRatio * 100).toStringAsFixed(1)}% reduction)',
      name: _logName,
    );

    // 2) Set cache policy based on mutability
    final cacheControl = isMutable
        ? 'public, max-age=60' // 1 minute for things that change
        : 'public, max-age=31536000, immutable'; // 1 year for stable media

    final metadata = SettableMetadata(
      contentType: _getContentType(format),
      cacheControl: cacheControl,
      customMetadata: {
        'originalSize': originalBytes.length.toString(),
        'compressedSize': compressed.length.toString(),
        'quality': quality.toString(),
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );

    developer.log(
      '⬆️ Uploading to Firebase Storage: $path (${compressed.length} bytes, cache: $cacheControl)',
      name: _logName,
    );

    // 3) Upload compressed data
    final ref = _storage.ref(path);
    await ref.putData(Uint8List.fromList(compressed), metadata);

    // 4) Get download URL
    final url = await StoragePerformanceMonitor.monitorGetDownloadURL(
      'Get Download URL',
      () => ref.getDownloadURL(),
      filePath: path,
    );

    developer.log('✅ Upload completed: $url', name: _logName);
    return url;
  }

  /// Upload multiple images with different sizes (thumbnail generation)
  static Future<Map<String, String>> uploadImageWithThumbnails({
    required Uint8List originalBytes,
    required String basePath, // e.g. 'offers/$offerId/image'
    bool isMutable = false,
    List<ImageSize> sizes = const [
      ImageSize(name: 'thumb320', width: 320, height: 320, quality: 80),
      ImageSize(name: 'thumb640', width: 640, height: 640, quality: 85),
      ImageSize(name: 'full', width: 1600, height: 1600, quality: 75),
    ],
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final results = <String, String>{};

    // Upload all sizes concurrently for speed
    final futures = sizes.map((size) async {
      final sizePath = '${basePath}_${size.name}.jpg';

      final url = await uploadImageFast(
        originalBytes: originalBytes,
        path: sizePath,
        isMutable: isMutable,
        quality: size.quality,
        maxWidth: size.width,
        maxHeight: size.height,
        format: CompressFormat.jpeg,
      );

      return MapEntry(size.name, url);
    });

    final uploadResults = await Future.wait(futures);

    for (final entry in uploadResults) {
      results[entry.key] = entry.value;
    }

    developer.log(
      '✅ Multi-size upload completed: ${results.keys.join(', ')}',
      name: _logName,
    );

    return results;
  }

  /// Upload video with optimized settings
  static Future<String> uploadVideoFast({
    required Uint8List videoBytes,
    required String path,
    bool isMutable = false,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final fullPath = 'users/$_currentUserId/$path';

    return await StoragePerformanceMonitor.monitorUpload(
      'Video Upload',
      () async {
        // For videos, use short cache for mutable, longer for immutable
        final cacheControl = isMutable
            ? 'public, max-age=300' // 5 minutes for mutable videos
            : 'public, max-age=2592000'; // 30 days for stable videos

        final metadata = SettableMetadata(
          contentType: 'video/mp4',
          cacheControl: cacheControl,
          customMetadata: {
            'originalSize': videoBytes.length.toString(),
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        );

        final ref = _storage.ref(fullPath);
        await ref.putData(videoBytes, metadata);

        return await ref.getDownloadURL();
      },
      additionalInfo: 'Path: $path, Size: ${videoBytes.length} bytes',
    );
  }

  /// Configure storage for different regions
  static FirebaseStorage getStorageForRegion(String bucketUrl) {
    return FirebaseStorage.instanceFor(bucket: bucketUrl);
  }

  /// Get UAE-optimized storage instance
  static FirebaseStorage get uaeStorage {
    // You'll need to create a bucket in a region closer to UAE
    // For now, return default instance - update with actual UAE bucket URL
    return _storage;
    // return FirebaseStorage.instanceFor(bucket: 'gs://your-uae-bucket');
  }

  /// Helper method to get content type based on format
  static String _getContentType(CompressFormat format) {
    switch (format) {
      case CompressFormat.jpeg:
        return 'image/jpeg';
      case CompressFormat.png:
        return 'image/png';
      case CompressFormat.heic:
        return 'image/heic';
      case CompressFormat.webp:
        return 'image/webp';
    }
  }

  /// Delete files from storage
  static Future<void> deleteFile(String path) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final fullPath = 'users/$_currentUserId/$path';

    try {
      await _storage.ref(fullPath).delete();
      developer.log('🗑️ Deleted file: $fullPath', name: _logName);
    } catch (e) {
      developer.log('⚠️ Failed to delete file: $fullPath - $e', name: _logName);
      rethrow;
    }
  }

  /// Delete multiple sizes of an image
  static Future<void> deleteImageWithThumbnails({
    required String basePath,
    List<String> sizeNames = const ['thumb320', 'thumb640', 'full'],
  }) async {
    final futures = sizeNames.map((sizeName) async {
      try {
        await deleteFile('${basePath}_$sizeName.jpg');
      } catch (e) {
        // Continue deleting other sizes even if one fails
        developer.log('⚠️ Failed to delete $sizeName: $e', name: _logName);
      }
    });

    await Future.wait(futures);
  }

  /// Check if file exists in storage
  static Future<bool> fileExists(String path) async {
    if (_currentUserId == null) {
      return false;
    }

    final fullPath = 'users/$_currentUserId/$path';

    try {
      await _storage.ref(fullPath).getMetadata();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get file metadata including cache info
  static Future<FullMetadata?> getFileMetadata(String path) async {
    if (_currentUserId == null) {
      return null;
    }

    final fullPath = 'users/$_currentUserId/$path';

    try {
      return await _storage.ref(fullPath).getMetadata();
    } catch (e) {
      developer.log('⚠️ Failed to get metadata for: $fullPath - $e',
          name: _logName);
      return null;
    }
  }
}

/// Image size configuration for multi-size uploads
class ImageSize {
  final String name;
  final int width;
  final int height;
  final int quality;

  const ImageSize({
    required this.name,
    required this.width,
    required this.height,
    required this.quality,
  });

  @override
  String toString() => '$name (${width}x$height @ $quality%)';
}

/// Predefined image size configurations
class ImageSizes {
  static const thumbnail = ImageSize(
    name: 'thumb',
    width: 320,
    height: 320,
    quality: 80,
  );

  static const medium = ImageSize(
    name: 'medium',
    width: 640,
    height: 640,
    quality: 85,
  );

  static const large = ImageSize(
    name: 'large',
    width: 1200,
    height: 1200,
    quality: 75,
  );

  static const full = ImageSize(
    name: 'full',
    width: 1600,
    height: 1600,
    quality: 75,
  );

  /// Standard set for property listings
  static const propertyListing = [thumbnail, medium, full];

  /// Standard set for avatars
  static const avatar = [
    ImageSize(name: 'small', width: 100, height: 100, quality: 90),
    ImageSize(name: 'medium', width: 200, height: 200, quality: 85),
    ImageSize(name: 'large', width: 400, height: 400, quality: 80),
  ];

  /// Standard set for documents/PDFs
  static const document = [
    ImageSize(name: 'preview', width: 400, height: 600, quality: 80),
    ImageSize(name: 'full', width: 800, height: 1200, quality: 75),
  ];
}
