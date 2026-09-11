import 'dart:async';

import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

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

  /// Shared fan-out of authoritative session identity.
  ///
  /// [authStateChanges] used to be a factory getter returning a fresh `async*`
  /// stream, so every subscriber independently re-ran a `public.profiles`
  /// fetch (and, through it, a Cloudflare R2 signed-URL request) for the same
  /// auth event. There is now exactly one subscription to Supabase and one
  /// broadcast pipeline, and the events it carries are pure session identity:
  /// no database read, no network call, no R2 resolution.
  ///
  /// Profile hydration is deliberately *not* performed here. It is owned by
  /// `AuthViewModel`, which is the single canonical owner of the authenticated
  /// `UserModel`, so hydration happens exactly once regardless of how many
  /// components listen for identity.
  final StreamController<UserModel?> _identityController =
      StreamController<UserModel?>.broadcast();

  StreamSubscription<AuthState>? _supabaseAuthSubscription;
  bool _pipelineStarted = false;
  UserModel? _latestIdentity;
  bool _hasLatestIdentity = false;

  @override
  Stream<UserModel?> get authStateChanges {
    _startIdentityPipeline();
    return _replayLatestThen(_identityController.stream);
  }

  /// Late subscribers must not miss the current session state, and a plain
  /// broadcast stream does not replay anything. This attaches to the shared
  /// broadcast stream *first* and only then hands over the cached latest
  /// value, so no event can be dropped between replay and subscription.
  Stream<UserModel?> _replayLatestThen(Stream<UserModel?> source) {
    late final StreamController<UserModel?> out;
    StreamSubscription<UserModel?>? subscription;

    out = StreamController<UserModel?>(
      onListen: () {
        subscription = source.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        if (_hasLatestIdentity) {
          out.add(_latestIdentity);
        }
      },
      onCancel: () async {
        await subscription?.cancel();
        subscription = null;
      },
    );

    return out.stream;
  }

  void _startIdentityPipeline() {
    if (_pipelineStarted) return;
    _pipelineStarted = true;

    // The restored session is available synchronously once Supabase has been
    // initialized, so bootstrap no longer waits on any network round trip.
    _publishIdentity(_client.auth.currentUser);

    _supabaseAuthSubscription = _client.auth.onAuthStateChange.listen(
      (state) => _publishIdentity(state.session?.user),
      onError: _identityController.addError,
    );
  }

  void _publishIdentity(User? user) {
    final identity = user == null ? null : _fromAuthUser(user);
    _latestIdentity = identity;
    _hasLatestIdentity = true;
    if (!_identityController.isClosed) {
      _identityController.add(identity);
    }
  }

  /// Releases the shared Supabase subscription. Not part of [AuthRepository];
  /// the repository is a process-lifetime singleton in production and this
  /// exists so tests can tear the pipeline down deterministically.
  Future<void> dispose() async {
    await _supabaseAuthSubscription?.cancel();
    _supabaseAuthSubscription = null;
    _pipelineStarted = false;
    await _identityController.close();
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
        emailRedirectTo: SupabaseConfig.authCallbackUri,
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
        emailRedirectTo: SupabaseConfig.authCallbackUri,
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

    // A pending signup has no session and cannot read profiles under RLS.
    // Confirmation must establish a session through the SDK callback first.
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
    if (kDebugMode) {
      print('🚀 Supabase logout started');
    }

    try {
      await _client.auth.signOut();
    } on AuthException catch (e) {
      throw AuthFailure.fromSupabase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to sign out: $e',
        originalException: e,
      );
    }

    final hasSession = _client.auth.currentSession != null;
    final hasUser = _client.auth.currentUser != null;
    if (hasSession || hasUser) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Supabase sign out did not clear the active session.',
      );
    }

    await OfflineAuthService.instance.clearAuthCache();

    if (kDebugMode) {
      print('✅ Supabase logout completed');
      print('✅ Supabase session after logout: absent');
    }
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
  /// Persists editable profile fields in one authoritative round trip.
  ///
  /// This used to read the row, write every editable column back from that
  /// read, then read the row again to verify — three sequential requests on
  /// the save path. It now issues a single `UPDATE … RETURNING` for only the
  /// columns the caller supplied. The returned row *is* the confirmation, so
  /// persistence is still verified, just without a second read. Columns that
  /// were not supplied are left untouched instead of being rewritten from a
  /// copy of themselves — which also means a name-only save can no longer fail
  /// on a stored phone number that does not normalize.
  ///
  /// [profileImageUrl] is intentionally ignored: in Supabase mode media is
  /// linked server-side by `profile_media_id`, never by URL.
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

    final sanitizedName = name?.trim();
    final changes = <String, dynamic>{};
    if (sanitizedName != null) {
      changes['name'] = sanitizedName;
    }
    if (phoneNumber != null) {
      // Same column mapping and normalization SupabaseUserRepository applies.
      final phone = phoneNumber.trim();
      changes['phone_number'] = phone.isEmpty ? null : phone;
      changes['phone_e164'] = PhoneNumberNormalizer.normalizeOptional(
        phoneNumber: phone,
        countryCode: '+971',
      );
    }
    if (changes.isEmpty) return;

    // RLS scopes both the write and the returned row to the caller's own
    // profile, so an update that matched nothing comes back as null.
    final row = await _client
        .from('profiles')
        .update(changes)
        .eq('id', user.id)
        .select('name')
        .maybeSingle();

    if (row == null) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Profile update could not be confirmed from database.',
      );
    }
    final persistedName = (row['name'] as String? ?? '').trim();
    if (sanitizedName != null && persistedName != sanitizedName) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Profile name did not persist to the profile repository.',
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
