import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Secure session persistence for Supabase Auth backed by [FlutterSecureStorage].
/// Replaces the default SharedPreferences session storage with encrypted device storage.
class SupabaseSecureStorage extends LocalStorage {
  SupabaseSecureStorage({
    FlutterSecureStorage? storage,
    this.persistSessionKey = 'supabase.auth.token',
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;
  final String persistSessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    return await _storage.containsKey(key: persistSessionKey);
  }

  @override
  Future<String?> accessToken() async {
    return await _storage.read(key: persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _storage.write(key: persistSessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _storage.delete(key: persistSessionKey);
  }
}
