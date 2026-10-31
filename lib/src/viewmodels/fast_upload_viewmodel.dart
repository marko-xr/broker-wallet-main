import 'package:flutter/foundation.dart';
import 'package:broker_wallet/src/services/fast_media_upload_service.dart';
import 'package:broker_wallet/src/services/fast_profile_upload_service.dart';

class FastUploadViewModel extends ChangeNotifier {
  final FastMediaUploadService _uploadService = FastMediaUploadService();
  final FastProfileUploadService _profileUploadService =
      FastProfileUploadService();

  int _pendingUploads = 0;
  int _pendingProfileUploads = 0;
  int get pendingUploads => _pendingUploads;
  int get pendingProfileUploads => _pendingProfileUploads;
  int get totalPendingUploads => _pendingUploads + _pendingProfileUploads;

  /// Initialize and check for pending uploads
  Future<void> initialize() async {
    try {
      await _checkPendingUploads();
    } catch (e) {
      // Continue even if initialization fails
      _pendingUploads = 0;
      _pendingProfileUploads = 0;
      notifyListeners();
    }
  }

  /// Check how many uploads are pending
  Future<void> _checkPendingUploads() async {
    try {
      _pendingUploads = await _uploadService.getPendingUploadCount();
      _pendingProfileUploads =
          await _profileUploadService.getPendingUploadCount();
      notifyListeners();
    } catch (e) {
    }
  }

  /// Clear local media for a document
  Future<void> clearLocalMedia(String docId) async {
    try {
      await _uploadService.clearLocalMedia(docId);
    } catch (e) {
    }
  }

  /// Get local media paths for a document
  Future<List<String>> getLocalMediaPaths(String docId) async {
    try {
      return await _uploadService.getLocalMediaPaths(docId);
    } catch (e) {
      return [];
    }
  }
}
