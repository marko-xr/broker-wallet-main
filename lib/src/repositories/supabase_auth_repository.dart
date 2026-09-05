import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase implementation of [AuthRepository].
///
/// Keeps user identity synchronized with `auth.users` and `public.profiles`.
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
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    _pendingVerificationEmail = normalizedEmail;

    try {
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
        throw const AuthFailure(
          code: AuthFailureCode.unknown,
          message: 'Supabase did not return the created user.',
        );
      }

      // Supabase can deliberately return an obfuscated user for an address that
      // already exists, to reduce user-enumeration risk. Do not treat a response
      // with no identities as a newly created Broker Wallet account.
      if (user.identities != null && user.identities!.isEmpty) {
        throw const AuthFailure(
          code: AuthFailureCode.emailAlreadyInUse,
          message:
              'An account already exists for this email. Try signing in or resetting your password.',
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
    } on AuthException catch (e) {
      throw AuthFailure.fromSupabase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to sign up: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    _pendingVerificationEmail = normalizedEmail;

    try {
      final response = await _client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw const AuthFailure(
          code: AuthFailureCode.unknown,
          message: 'Supabase sign in did not return a user.',
        );
      }

      _pendingVerificationEmail = user.email;
      return await _userRepository.getUserById(user.id) ?? _fromAuthUser(user);
    } on AuthException catch (e) {
      throw AuthFailure.fromSupabase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to sign in: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    throw AuthFailure.providerUnavailable('Google');
  }

  @override
  Future<UserModel> signInWithFacebook() async {
    throw AuthFailure.providerUnavailable('Facebook');
  }

  @override
  Future<void> sendEmailVerification({String? email}) async {
    final targetEmail = email?.trim().toLowerCase() ??
        _client.auth.currentUser?.email ??
        _pendingVerificationEmail;
    if (targetEmail == null || targetEmail.isEmpty) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'No email is available to resend confirmation.',
      );
    }

    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: targetEmail,
      );
    } on AuthException catch (e) {
      throw AuthFailure.fromSupabase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to send confirmation email: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<bool> isEmailVerified() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      if (_authUserEmailVerified(user)) return true;
      final profile = await _userRepository.getUserById(user.id);
      if (profile?.isEmailVerified == true) return true;
    }

    if (_pendingVerificationEmail != null) {
      final profile =
          await _userRepository.getUserByEmail(_pendingVerificationEmail!);
      if (profile?.isEmailVerified == true) return true;
    }

    return false;
  }

  @override
  Future<UserModel?> reloadUser() async {
    try {
      if (_client.auth.currentSession != null) {
        final response = await _client.auth.getUser();
        final user = response.user;
        if (user != null) {
          final profile = await _userRepository.getUserById(user.id);
          if (profile != null) return profile;
          return _fromAuthUser(user);
        }
      }
    } catch (_) {}

    final user = _client.auth.currentUser;
    if (user != null) {
      return await _userRepository.getUserById(user.id) ?? _fromAuthUser(user);
    }

    if (_pendingVerificationEmail != null) {
      final profile =
          await _userRepository.getUserByEmail(_pendingVerificationEmail!);
      if (profile != null) return profile;
    }

    return null;
  }

  @override
  Future<bool> checkEmailVerificationAndUpdate() async {
    // The database trigger keeps public.profiles synchronized with auth.users.
    return isEmailVerified();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
    } on AuthException catch (e) {
      throw AuthFailure.fromSupabase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to send password reset email: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<void> signOut() async {
    await OfflineAuthService.instance.clearAuthCache();
    await _client.auth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    throw const AuthFailure(
      code: AuthFailureCode.operationNotAllowed,
      message:
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
    const failure = AuthFailure(
      code: AuthFailureCode.providerUnavailable,
      message:
          'Phone sign-in is not supported in the Supabase configuration yet.',
    );
    onError(failure.message);
    throw failure;
  }

  @override
  Future<void> verifyPhoneNumber({
    required String verificationId,
    required String otpCode,
  }) async {
    throw AuthFailure.providerUnavailable('Phone');
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
    return user.emailConfirmedAt != null;
  }

  bool _authUserPhoneVerified(User user) {
    return user.phoneConfirmedAt != null;
  }

  UserSubscription _compatibilitySubscription() {
    return UserSubscription(
      plan: 'pending_revenuecat',
      isActive: false,
      features: const [],
    );
  }
}
