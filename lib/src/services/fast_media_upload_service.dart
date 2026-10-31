import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
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
