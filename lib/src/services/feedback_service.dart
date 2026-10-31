// lib/src/services/feedback_service.dart
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/feedback_model.dart';
import '../data/models/user_model.dart';
import 'dart:io';

class FeedbackService {
  /// Submit feedback for admin review
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
}
