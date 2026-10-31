// lib/src/services/analytics_service.dart

import 'package:hive_flutter/hive_flutter.dart';

/// Startup holder for the analytics cache box.
///
/// The Firestore aggregation that used to live here had no caller; only the
/// box that earlier installs may already hold is still opened at startup.
class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._internal();
  factory AnalyticsService() => instance;
  AnalyticsService._internal();

  static const String _cacheBoxName = 'analytics_cache';

  /// Initialize Hive box for analytics caching
  Future<void> initialize() async {
    try {
      await Hive.openBox(_cacheBoxName);
      print('✅ AnalyticsService initialized with cache');
    } catch (e) {
      print('⚠️ AnalyticsService cache init failed: $e');
    }
  }
}
