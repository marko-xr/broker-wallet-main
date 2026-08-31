import 'dart:io';
import 'package:broker_wallet/src/services/universal_media_upload_service.dart';
import 'package:broker_wallet/src/services/media_type_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// **MIGRATION WRAPPER**: Drop-in replacement for MediaUploadService
///
/// This wrapper provides backward compatibility while using the new
/// UniversalMediaUploadService under the hood for HEIC→JPEG conversion.
///
/// **How to use:**
/// 1. Import this file instead of media_type_service.dart
/// 2. No code changes needed - same API as MediaUploadService
/// 3. HEIC images will automatically convert to JPEG
///
/// ```dart
/// // Old code (still works)
/// final service = MediaUploadServiceCompat();
/// final url = await service.uploadPropertyMedia(file, 'offers', offerId);
///
/// // Same result, but HEIC→JPEG conversion happens automatically!
/// ```
class MediaUploadServiceCompat {
  final UniversalMediaUploadService _universalService =
      UniversalMediaUploadService();
  final MediaUploadService _legacyService = MediaUploadService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  /// Upload property media with automatic HEIC→JPEG conversion
  ///
  /// This method maintains backward compatibility with the old API
  /// but uses UniversalMediaUploadService internally for format conversion.
  Future<String> uploadPropertyMedia(
    File file,
    String documentType, // 'offers' or 'owners'
    String documentId, {
    Function(double)? onProgress,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final extension = file.path.split('.').last.toLowerCase();

    // Check if file needs conversion (HEIC, HEIF, MOV, etc.)
    final needsConversion = ['heic', 'heif', 'mov', 'avi'].contains(extension);

    if (needsConversion) {
      // File needs conversion (log removed): $extension → using UniversalMediaUploadService

      // Use new service for conversion
      final mediaFile = await _universalService.uploadMedia(
        file: file,
        collection: documentType,
        documentId: documentId,
        onProgress: onProgress != null
            ? (progress) => onProgress(progress.progress)
            : null,
      );

      // Save metadata to Firestore (optional - can be done by caller)
      try {
        await _firestore
            .collection('users')
            .doc(_currentUserId)
            .collection(documentType)
            .doc(documentId)
            .collection('media')
            .doc(mediaFile.id)
            .set(mediaFile.toMap());
      } catch (e) {
        // Failed to save media metadata (log removed): $e
        // Continue anyway - URL is still valid
      }

      return mediaFile.downloadUrl;
    } else {
      // File format OK (log removed): $extension → using legacy service

      // Use legacy service for already-compatible formats
      return await _legacyService.uploadPropertyMedia(
        file,
        documentType,
        documentId,
        onProgress: onProgress,
      );
    }
  }

  /// Upload document with automatic format handling
  Future<String> uploadDocument(
    File file,
    String documentType,
    String documentId,
    String customName, {
    Function(double)? onProgress,
  }) async {
    // Documents (PDFs) don't need conversion
    return await _legacyService.uploadDocument(
      file,
      documentType,
      documentId,
      customName,
      onProgress: onProgress,
    );
  }

  /// Upload profile image with HEIC→JPEG conversion
  Future<String> uploadProfileImage(
    dynamic imageFile, {
    // Can be XFile or File
    Function(double)? onProgress,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // Convert XFile to File if needed
    final File file =
        imageFile is XFile ? File(imageFile.path) : imageFile as File;

    final extension = file.path.split('.').last.toLowerCase();
    final needsConversion = ['heic', 'heif'].contains(extension);

    if (needsConversion) {
      // Profile image needs conversion (log removed): $extension

      final mediaFile = await _universalService.uploadMedia(
        file: file,
        collection: 'profiles',
        documentId: _currentUserId!,
        onProgress: onProgress != null
            ? (progress) => onProgress(progress.progress)
            : null,
      );

      return mediaFile.downloadUrl;
    } else {
      // Legacy path for compatibility
      final xFile = imageFile is XFile ? imageFile : XFile(file.path);
      return await _legacyService.uploadProfileImage(
        xFile,
        onProgress: onProgress,
      );
    }
  }

  // ========================================
  // DELEGATE ALL HELPER METHODS TO LEGACY SERVICE
  // ========================================

  /// Pick image from camera or gallery
  Future<XFile?> pickImage({required ImageSource source}) async {
    return await _legacyService.pickImage(source: source);
  }

  /// Test upload permissions
  Future<bool> testUploadPermissions() async {
    return await _legacyService.testUploadPermissions();
  }

  /// Pick multiple files
  Future<List<PlatformFile>> pickMultipleFiles({
    List<String>? allowedExtensions,
    int? maxSizeInMB,
  }) async {
    return await _legacyService.pickMultipleFiles(
      allowedExtensions: allowedExtensions,
      maxSizeInMB: maxSizeInMB,
    );
  }

  /// Upload quotation logo
  Future<String> uploadQuotationLogo(
    File file,
    String quotationId, {
    Function(double)? onProgress,
  }) async {
    return await _legacyService.uploadQuotationLogo(
      file,
      quotationId,
      onProgress: onProgress,
    );
  }
}

/// **QUICK FIX GUIDE**
/// 
/// To fix HEIC upload issues in your existing code:
/// 
/// 1. Find this line in your ViewModel:
///    ```dart
///    final MediaUploadService _uploadService = MediaUploadService();
///    ```
/// 
/// 2. Replace with:
///    ```dart
///    final MediaUploadServiceCompat _uploadService = MediaUploadServiceCompat();
///    ```
/// 
/// 3. Add import:
///    ```dart
///    import 'package:broker_wallet/src/services/media_upload_service_compat.dart';
///    ```
/// 
/// 4. No other changes needed! HEIC files will now automatically convert to JPEG.
/// 
/// **Example:**
/// ```dart
/// // ❌ Before (shows "Unknown File Type" for HEIC)
/// import 'package:broker_wallet/src/services/media_type_service.dart';
/// final MediaUploadService _service = MediaUploadService();
/// 
/// // ✅ After (converts HEIC→JPEG automatically)
/// import 'package:broker_wallet/src/services/media_upload_service_compat.dart';
/// final MediaUploadServiceCompat _service = MediaUploadServiceCompat();
/// ```
