import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/r2_profile_upload_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves the short-lived signed read URL for a canonical profile media id.
///
/// Deliberately a separate capability rather than part of [UserRepository]:
/// a signed URL is ephemeral presentation data, it is not profile state, and
/// it must never sit inside an authoritative `public.profiles` read. Callers
/// feature-test for this interface, so backends without private media (the
/// Firestore repository) need no changes.
abstract class ProfileImageUrlResolver {
  /// Returns a signed read URL for [profileMediaId], or null when it cannot be
  /// resolved. Never throws: an unresolved image is a presentation outcome,
  /// never an authentication or profile failure.
  Future<String?> resolveProfileImageUrl(String profileMediaId);
}

/// Supabase implementation of [UserRepository].
///
/// During the backend migration, identity/profile data lives in
/// `public.profiles`. Subscription state remains server-owned and will be
/// connected to RevenueCat in a later stage.
class SupabaseUserRepository
    implements UserRepository, ProfileImageUrlResolver {
  SupabaseUserRepository({
    SupabaseClient? client,
    R2ProfileUploadService? profileImageService,
  })  : _client = client ?? Supabase.instance.client,
        _profileImageService = profileImageService ??
            R2ProfileUploadService(
              supabaseClient: client ?? Supabase.instance.client,
            );

  final SupabaseClient _client;
  final R2ProfileUploadService _profileImageService;

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

  @override
  Future<String?> resolveProfileImageUrl(String profileMediaId) =>
      _resolveProfileImageUrl(profileMediaId);

  /// The profile columns a client may write: exactly the ones the database
  /// grants to `authenticated`.
  ///
  /// `phone_number` and `phone_e164` are deliberately absent. They mirror
  /// Supabase Auth's confirmed phone and are maintained only by the
  /// `sync_auth_identity_to_profile` trigger; clients have no UPDATE privilege
  /// on them. Sending them would make every save here — notification settings,
  /// preference toggles, name backfill — fail outright, and before that it let
  /// a stale cached phone overwrite a freshly confirmed one. Phone changes go
  /// through `PhoneVerificationCapability` instead.
  Map<String, dynamic> _editableColumns(UserModel user) {
    return {
      'name': user.name.trim(),
      'preferences': user.preferences,
    };
  }

  /// Maps an authoritative `public.profiles` row to a [UserModel].
  ///
  /// Synchronous by design. This read is on the authentication/profile
  /// critical path, so it must never await a Cloudflare R2 signed-URL
  /// request. `profile_media_id` stays canonical here; `profileImageUrl` is
  /// left null and resolved separately through [resolveProfileImageUrl].
  UserModel _fromProfile(Map<String, dynamic> row) {
    final profileMediaId = _profileMediaId(row['profile_media_id']);

    return UserModel(
      uid: row['id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      phoneNumber: row['phone_number'] as String?,
      profileImageUrl: null,
      profileMediaId: profileMediaId,
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

  String? _profileMediaId(dynamic value) {
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Future<String?> _resolveProfileImageUrl(String profileMediaId) async {
    try {
      final url = await _profileImageService.resolveSignedUrl(profileMediaId);
      return url == null || url.trim().isEmpty ? null : url;
    } catch (_) {
      // Signed image URLs are optional presentation data. The authoritative
      // profile read must still succeed if this request cannot be resolved.
      return null;
    }
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
