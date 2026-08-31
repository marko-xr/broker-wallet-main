import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';

/// Supabase implementation of [UserRepository].
///
/// During the backend migration, identity/profile data lives in
/// `public.profiles`. Subscription state remains server-owned and will be
/// connected to RevenueCat in a later stage.
class SupabaseUserRepository implements UserRepository {
  SupabaseUserRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _table = 'profiles';

  @override
  Future<void> createUser(UserModel user) async {
    // Auth signup creates the profile through the database trigger. A client
    // may only update its own editable profile columns after it has a session.
    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != user.uid) {
      return;
    }

    await _client
        .from(_table)
        .update(_editableColumns(user))
        .eq('id', user.uid);
  }

  @override
  Future<UserModel?> getUserById(String uid) async {
    final row = await _client.from(_table).select().eq('id', uid).maybeSingle();
    return row == null ? null : _fromProfile(row);
  }

  @override
  Future<void> updateUser(UserModel user) async {
    await _client
        .from(_table)
        .update(_editableColumns(user))
        .eq('id', user.uid);
  }

  @override
  Future<void> deleteUser(String uid) async {
    throw UnsupportedError(
      'Supabase account deletion is server-owned and will be implemented with a protected backend operation.',
    );
  }

  @override
  Future<bool> userExists(String uid) async {
    return await getUserById(uid) != null;
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    // RLS means an authenticated client can only ever see its own profile.
    final row = await _client
        .from(_table)
        .select()
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    return row == null ? null : _fromProfile(row);
  }

  @override
  Future<void> updateUserPreferences(
    String uid,
    Map<String, dynamic> preferences,
  ) async {
    final existing = await getUserById(uid);
    final merged = <String, dynamic>{
      ...?existing?.preferences,
      ...preferences,
    };

    await _client.from(_table).update({'preferences': merged}).eq('id', uid);
  }

  @override
  Future<void> updateUserSubscription(
    String uid,
    UserSubscription subscription,
  ) async {
    throw UnsupportedError(
      'Subscription state is server-owned and will be supplied by RevenueCat.',
    );
  }

  @override
  Stream<UserModel?> getUserStream(String uid) {
    return _client
        .from(_table)
        .stream(primaryKey: const ['id'])
        .eq('id', uid)
        .map((rows) => rows.isEmpty ? null : _fromProfile(rows.first));
  }

  Map<String, dynamic> _editableColumns(UserModel user) {
    final phone = user.phoneNumber?.trim();
    return {
      'name': user.name.trim(),
      'phone_number': phone == null || phone.isEmpty ? null : phone,
      'phone_e164': PhoneNumberNormalizer.normalizeOptional(
        phoneNumber: phone,
        countryCode: '+971',
      ),
      'preferences': user.preferences,
    };
  }

  UserModel _fromProfile(Map<String, dynamic> row) {
    return UserModel(
      uid: row['id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      phoneNumber: row['phone_number'] as String?,
      // Profile media is stored as R2-backed metadata, not a permanent URL.
      // It will be resolved when the R2 media layer is migrated.
      profileImageUrl: null,
      createdAt: _parseTimestamp(row['created_at']) ?? DateTime.now(),
      lastLoginAt: _parseTimestamp(row['last_login_at']),
      isEmailVerified: row['is_email_verified'] as bool? ?? false,
      isPhoneVerified: row['is_phone_verified'] as bool? ?? false,
      subscription: _compatibilitySubscription(),
      preferences: Map<String, dynamic>.from(
        row['preferences'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  UserSubscription _compatibilitySubscription() {
    return UserSubscription(
      plan: 'pending_revenuecat',
      isActive: false,
      features: const [],
    );
  }
}
