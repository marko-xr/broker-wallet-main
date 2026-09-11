import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'dart:convert';

/// Service to cache user authentication state for offline access
/// Ensures users remain authenticated even when Firestore is unreachable
class OfflineAuthService {
  static const String _userCacheKey = 'cached_user_model';
  static const String _authStateKey = 'is_authenticated';

  /// Separate key for the Supabase last-known-good profile snapshot.
  ///
  /// Deliberately not [_userCacheKey]: that key belongs to the legacy Firebase
  /// path, which is the only remaining reader of [getCachedUserModel]. Keeping
  /// them apart means the snapshot's stricter rules (no signed URL, strict uid
  /// match) cannot alter legacy behavior, and needs no change to
  /// `UserModel.toMap()` — which both paths share.
  static const String _profileSnapshotKey = 'cached_profile_snapshot_v1';

  /// Signed R2 read URLs are short-lived presentation data. Persisting one
  /// means restoring an expired URL on the next cold start, which fails with a
  /// 403 and renders an error widget — strictly worse than the placeholder it
  /// would be replacing. `profileMediaId` is the durable identity and is
  /// persisted instead.
  static const String _signedUrlField = 'profileImageUrl';

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

  /// Store the last-known-good profile snapshot.
  ///
  /// Only a hydrated, `public.profiles`-backed model may be written here. A
  /// session-only identity would degrade the snapshot to signup-era metadata
  /// with no `profileMediaId`, which is exactly what the snapshot exists to
  /// avoid showing.
  Future<void> cacheProfileSnapshot(UserModel user) async {
    if (user.uid.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = Map<String, dynamic>.from(user.toMap())
        ..remove(_signedUrlField);
      await prefs.setString(_profileSnapshotKey, json.encode(snapshot));
    } catch (e) {
      // Snapshot caching is best effort and must never affect the save path.
    }
  }

  /// Read the last-known-good profile snapshot for [expectedUid].
  ///
  /// Returns null unless the stored snapshot belongs to exactly that user.
  /// Account isolation must not depend on [clearAuthCache] alone: that clear is
  /// dispatched without being awaited, so a snapshot for a previous user can
  /// still be on disk when the next session resolves.
  Future<UserModel?> getProfileSnapshot(String expectedUid) async {
    if (expectedUid.isEmpty) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshotJson = prefs.getString(_profileSnapshotKey);
      if (snapshotJson == null) return null;

      final snapshotMap = json.decode(snapshotJson) as Map<String, dynamic>;
      if (snapshotMap['uid'] != expectedUid) {
        return null;
      }

      // A snapshot never carries a signed URL, but strip defensively so an
      // older stored payload cannot reintroduce one.
      snapshotMap.remove(_signedUrlField);
      return UserModel.fromMap(snapshotMap);
    } catch (e) {
      return null;
    }
  }

  /// Clear cached auth state (for sign out)
  Future<void> clearAuthCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userCacheKey);
      await prefs.remove(_profileSnapshotKey);
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
