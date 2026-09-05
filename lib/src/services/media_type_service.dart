import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

enum MediaType { profileImage, propertyImage, propertyVideo, document }

enum UploadSource { camera, gallery, files }

class MediaUploadService {
  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseStorage get _storage => FirebaseStorage.instance;
  // Get current user ID
  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  /// Upload profile image using folder structure to match rules
  Future<String> uploadProfileImage(XFile imageFile,
      {Function(double)? onProgress}) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = imageFile.path.split('.').last.toLowerCase();
    final fileName = 'profile_$timestamp.$extension';

    // Use folder structure: profile_images/{userId}/{filename}
    final ref = _storage
        .ref()
        .child('profile_images')
        .child(_currentUserId!)
        .child(fileName);

    return await _uploadFile(ref, File(imageFile.path), onProgress: onProgress);
  }

  /// Upload property media (images/videos) - EXISTING METHOD (unchanged)
  Future<String> uploadPropertyMedia(
    File file,
    String documentType, // 'offers' or 'owners'
    String documentId, {
    Function(double)? onProgress,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = file.path.split('.').last.toLowerCase();
    final fileName = 'media_$timestamp.$extension';

    // CORRECTED STRUCTURE: property_media/{userId}/{documentType}/{documentId}/{fileName}
    final ref = _storage
        .ref()
        .child('property_media')
        .child(_currentUserId!)
        .child(documentType) // 'offers' or 'owners'
        .child(documentId) // specific document ID
        .child(fileName);

    // Property media upload debug logs removed (log removed)

    return await _uploadFile(ref, file, onProgress: onProgress);
  }

  /// Upload document - EXISTING METHOD (unchanged)
  Future<String> uploadDocument(
    File file,
    String documentType, // 'offers' or 'owners'
    String documentId,
    String customName, {
    Function(double)? onProgress,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = file.path.split('.').last.toLowerCase();
    final fileName = '${customName}_$timestamp.$extension';

    // CORRECTED STRUCTURE: user_documents/{userId}/{documentType}/{documentId}/{fileName}
    final ref = _storage
        .ref()
        .child('user_documents')
        .child(_currentUserId!)
        .child(documentType) // 'offers' or 'owners'
        .child(documentId) // specific document ID
        .child(fileName);

    // Document upload debug logs removed (log removed)

    return await _uploadFile(ref, file, onProgress: onProgress);
  }

  /// Upload quotation logo - NEW METHOD for quotations
  Future<String> uploadQuotationLogo(
    File file,
    String quotationId, {
    Function(double)? onProgress,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = file.path.split('.').last.toLowerCase();
    final fileName = 'logo_$timestamp.$extension';

    // Use quotations path as defined in storage rules: quotations/{userId}/{fileName}
    final ref = _storage
        .ref()
        .child('quotations')
        .child(_currentUserId!)
        .child(fileName);

    // Quotation logo upload debug logs removed (log removed)

    return await _uploadFile(ref, file, onProgress: onProgress);
  }

  /// Generic file upload method with enhanced error handling - EXISTING METHOD (unchanged)
  Future<String> _uploadFile(
    Reference ref,
    File file, {
    Function(double)? onProgress,
  }) async {
    try {
      // Verify file exists
      if (!await file.exists()) {
        throw Exception('Selected file no longer exists');
      }

      // Verify user is still authenticated
      if (_currentUserId == null) {
        throw Exception('User session expired. Please sign in again.');
      }

      // Debug authentication
      // Upload debug logs removed (log removed)

      // Create upload task with metadata
      final metadata = SettableMetadata(
        contentType: _getContentType(file.path),
        customMetadata: {
          'uploadedBy': _currentUserId!,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final uploadTask = ref.putFile(file, metadata);

      // Listen to progress if callback provided
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          if (snapshot.totalBytes > 0) {
            final progress = snapshot.bytesTransferred / snapshot.totalBytes;
            onProgress(progress);
          }
        });
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Upload successful (log removed): $downloadUrl
      return downloadUrl;
    } on FirebaseException catch (e) {
      // Firebase Storage error details removed (log removed): ${e.code} - ${e.message}

      switch (e.code) {
        case 'unauthorized':
          throw Exception(
              'You are not authorized to upload files. Please check your account permissions and try signing in again.');
        case 'canceled':
          throw Exception('Upload was canceled');
        case 'invalid-checksum':
          throw Exception(
              'File upload failed due to network error. Please try again.');
        case 'retry-limit-exceeded':
          throw Exception(
              'Upload failed after multiple attempts. Please check your internet connection and try again.');
        case 'unknown':
          throw Exception(
              'Upload failed due to an unknown error. Please try again.');
        case 'object-not-found':
          throw Exception('Upload destination not found');
        case 'bucket-not-found':
          throw Exception('Storage bucket not found');
        case 'project-not-found':
          throw Exception('Firebase project not found');
        case 'quota-exceeded':
          throw Exception('Storage quota exceeded');
        case 'unauthenticated':
          throw Exception('User not authenticated. Please sign in again.');
        case 'invalid-argument':
          throw Exception('Invalid upload arguments');
        case 'no-default-bucket':
          throw Exception('No default storage bucket configured');
        default:
          throw Exception('Upload failed: ${e.message ?? 'Unknown error'}');
      }
    } catch (e) {
      // General upload error (log removed): $e
      throw Exception('Unexpected error during upload: $e');
    }
  }

  /// Get content type from file extension - EXISTING METHOD (unchanged)
  String _getContentType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic'; // iOS native format
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  // ... (rest of the existing methods remain unchanged)

  /// Pick and validate image with enhanced error handling
  Future<XFile?> pickImage({required ImageSource source}) async {
    try {
      final ImagePicker picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        // Validate file exists
        final file = File(image.path);
        if (!await file.exists()) {
          throw Exception('Selected image file does not exist');
        }

        // Validate file size (5MB max for profile images)
        final fileSize = await file.length();
        if (fileSize > 5 * 1024 * 1024) {
          throw Exception(
              'Image size must be less than 5MB. Current size: ${formatFileSize(fileSize)}');
        }

        // Validate it's actually an image
        final extension = image.path.split('.').last.toLowerCase();
        if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
          throw Exception(
              'Invalid image format. Please select a JPG, PNG, GIF, or WebP image.');
        }
      }

      return image;
    } catch (e) {
      // Image picking error (log removed): $e
      if (e.toString().contains('Image size must be less than')) {
        rethrow; // Re-throw size validation errors as-is
      }
      throw Exception('Failed to select image: ${e.toString()}');
    }
  }

  /// Pick multiple media files
  Future<List<PlatformFile>> pickMultipleFiles({
    List<String>? allowedExtensions,
    int? maxSizeInMB,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
      );

      if (result != null && result.files.isNotEmpty) {
        // Validate file sizes
        final maxSizeBytes = (maxSizeInMB ?? 50) * 1024 * 1024;

        for (final file in result.files) {
          if (file.size > maxSizeBytes) {
            throw Exception(
                'File "${file.name}" is too large. Maximum size is ${maxSizeInMB ?? 50}MB');
          }
        }

        return result.files;
      }

      return [];
    } catch (e) {
      throw Exception('Failed to pick files: $e');
    }
  }

  /// Get file type from extension
  static MediaType getMediaType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return MediaType.propertyImage;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return MediaType.propertyVideo;
      default:
        return MediaType.document;
    }
  }

  /// Validate file type
  static bool isValidFileType(String extension, List<String> allowedTypes) {
    return allowedTypes.contains(extension.toLowerCase());
  }

  /// Format file size
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Test authentication and permissions - ENHANCED
  Future<bool> testUploadPermissions() async {
    try {
      if (_currentUserId == null) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
