import 'dart:async';

import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Supabase implementation of [AuthRepository].
///
/// Keeps user identity synchronized with `auth.users` and `public.profiles`.
class SupabaseAuthRepository
    implements
        AuthRepository,
        PhoneVerificationCapability,
        EmailChangeCapability,
        PasswordCapability {
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
  final StreamController<EmailChangeState?> _emailChangeController =
      StreamController<EmailChangeState?>.broadcast();

  /// Recovery sessions, fanned out from the same single Supabase auth
  /// subscription as identity. Deliberately not replayed to late
  /// subscribers: a recovery session is an event in time, and replaying a
  /// stale one would re-open the reset screen long after the reset finished.
  final StreamController<PasswordRecoverySession> _passwordRecoveryController =
      StreamController<PasswordRecoverySession>.broadcast();

  StreamSubscription<AuthState>? _supabaseAuthSubscription;

  /// The account whose live session is a password recovery, or null.
  ///
  /// Assigned before the matching identity is published, so a consumer that
  /// reads [isPasswordRecoveryActive] while handling that identity sees the
  /// truth for the same session rather than the previous one.
  String? _passwordRecoveryUid;

  bool _pipelineStarted = false;
  UserModel? _latestIdentity;
  bool _hasLatestIdentity = false;
  EmailChangeState? _latestEmailChange;
  bool _hasLatestEmailChange = false;

  @override
  Stream<UserModel?> get authStateChanges {
    _startIdentityPipeline();
    return _replayLatestThen(_identityController.stream);
  }

  @override
  EmailChangeState? get currentEmailChange {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final latest = _latestEmailChange;
    return latest?.ownerUid == user.id
        ? latest
        : _emailChangeFromAuthUser(user);
  }

  @override
  Stream<EmailChangeState?> get emailChangeChanges {
    _startIdentityPipeline();
    return _replayLatestEmailChangeThen(_emailChangeController.stream);
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

  Stream<EmailChangeState?> _replayLatestEmailChangeThen(
    Stream<EmailChangeState?> source,
  ) {
    late final StreamController<EmailChangeState?> out;
    StreamSubscription<EmailChangeState?>? subscription;

    out = StreamController<EmailChangeState?>(
      onListen: () {
        subscription = source.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        if (_hasLatestEmailChange) {
          out.add(_latestEmailChange);
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

    // A recovery session that survived process death carries no marker of its
    // own: `recoverSession` restores it and announces `initialSession`, the
    // same event an ordinary restored session produces. The persisted owner id
    // is therefore read *first*, so the very first identity this pipeline
    // publishes already knows what kind of session it belongs to.
    _passwordRecoveryUid = PasswordRecoveryStateStore.ownerUid;

    // The restored session is available synchronously once Supabase has been
    // initialized, so bootstrap no longer waits on any network round trip.
    _publishIdentity(_client.auth.currentUser);

    _supabaseAuthSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthState,
      onError: _identityController.addError,
    );
  }

  /// The one place a Supabase auth event is interpreted.
  ///
  /// Identity is published for every event, exactly as before. A password
  /// recovery is additionally announced, because it is the only event that
  /// tells the application the session it just received came from a recovery
  /// link rather than from an ordinary sign-in. Nothing here creates,
  /// refreshes or invalidates a session.
  void _handleAuthState(AuthState state) {
    final user = state.session?.user;

    // Recovery ownership is resolved BEFORE the identity is published. This
    // ordering is the fix for the real-device failure: publishing identity
    // first let `AuthViewModel` reach `authenticated`, and the router reach
    // Home, a microtask before anything could say the session was a recovery.
    PasswordRecoverySession? started;
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        // Supabase emits this only after it has exchanged a `type=recovery`
        // callback, so the uid is authoritative session identity. A recovery
        // event without a session cannot be acted on and is dropped.
        if (user != null) {
          _passwordRecoveryUid = user.id;
          unawaited(PasswordRecoveryStateStore.remember(user.id));
          started = PasswordRecoverySession(
            ownerUid: user.id,
            startedAt: DateTime.now().toUtc(),
          );
        }
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.signedOut:
        // An ordinary sign-in and an authoritative sign-out both end any
        // recovery. Clearing on `signedIn` is what stops a marker left behind
        // by an abandoned recovery from following the account into its next
        // normal session.
        _clearPasswordRecovery();
      case _:
        break;
    }

    _publishIdentity(user);

    if (started != null && !_passwordRecoveryController.isClosed) {
      _passwordRecoveryController.add(started);
    }
  }

  void _clearPasswordRecovery() {
    if (_passwordRecoveryUid == null &&
        PasswordRecoveryStateStore.ownerUid == null) {
      return;
    }
    _passwordRecoveryUid = null;
    unawaited(PasswordRecoveryStateStore.forget());
  }

  void _publishIdentity(User? user) {
    final identity = user == null ? null : _fromAuthUser(user);
    _latestIdentity = identity;
    _hasLatestIdentity = true;
    if (!_identityController.isClosed) {
      _identityController.add(identity);
    }

    final emailChange = _emailChangeFromAuthUser(user);
    _latestEmailChange = emailChange;
    _hasLatestEmailChange = true;
    if (!_emailChangeController.isClosed) {
      _emailChangeController.add(emailChange);
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
    await _emailChangeController.close();
    await _passwordRecoveryController.close();
  }

  @override
  UserModel? get currentUser {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final latest = _latestIdentity;
    return latest?.uid == user.id ? latest : _fromAuthUser(user);
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

  /// Compatibility for the backend-neutral legacy contract. Every Supabase
  /// path converges on [requestPasswordReset], so the generic contract and the
  /// capability cannot drift apart.
  @override
  Future<void> sendPasswordResetEmail(String email) =>
      requestPasswordReset(email);

  // ---------------------------------------------------------------------------
  // PasswordCapability
  // ---------------------------------------------------------------------------

  /// Sending a current password that the server will not check would claim a
  /// verification that never happens, so this follows the hosted setting and
  /// nothing else.
  @override
  bool get verifiesCurrentPassword =>
      SupabaseConfig.requireCurrentPasswordOnChange;

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        // Deliberately *not* the shared auth callback. A recovery link that
        // succeeds is identifiable from `AuthChangeEvent.passwordRecovery`,
        // but one that has expired is never exchanged at all and comes back
        // as a bare error redirect. Giving recovery its own address is what
        // lets the application recognise that case without guessing.
        redirectTo: SupabaseConfig.passwordRecoveryCallbackUri,
      );
    } catch (e) {
      throw AuthFailure.fromSupabasePassword(e);
    }
  }

  /// Changes the password of the account that owns the live session.
  ///
  /// The account is captured before the call and re-checked after it, against
  /// the session itself rather than any caller-supplied id, so a sign-out or
  /// an account switch that lands mid-request can never be reported as a
  /// successful change on the wrong account.
  ///
  /// This is the same call for an ordinary Change Password and for the final
  /// step of a recovery, because Supabase treats a recovery session as a
  /// normal session â which is exactly why the recovery *context* is tracked
  /// separately by the application rather than inferred here.
  @override
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || _client.auth.currentSession == null) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    final ownerUid = user.id;

    final UserResponse response;
    try {
      response = await _client.auth.updateUser(
        UserAttributes(
          password: newPassword,
          currentPassword: verifiesCurrentPassword ? currentPassword : null,
        ),
      );
    } catch (e) {
      throw AuthFailure.fromSupabasePassword(e);
    }

    final updated = response.user;
    if (updated == null ||
        updated.id != ownerUid ||
        _client.auth.currentUser?.id != ownerUid) {
      throw const AuthFailure(
        code: AuthFailureCode.accountChanged,
        message: 'The authenticated account changed.',
      );
    }
  }

  @override
  Stream<PasswordRecoverySession> get passwordRecoverySessions {
    _startIdentityPipeline();
    return _passwordRecoveryController.stream;
  }

  /// True only while the live session is the one the recovery was established
  /// for. Binding to the uid means a marker can never describe a session that
  /// belongs to someone else, and a signed-out client is never "in recovery".
  @override
  bool get isPasswordRecoveryActive {
    _startIdentityPipeline();
    final uid = _passwordRecoveryUid;
    if (uid == null) return false;
    return _client.auth.currentUser?.id == uid;
  }

  @override
  Future<void> endPasswordRecovery() async {
    _clearPasswordRecovery();
    if (_client.auth.currentSession == null) return;
    try {
      await _client.auth.signOut();
    } catch (_) {
      // The recovery marker is already gone, so the gate is released either
      // way. A sign-out that cannot reach the server must not strand the user
      // on the reset screen.
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

  /// Persists editable profile fields in one authoritative round trip.
  ///
  /// This used to read the row, write every editable column back from that
  /// read, then read the row again to verify — three sequential requests on
  /// the save path. It now issues a single `UPDATE … RETURNING` for only the
  /// columns the caller supplied. The returned row *is* the confirmation, so
  /// persistence is still verified, just without a second read. Columns that
  /// were not supplied are left untouched instead of being rewritten from a
  /// copy of themselves.
  ///
  /// [phoneNumber] is refused. The profile phone mirrors Supabase Auth's
  /// confirmed phone, is maintained only by the database, and is not
  /// client-writable; a phone change must go through
  /// [PhoneVerificationCapability]. Refusing — rather than silently ignoring —
  /// means a caller can never believe an unverified number was saved.
  ///
  /// [profileImageUrl] is intentionally ignored: in Supabase mode media is
  /// linked server-side by `profile_media_id`, never by URL.
  @override
  Future<void> updateUserProfile({
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  }) async {
    if (phoneNumber != null) {
      throw const AuthFailure(
        code: AuthFailureCode.operationNotAllowed,
        message: 'Phone numbers change only through phone verification.',
      );
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      throw AuthException('No authenticated Supabase user.');
    }

    final sanitizedName = name?.trim();
    final changes = <String, dynamic>{};
    if (sanitizedName != null) {
      changes['name'] = sanitizedName;
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
    // Compatibility for the backend-neutral legacy contract. Supabase email
    // change is session-owned and does not require a second password sign-in;
    // every Supabase path converges on the capability below.
    await requestEmailChange(newEmail);
  }

  @override
  Future<EmailChangeState> requestEmailChange(String newEmail) async {
    final initiatingUser = _client.auth.currentUser;
    final ownerUid = initiatingUser?.id;
    final currentEmail = initiatingUser?.email?.trim().toLowerCase() ?? '';
    if (ownerUid == null ||
        currentEmail.isEmpty ||
        _client.auth.currentSession == null) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active email session.',
      );
    }

    final normalizedEmail = newEmail.trim().toLowerCase();
    if (normalizedEmail == currentEmail) {
      throw const AuthFailure(
        code: AuthFailureCode.sameEmail,
        message: 'The new email matches the current email.',
      );
    }

    final UserResponse response;
    try {
      response = await _client.auth.updateUser(
        UserAttributes(email: normalizedEmail),
        emailRedirectTo: SupabaseConfig.authCallbackUri,
      );
    } catch (error) {
      throw AuthFailure.fromSupabaseEmailChange(error);
    }

    final liveUid = _client.auth.currentUser?.id;
    final responseUser = response.user;
    if (liveUid != ownerUid ||
        responseUser == null ||
        responseUser.id != ownerUid) {
      throw const AuthFailure(
        code: AuthFailureCode.accountChanged,
        message: 'The authenticated account changed.',
      );
    }

    return _emailChangeFromAuthUser(responseUser)!;
  }

  @override
  Future<EmailChangeState> resendEmailChange() async {
    final state = currentEmailChange;
    final ownerUid = state?.ownerUid;
    final pendingEmail = state?.pendingEmail;
    final confirmedEmail = state?.confirmedEmail ?? '';
    if (ownerUid == null ||
        confirmedEmail.isEmpty ||
        _client.auth.currentSession == null) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    if (pendingEmail == null || pendingEmail.isEmpty) {
      throw const AuthFailure(
        code: AuthFailureCode.noPendingEmailChange,
        message: 'There is no pending email change.',
      );
    }

    try {
      // The *confirmed* address, not the pending one. GoTrue's resend handler
      // finds the account with `FindUserByEmailAndAudience` over `users.email`,
      // which still holds the confirmed address while a change is pending; it
      // then sends to the stored `user.EmailChange` itself. Passing the pending
      // address here matches no account, so the resend silently does nothing.
      await _client.auth.resend(
        type: OtpType.emailChange,
        email: confirmedEmail,
        emailRedirectTo: SupabaseConfig.authCallbackUri,
      );
    } catch (error) {
      throw AuthFailure.fromSupabaseEmailChange(error);
    }

    if (_client.auth.currentUser?.id != ownerUid) {
      throw const AuthFailure(
        code: AuthFailureCode.accountChanged,
        message: 'The authenticated account changed.',
      );
    }
    return currentEmailChange!;
  }

  @override
  Future<EmailChangeState?> refreshEmailChange() async {
    final ownerUid = _client.auth.currentUser?.id;
    if (ownerUid == null || _client.auth.currentSession == null) return null;

    final UserResponse response;
    try {
      response = await _client.auth.getUser();
    } catch (error) {
      throw AuthFailure.fromSupabaseEmailChange(error);
    }

    final user = response.user;
    if (_client.auth.currentUser?.id != ownerUid ||
        user == null ||
        user.id != ownerUid) {
      throw const AuthFailure(
        code: AuthFailureCode.accountChanged,
        message: 'The authenticated account changed.',
      );
    }

    // `getUser()` is the authoritative network read but does not update the
    // SDK's stored session user. Publishing it through the existing single
    // identity pipeline refreshes AuthViewModel without adding another auth
    // listener or creating a second email authority.
    _publishIdentity(user);
    return _emailChangeFromAuthUser(user);
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

  /// Phone verification is a Supabase **phone change** on the signed-in
  /// account, never a phone sign-in:
  ///
  ///  * `updateUser(phone:)` requires the current session — it throws when
  ///    there is none — so the pending number is recorded against that
  ///    account, server-side. Supabase holds it apart from the confirmed
  ///    `auth.users.phone` until verified, so an unverified number is never
  ///    persisted as the account's phone, and the `auth.users` → profiles sync
  ///    trigger does not fire for it.
  ///  * `verifyOTP(type: phoneChange)` confirms it for that same account. It
  ///    cannot create a user; phone sign-up is disabled in this project.
  ///
  /// Nothing here touches `public.profiles`. The existing
  /// `sync_auth_identity_to_profile` trigger copies the confirmed phone and
  /// `phone_confirmed_at` across, and `is_phone_verified` is not writable by
  /// clients at all.
  @override
  Future<void> requestPhoneVerification(String phoneE164) async {
    try {
      final phone = PhoneNumberNormalizer.normalizeUaeMobile(phoneE164);
      await _client.auth.updateUser(UserAttributes(phone: phone));
    } catch (e) {
      throw AuthFailure.fromSupabasePhoneVerification(e);
    }
  }

  @override
  Future<void> resendPhoneVerification(String phoneE164) async {
    try {
      final phone = PhoneNumberNormalizer.normalizeUaeMobile(phoneE164);
      if (_client.auth.currentSession == null) {
        throw AuthSessionMissingException();
      }
      await _client.auth.resend(phone: phone, type: OtpType.phoneChange);
    } catch (e) {
      throw AuthFailure.fromSupabasePhoneVerification(e);
    }
  }

  @override
  Future<UserModel> confirmPhoneVerification({
    required String phoneE164,
    required String code,
  }) async {
    final String phone;
    final AuthResponse response;
    try {
      phone = PhoneNumberNormalizer.normalizeUaeMobile(phoneE164);
      if (_client.auth.currentSession == null) {
        throw AuthSessionMissingException();
      }
      response = await _client.auth.verifyOTP(
        phone: phone,
        token: code,
        type: OtpType.phoneChange,
      );
    } catch (e) {
      throw AuthFailure.fromSupabasePhoneVerification(e);
    }

    // An accepted code is not, by itself, proof of confirmation: a secure
    // two-step change accepts the first code without confirming anything.
    // Only the server reporting this exact number as the account's confirmed
    // phone counts.
    final user = response.user ?? _client.auth.currentUser;
    if (user == null ||
        user.phoneConfirmedAt == null ||
        !_isSamePhone(user.phone, phone)) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Supabase did not confirm the phone number.',
      );
    }
    return _fromAuthUser(user);
  }

  /// Supabase Auth may store phones without the leading `+`, so compare the
  /// canonical forms rather than the raw strings.
  bool _isSamePhone(String? stored, String expectedE164) {
    if (stored == null || stored.trim().isEmpty) return false;
    try {
      return PhoneNumberNormalizer.normalizeUaeMobile(stored) == expectedE164;
    } on PhoneValidationException {
      return false;
    }
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

  EmailChangeState? _emailChangeFromAuthUser(User? user) {
    if (user == null) return null;
    final confirmedEmail = user.email?.trim().toLowerCase() ?? '';
    final rawPending = user.newEmail?.trim().toLowerCase() ?? '';
    final pendingEmail =
        rawPending.isEmpty || rawPending == confirmedEmail ? null : rawPending;
    return EmailChangeState(
      ownerUid: user.id,
      confirmedEmail: confirmedEmail,
      pendingEmail: pendingEmail,
      requestedAt: DateTime.tryParse(user.emailChangeSentAt ?? ''),
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
