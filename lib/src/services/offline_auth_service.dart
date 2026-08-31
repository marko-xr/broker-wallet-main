import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'dart:convert';

/// Service to cache user authentication state for offline access
/// Ensures users remain authenticated even when Firestore is unreachable
class OfflineAuthService {
  static const String _userCacheKey = 'cached_user_model';
  static const String _authStateKey = 'is_authenticated';

  static OfflineAuthService? _instance;
  static OfflineAuthService get instance =>
      _instance ??= OfflineAuthService._();
  OfflineAuthService._();

  /// Cache the user model for offline access
  Future<void> cacheUserModel(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = json.encode(user.toMap());
      await prefs.setString(_userCacheKey, userJson);
      await prefs.setBool(_authStateKey, true);
      // User model cached for offline access (log removed)
    } catch (e) {
      // Failed to cache user model (log removed): $e
    }
  }

  /// Get cached user model for offline access
  Future<UserModel?> getCachedUserModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userCacheKey);
      final isAuthenticated = prefs.getBool(_authStateKey) ?? false;

      if (userJson != null && isAuthenticated) {
        final userMap = json.decode(userJson) as Map<String, dynamic>;
        return UserModel.fromMap(userMap);
      }
      return null;
    } catch (e) {
      // Failed to get cached user model (log removed): $e
      return null;
    }
  }

  /// Check if user was authenticated based on cache
  Future<bool> isUserAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_authStateKey) ?? false;
    } catch (e) {
      // Failed to check auth state (log removed): $e
      return false;
    }
  }

  /// Clear cached auth state (for sign out)
  Future<void> clearAuthCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userCacheKey);
      await prefs.setBool(_authStateKey, false);
      // Auth cache cleared (log removed)
    } catch (e) {
      // Failed to clear auth cache (log removed): $e
    }
  }

  /// Update cached user model (for profile updates)
  Future<void> updateCachedUserModel(UserModel user) async {
    await cacheUserModel(user); // Same as caching
  }
}
