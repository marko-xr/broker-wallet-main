import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

/// Service to cache item counts for instant display and offline access
/// Provides immediate count values to prevent 0→real number flicker
class CountCacheService {
  static const String _countCacheKey = 'cached_item_counts';
  static const String _lastUpdateKey = 'counts_last_updated';

  static CountCacheService? _instance;
  static CountCacheService get instance => _instance ??= CountCacheService._();
  CountCacheService._();

  Map<String, int> _memoryCache = {};
  bool _isInitialized = false;

  /// Initialize the count cache service - load from disk into memory
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_countCacheKey);

      if (cachedJson != null) {
        final cachedData = json.decode(cachedJson) as Map<String, dynamic>;
        _memoryCache = Map<String, int>.from(cachedData);
      } else {
        // Initialize with zero counts if no cache exists
        _memoryCache = {
          'watchmen': 0,
          'brokers': 0,
          'offers': 0,
          'offices': 0,
          'owners': 0,
          'requested': 0,
          'quotation': 0,
        };
      }

      _isInitialized = true;
    } catch (e) {
      // Fallback to zero counts
      _memoryCache = {
        'watchmen': 0,
        'brokers': 0,
        'offers': 0,
        'offices': 0,
        'owners': 0,
        'requested': 0,
        'quotation': 0,
      };
      _isInitialized = true;
    }
  }

  /// Get cached count instantly (synchronous) - always returns immediately
  int getCachedCount(String type) {
    if (!_isInitialized) {
      // Return 0 if not yet initialized to prevent null issues
      return 0;
    }
    return _memoryCache[type] ?? 0;
  }

  /// Get all cached counts at once for efficiency
  Map<String, int> getAllCachedCounts() {
    if (!_isInitialized) {
      return {
        'watchmen': 0,
        'brokers': 0,
        'offers': 0,
        'offices': 0,
        'owners': 0,
        'requested': 0,
        'quotation': 0,
      };
    }
    return Map<String, int>.from(_memoryCache);
  }

  /// Update cached count and persist to disk (async but non-blocking)
  Future<void> updateCachedCount(String type, int count) async {
    _memoryCache[type] = count;

    // Persist to disk asynchronously without blocking
    _persistToStorage();
  }

  /// Update multiple counts at once for efficiency
  Future<void> updateCachedCounts(Map<String, int> counts) async {
    _memoryCache.addAll(counts);

    // Persist to disk asynchronously
    _persistToStorage();
  }

  /// Persist cached counts to SharedPreferences (fire-and-forget)
  void _persistToStorage() {
    // Use microtask to avoid blocking the UI
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonString = json.encode(_memoryCache);
        await prefs.setString(_countCacheKey, jsonString);
        await prefs.setInt(
            _lastUpdateKey, DateTime.now().millisecondsSinceEpoch);
      } catch (e) {
        // Non-critical failure - continue with memory cache
      }
    });
  }

  /// Check if cached data is recent (less than 1 hour old)
  Future<bool> isCacheRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdate = prefs.getInt(_lastUpdateKey) ?? 0;
      final hourAgo = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      return lastUpdate > hourAgo;
    } catch (e) {
      return false;
    }
  }

  /// Clear all cached counts (useful for debugging or sign out)
  Future<void> clearCache() async {
    try {
      _memoryCache.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_countCacheKey);
      await prefs.remove(_lastUpdateKey);
    } catch (e) {
    }
  }

  /// Get cache age in minutes
  Future<int> getCacheAgeMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdate = prefs.getInt(_lastUpdateKey) ?? 0;
      if (lastUpdate == 0) return -1; // No cache

      final now = DateTime.now().millisecondsSinceEpoch;
      return ((now - lastUpdate) / (1000 * 60)).round();
    } catch (e) {
      return -1;
    }
  }
}
