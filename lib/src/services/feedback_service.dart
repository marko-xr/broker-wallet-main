// lib/src/services/feedback_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../data/models/feedback_model.dart';
import '../data/models/user_model.dart';
import 'dart:io';

class FeedbackService {
  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const String _collectionName = 'feedback';

  /// Submit feedback to Firebase for admin review
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required UserModel user,
  }) async {
    try {
      // Get device and app information for admin context
      final deviceInfo = await _getDeviceInfo();
      final packageInfo = await PackageInfo.fromPlatform();

      final feedback = FeedbackModel(
        userId: user.uid,
        userName: user.name,
        userEmail: user.email,
        rating: rating,
        comment: comment,
        createdAt: DateTime.now(),
        appVersion: packageInfo.version,
        platform: _getPlatformName(),
        deviceInfo: deviceInfo,
        status: FeedbackStatus.unread,
      );

      if (SupabaseConfig.useSupabaseAuth) {
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser == null || currentUser.id != user.uid) {
          throw StateError('An authenticated user session is required.');
        }
        await Supabase.instance.client.from('feedback').insert({
          'owner_id': currentUser.id,
          'rating': feedback.rating,
          'comment': feedback.comment,
          'app_version': feedback.appVersion,
          'platform': feedback.platform,
          'device_info': feedback.deviceInfo,
        });
      } else {
        await _firestore.collection(_collectionName).add(feedback.toMap());
      }

      // Feedback submitted successfully (log removed)
    } catch (e) {
      // Failed to submit feedback (log removed): $e
      throw Exception('We could not submit your feedback. Please try again.');
    }
  }

  /// Get device information for admin context
  Future<String?> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion})';
      } else if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        return '${webInfo.browserName} ${webInfo.appVersion}';
      }
      return 'Unknown Device';
    } catch (e) {
      // Failed to get device info (log removed): $e
      return null;
    }
  }

  /// Get platform name
  String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  // ADMIN METHODS - For future admin dashboard implementation

  /// Get all feedback for admin review (paginated)
  Future<List<FeedbackModel>> getAllFeedback({
    int limit = 20,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query query = _firestore
          .collection(_collectionName)
          .orderBy('createdAt', descending: true);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.limit(limit).get();

      return snapshot.docs
          .map((doc) => FeedbackModel.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    } catch (e) {
      // Failed to get feedback (log removed): $e
      throw Exception('Failed to get feedback: $e');
    }
  }

  /// Get feedback by rating for admin filtering
  Future<List<FeedbackModel>> getFeedbackByRating(int rating) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('rating', isEqualTo: rating)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => FeedbackModel.fromMap(
                doc.data(),
                doc.id,
              ))
          .toList();
    } catch (e) {
      // Failed to get feedback by rating (log removed): $e
      throw Exception('Failed to get feedback by rating: $e');
    }
  }

  /// Update feedback status (for admin use)
  Future<void> updateFeedbackStatus(
      String feedbackId, FeedbackStatus status) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(feedbackId)
          .update({'status': status.name});
    } catch (e) {
      // Failed to update feedback status (log removed): $e
      throw Exception('Failed to update feedback status: $e');
    }
  }

  /// Get feedback statistics for admin dashboard
  Future<Map<String, dynamic>> getFeedbackStats() async {
    try {
      final snapshot = await _firestore.collection(_collectionName).get();

      int totalFeedback = snapshot.docs.length;
      Map<int, int> ratingCounts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      Map<String, int> statusCounts = {
        'unread': 0,
        'read': 0,
        'resolved': 0,
      };

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] as int;
        final status = data['status'] as String;

        ratingCounts[rating] = (ratingCounts[rating] ?? 0) + 1;
        statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      }

      double averageRating = 0;
      if (totalFeedback > 0) {
        int totalStars = 0;
        ratingCounts.forEach((rating, count) {
          totalStars += rating * count;
        });
        averageRating = totalStars / totalFeedback;
      }

      return {
        'totalFeedback': totalFeedback,
        'averageRating': averageRating,
        'ratingCounts': ratingCounts,
        'statusCounts': statusCounts,
      };
    } catch (e) {
      // Failed to get feedback stats (log removed): $e
      throw Exception('Failed to get feedback stats: $e');
    }
  }
}
