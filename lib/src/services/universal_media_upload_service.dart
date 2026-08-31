import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:broker_wallet/src/data/models/media_file_model.dart';
import 'dart:developer' as developer;

class UniversalMediaUploadService {
  static const String _logName = 'UniversalMediaUpload';

  // Size limits (bytes)
  static const int _maxImageInputSize = 10 * 1024 * 1024; // 10 MB
  static const int _maxVideoInputSize = 200 * 1024 * 1024; // 200 MB
  static const int _maxPdfSize = 20 * 1024 * 1024; // 20 MB

  // Target compression sizes
  static const int _targetImageSize = 2 * 1024 * 1024; // 2 MB
  static const int _targetVideoSize = 80 * 1024 * 1024; // 80 MB

  // Thumbnail settings
  static const int _thumbnailMaxWidth = 320;
  static const int _thumbnailQuality = 75;

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  /// Upload any media file (image, video, or PDF) with standardization
  Future<MediaFileModel> uploadMedia({
    required File file,
    required String collection, // 'offers', 'owners', etc.
    required String documentId,
    Function(MediaUploadProgress)? onProgress,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final extension = path.extension(file.path).toLowerCase();
    final fileSize = await file.length();

    developer.log('📁 Starting upload: ${file.path} ($fileSize bytes)',
        name: _logName);

    // Route to appropriate handler based on file type
    if (_isImageFile(extension)) {
      return await _uploadImage(file, collection, documentId, onProgress);
    } else if (_isVideoFile(extension)) {
      return await _uploadVideo(file, collection, documentId, onProgress);
    } else if (_isPdfFile(extension)) {
      return await _uploadPdf(file, collection, documentId, onProgress);
    } else {
      throw Exception('Unsupported file type: $extension');
    }
  }

  /// Upload image with HEIC→JPEG conversion and compression
  Future<MediaFileModel> _uploadImage(
    File file,
    String collection,
    String documentId,
    Function(MediaUploadProgress)? onProgress,
  ) async {
    onProgress
        ?.call(const MediaUploadProgress(stage: 'compressing', progress: 0.0));

    try {
      final fileSize = await file.length();

      // Validate input size
      if (fileSize > _maxImageInputSize) {
        throw Exception(
            'Image too large (${_formatBytes(fileSize)}). Max: ${_formatBytes(_maxImageInputSize)}');
      }

      // Compress and convert to JPEG
      final compressedFile = await _compressImage(file);
      final compressedSize = await compressedFile.length();

      developer.log(
          '✅ Compressed: ${_formatBytes(fileSize)} → ${_formatBytes(compressedSize)}',
          name: _logName);

      // Generate thumbnail
      onProgress
          ?.call(const MediaUploadProgress(stage: 'thumbnail', progress: 0.3));
      final thumbnailFile = await _generateImageThumbnail(compressedFile);

      // Upload main image
      onProgress
          ?.call(const MediaUploadProgress(stage: 'uploading', progress: 0.5));
      final mainUrl = await _uploadToStorage(
        file: compressedFile,
        collection: collection,
        documentId: documentId,
        contentType: 'image/jpeg',
        extension: '.jpg',
        onProgress: (p) => onProgress?.call(
            MediaUploadProgress(stage: 'uploading', progress: 0.5 + (p * 0.4))),
      );

      // Upload thumbnail
      String? thumbnailUrl;
      if (thumbnailFile != null) {
        thumbnailUrl = await _uploadToStorage(
          file: thumbnailFile,
          collection: collection,
          documentId: documentId,
          contentType: 'image/jpeg',
          extension: '_thumb.jpg',
        );
      }

      // Get image dimensions
      final dimensions = await _getImageDimensions(compressedFile);

      // Cleanup temp files
      await compressedFile.delete();
      if (thumbnailFile != null) await thumbnailFile.delete();

      onProgress?.call(const MediaUploadProgress(stage: 'done', progress: 1.0));

      return MediaFileModel(
        id: const Uuid().v4(),
        mediaType: MediaFileType.image,
        format: 'jpeg',
        contentType: 'image/jpeg',
        downloadUrl: mainUrl,
        thumbnailUrl: thumbnailUrl,
        storagePath: _getStoragePath(collection, documentId, '.jpg'),
        width: dimensions?['width'],
        height: dimensions?['height'],
        sizeBytes: compressedSize,
        ownerUid: _currentUserId!,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      developer.log('❌ Image upload failed: $e', name: _logName);
      onProgress?.call(MediaUploadProgress(
        stage: 'failed',
        progress: 0.0,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Upload video with MOV/HEVC→MP4 conversion
  Future<MediaFileModel> _uploadVideo(
    File file,
    String collection,
    String documentId,
    Function(MediaUploadProgress)? onProgress,
  ) async {
    onProgress
        ?.call(const MediaUploadProgress(stage: 'compressing', progress: 0.0));

    try {
      final fileSize = await file.length();

      // Validate input size
      if (fileSize > _maxVideoInputSize) {
        throw Exception(
            'Video too large (${_formatBytes(fileSize)}). Max: ${_formatBytes(_maxVideoInputSize)}');
      }

      // Compress video to MP4
      final compressedInfo = await _compressVideo(file, onProgress);
      if (compressedInfo == null || compressedInfo.file == null) {
        throw Exception('Video compression failed');
      }

      final compressedFile = compressedInfo.file!;
      final compressedSize = await compressedFile.length();

      developer.log(
          '✅ Compressed: ${_formatBytes(fileSize)} → ${_formatBytes(compressedSize)}',
          name: _logName);

      // Generate thumbnail
      onProgress
          ?.call(const MediaUploadProgress(stage: 'thumbnail', progress: 0.6));
      final thumbnailFile = await _generateVideoThumbnail(compressedFile);

      // Upload main video
      onProgress
          ?.call(const MediaUploadProgress(stage: 'uploading', progress: 0.7));
      final mainUrl = await _uploadToStorage(
        file: compressedFile,
        collection: collection,
        documentId: documentId,
        contentType: 'video/mp4',
        extension: '.mp4',
        onProgress: (p) => onProgress?.call(MediaUploadProgress(
            stage: 'uploading', progress: 0.7 + (p * 0.25))),
      );

      // Upload thumbnail
      String? thumbnailUrl;
      if (thumbnailFile != null) {
        thumbnailUrl = await _uploadToStorage(
          file: thumbnailFile,
          collection: collection,
          documentId: documentId,
          contentType: 'image/jpeg',
          extension: '_thumb.jpg',
        );
      }

      // Get video metadata
      final duration = compressedInfo.duration?.toInt();

      // Cleanup temp files
      await compressedFile.delete();
      if (thumbnailFile != null) await thumbnailFile.delete();

      onProgress?.call(const MediaUploadProgress(stage: 'done', progress: 1.0));

      return MediaFileModel(
        id: const Uuid().v4(),
        mediaType: MediaFileType.video,
        format: 'mp4',
        contentType: 'video/mp4',
        downloadUrl: mainUrl,
        thumbnailUrl: thumbnailUrl,
        storagePath: _getStoragePath(collection, documentId, '.mp4'),
        durationMs: duration,
        sizeBytes: compressedSize,
        ownerUid: _currentUserId!,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      developer.log('❌ Video upload failed: $e', name: _logName);
      onProgress?.call(MediaUploadProgress(
        stage: 'failed',
        progress: 0.0,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Upload PDF (no conversion needed)
  Future<MediaFileModel> _uploadPdf(
    File file,
    String collection,
    String documentId,
    Function(MediaUploadProgress)? onProgress,
  ) async {
    onProgress
        ?.call(const MediaUploadProgress(stage: 'uploading', progress: 0.0));

    try {
      final fileSize = await file.length();

      // Validate size
      if (fileSize > _maxPdfSize) {
        throw Exception(
            'PDF too large (${_formatBytes(fileSize)}). Max: ${_formatBytes(_maxPdfSize)}');
      }

      // Upload directly (no compression needed)
      final url = await _uploadToStorage(
        file: file,
        collection: collection,
        documentId: documentId,
        contentType: 'application/pdf',
        extension: '.pdf',
        onProgress: (p) => onProgress
            ?.call(MediaUploadProgress(stage: 'uploading', progress: p)),
      );

      onProgress?.call(const MediaUploadProgress(stage: 'done', progress: 1.0));

      return MediaFileModel(
        id: const Uuid().v4(),
        mediaType: MediaFileType.pdf,
        format: 'pdf',
        contentType: 'application/pdf',
        downloadUrl: url,
        thumbnailUrl: null, // No thumbnail for PDF
        storagePath: _getStoragePath(collection, documentId, '.pdf'),
        sizeBytes: fileSize,
        ownerUid: _currentUserId!,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      developer.log('❌ PDF upload failed: $e', name: _logName);
      onProgress?.call(MediaUploadProgress(
        stage: 'failed',
        progress: 0.0,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Compress image and convert to JPEG
  Future<File> _compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = path.join(tempDir.path, '${const Uuid().v4()}.jpg');

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 80,
      format: CompressFormat.jpeg,
      minWidth: 1920,
      minHeight: 1080,
    );

    if (result == null) {
      throw Exception('Image compression failed');
    }

    return File(result.path);
  }

  /// Generate thumbnail for image
  Future<File?> _generateImageThumbnail(File file) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          path.join(tempDir.path, '${const Uuid().v4()}_thumb.jpg');

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: _thumbnailQuality,
        format: CompressFormat.jpeg,
        minWidth: _thumbnailMaxWidth,
        minHeight: _thumbnailMaxWidth,
      );

      return result != null ? File(result.path) : null;
    } catch (e) {
      developer.log('⚠️ Thumbnail generation failed: $e', name: _logName);
      return null;
    }
  }

  /// Compress video to MP4
  Future<MediaInfo?> _compressVideo(
    File file,
    Function(MediaUploadProgress)? onProgress,
  ) async {
    // Subscribe to compression progress
    final subscription = VideoCompress.compressProgress$.subscribe((progress) {
      onProgress?.call(MediaUploadProgress(
        stage: 'compressing',
        progress: progress / 100.0,
      ));
    });

    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      return info;
    } finally {
      subscription.unsubscribe();
    }
  }

  /// Generate thumbnail for video
  Future<File?> _generateVideoThumbnail(File file) async {
    try {
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        file.path,
        quality: _thumbnailQuality,
        position: -1, // Get middle frame
      );

      return thumbnailFile;
    } catch (e) {
      developer.log('⚠️ Video thumbnail generation failed: $e', name: _logName);
      return null;
    }
  }

  /// Upload file to Firebase Storage
  Future<String> _uploadToStorage({
    required File file,
    required String collection,
    required String documentId,
    required String contentType,
    required String extension,
    Function(double)? onProgress,
  }) async {
    final fileName = '${const Uuid().v4()}$extension';
    final storagePath =
        'property_media/$_currentUserId/$collection/$documentId/$fileName';

    final ref = _storage.ref(storagePath);
    final metadata = SettableMetadata(
      contentType: contentType,
      customMetadata: {
        'uploadedAt': DateTime.now().toIso8601String(),
        'ownerUid': _currentUserId!,
      },
    );

    final uploadTask = ref.putFile(file, metadata);

    // Listen to progress
    uploadTask.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      }
    });

    await uploadTask;
    return await ref.getDownloadURL();
  }

  /// Get storage path for reference
  String _getStoragePath(
      String collection, String documentId, String extension) {
    return 'property_media/$_currentUserId/$collection/$documentId/${const Uuid().v4()}$extension';
  }

  /// Get image dimensions
  Future<Map<String, int>?> _getImageDimensions(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      return {'width': image.width, 'height': image.height};
    } catch (e) {
      developer.log('⚠️ Failed to get image dimensions: $e', name: _logName);
      return null;
    }
  }

  // Helper methods for file type detection
  bool _isImageFile(String extension) {
    return ['.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp']
        .contains(extension);
  }

  bool _isVideoFile(String extension) {
    return ['.mp4', '.mov', '.avi', '.mkv', '.m4v', '.3gp'].contains(extension);
  }

  bool _isPdfFile(String extension) {
    return extension == '.pdf';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
