import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

/// Event emitted when profile image upload completes
class ProfileUploadCompletedEvent {
  final String userId;
  final String newProfileImageUrl;

  ProfileUploadCompletedEvent({
    required this.userId,
    required this.newProfileImageUrl,
  });
}

class FastProfileUploadService {
  static const String _pendingProfileUploadsBox = 'pending_profile_uploads';
  static const String _localProfileBox = 'local_profile';

  // Stream controller for upload completion notifications
  static final StreamController<ProfileUploadCompletedEvent>
      _uploadCompletedController =
      StreamController<ProfileUploadCompletedEvent>.broadcast();

  /// Stream that emits when profile upload completes
  static Stream<ProfileUploadCompletedEvent> get onUploadCompleted =>
      _uploadCompletedController.stream;

  // Use lazy getters to avoid accessing Firebase before initialization
  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  /// Get count of pending profile uploads (for UI indicators)
  Future<int> getPendingUploadCount() async {
    try {
      final pendingBox = await Hive.openBox(_pendingProfileUploadsBox);
      return pendingBox.length;
    } catch (e) {
      // Error getting pending profile upload count (log removed): $e
      return 0;
    }
  }

  /// Get local profile image URL if available
  Future<String?> getLocalProfileUrl() async {
    if (_currentUserId == null) return null;

    try {
      final localBox = await Hive.openBox(_localProfileBox);
      final userData = localBox.get(_currentUserId!);

      if (userData != null && userData['profileImageUrl'] != null) {
        final url = userData['profileImageUrl'] as String;
        if (url.startsWith('local://')) {
          return url;
        }
      }
    } catch (e) {
      // Error getting local profile URL (log removed): $e
    }

    return null;
  }

  /// Clean up local cache (if needed)
  Future<void> clearLocalCache() async {
    try {
      final localBox = await Hive.openBox(_localProfileBox);
      final pendingBox = await Hive.openBox(_pendingProfileUploadsBox);

      await localBox.clear();
      await pendingBox.clear();

      // Also clean up local files
      final appDir = await getApplicationDocumentsDirectory();
      final profileDir = Directory('${appDir.path}/local_profile');
      if (await profileDir.exists()) {
        await profileDir.delete(recursive: true);
      }

      // Local profile cache cleared (log removed)
    } catch (e) {
      // Error clearing local cache (log removed): $e
    }
  }
}
