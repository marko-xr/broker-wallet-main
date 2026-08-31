import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Auth implementation prepared for the Broker Wallet migration.
///
/// This foundation implements the email/password path first. Social login,
/// phone OTP, and protected account deletion intentionally remain disabled
/// until their dedicated migration stages.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({
    required UserRepository userRepository,
    SupabaseClient? client,
  })  : _userRepository = userRepository,
        _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final UserRepository _userRepository;
  String? _pendingVerificationEmail;

  @override
  Stream<UserModel?> get authStateChanges => _authStateStream();

  Stream<UserModel?> _authStateStream() async* {
    final initial = _client.auth.currentUser;
    yield await _resolveAuthUser(initial);

    await for (final state in _client.auth.onAuthStateChange) {
      yield await _resolveAuthUser(state.session?.user);
    }
  }

  @override
  UserModel? get currentUser {
    final user = _client.auth.currentUser;
    return user == null ? null : _fromAuthUser(user);
  }

  @override
  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    _pendingVerificationEmail = normalizedEmail;

    final response = await _client.auth.signUp(
      email: normalizedEmail,
      password: password,
      data: {
        'name': name.trim(),
        'full_name': name.trim(),
        if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
          'phone_number': phoneNumber.trim(),
      },
    );

    final user = response.user;
    if (user == null) {
      throw AuthException('Supabase did not return the created user.');
    }

    // Supabase can deliberately return an obfuscated user for an address that
    // already exists, to reduce user-enumeration risk. Do not treat a response
    // with no identities as a newly created Broker Wallet account.
    if (user.identities != null && user.identities!.isEmpty) {
      throw AuthException(
        'Unable to create this account. Try signing in or resetting the password.',
      );
    }

    // With hosted email confirmation enabled there is normally no session yet,
    // so RLS does not allow reading public.profiles until confirmation.
    if (response.session != null) {
      final profile = await _userRepository.getUserById(user.id);
      if (profile != null) return profile;
    }

    return UserModel(
      uid: user.id,
      name: name.trim(),
      email: normalizedEmail,
      phoneNumber: phoneNumber,
      profileImageUrl: null,
      createdAt: DateTime.now(),
      lastLoginAt: null,
      isEmailVerified: false,
      isPhoneVerified: false,
      subscription: _compatibilitySubscription(),
      preferences: const {},
    );
  }

  @override
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    _pendingVerificationEmail = normalizedEmail;

    final response = await _client.auth.signInWithPassword(
      email: normalizedEmail,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw AuthException('Supabase sign in did not return a user.');
    }

    _pendingVerificationEmail = user.email;
    return await _userRepository.getUserById(user.id) ?? _fromAuthUser(user);
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    throw UnsupportedError(
      'Google sign-in has not been migrated to Supabase yet.',
    );
  }

  @override
  Future<UserModel> signInWithFacebook() async {
    throw UnsupportedError(
      'Facebook sign-in has not been migrated to Supabase yet.',
    );
  }

  @override
  Future<void> sendEmailVerification() async {
    final email = _client.auth.currentUser?.email ?? _pendingVerificationEmail;
    if (email == null || email.isEmpty) {
      throw AuthException('No email is available to resend confirmation.');
    }

    await _client.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  @override
  Future<bool> isEmailVerified() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final profile = await _userRepository.getUserById(user.id);
    return profile?.isEmailVerified ?? _authUserEmailVerified(user);
  }

  @override
  Future<bool> checkEmailVerificationAndUpdate() async {
    // The database trigger keeps public.profiles synchronized with auth.users.
    return isEmailVerified();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    throw UnsupportedError(
      'Account deletion requires a protected server-side Supabase operation.',
    );
  }

  @override
  Future<void> updateUserProfile({
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw AuthException('No authenticated Supabase user.');
    }

    final existing = await _userRepository.getUserById(user.id);
    if (existing == null) {
      throw AuthException('The authenticated profile could not be loaded.');
    }

    await _userRepository.updateUser(
      existing.copyWith(
        name: name,
        phoneNumber: phoneNumber,
        profileImageUrl: profileImageUrl,
      ),
    );

    if (name != null) {
      await _client.auth.updateUser(
        UserAttributes(
          data: {
            ...?user.userMetadata,
            'name': name.trim(),
            'full_name': name.trim(),
          },
        ),
      );
    }
  }

  @override
  Future<void> updateEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    final current = _client.auth.currentUser;
    final currentEmail = current?.email;
    if (current == null || currentEmail == null || currentEmail.isEmpty) {
      throw AuthException('No authenticated email user.');
    }

    await _client.auth.signInWithPassword(
      email: currentEmail,
      password: currentPassword,
    );
    await _client.auth.updateUser(
      UserAttributes(email: newEmail.trim().toLowerCase()),
    );
  }

  @override
  Future<void> addEmailToAccount({
    required String email,
    required String password,
  }) async {
    if (_client.auth.currentUser == null) {
      throw AuthException('No authenticated Supabase user.');
    }

    await _client.auth.updateUser(
      UserAttributes(email: email.trim().toLowerCase()),
    );
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> sendPhoneVerificationOTP({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    throw UnsupportedError(
      'The current AuthRepository phone contract is Firebase-specific and will be replaced during the Supabase phone-auth stage.',
    );
  }

  @override
  Future<void> verifyPhoneNumber({
    required String verificationId,
    required String otpCode,
  }) async {
    throw UnsupportedError(
      'Supabase phone OTP verification has not been migrated yet.',
    );
  }

  @override
  Future<UserModel?> getUserProfile(String uid) {
    return _userRepository.getUserById(uid);
  }

  Future<UserModel?> _resolveAuthUser(User? user) async {
    if (user == null) return null;

    try {
      return await _userRepository.getUserById(user.id) ?? _fromAuthUser(user);
    } catch (_) {
      // Keep auth-state delivery resilient if profile loading is temporarily
      // unavailable. RLS still protects database access independently.
      return _fromAuthUser(user);
    }
  }

  UserModel _fromAuthUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return UserModel(
      uid: user.id,
      name: (metadata['full_name'] ?? metadata['name'] ?? '').toString(),
      email: user.email ?? '',
      phoneNumber: user.phone,
      profileImageUrl: null,
      createdAt: DateTime.now(),
      lastLoginAt: null,
      isEmailVerified: _authUserEmailVerified(user),
      isPhoneVerified: _authUserPhoneVerified(user),
      subscription: _compatibilitySubscription(),
      preferences: const {},
    );
  }

  bool _authUserEmailVerified(User user) {
    final dynamic value = user;
    return value.emailConfirmedAt != null;
  }

  bool _authUserPhoneVerified(User user) {
    final dynamic value = user;
    return value.phoneConfirmedAt != null;
  }

  UserSubscription _compatibilitySubscription() {
    return UserSubscription(
      plan: 'pending_revenuecat',
      isActive: false,
      features: const [],
    );
  }
}
