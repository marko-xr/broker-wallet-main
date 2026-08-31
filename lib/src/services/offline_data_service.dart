import 'package:hive/hive.dart';
import 'dart:async';

/// Service to manage offline data caching for critical app data
/// Ensures users can access saved/favorite items even when offline
class OfflineDataService {
  static const String _savedItemsBoxName = 'saved_items_offline';
  static const String _userDataBoxName = 'user_data_offline';

  late Box<Map> _savedItemsBox;
  late Box<Map> _userDataBox;

  static OfflineDataService? _instance;
  static OfflineDataService get instance =>
      _instance ??= OfflineDataService._();
  OfflineDataService._();

  /// Initialize offline data service
  Future<void> initialize() async {
    try {
      _savedItemsBox = await Hive.openBox<Map>(_savedItemsBoxName);
      _userDataBox = await Hive.openBox<Map>(_userDataBoxName);
      // OfflineDataService initialized (log removed)
    } catch (e) {
      // OfflineDataService init failed (log removed): $e
      // Continue without offline data service if needed
    }
  }

  /// Cache user's saved/favorite items for offline access
  Future<void> cacheSavedItems(
      String userId, Map<String, List<Map<String, dynamic>>> savedItems) async {
    try {
      if (!Hive.isBoxOpen(_savedItemsBoxName)) return;

      await _savedItemsBox.put(userId, savedItems);
      // Cached ${savedItems.length} saved item categories for offline access (log removed)
    } catch (e) {
      // Failed to cache saved items (log removed): $e
    }
  }

  /// Get cached saved items for offline access
  Map<String, List<Map<String, dynamic>>> getCachedSavedItems(String userId) {
    try {
      if (!Hive.isBoxOpen(_savedItemsBoxName)) return {};

      final cached = _savedItemsBox.get(userId);
      if (cached != null) {
        return Map<String, List<Map<String, dynamic>>>.from(cached.map(
            (key, value) => MapEntry(
                key.toString(), List<Map<String, dynamic>>.from(value ?? []))));
      }
      return {};
    } catch (e) {
      // Failed to get cached saved items (log removed): $e
      return {};
    }
  }

  /// Cache basic user data for offline access
  Future<void> cacheUserData(
      String userId, Map<String, dynamic> userData) async {
    try {
      if (!Hive.isBoxOpen(_userDataBoxName)) return;

      await _userDataBox.put(userId, userData);
      // Cached user data for offline access (log removed)
    } catch (e) {
      // Failed to cache user data (log removed): $e
    }
  }

  /// Get cached user data for offline access
  Map<String, dynamic>? getCachedUserData(String userId) {
    try {
      if (!Hive.isBoxOpen(_userDataBoxName)) return null;

      final cached = _userDataBox.get(userId);
      return cached != null ? Map<String, dynamic>.from(cached) : null;
    } catch (e) {
      return null;
    }
  }

  /// Check if we have enough offline data to show saved items
  bool hasOfflineData(String userId) {
    try {
      final savedItems = getCachedSavedItems(userId);
      return savedItems.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Clear cached data for a user (useful for sign out)
  Future<void> clearUserCache(String userId) async {
    try {
      if (Hive.isBoxOpen(_savedItemsBoxName)) {
        await _savedItemsBox.delete(userId);
      }
      if (Hive.isBoxOpen(_userDataBoxName)) {
        await _userDataBox.delete(userId);
      }
      // Cleared offline cache for user (log removed)
    } catch (e) {
      // Failed to clear user cache (log removed): $e
    }
  }

  /// Get total cached data size info
  int getCachedItemsCount(String userId) {
    try {
      final savedItems = getCachedSavedItems(userId);
      return savedItems.values.fold(0, (sum, list) => sum + list.length);
    } catch (e) {
      return 0;
    }
  }
}
