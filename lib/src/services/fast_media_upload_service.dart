import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'dart:async';

/// Event emitted when media upload completes for a document
class UploadCompletedEvent {
  final String documentId;
  final String collection;
  final List<String> newFirebaseUrls;
  final List<String> allMediaUrls;

  UploadCompletedEvent({
    required this.documentId,
    required this.collection,
    required this.newFirebaseUrls,
    required this.allMediaUrls,
  });
}

class FastMediaUploadService {
  static const String _pendingUploadsBox = 'pending_uploads';
  static const String _localMediaBox = 'local_media';

  // Stream controller for upload completion notifications
  static final StreamController<UploadCompletedEvent>
      _uploadCompletedController =
      StreamController<UploadCompletedEvent>.broadcast();

  /// Stream that emits when uploads complete for documents
  static Stream<UploadCompletedEvent> get onUploadCompleted =>
      _uploadCompletedController.stream;

  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseStorage get _storage => FirebaseStorage.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  /// Save data immediately to local storage and queue for upload
  Future<String> saveDataWithMedia({
    required Map<String, dynamic> data,
    required List<File> mediaFiles,
    required String collection,
    String? documentId,
  }) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final docId = documentId ?? const Uuid().v4();
    // FastMediaUploadService start (log removed): docId: $docId

    final localBox = await Hive.openBox(_localMediaBox);
    final pendingBox = await Hive.openBox(_pendingUploadsBox);

    // 1. Save local copies of media files immediately (< 1 second)
    List<String> localMediaPaths = [];
    List<String> tempUrls = [];
    for (int i = 0; i < mediaFiles.length; i++) {
      final localPath = await _saveMediaLocally(mediaFiles[i], docId, i);
      localMediaPaths.add(localPath);

      // Create temporary URL for immediate use in UI
      final tempUrl =
          'local://$docId/media_$i${path.extension(mediaFiles[i].path)}';
      tempUrls.add(tempUrl);

      // Map temp URL to local file for offline access
      await OfflineMediaService.instance.mapUrlToLocalFile(tempUrl, localPath);

      // Saved local media (log removed): $localPath -> $tempUrl
    }

    // 2. Convert data to Hive-compatible format (remove Firestore-specific types)
    final hiveCompatibleData = _makeHiveCompatible({
      ...data,
      'mediaFiles': localMediaPaths,
      'mediaUrls': [
        ...(data['mediaUrls'] ?? []),
        ...tempUrls
      ], // Include temp URLs for immediate display
      'id': docId,
      'userId': _currentUserId!,
      'status': 'local', // Mark as local only
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Saving to local Hive storage (log removed)
    await localBox.put(docId, hiveCompatibleData);
    // Local save completed (log removed)

    // 3. Save basic data to Firestore immediately (preserving existing media URLs)
    final firestoreData = <String, dynamic>{
      ...data,
      'id': docId,
      'userId': _currentUserId!,
      // Include temp URLs for immediate display
      'mediaUrls': [...(data['mediaUrls'] ?? []), ...tempUrls],
      'status': 'uploading', // Mark as uploading
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Convert DateTime objects to Timestamp for Firestore
    for (final entry in firestoreData.entries.toList()) {
      if (entry.value is DateTime) {
        firestoreData[entry.key] = Timestamp.fromDate(entry.value);
      }
    }

    // Saving to Firestore (log removed)
    // Save to user's subcollection
    await _firestore
        .collection('users')
        .doc(_currentUserId!)
        .collection(collection)
        .doc(docId)
        .set(firestoreData);

    // Firestore save completed (log removed)

    // 4. Queue for background upload
    await pendingBox.put(docId, {
      'collection': collection,
      'data': data, // Store original data for reference
      'mediaFiles': localMediaPaths,
      'userId': _currentUserId!,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Queued for background upload (log removed)

    // 5. Start background upload (fire and forget)
    _uploadInBackground(docId);

    return docId;
  }

  /// Convert data to Hive-compatible format by removing Firestore-specific types
  Map<String, dynamic> _makeHiveCompatible(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Timestamp) {
        // Convert Firestore Timestamp to ISO string
        result[key] = value.toDate().toIso8601String();
      } else if (value is FieldValue) {
        // Skip FieldValue objects as they can't be stored locally
        continue;
      } else if (value is Map<String, dynamic>) {
        // Recursively handle nested maps
        result[key] = _makeHiveCompatible(value);
      } else if (value is List) {
        // Handle lists that might contain Firestore types
        result[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _makeHiveCompatible(item);
          } else if (item is Timestamp) {
            return item.toDate().toIso8601String();
          }
          return item;
        }).toList();
      } else {
        // Keep primitive types as-is
        result[key] = value;
      }
    }

    return result;
  }

  /// Save media files locally for immediate access
  Future<String> _saveMediaLocally(File file, String docId, int index) async {
    final appDir = await getApplicationDocumentsDirectory();
    final localDir = Directory('${appDir.path}/local_media/$docId');
    await localDir.create(recursive: true);

    final extension = path.extension(file.path);
    final localPath = '${localDir.path}/media_$index$extension';
    await file.copy(localPath);

    return localPath;
  }

  /// Background upload process (non-blocking)
  Future<void> _uploadInBackground(String docId) async {
    try {
      final pendingBox = await Hive.openBox(_pendingUploadsBox);
      final localBox = await Hive.openBox(_localMediaBox);

      final pendingData = pendingBox.get(docId);
      if (pendingData == null) return;

      // Starting background upload (log removed): $docId

      // Upload media files to Firebase Storage in parallel for speed
      List<String> firebaseUrls = [];
      final mediaFilePaths = List<String>.from(pendingData['mediaFiles']);

      // Create upload futures for parallel execution
      final uploadFutures = <Future<String>>[];
      for (int i = 0; i < mediaFilePaths.length; i++) {
        final file = File(mediaFilePaths[i]);
        if (await file.exists()) {
          // Add upload task to futures list for parallel execution
          uploadFutures.add(_uploadToFirebaseStorage(
              file, pendingData['collection'], docId, i));
        }
      }

      // Wait for all uploads to complete in parallel
      if (uploadFutures.isNotEmpty) {
        // Starting parallel uploads (log removed): ${uploadFutures.length} for $docId
        firebaseUrls = await Future.wait(uploadFutures);

        // Map Firebase URLs to local files for offline access
        for (int i = 0;
            i < firebaseUrls.length && i < mediaFilePaths.length;
            i++) {
          await OfflineMediaService.instance
              .mapUrlToLocalFile(firebaseUrls[i], mediaFilePaths[i]);
          // Parallel upload completed (log removed): ${mediaFilePaths[i]} -> ${firebaseUrls[i]}
        }
      }

      // Update Firestore with final media URLs (existing + newly uploaded)
      // Get the existing mediaUrls from the original data that was passed in
      final originalData = pendingData['data'];
      final existingUrls = List<String>.from(originalData['mediaUrls'] ?? []);
      final finalUrls = [...existingUrls, ...firebaseUrls];

      await _firestore
          .collection('users')
          .doc(pendingData['userId'])
          .collection(pendingData['collection'])
          .doc(docId)
          .update({
        'mediaUrls': finalUrls, // Set complete final state
        'status': 'synced',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local data status with final URLs
      final localData = localBox.get(docId);
      if (localData != null) {
        localData['status'] = 'synced';
        // Set the complete final URLs (existing + newly uploaded)
        localData['mediaUrls'] = finalUrls;
        await localBox.put(docId, localData);
      }

      // Remove from pending queue
      await pendingBox.delete(docId);

      // Emit upload completed event for UI refresh
      _uploadCompletedController.add(UploadCompletedEvent(
        documentId: docId,
        collection: pendingData['collection'],
        newFirebaseUrls: firebaseUrls,
        allMediaUrls: finalUrls,
      ));

      // Background upload completed (log removed): $docId
      // Upload completion event emitted for UI refresh (log removed)
    } catch (e) {
      // Background upload failed (log removed): $docId -> $e
      // Will retry on next app start or manual retry
    }
  }

  /// Upload file to Firebase Storage
  Future<String> _uploadToFirebaseStorage(
      File file, String collection, String docId, int index) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(file.path);
    final fileName = 'media_${index}_$timestamp$extension';

    final ref = _storage
        .ref()
        .child('property_media')
        .child(_currentUserId!)
        .child(collection)
        .child(docId)
        .child(fileName);

    final uploadTask = ref.putFile(file);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// Get local data for immediate display
  Future<Map<String, dynamic>?> getLocalData(String docId) async {
    try {
      final localBox = await Hive.openBox(_localMediaBox);
      final data = localBox.get(docId);
      return data != null ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      // Failed to get local data (log removed): $e
      return null;
    }
  }

  /// Get count of pending uploads
  Future<int> getPendingUploadCount() async {
    try {
      final pendingBox = await Hive.openBox(_pendingUploadsBox);
      return pendingBox.keys.length;
    } catch (e) {
      // Failed to get pending upload count (log removed): $e
      return 0;
    }
  }

  /// Get local media paths for a document
  Future<List<String>> getLocalMediaPaths(String docId) async {
    try {
      final localData = await getLocalData(docId);
      if (localData != null && localData['mediaFiles'] != null) {
        return List<String>.from(localData['mediaFiles']);
      }
      return [];
    } catch (e) {
      // Failed to get local media paths (log removed): $e
      return [];
    }
  }

  /// Clear local media for a specific document
  Future<void> clearLocalMedia(String docId) async {
    try {
      final localBox = await Hive.openBox(_localMediaBox);
      final pendingBox = await Hive.openBox(_pendingUploadsBox);

      // Remove from local storage
      await localBox.delete(docId);

      // Remove from pending uploads
      await pendingBox.delete(docId);

      // Delete local files
      final appDir = await getApplicationDocumentsDirectory();
      final localDir = Directory('${appDir.path}/local_media/$docId');
      if (await localDir.exists()) {
        await localDir.delete(recursive: true);
      }

      // Cleared local media (log removed): $docId
    } catch (e) {
      // Failed to clear local media (log removed): $e
    }
  }

  /// Retry pending uploads (alias for retryFailedUploads for consistency)
  Future<void> retryPendingUploads() async {
    return retryFailedUploads();
  }

  /// Retry failed uploads
  Future<void> retryFailedUploads() async {
    try {
      final pendingBox = await Hive.openBox(_pendingUploadsBox);
      final keys = pendingBox.keys.toList();

      // Retrying failed uploads (log removed): ${keys.length}

      for (final key in keys) {
        _uploadInBackground(key.toString());
        // Add small delay to avoid overwhelming the server
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      // Failed to retry uploads (log removed): $e
    }
  }

  /// Clean up old local files
  Future<void> cleanupLocalFiles({int maxAgeInDays = 30}) async {
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
            // Cleaned up old file (log removed): ${entity.path}
          }
        }
      }
    } catch (e) {
      // Cleanup failed (log removed): $e
    }
  }
}
