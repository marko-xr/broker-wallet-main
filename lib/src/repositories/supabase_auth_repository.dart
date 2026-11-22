import 'dart:async';

import 'package:broker_wallet/src/common/utils/email_validator.dart';
import 'package:broker_wallet/src/common/utils/password_policy.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart'
    show AccountExistence, AccountExistenceProbe;
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/password_recovery_state_store.dart';
import 'package:broker_wallet/src/services/app_session_check_outcome.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/contact_phone_service.dart';
import 'package:broker_wallet/src/services/offline_pass_lifecycle.dart';
import 'package:broker_wallet/src/services/list_refresh_signals.dart';
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
        PhoneSignInCapability,
        AddEmailCapability,
        SignInPhoneSource,
        PhoneNumberChangeCapability,
        EmailChangeCapability,
        PasswordCapability,
        AccountExistenceProbe,
        AppSessionEvents,
        AppSessionCheckProgress {
  SupabaseAuthRepository({
    required UserRepository userRepository,
    SupabaseClient? client,
    ContactPhoneGateway? contactPhones,
    PhoneNumberChangeGateway? phoneNumberChanges,
  })  : _userRepository = userRepository,
        _client = client ?? Supabase.instance.client,
        _contactPhonesOverride = contactPhones,
        _phoneNumberChangesOverride = phoneNumberChanges;

  final SupabaseClient _client;

  final ContactPhoneGateway? _contactPhonesOverride;
  late final ContactPhoneGateway _contactPhones =
      _contactPhonesOverride ?? WorkerContactPhoneGateway();

  final PhoneNumberChangeGateway? _phoneNumberChangesOverride;
  late final PhoneNumberChangeGateway _phoneNumberChanges =
      _phoneNumberChangesOverride ?? WorkerContactPhoneGateway();

  /// The sign-in number change this repository started, if any.
  _PendingPhoneChange? _pendingPhoneChange;

  /// A sign-in number this session changed, until the cached user catches up.
  ({String uid, String phoneE164})? _changedSignInPhone;

  /// The contact-number verification this repository started, if any. It
  /// belongs to the account and session that started it.
  _PendingContactPhone? _pendingContactPhone;

  /// The password chosen in Add Email, held in memory only until the server
  /// reports the new address confirmed for the same account.
  _PendingAddEmail? _pendingAddEmail;

  /// OFF-2b-3: the process's one offline pass lifecycle (and lease).
  final OfflinePassLifecycle _offlinePass = OfflinePassLifecycle.shared;

  late final AppSessionCoordinator _appSession = AppSessionCoordinator(
    _client,
    onSuperseded: () => unawaited(_endSupersededSession()),
    // Only an authoritative check confirmation issues the pass (never the
    // sign-in claim), for that exact session while it is still current.
    onConfirmed: (session, startedEpoch) => unawaited(_offlinePass
        .confirmed(session,
            startedEpoch: startedEpoch,
            currentSession: () => _client.auth.currentSession)
        .then<void>((_) {}, onError: (Object _) {})),
    confirmationEpoch: () => _offlinePass.epoch,
    onCredentialsRejected: () => _offlinePass
        .invalidate(OfflinePassInvalidation.credentialsRejected)
        .then<void>((_) {}),
    onResumeWhileUnverified: () {
      unawaited(retryAppSessionValidation().then<void>(
        (_) {}, onError: (Object _) {},
      ));
    },
    onCheckSlow: _showSessionCheckRetry,
    onCheckProgress: (running) {
      if (!_sessionCheckProgressController.isClosed) {
        _sessionCheckProgressController.add(running);
      }
    },
  );
  final StreamController<bool> _sessionCheckProgressController =
      StreamController<bool>.broadcast();
  @override
  Stream<bool> get sessionCheckInProgressEvents =>
      _sessionCheckProgressController.stream;

  /// While Retry is shown: a hint that the network is back (or the app came
  /// to the foreground) asks for one check. A hint is not proof of anything;
  /// the check joins one that is already running.
  StreamSubscription<void>? _recheckHints;

  void _showSessionCheckRetry() {
    final session = _client.auth.currentSession;
    if (session == null ||
        isPasswordRecoveryActive ||
        _appSession.isAuthorized(session)) {
      return;
    }
    _sessionCheckUnavailableController.add(true);
    _listenForRecheckHints();
  }

  void _listenForRecheckHints() {
    _recheckHints ??= ListRefreshSignals.instance.hints.listen((_) {
      unawaited(retryAppSessionValidation().then<void>(
        (_) {},
        onError: (Object _) {},
      ));
    });
  }

  void _stopRecheckHints() {
    final hints = _recheckHints;
    _recheckHints = null;
    if (hints != null) unawaited(hints.cancel());
  }

  // Deliver accessRevoked synchronously so the view model closes protected
  // state before the local Auth sign-out begins.
  final StreamController<AppSessionSupersededPhase> _supersededController =
      StreamController<AppSessionSupersededPhase>.broadcast(sync: true);
  final StreamController<bool> _sessionCheckUnavailableController =
      StreamController<bool>.broadcast();
  @override
  Stream<AppSessionSupersededPhase> get sessionSupersededEvents =>
      _supersededController.stream;
  @override
  Stream<bool> get sessionCheckUnavailableEvents =>
      _sessionCheckUnavailableController.stream;
  bool _endingSuperseded = false;

  @override
  Future<void> retryAppSessionValidation() async {
    final session = _client.auth.currentSession;
    if (session == null || isPasswordRecoveryActive || _appSession.isAuthorized(session)) return;
    await _authorizeAndPublish(session, claim: false);
  }
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
    final restored = _client.auth.currentSession;
    if (restored == null) {
      _publishIdentity(null);
    } else if (isPasswordRecoveryActive) {
      _publishIdentity(restored.user);
    } else {
      unawaited(_authorizeAndPublish(restored, claim: false).then<void>(
        (_) {}, onError: (Object _) {},
      ));
    }

    _supabaseAuthSubscription = _client.auth.onAuthStateChange.listen(
      _handleAuthState,
      onError: (Object error, StackTrace stackTrace) {
        // The SDK's own type for "the server was not reached, or answered
        // 5xx" while refreshing. It keeps the session and carries nothing
        // about authorization, so it must not read as a sign-out while that
        // session is still stored; the session check decides. Every other
        // error is passed on as before, and a sign-out is an event, not an
        // error, so it is never held back here.
        if (error is AuthRetryableFetchException &&
            _client.auth.currentSession != null) {
          return;
        }
        _identityController.addError(error, stackTrace);
      },
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
    // OFF-2b-3: these end offline access before anything else happens. The
    // lease runs its operations in order, so a later issue cannot overtake.
    final endsOfflineAccess = switch (state.event) {
      AuthChangeEvent.passwordRecovery =>
        OfflinePassInvalidation.passwordRecovery,
      AuthChangeEvent.signedIn => OfflinePassInvalidation.newSignIn,
      AuthChangeEvent.signedOut => OfflinePassInvalidation.signedOut,
      _ => state.session == null ? OfflinePassInvalidation.signedOut : null,
    };
    if (endsOfflineAccess != null) {
      // A recovery session is latched (no pass for it in this process).
      final recovering =
          endsOfflineAccess == OfflinePassInvalidation.passwordRecovery
              ? state.session
              : null;
      unawaited(_offlinePass
          .invalidate(endsOfflineAccess,
              uid: recovering?.user.id,
              sid: AppSessionCoordinator.sessionId(recovering))
          .then<void>((_) {}, onError: (Object _) {}));
    }
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

    final session = state.session;
    if (session == null) {
      _stopRecheckHints();
      _appSession.clear();
      _publishIdentity(null);
    } else if (started != null || isPasswordRecoveryActive) {
      _stopRecheckHints();
      _appSession.clear();
      _publishIdentity(user);
    } else if (state.event == AuthChangeEvent.signedIn) {
      if (!_appSession.isAuthorized(session)) _publishIdentity(null);
      unawaited(_authorizeAndPublish(session, claim: true).then<void>(
        (_) {}, onError: (Object _) {},
      ));
    } else if (_appSession.isAuthorized(session)) {
      _publishIdentity(user);
      if (state.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(_appSession.validateNow().then<void>(
          (_) {}, onError: (Object _) {},
        ));
      }
    } else {
      unawaited(_authorizeAndPublish(session, claim: false).then<void>(
        (_) {}, onError: (Object _) {},
      ));
    }

    if (started != null && !_passwordRecoveryController.isClosed) {
      _passwordRecoveryController.add(started);
    }
  }

  Future<bool> _authorizeAndPublish(Session session, {required bool claim}) async {
    try {
      final allowed = await _appSession.authorize(session, claim: claim);
      if (allowed && _appSession.isAuthorized(session)) {
        _stopRecheckHints();
        _sessionCheckUnavailableController.add(false);
        _publishIdentity(session.user);
        return true;
      }
      return false;
    } catch (error) {
      // OFF-2b-3: a token the server refused (401/403) ends offline access; a
      // later network failure can never turn it back into a pass.
      if (classifySessionCheckError(error) ==
          AppSessionCheckOutcome.credentialsRejected) {
        await _offlinePass
            .invalidate(OfflinePassInvalidation.credentialsRejected);
      }
      final displaced = error.toString().contains('session_superseded');
      if (displaced) _appSession.supersede();
      if (!claim && !displaced) {
        // A restored session with no network remains cached for a retry, but
        // its app identity is never published until the server confirms it.
        // A failure that belongs to a session that has since gone or changed
        // raises nothing.
        if (AppSessionCoordinator.sessionId(_client.auth.currentSession) ==
            AppSessionCoordinator.sessionId(session)) {
          _sessionCheckUnavailableController.add(true);
          _listenForRecheckHints();
        }
        throw AuthFailure(
          code: AuthFailureCode.appSessionUnavailable,
          message: 'Application session verification is unavailable.',
          originalException: error,
        );
      }
      // A check that could not complete cannot authorize Home. End this local
      // session; the sign-in caller also receives the authoritative failure.
      if (!displaced &&
          AppSessionCoordinator.sessionId(_client.auth.currentSession) ==
          AppSessionCoordinator.sessionId(session)) {
        try {
          await _client.auth.signOut(scope: SignOutScope.local);
        } catch (signOutError) {
          _identityController.addError(signOutError);
        }
      }
      _identityController.addError(error);
      throw AuthFailure(
        code: displaced
            ? AuthFailureCode.sessionExpired
            : AuthFailureCode.appSessionUnavailable,
        message: displaced
            ? 'This sign-in session was replaced.'
            : 'Application session verification is unavailable.',
        originalException: error,
      );
    }
  }

  Future<void> _endSupersededSession() async {
    if (_endingSuperseded) return;
    _endingSuperseded = true;
    _supersededController.add(AppSessionSupersededPhase.accessRevoked);
    // OFF-2b-3: no offline access for a displaced session, before sign-out.
    // Bounded once the revocation is durable; the local sign-out (the safer
    // step) follows either way.
    final displaced = _client.auth.currentSession;
    await _offlinePass.invalidate(OfflinePassInvalidation.superseded,
        uid: displaced?.user.id,
        sid: AppSessionCoordinator.sessionId(displaced));
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (error) {
      if (!_identityController.isClosed) _identityController.addError(error);
    } finally {
      _appSession.clear();
      _publishIdentity(null);
      // The awaits above leave room for a test-only dispose().
      if (!_supersededController.isClosed) {
        _supersededController
            .add(AppSessionSupersededPhase.localSignOutCompleted);
      }
      _endingSuperseded = false;
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
    _stopRecheckHints();
    await _appSession.dispose();
    await _supersededController.close();
    await _sessionCheckUnavailableController.close();
    await _sessionCheckProgressController.close();
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
        if (!(await _authorizeAndPublish(response.session!, claim: true))) {
          throw const AuthFailure(
            code: AuthFailureCode.sessionExpired,
            message: 'This sign-up session is no longer active.',
          );
        }
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

      final session = response.session;
      if (session == null ||
          !(await _authorizeAndPublish(session, claim: true))) {
        throw const AuthFailure(
          code: AuthFailureCode.sessionExpired,
          message: 'This sign-in session is no longer active.',
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
      await _client.auth.signOut(scope: SignOutScope.local);
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
    // Nothing started by this account outlives its session.
    _pendingAddEmail = null;
    _pendingContactPhone = null;
    _pendingPhoneChange = null;
    _changedSignInPhone = null;
    // OFF-2b-3: offline access ends first, even with no network. Nothing
    // below runs before the revocation is durable (or, failing that, the
    // pass is deleted or its delete has failed).
    final ending = _client.auth.currentSession;
    final revocation = await _offlinePass.invalidate(
        OfflinePassInvalidation.signOut,
        uid: ending?.user.id,
        sid: AppSessionCoordinator.sessionId(ending));

    try {
      Object? releaseFailure;
      try {
        await _appSession.release();
      } catch (error) {
        releaseFailure = error;
      }
      await _client.auth.signOut(scope: SignOutScope.local);
      if (releaseFailure != null) {
        throw AuthFailure(
          code: AuthFailureCode.appSessionUnavailable,
          message: 'Signed out locally, but session release could not be confirmed.',
          originalException: releaseFailure,
        );
      }
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

    if (!revocation.safe) {
      // The session is ended locally, but an old offline pass may remain.
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Signed out locally, but offline access could not be revoked.',
      );
    }

    if (kDebugMode) {
      print('✅ Supabase logout completed');
      print('✅ Supabase session after logout: absent');
    }
  }

  /// Supabase Auth's own answer about the live session's account.
  ///
  /// `getUser()` is a network read that, in the pinned `gotrue`, neither
  /// refreshes nor removes the session, so asking cannot change anything.
  /// Only the server's `user_not_found` code is taken to mean the account is
  /// gone; any other rejection only means the session is unusable.
  @override
  Future<AccountExistence> probeCurrentAccount() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || _client.auth.currentSession == null) {
      return AccountExistence.sessionInvalid;
    }
    try {
      // A bound on one network read, not a guard against a race: the session
      // is already quarantined and nothing is published while this waits. A
      // read that cannot finish is reported as unknown, which ends the session
      // without claiming a deletion.
      final response =
          await _client.auth.getUser().timeout(const Duration(seconds: 15));
      return response.user?.id == uid
          ? AccountExistence.exists
          : AccountExistence.sessionInvalid;
    } on AuthSessionMissingException {
      return AccountExistence.sessionInvalid;
    } on AuthRetryableFetchException {
      return AccountExistence.unknown;
    } on AuthException catch (error) {
      if (error.code == 'user_not_found') return AccountExistence.deleted;
      const rejected = {'401', '403', '404'};
      return rejected.contains(error.statusCode)
          ? AccountExistence.sessionInvalid
          : AccountExistence.unknown;
    } catch (_) {
      return AccountExistence.unknown;
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

  /// Adds an email address, with a password for it, to a signed-in account
  /// that has no email yet — a phone-primary account.
  ///
  /// Email accounts never use this and are refused here: they change their
  /// address through [requestEmailChange] (Secure Email Change).
  ///
  /// The password is set first, then the address is requested with the app
  /// callback. GoTrue sends one confirmation to the new address (an account
  /// without an email has nothing to double-confirm) and creates the email
  /// identity only when that link is opened; until then the account signs in
  /// exactly as before. Retrying after a failed address step is safe: setting
  /// the same password again reports `same_password`, which is accepted.
  ///
  /// Every failure is a typed [AuthFailure] without provider text.
  @override
  Future<void> addEmailToAccount({
    required String email,
    required String password,
  }) async {
    final session = _client.auth.currentSession;
    final user = _client.auth.currentUser;
    final ownerUid = user?.id;
    if (session == null ||
        user == null ||
        ownerUid == null ||
        !_appSession.isAuthorized(session)) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    if ((user.email ?? '').trim().isNotEmpty) {
      throw const AuthFailure(
        code: AuthFailureCode.operationNotAllowed,
        message: 'This account already has an email address.',
      );
    }

    final normalizedEmail = email.trim().toLowerCase();
    if (!EmailValidator.isValidFormat(normalizedEmail)) {
      throw const AuthFailure(
        code: AuthFailureCode.invalidEmail,
        message: 'The email address is not valid.',
      );
    }
    if (!PasswordPolicy.validate(password).isValid) {
      throw const AuthFailure(
        code: AuthFailureCode.weakPassword,
        message: 'The password does not meet the password policy.',
      );
    }

    // Only the address change is requested now. The password is set by
    // [completeAddEmail] after the address is confirmed, so a failure at any
    // step can never leave a password on an account without its email.
    _pendingAddEmail = null;
    try {
      await _client.auth.updateUser(
        UserAttributes(email: normalizedEmail),
        emailRedirectTo: SupabaseConfig.authCallbackUri,
      );
    } catch (error) {
      throw AuthFailure.fromSupabaseEmailChange(error);
    }
    _requireAccount(ownerUid);
    _pendingAddEmail = _PendingAddEmail(
      uid: ownerUid,
      email: normalizedEmail,
      password: password,
    );
  }

  @override
  Future<AddEmailCompletion> completeAddEmail() async {
    final session = _client.auth.currentSession;
    if (session == null || !_appSession.isAuthorized(session)) {
      _pendingAddEmail = null;
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    // The server's view of the account, not the cached one.
    final User user;
    try {
      final fetched = (await _client.auth.getUser()).user;
      if (fetched == null) throw AuthSessionMissingException();
      user = fetched;
    } catch (error) {
      throw AuthFailure.fromSupabaseEmailChange(error);
    }

    final pending = _pendingAddEmail;
    if (pending != null && pending.uid != user.id) {
      _pendingAddEmail = null;
      throw const AuthFailure(
        code: AuthFailureCode.accountChanged,
        message: 'The authenticated account changed.',
      );
    }
    final email = (user.email ?? '').trim().toLowerCase();
    final confirmed = email.isNotEmpty &&
        user.emailConfirmedAt != null &&
        (pending == null || email == pending.email);
    if (!confirmed) return AddEmailCompletion.notConfirmed;
    if (pending == null) return AddEmailCompletion.passwordNotSet;

    try {
      await _client.auth.updateUser(UserAttributes(password: pending.password));
    } catch (error) {
      final failure = AuthFailure.fromSupabasePassword(error);
      switch (failure.code) {
        case AuthFailureCode.samePassword:
          break;
        case AuthFailureCode.network:
        case AuthFailureCode.tooManyRequests:
        case AuthFailureCode.unknown:
          // Transient: keep the password for another try.
          throw failure;
        case AuthFailureCode.sessionExpired:
          _pendingAddEmail = null;
          throw failure;
        default:
          // Refused for good (policy, reauthentication required, ...): the
          // email stays added and the user sets a password with a reset.
          _pendingAddEmail = null;
          return AddEmailCompletion.passwordNotSet;
      }
    }
    _pendingAddEmail = null;
    _requireAccount(pending.uid);
    return AddEmailCompletion.completed;
  }

  void _requireAccount(String ownerUid) {
    if (_client.auth.currentUser?.id != ownerUid) {
      throw const AuthFailure(
        code: AuthFailureCode.accountChanged,
        message: 'The authenticated account changed.',
      );
    }
  }

  /// Add Phone verifies a CONTACT number for the signed-in account (Model X).
  ///
  ///  * It never uses Supabase Auth's phone change (`updateUser(phone:)` /
  ///    `verifyOTP(type: phoneChange)`): that confirmation is not bound to the
  ///    account's session and issues a session to whoever holds the code, and
  ///    the database now refuses it for every account.
  ///  * The Worker checks the code with the SMS provider for this account's
  ///    current app session only, and stores the number on the profile as a
  ///    contact number. It is never `auth.users.phone`, so it can never be
  ///    used to sign in, and no session is ever created or returned.
  ///  * A phone account's sign-in number is not changed here.
  ///
  /// Nothing here writes `public.profiles`; the server does, and
  /// `is_phone_verified` is not writable by clients at all.
  @override
  Future<void> requestPhoneVerification(String phoneE164) async {
    final phone = _normalizedContactPhone(phoneE164);
    final session = _authorizedSessionForContactPhone();
    _pendingContactPhone = null;
    final verificationId = await _contactPhones.startContactPhone(
      accessToken: session.accessToken,
      phoneE164: phone,
    );
    // Only for the account and session that asked, if still signed in.
    if (AppSessionCoordinator.sessionId(_client.auth.currentSession) !=
        AppSessionCoordinator.sessionId(session)) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    _pendingContactPhone = _PendingContactPhone(
      uid: session.user.id,
      sessionId: AppSessionCoordinator.sessionId(session),
      phoneE164: phone,
      verificationId: verificationId,
    );
  }

  /// A new code is a new verification: the server supersedes the previous
  /// one, so an older code can no longer be used.
  @override
  Future<void> resendPhoneVerification(String phoneE164) =>
      requestPhoneVerification(phoneE164);

  @override
  Future<UserModel> confirmPhoneVerification({
    required String phoneE164,
    required String code,
  }) async {
    final phone = _normalizedContactPhone(phoneE164);
    final session = _authorizedSessionForContactPhone();
    final pending = _pendingContactPhone;
    if (pending == null ||
        pending.uid != session.user.id ||
        pending.sessionId != AppSessionCoordinator.sessionId(session) ||
        pending.phoneE164 != phone) {
      throw const AuthFailure(
        code: AuthFailureCode.otpInvalidOrExpired,
        message: 'No pending verification for this number.',
      );
    }

    final confirmed = await _contactPhones.confirmContactPhone(
      accessToken: session.accessToken,
      verificationId: pending.verificationId,
      code: code,
    );
    if (identical(_pendingContactPhone, pending)) _pendingContactPhone = null;

    // Only the server reporting this exact number counts.
    if (!_isSamePhone(confirmed, phone)) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'The server did not confirm the phone number.',
      );
    }
    final user = _client.auth.currentUser;
    if (user == null || user.id != pending.uid) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    final profile = await _profileOrNull(user.id);
    if (profile != null &&
        profile.isPhoneVerified &&
        _isSamePhone(profile.phoneNumber, phone)) {
      return profile;
    }
    // The server confirmed it; the profile read is only presentation and may
    // lag or fail. The view model re-reads the profile afterwards.
    return (profile ?? _fromAuthUser(user))
        .copyWith(phoneNumber: phone, isPhoneVerified: true);
  }

  // -------------------------------------------------------------------------
  // Phone accounts: sign-in number (Model X)
  // -------------------------------------------------------------------------

  /// Only an account created by phone holds `auth.users.phone` (Model X), so
  /// this is null for every email account, whatever contact number it has.
  @override
  String? get currentSignInPhoneE164 {
    final user = _client.auth.currentUser;
    final changed = _changedSignInPhone;
    if (user != null && changed != null && changed.uid == user.id) {
      return changed.phoneE164;
    }
    final phone = user?.phone;
    if (phone == null || phone.trim().isEmpty) return null;
    try {
      return PhoneNumberNormalizer.normalizeUaeMobile(phone);
    } on PhoneValidationException {
      return null;
    }
  }

  @override
  bool get currentNumberProven => _pendingPhoneChange?.currentProven ?? false;

  @override
  Future<void> requestPhoneNumberChange(String newPhoneE164) async {
    final phone = _normalizedContactPhone(newPhoneE164);
    final session = _authorizedSessionForContactPhone();
    final current = currentSignInPhoneE164;
    if (current == null || current == phone) {
      throw const AuthFailure(
        code: AuthFailureCode.operationNotAllowed,
        message: 'This account cannot change its sign-in number to this one.',
      );
    }
    _pendingPhoneChange = null;
    final verificationId = await _phoneNumberChanges.startSignInNumberChange(
      accessToken: session.accessToken,
      newPhoneE164: phone,
    );
    if (AppSessionCoordinator.sessionId(_client.auth.currentSession) !=
        AppSessionCoordinator.sessionId(session)) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    _pendingPhoneChange = _PendingPhoneChange(
      uid: session.user.id,
      sessionId: AppSessionCoordinator.sessionId(session),
      phoneE164: phone,
      verificationId: verificationId,
    );
  }

  @override
  Future<UserModel> confirmPhoneNumberChange({
    required String newPhoneE164,
    required String newCode,
    String? currentCode,
  }) async {
    final phone = _normalizedContactPhone(newPhoneE164);
    final session = _authorizedSessionForContactPhone();
    final pending = _pendingPhoneChange;
    if (pending == null ||
        pending.uid != session.user.id ||
        pending.sessionId != AppSessionCoordinator.sessionId(session) ||
        pending.phoneE164 != phone) {
      throw const AuthFailure(
        code: AuthFailureCode.otpInvalidOrExpired,
        message: 'No pending number change for this number.',
      );
    }

    final String confirmed;
    try {
      confirmed = await _phoneNumberChanges.confirmSignInNumberChange(
        accessToken: session.accessToken,
        verificationId: pending.verificationId,
        newCode: newCode,
        currentCode: pending.currentProven ? null : currentCode,
      );
    } on NewNumberCodeRejected {
      pending.currentProven = true;
      rethrow;
    }
    if (identical(_pendingPhoneChange, pending)) _pendingPhoneChange = null;
    if (!_isSamePhone(confirmed, phone)) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'The server did not confirm the phone number.',
      );
    }

    // The server changed the number. This session's token and cached user
    // still carry the old one until the SDK's next regular refresh; no refresh
    // is forced here, because a refused refresh signs the user out. Until
    // then the confirmed number is remembered for this account.
    final user = _client.auth.currentUser;
    if (user == null || user.id != pending.uid) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    _changedSignInPhone = (uid: user.id, phoneE164: phone);
    final profile = await _profileOrNull(user.id);
    if (profile != null && _isSamePhone(profile.phoneNumber, phone)) {
      return profile;
    }
    return (profile ?? _fromAuthUser(user))
        .copyWith(phoneNumber: phone, isPhoneVerified: true);
  }

  String _normalizedContactPhone(String phoneE164) {
    try {
      return PhoneNumberNormalizer.normalizeUaeMobile(phoneE164);
    } catch (e) {
      throw AuthFailure.fromSupabasePhoneVerification(e);
    }
  }

  Session _authorizedSessionForContactPhone() {
    final session = _client.auth.currentSession;
    if (session == null || !_appSession.isAuthorized(session)) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'No active session.',
      );
    }
    return session;
  }

  // -------------------------------------------------------------------------
  // Phone sign-in / sign-up (Supabase OTP)
  // -------------------------------------------------------------------------

  /// Sends a sign-in code. Supabase Auth generates and stores it; the app
  /// never sees it. No user metadata is sent: the server-side sign-up policy
  /// refuses phone accounts created with metadata, and the name is written
  /// only after verification.
  ///
  /// Resending is this same call. GoTrue's `/resend` with `type: sms` answers
  /// success **without sending anything** for an already-confirmed number, so
  /// using it for sign-in would report a code that never left the server.
  @override
  Future<void> requestPhoneSignInCode({
    required String phoneE164,
    required bool createAccount,
  }) async {
    try {
      final phone = PhoneNumberNormalizer.normalizeUaeMobile(phoneE164);
      await _client.auth.signInWithOtp(
        phone: phone,
        shouldCreateUser: createAccount,
      );
    } catch (e) {
      throw AuthFailure.fromSupabasePhoneSignIn(e);
    }
  }

  /// Verifies the code and completes the sign-in.
  ///
  /// A verified code is not access. The session Supabase returns goes through
  /// the same `claim: true` Single Active Device authorization as
  /// [signInWithEmailAndPassword], and the identity is published only once
  /// that claim succeeds. A claim that fails or is superseded ends the local
  /// session there (inside [_authorizeAndPublish]) and is reported, so a
  /// caller can never reach Home on a session the server did not accept.
  @override
  Future<PhoneSignInResult> verifyPhoneSignInCode({
    required String phoneE164,
    required String code,
  }) async {
    final String phone;
    final AuthResponse response;
    try {
      phone = PhoneNumberNormalizer.normalizeUaeMobile(phoneE164);
      // gotrue checks its own arguments only with asserts, which do not run in
      // release builds, so a malformed code never reaches the network.
      if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
        throw const AuthFailure(
          code: AuthFailureCode.otpInvalidOrExpired,
          message: 'The verification code is malformed.',
        );
      }
      response = await _client.auth.verifyOTP(
        phone: phone,
        token: code,
        type: OtpType.sms,
      );
    } catch (e) {
      throw AuthFailure.fromSupabasePhoneSignIn(e);
    }

    final session = response.session;
    final user = response.user ?? session?.user;
    if (session == null || user == null) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Supabase did not return a session.',
      );
    }

    // The session must belong to the number that was verified. Anything else
    // is never kept.
    if (user.phoneConfirmedAt == null || !_isSamePhone(user.phone, phone)) {
      await _endLocalSessionIfCurrent(session);
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Supabase did not confirm this phone number.',
      );
    }

    if (!(await _authorizeAndPublish(session, claim: true))) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'This sign-in session is no longer active.',
      );
    }

    // Another sign-in may have replaced the session while this one was being
    // authorized; then this result describes nothing current.
    if (AppSessionCoordinator.sessionId(_client.auth.currentSession) !=
        AppSessionCoordinator.sessionId(session)) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'The session changed during sign-in.',
      );
    }

    final profile = await _profileOrNull(user.id);
    return PhoneSignInResult(
      user: profile ?? _fromAuthUser(user),
      accountExisted: profile != null && profile.name.trim().isNotEmpty,
    );
  }

  @override
  Future<UserModel> completePhoneSignUpName({
    required String expectedUid,
    required String name,
  }) async {
    const notSaved = AuthFailure(
      code: AuthFailureCode.unknown,
      message: 'The profile name was not saved.',
    );
    final user = _client.auth.currentUser;
    if (user == null || user.id != expectedUid) {
      throw const AuthFailure(
        code: AuthFailureCode.sessionExpired,
        message: 'The account changed before the name was saved.',
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw notSaved;

    final UserModel? existing;
    try {
      existing = await _userRepository.getUserById(user.id);
    } catch (_) {
      throw notSaved;
    }
    // An account that already has a name keeps it.
    if (existing != null && existing.name.trim().isNotEmpty) return existing;

    try {
      await updateUserProfile(name: trimmed);
      return await _userRepository.getUserById(user.id) ?? _fromAuthUser(user);
    } catch (_) {
      throw notSaved;
    }
  }

  Future<UserModel?> _profileOrNull(String uid) async {
    try {
      return await _userRepository.getUserById(uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> _endLocalSessionIfCurrent(Session session) async {
    if (AppSessionCoordinator.sessionId(_client.auth.currentSession) !=
        AppSessionCoordinator.sessionId(session)) {
      return;
    }
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The session is still ended locally by the SDK on most failures; the
      // caller reports the refusal either way.
    }
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

/// A contact-number verification started by this repository.
class _PendingContactPhone {
  const _PendingContactPhone({
    required this.uid,
    required this.sessionId,
    required this.phoneE164,
    required this.verificationId,
  });

  final String uid;
  final String? sessionId;
  final String phoneE164;
  final String verificationId;
}

/// A sign-in number change started by this repository.
class _PendingPhoneChange {
  _PendingPhoneChange({
    required this.uid,
    required this.sessionId,
    required this.phoneE164,
    required this.verificationId,
  });

  final String uid;
  final String? sessionId;
  final String phoneE164;
  final String verificationId;

  /// The server accepted the current-number code for this verification.
  bool currentProven = false;
}

/// Add Email waiting for the user to confirm the new address.
class _PendingAddEmail {
  const _PendingAddEmail({
    required this.uid,
    required this.email,
    required this.password,
  });

  final String uid;
  final String email;
  final String password;
}
