import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:image_picker/image_picker.dart';
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
  FirebaseStorage get _storage => FirebaseStorage.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  /// Save profile image immediately to local storage and queue for upload
  /// Returns temporary URL for immediate UI display
  Future<String> saveProfileImageFast({
    required XFile imageFile,
    required Map<String, dynamic> userData,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // FastProfileUploadService start (log removed)

    final localBox = await Hive.openBox(_localProfileBox);
    final pendingBox = await Hive.openBox(_pendingProfileUploadsBox);

    // Get old profile image URL if it exists (to clean up old mapping later)
    String? oldProfileUrl;
    try {
      final oldLocalData = localBox.get(_currentUserId!);
      if (oldLocalData != null && oldLocalData['profileImageUrl'] != null) {
        oldProfileUrl = oldLocalData['profileImageUrl'] as String;
        // Old profile URL found (log removed): $oldProfileUrl
      }
    } catch (e) {
      // Could not retrieve old profile URL (log removed): $e
    }

    // 1. Save local copy of image file immediately (< 500ms)
    final localPath = await _saveImageLocally(File(imageFile.path));

    // Create temporary URL for immediate use in UI
    final tempUrl =
        'local://profile/${_currentUserId!}/profile_image_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Clear old URL mapping from OfflineMediaService if it exists
    if (oldProfileUrl != null && oldProfileUrl.isNotEmpty) {
      try {
        // Note: OfflineMediaService should have a method to clear specific URL mappings
        // For now, we'll rely on overwriting the mapping
        // Clearing old profile URL mapping (log removed)
      } catch (e) {
        // Could not clear old mapping (log removed): $e
      }
    }

    // Map temp URL to local file for offline access
    await OfflineMediaService.instance.mapUrlToLocalFile(tempUrl, localPath);

    // Saved local profile image (log removed): $localPath -> $tempUrl

    // 2. Update user data with temp URL and save to local Hive
    // Create Hive-compatible data (exclude complex objects)
    final updatedUserData = {
      'uid': _currentUserId!,
      'name': userData['name'],
      'email': userData['email'],
      'phoneNumber': userData['phoneNumber'],
      'profileImageUrl': tempUrl,
      'createdAt': userData['createdAt']?.toIso8601String() ??
          DateTime.now().toIso8601String(),
      'lastLoginAt': userData['lastLoginAt']?.toIso8601String() ??
          DateTime.now().toIso8601String(),
      'isEmailVerified': userData['isEmailVerified'] ?? false,
      'isPhoneVerified': userData['isPhoneVerified'] ?? false,
      'status': 'local',
      'timestamp': DateTime.now().toIso8601String(),
      // Exclude subscription and preferences to avoid Hive adapter issues
    };

    await localBox.put(_currentUserId!, updatedUserData);
    // Local profile save completed (log removed)

    // 3. Update Firestore user document immediately with temp URL
    final firestoreUserData = {
      'name': userData['name'],
      'email': userData['email'],
      'phoneNumber': userData['phoneNumber'],
      'profileImageUrl': tempUrl,
      'isEmailVerified': userData['isEmailVerified'] ?? false,
      'isPhoneVerified': userData['isPhoneVerified'] ?? false,
      'status': 'uploading',
      'updatedAt': FieldValue.serverTimestamp(),
      // Convert DateTime objects to Timestamps for Firestore
      'createdAt': userData['createdAt'] is DateTime
          ? Timestamp.fromDate(userData['createdAt'])
          : FieldValue.serverTimestamp(),
      'lastLoginAt': userData['lastLoginAt'] is DateTime
          ? Timestamp.fromDate(userData['lastLoginAt'])
          : FieldValue.serverTimestamp(),
      // Include subscription and preferences if they exist
      if (userData['subscription'] != null)
        'subscription': userData['subscription'],
      if (userData['preferences'] != null)
        'preferences': userData['preferences'],
    };

    // Saving to Firestore users collection (log removed)
    await _firestore
        .collection('users')
        .doc(_currentUserId!)
        .update(firestoreUserData);

    // Firestore user update completed (log removed)

    // 4. Queue for background upload
    await pendingBox.put(_currentUserId!, {
      'originalUserData': userData,
      'localImagePath': localPath,
      'userId': _currentUserId!,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Queued for background upload (log removed)

    // 5. Start background upload (fire and forget)
    _uploadInBackground();

    return tempUrl;
  }

  /// Save profile image locally for immediate access
  Future<String> _saveImageLocally(File imageFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final profileDir =
        Directory('${appDir.path}/local_profile/${_currentUserId!}');
    await profileDir.create(recursive: true);

    // Use timestamp to create unique local file names to avoid conflicts
    // This ensures each new image has a unique local path
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(imageFile.path);
    final localPath = '${profileDir.path}/profile_image_$timestamp$extension';

    await imageFile.copy(localPath);

    // Saved new profile image locally (log removed): $localPath
    return localPath;
  }

  /// Background upload process (non-blocking)
  Future<void> _uploadInBackground() async {
    try {
      if (_currentUserId == null) return;

      final pendingBox = await Hive.openBox(_pendingProfileUploadsBox);
      final localBox = await Hive.openBox(_localProfileBox);

      final pendingData = pendingBox.get(_currentUserId!);
      if (pendingData == null) return;

      // Starting background profile image upload (log removed)

      final localImagePath = pendingData['localImagePath'] as String;
      final originalUserData =
          Map<String, dynamic>.from(pendingData['originalUserData']);

      // Upload to Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(localImagePath);
      final fileName = 'profile_$timestamp$extension';

      final storageRef = _storage
          .ref()
          .child('profile_images')
          .child(_currentUserId!)
          .child(fileName);

      // Uploading to Firebase Storage (log removed): profile_images/${_currentUserId!}/$fileName

      final uploadTask = storageRef.putFile(File(localImagePath));

      // Wait for upload to complete
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Firebase upload completed (log removed): $downloadUrl

      // CRITICAL: Map Firebase URL to local file BEFORE updating Firestore
      // This ensures when AuthViewModel refreshes, the local cache is already ready
      await OfflineMediaService.instance
          .mapUrlToLocalFile(downloadUrl, localImagePath);
      // Pre-mapped Firebase URL to local cache (log removed): $downloadUrl -> $localImagePath

      // Update Firestore with the real Firebase URL
      final finalUserData = {
        'name': originalUserData['name'],
        'email': originalUserData['email'],
        'phoneNumber': originalUserData['phoneNumber'],
        'profileImageUrl': downloadUrl,
        'isEmailVerified': originalUserData['isEmailVerified'] ?? false,
        'isPhoneVerified': originalUserData['isPhoneVerified'] ?? false,
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
        // Convert DateTime objects to Timestamps for Firestore
        'createdAt': originalUserData['createdAt'] is DateTime
            ? Timestamp.fromDate(originalUserData['createdAt'])
            : FieldValue.serverTimestamp(),
        'lastLoginAt': originalUserData['lastLoginAt'] is DateTime
            ? Timestamp.fromDate(originalUserData['lastLoginAt'])
            : FieldValue.serverTimestamp(),
        // Include subscription and preferences if they exist
        if (originalUserData['subscription'] != null)
          'subscription': originalUserData['subscription'],
        if (originalUserData['preferences'] != null)
          'preferences': originalUserData['preferences'],
      };

      await _firestore
          .collection('users')
          .doc(_currentUserId!)
          .update(finalUserData);

      // Firestore updated with final profile URL (log removed)

      // Update local cache with final URL (Hive-compatible format)
      await localBox.put(_currentUserId!, {
        'uid': _currentUserId!,
        'name': originalUserData['name'],
        'email': originalUserData['email'],
        'phoneNumber': originalUserData['phoneNumber'],
        'profileImageUrl': downloadUrl,
        'createdAt': originalUserData['createdAt']?.toIso8601String() ??
            DateTime.now().toIso8601String(),
        'lastLoginAt': originalUserData['lastLoginAt']?.toIso8601String() ??
            DateTime.now().toIso8601String(),
        'isEmailVerified': originalUserData['isEmailVerified'] ?? false,
        'isPhoneVerified': originalUserData['isPhoneVerified'] ?? false,
        'status': 'completed',
        'timestamp': DateTime.now().toIso8601String(),
        // Exclude subscription and preferences from Hive cache
      });

      // Clean up pending upload
      await pendingBox.delete(_currentUserId!);

      // Notify completion
      _uploadCompletedController.add(ProfileUploadCompletedEvent(
        userId: _currentUserId!,
        newProfileImageUrl: downloadUrl,
      ));

      // Background profile upload completed successfully (log removed)
    } catch (e) {
      // Background profile upload failed (log removed): $e
      // Keep the pending upload for retry
      // Could implement retry logic here
    }
  }

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

  /// Retry failed uploads
  Future<void> retryFailedUploads() async {
    try {
      final pendingBox = await Hive.openBox(_pendingProfileUploadsBox);

      if (pendingBox.isNotEmpty) {
        // Retrying failed profile uploads (log removed)
        await _uploadInBackground();
      }
    } catch (e) {
      // Error retrying profile uploads (log removed): $e
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
