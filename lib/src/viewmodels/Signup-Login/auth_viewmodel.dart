import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart'
    show ProfileImageUrlResolver;
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/count_reconciliation_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';

/// Bootstrap / session status.
///
/// Resolved from the authoritative Supabase session identity alone. It never
/// waits on `public.profiles` hydration or on Cloudflare R2 signed-image
/// resolution, and there is no timer that guesses at it.
enum AuthStatus { unknown, authenticated, unauthenticated }

/// Auth operation in progress. Deliberately separate from [AuthStatus]: a
/// sign-in that is still running is an operation, not an unresolved bootstrap.
enum AuthOperation { idle, signingIn, signingUp, signingOut }

/// Progress of `public.profiles` hydration for the authenticated session.
/// Reported independently of [AuthStatus] — a failed or slow profile read
/// never demotes an authenticated session.
enum ProfileHydrationStatus { unresolved, resolving, resolved, failed }

/// Presentation-only description of where the current user's avatar should be
/// drawn from. Never persisted, never sent to Supabase.
///
/// [mediaId] is the canonical `public.profiles.profile_media_id` and is the
/// stable cache identity. [signedUrl] is a short-lived R2 read URL and is a
/// fetch mechanism only — it must never be treated as identity, because its
/// signature and expiry query parameters rotate on every resolution.
@immutable
class ProfileImageSource {
  const ProfileImageSource({
    this.mediaId,
    this.signedUrl,
  });

  final String? mediaId;
  final String? signedUrl;

  static const ProfileImageSource empty = ProfileImageSource();

  bool get hasStableIdentity => (mediaId ?? '').isNotEmpty;
  bool get hasNetworkSource => (signedUrl ?? '').isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ProfileImageSource &&
      other.mediaId == mediaId &&
      other.signedUrl == signedUrl;

  @override
  int get hashCode => Object.hash(mediaId, signedUrl);
}

class AuthViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  /// Bound so a stalled `public.profiles` read reports a hydration failure
  /// instead of leaving hydration pending forever. Authentication state is
  /// unaffected either way.
  static const Duration _profileHydrationTimeout = Duration(seconds: 15);

  UserModel? _currentUser;
  AuthStatus _status = AuthStatus.unknown;
  AuthOperation _operation = AuthOperation.idle;
  ProfileHydrationStatus _profileHydration = ProfileHydrationStatus.unresolved;

  StreamSubscription<UserModel?>? _authSubscription;
  StreamSubscription<UserModel?>? _userStreamSubscription;

  String _resolvedDisplayName = '';

  /// Invalidates hydration and signed-image work that belongs to a session
  /// that is no longer current.
  int _hydrationToken = 0;
  String? _resolvingImageMediaId;

  /// Last-known-good `public.profiles` snapshot for the current session's uid.
  ///
  /// Presentation only. It fills the gap between the session resolving and
  /// hydration landing; it is never authoritative and is discarded the moment
  /// a real profile row arrives.
  UserModel? _lastKnownGood;
  bool _snapshotLoaded = false;
  bool _lastKnownGoodApplied = false;

  AuthViewModel({
    AuthRepository? authRepository,
    UserRepository? userRepository,
    bool autoInitialize = true,
  })  : _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository,
        _userRepository =
            userRepository ?? RepositoryProvider.instance.userRepository {
    if (autoInitialize) {
      _initializeAuth();
    }
  }

  // Getters
  UserModel? get currentUser => _currentUser;

  /// Canonical authenticated user ID.
  /// Delegates directly to the active AuthRepository session.
  /// Returns null if not authenticated.
  String? get currentUserId => _authRepository.currentUserId;

  /// Auth operation state. Never bootstrap state.
  AuthOperation get operation => _operation;

  /// Retained for existing operation-driven UI (button spinners). It reflects
  /// an in-flight auth operation only and must never be treated as bootstrap
  /// state.
  bool get isLoading => _operation != AuthOperation.idle;

  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// Progress of profile hydration for the current session.
  ProfileHydrationStatus get profileHydration => _profileHydration;

  /// Where the current user's avatar should be drawn from.
  ///
  /// Exposed separately from [UserModel] so a stable cache identity is
  /// available to consumers without overloading `profileImageUrl`, which every
  /// consumer already treats as a network URL and which `UserModel.toMap()`
  /// persists.
  ProfileImageSource get profileImage {
    final user = _currentUser;
    if (user == null) return ProfileImageSource.empty;
    return ProfileImageSource(
      mediaId: user.profileMediaId,
      signedUrl: user.profileImageUrl,
    );
  }

  bool get isEmailVerified => _currentUser?.isEmailVerified ?? false;
  String get displayName => _resolvedDisplayName;

  /// Three-state session/bootstrap status consumed by the router and
  /// AuthWrapper.
  AuthStatus get status => _status;

  /// Recomputes [AuthStatus] from the current user's verification state.
  ///
  /// Preserves the existing verified-account rule exactly: a session alone is
  /// never enough — the account must have a confirmed email or a confirmed
  /// phone. The only thing that changed is *when* this can be answered, since
  /// `emailConfirmedAt` / `phoneConfirmedAt` arrive with the session rather
  /// than with the profile row.
  void _recomputeStatus() {
    final user = _currentUser;
    if (user == null) {
      _status = AuthStatus.unauthenticated;
      return;
    }
    _status = (user.isEmailVerified == true) || (user.isPhoneVerified == true)
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
  }

  void _beginOperation(AuthOperation operation) {
    _operation = operation;
    notifyListeners();
  }

  void _endOperation() {
    _operation = AuthOperation.idle;
    notifyListeners();
  }

  /// Canonical email precedence: the live Supabase Auth session's email wins
  /// whenever available, so a stale `public.profiles.email` mirror can never
  /// override it. No email-change flow, no extra network calls — this only
  /// reorders precedence between two values already fetched.
  UserModel _applyEmailAuthority(UserModel user) {
    final authEmail = _authRepository.currentUser?.email.trim() ?? '';
    if (authEmail.isEmpty || authEmail == user.email) return user;
    return user.copyWith(email: authEmail);
  }

  /// `auth.users` is the canonical source of verification state. A profile row
  /// that has not yet been synchronized by the database trigger must never be
  /// able to demote a confirmed account.
  UserModel _applySessionVerification(UserModel user) {
    final session = _authRepository.currentUser;
    if (session == null) return user;

    final emailVerified = user.isEmailVerified || session.isEmailVerified;
    final phoneVerified = user.isPhoneVerified || session.isPhoneVerified;
    if (emailVerified == user.isEmailVerified &&
        phoneVerified == user.isPhoneVerified) {
      return user;
    }
    return user.copyWith(
      isEmailVerified: emailVerified,
      isPhoneVerified: phoneVerified,
    );
  }

  /// Folds a fresh session identity event onto the already hydrated user.
  ///
  /// Supabase emits `tokenRefreshed` periodically. Those events carry session
  /// identity only, so replacing the current user with them wholesale would
  /// blank out the hydrated name and the resolved profile image and make them
  /// visibly reappear a moment later.
  UserModel _mergeSessionIdentity(UserModel existing, UserModel session) {
    return existing.copyWith(
      email: session.email.trim().isNotEmpty ? session.email : existing.email,
      phoneNumber: existing.phoneNumber ?? session.phoneNumber,
      isEmailVerified: existing.isEmailVerified || session.isEmailVerified,
      isPhoneVerified: existing.isPhoneVerified || session.isPhoneVerified,
    );
  }

  /// Keeps an already resolved signed image URL when a newer profile read for
  /// the same canonical `profile_media_id` arrives without one. The signed URL
  /// stays ephemeral in-memory presentation data; it is never persisted.
  UserModel _preserveResolvedImage(UserModel incoming, UserModel? previous) {
    if (previous == null || previous.uid != incoming.uid) return incoming;

    final existingUrl = previous.profileImageUrl;
    if (existingUrl == null || existingUrl.isEmpty) return incoming;

    final incomingUrl = incoming.profileImageUrl;
    if (incomingUrl != null && incomingUrl.isNotEmpty) return incoming;

    final mediaId = incoming.profileMediaId;
    if (mediaId == null || mediaId != previous.profileMediaId) return incoming;

    return incoming.copyWith(profileImageUrl: existingUrl);
  }

  String _extractNameFromEmail(String? email) {
    if (email == null) return '';
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '';
    final atIndex = trimmed.indexOf('@');
    if (atIndex > 0) {
      return trimmed.substring(0, atIndex);
    }
    return trimmed;
  }

  /// True when [_currentUser]'s `name` came from `public.profiles` — either a
  /// hydrated row or the last-known-good snapshot of one — rather than from
  /// Supabase Auth metadata.
  bool get _hasProfileBackedName =>
      _profileHydration == ProfileHydrationStatus.resolved ||
      _lastKnownGoodApplied;

  String _computeDisplayName({UserModel? user}) {
    // `auth.users.raw_user_meta_data.full_name` is written once, at signup, and
    // is never updated when the profile name changes — `updateUserProfile`
    // writes only to `public.profiles`. It is therefore a genuinely stale
    // value, not merely an early one, and is demoted to a last-resort fallback
    // for accounts that have no profile data available yet.
    //
    // While the local snapshot read is still in flight and no profile-backed
    // name is available, hold the previously resolved value rather than
    // guessing. Microtasks drain before Flutter builds a frame, so the snapshot
    // settles before anything paints and this window is not observable — but
    // holding means that even if it were, a stale signup name could not appear.
    if (!_hasProfileBackedName && !_snapshotLoaded) {
      return _resolvedDisplayName;
    }

    final candidates = <String?>[
      if (_hasProfileBackedName) user?.name,
      _lastKnownGood?.name,
      user?.name,
      _authRepository.currentUser?.name,
      _extractNameFromEmail(user?.email),
      _extractNameFromEmail(_authRepository.currentUser?.email),
      user?.phoneNumber,
      _authRepository.currentUser?.phoneNumber,
    ];

    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  /// [allowBackfill] guards the write-back of a missing profile name.
  ///
  /// It must only ever run against a hydrated `public.profiles` row. Running it
  /// against a session-identity event would compare auth metadata to an empty
  /// name that simply has not been fetched yet, and could overwrite a good
  /// stored name.
  bool _refreshDisplayName(UserModel? candidate, {bool allowBackfill = false}) {
    final user = candidate ?? _currentUser;
    final resolved = _computeDisplayName(user: user);
    final sanitized = resolved.trim();
    final changed = sanitized != _resolvedDisplayName;

    if (changed) {
      _resolvedDisplayName = sanitized;
    }

    if (allowBackfill &&
        user != null &&
        user.uid.isNotEmpty &&
        user.name.trim().isEmpty) {
      final authDisplayName = _authRepository.currentUser?.name.trim() ?? '';
      if (authDisplayName.isNotEmpty) {
        final updatedUser = user.copyWith(name: authDisplayName);
        _userRepository.updateUser(updatedUser).catchError((error) {
          // Debug log suppressed: Failed to backfill missing user name: $error
        });
      }
    }

    return changed;
  }

  // Authentication methods using Repository pattern
  Future<UserModel?> signUpWithEmail(
      String email, String password, String name) async {
    try {
      _beginOperation(AuthOperation.signingUp);

      final userModel = await _authRepository.signUpWithEmailAndPassword(
        email: email,
        password: password,
        name: name,
      );

      return userModel;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: e.toString(),
        originalException: e,
      );
    } finally {
      _endOperation();
    }
  }

  Future<UserModel?> signInWithEmail(String email, String password) async {
    try {
      _beginOperation(AuthOperation.signingIn);

      final userModel = await _authRepository.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userModel;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: e.toString(),
        originalException: e,
      );
    } finally {
      _endOperation();
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      _beginOperation(AuthOperation.signingIn);

      final userModel = await _authRepository.signInWithGoogle();
      return userModel;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: e.toString(),
        originalException: e,
      );
    } finally {
      _endOperation();
    }
  }

  Future<UserModel?> signInWithFacebook() async {
    try {
      _beginOperation(AuthOperation.signingIn);

      final userModel = await _authRepository.signInWithFacebook();
      return userModel;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: e.toString(),
        originalException: e,
      );
    } finally {
      _endOperation();
    }
  }

  Future<UserModel?> reloadUser() async {
    try {
      final reloaded = await _authRepository.reloadUser();
      if (reloaded != null) {
        // _applyProfile owns the snapshot write; caching here as well would
        // persist the resolved signed URL.
        _applyProfile(reloaded, markHydrated: true);
        return _currentUser;
      }
      return reloaded;
    } catch (_) {
      return _currentUser;
    }
  }

  Future<void> checkEmailVerificationStatus() async {
    final isVerified = await _authRepository.isEmailVerified();
    if (_currentUser != null && isVerified != _currentUser!.isEmailVerified) {
      final updatedUser = _currentUser!.copyWith(isEmailVerified: isVerified);

      // Update user in repository so the auth state stream picks it up
      try {
        await RepositoryProvider.instance.userRepository
            .updateUser(updatedUser);
        // Debug log suppressed: User email verification status updated in repository
      } catch (e) {
        // Debug log suppressed: Failed to update user in repository: $e
        // Even if repository update fails, update local state
        _currentUser = updatedUser;
        _recomputeStatus();
        notifyListeners();
      }
    }
  }

  Future<void> sendEmailVerification() async {
    try {
      await _authRepository.sendEmailVerification();
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: e.toString(),
        originalException: e,
      );
    }
  }

  Future<void> syncUserFromRepository() async {
    final uid = _currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      final userDoc = await _userRepository.getUserById(uid);
      if (userDoc != null) {
        // _applyProfile owns the snapshot write.
        _applyProfile(userDoc, markHydrated: true);
      }
    } catch (e) {
      // Debug log suppressed: Failed to sync user from repository: $e
    }
  }

  Future<void> markPhoneVerified({String? phoneNumber}) async {
    UserModel? baseUser = _currentUser ?? _authRepository.currentUser;

    if (baseUser == null) {
      _status = AuthStatus.authenticated;
      notifyListeners();
      return;
    }

    final updatedUser = baseUser.copyWith(
      phoneNumber: phoneNumber ?? baseUser.phoneNumber,
      isPhoneVerified: true,
    );

    _currentUser = updatedUser;
    _recomputeStatus();
    _refreshDisplayName(updatedUser);
    notifyListeners();

    try {
      await OfflineAuthService.instance.updateCachedUserModel(updatedUser);
    } catch (e) {
      // Debug log suppressed: Failed to update cached user after phone verification: $e
    }
  }

  void _initializeAuth() {
    // Cancel any existing subscription
    _authSubscription?.cancel();

    try {
      // The repository now delivers authoritative session identity only, with
      // the current session replayed to every subscriber. The first event
      // therefore requires no network round trip, and bootstrap resolves
      // without any safety timer.
      _authSubscription = _authRepository.authStateChanges.listen(
        _handleSessionIdentity,
        onError: (Object error) => _resolveBootstrapAsUnauthenticated(),
      );
    } catch (e) {
      _resolveBootstrapAsUnauthenticated();
    }
  }

  /// Bootstrap is resolved (to unauthenticated) when the auth pipeline itself
  /// cannot be established.
  ///
  /// Every field is final before `notifyListeners()` runs. The previous
  /// implementation assigned its bootstrap flag *after* broadcasting, so a
  /// listener that read [status] synchronously still saw `unknown` and nothing
  /// ever notified again.
  void _resolveBootstrapAsUnauthenticated() {
    _hydrationToken++;
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    _profileHydration = ProfileHydrationStatus.unresolved;
    _resolvingImageMediaId = null;
    _discardLastKnownGood();
    _refreshDisplayName(null);
    notifyListeners();
  }

  /// Loads the last-known-good snapshot for exactly [uid].
  ///
  /// The read is scoped to the uid at the storage boundary, so a snapshot
  /// belonging to another account is never even materialized here. It runs as
  /// a chain of microtasks — `SharedPreferences` is warmed during app startup —
  /// and microtasks drain before Flutter builds a frame, so it settles before
  /// anything can paint.
  Future<void> _loadSnapshotFor(String uid) async {
    UserModel? snapshot;
    try {
      snapshot = await OfflineAuthService.instance.getProfileSnapshot(uid);
    } catch (_) {
      snapshot = null;
    }

    _snapshotLoaded = true;
    _restoreLastKnownGood(uid, snapshot);
  }

  /// Applies the last-known-good snapshot for [uid] as presentation fill.
  ///
  /// Never authoritative, and refused whenever fresher data already exists.
  void _restoreLastKnownGood(String uid, UserModel? snapshot) {
    if (_lastKnownGoodApplied) return;

    // Fresher data already won. A snapshot must never overwrite a hydrated
    // profile row — this is a genuine race, since the local read and the
    // network read are both in flight from the same moment.
    if (_profileHydration == ProfileHydrationStatus.resolved) {
      _snapshotSettled();
      return;
    }

    // Strict uid isolation, re-checked after the await. Account separation must
    // not depend on `clearAuthCache()`, which is dispatched without being
    // awaited and may not have completed.
    if (snapshot == null || snapshot.uid != uid) {
      _snapshotSettled();
      return;
    }

    final current = _currentUser;
    if (current == null || current.uid != uid) {
      _snapshotSettled();
      return;
    }

    _lastKnownGood = snapshot;
    _lastKnownGoodApplied = true;

    // Only profile-owned fields are filled. Email and verification state stay
    // with the authoritative session; a snapshot can never influence
    // [AuthStatus].
    final trimmedName = snapshot.name.trim();
    _currentUser = current.copyWith(
      name: trimmedName.isEmpty ? null : trimmedName,
      phoneNumber: current.phoneNumber ?? snapshot.phoneNumber,
      profileMediaId: snapshot.profileMediaId,
    );

    _refreshDisplayName(_currentUser);
    notifyListeners();
  }

  /// Marks the snapshot read as settled without applying it, so a held
  /// display name is recomputed instead of staying frozen.
  void _snapshotSettled() {
    if (_refreshDisplayName(_currentUser)) {
      notifyListeners();
    }
  }

  void _discardLastKnownGood() {
    _lastKnownGood = null;
    _lastKnownGoodApplied = false;
    _snapshotLoaded = false;
  }

  void _handleSessionIdentity(UserModel? sessionUser) {
    final previousUid = _currentUser?.uid;

    if (sessionUser == null) {
      _hydrationToken++;
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _profileHydration = ProfileHydrationStatus.unresolved;
      _resolvingImageMediaId = null;
      _discardLastKnownGood();
      _refreshDisplayName(null);
      OfflineAuthService.instance.clearAuthCache();
      notifyListeners();

      if (previousUid != null) {
        _subscribeToUserUpdates(null);
      }
      return;
    }

    final isSameUser = previousUid == sessionUser.uid;

    if (!isSameUser) {
      // Cache ownership: session state is authoritative and a different user
      // must never inherit the previous user's cached state.
      _hydrationToken++;
      _profileHydration = ProfileHydrationStatus.unresolved;
      _resolvingImageMediaId = null;
      _discardLastKnownGood();
      if (previousUid != null) {
        OfflineAuthService.instance.clearAuthCache();
      }
    }

    final resolved = isSameUser && _currentUser != null
        ? _mergeSessionIdentity(_currentUser!, sessionUser)
        : sessionUser;

    _currentUser = resolved;
    _recomputeStatus();
    _refreshDisplayName(resolved);
    // Deliberately no cache write here. A session-identity event carries only
    // signup-era metadata with no `profileMediaId`, so writing it would
    // overwrite the last-known-good snapshot with exactly the degraded values
    // the snapshot exists to prevent showing — and would leave it poisoned if
    // hydration then failed. Only `_applyProfile` writes the snapshot.
    notifyListeners();

    if (!isSameUser) {
      _subscribeToUserUpdates(resolved.uid);
      // Local, and strictly scoped to this uid. Runs alongside hydration, never
      // ahead of it in authority.
      unawaited(_loadSnapshotFor(resolved.uid));
    }

    if (_profileHydration == ProfileHydrationStatus.unresolved ||
        _profileHydration == ProfileHydrationStatus.failed) {
      unawaited(_hydrateProfile(resolved.uid, _hydrationToken));
    }
  }

  /// Hydrates `public.profiles` for the authenticated session.
  ///
  /// Owned here, and only here, so a single hydration runs per session no
  /// matter how many components observe auth state. Its outcome is reported
  /// through [profileHydration]; it can never change [status].
  Future<void> _hydrateProfile(String uid, int token) async {
    _profileHydration = ProfileHydrationStatus.resolving;
    notifyListeners();

    try {
      final profile = await _userRepository
          .getUserById(uid)
          .timeout(_profileHydrationTimeout);

      if (token != _hydrationToken) return;

      if (profile == null) {
        _profileHydration = ProfileHydrationStatus.failed;
        notifyListeners();
        return;
      }

      _applyProfile(profile, markHydrated: true);
      if (kDebugMode) {
        debugPrint('Supabase profile hydration: database');
      }
    } catch (_) {
      if (token != _hydrationToken) return;
      // The authoritative session still governs authentication. Only the
      // hydration outcome is degraded.
      _profileHydration = ProfileHydrationStatus.failed;
      notifyListeners();
    }
  }

  /// Applies an authoritative `public.profiles` row onto the canonical user.
  void _applyProfile(UserModel profile, {bool markHydrated = false}) {
    final previous = _currentUser;
    if (previous != null && previous.uid != profile.uid) return;

    var resolved = _applyEmailAuthority(profile);
    resolved = _applySessionVerification(resolved);
    resolved = _preserveResolvedImage(resolved, previous);

    final hydrationChanged = markHydrated &&
        _profileHydration != ProfileHydrationStatus.resolved;
    final userChanged = previous == null ||
        resolved.profileImageUrl != previous.profileImageUrl ||
        resolved.profileMediaId != previous.profileMediaId ||
        resolved.name != previous.name ||
        resolved.email != previous.email ||
        resolved.phoneNumber != previous.phoneNumber ||
        resolved.isEmailVerified != previous.isEmailVerified ||
        resolved.isPhoneVerified != previous.isPhoneVerified;

    _currentUser = resolved;
    if (markHydrated) {
      _profileHydration = ProfileHydrationStatus.resolved;
      // An authoritative row has landed, so the snapshot is now redundant as a
      // display source and must not be applied late over fresher data.
      _lastKnownGood = null;
      _lastKnownGoodApplied = true;
    }
    _recomputeStatus();
    final displayNameChanged =
        _refreshDisplayName(resolved, allowBackfill: true);

    if (userChanged || displayNameChanged || hydrationChanged) {
      notifyListeners();
    }

    if (markHydrated) {
      // The single writer of the last-known-good snapshot: only a hydrated,
      // `public.profiles`-backed model. The stored payload carries
      // `profileMediaId` and never the signed URL.
      unawaited(
        OfflineAuthService.instance.cacheProfileSnapshot(resolved),
      );
    }

    _maybeResolveProfileImage(resolved);
  }

  /// Resolves the short-lived signed read URL for the canonical
  /// `profile_media_id`, off the authoritative read path.
  ///
  /// A failure here yields an authenticated user with a valid profile and no
  /// image — never a sign-out, a redirect, or a blocked route.
  void _maybeResolveProfileImage(UserModel user) {
    final repository = _userRepository;
    if (repository is! ProfileImageUrlResolver) return;
    final resolver = repository as ProfileImageUrlResolver;

    final mediaId = user.profileMediaId;
    if (mediaId == null || mediaId.isEmpty) {
      _resolvingImageMediaId = null;
      return;
    }

    final existingUrl = user.profileImageUrl;
    if (existingUrl != null && existingUrl.isNotEmpty) return;
    if (_resolvingImageMediaId == mediaId) return;

    _resolvingImageMediaId = mediaId;
    final token = _hydrationToken;

    resolver.resolveProfileImageUrl(mediaId).then((url) {
      if (_resolvingImageMediaId == mediaId) {
        _resolvingImageMediaId = null;
      }
      if (token != _hydrationToken) return;
      if (url == null || url.isEmpty) return;

      final current = _currentUser;
      if (current == null || current.profileMediaId != mediaId) return;

      _currentUser = current.copyWith(profileImageUrl: url);
      notifyListeners();
    }).catchError((_) {
      if (_resolvingImageMediaId == mediaId) {
        _resolvingImageMediaId = null;
      }
    });
  }

  void _subscribeToUserUpdates(String? uid) {
    _userStreamSubscription?.cancel();

    if (uid == null || uid.isEmpty) {
      _refreshDisplayName(null);
      return;
    }

    _userStreamSubscription = _userRepository.getUserStream(uid).listen(
      (userDoc) async {
        if (userDoc == null) {
          return;
        }

        // _applyProfile owns the snapshot write.
        _applyProfile(userDoc, markHydrated: true);

        // 🔒 SECURITY: The current reconciliation implementation is a
        // Firebase Cloud Function. Do not invoke it for a Supabase-authenticated
        // session. Supabase quota reconciliation will be wired in its own stage.
        if (SupabaseConfig.useSupabaseAuth) {
          return;
        }

        // Reconcile counts on first login or if stale.
        try {
          final lastReconciliation =
              userDoc.preferences['lastCountReconciliation'] as int?;
          final lastReconciliationTime = lastReconciliation != null
              ? DateTime.fromMillisecondsSinceEpoch(lastReconciliation)
              : null;

          // Reconcile if never done or > 1 hour old
          if (lastReconciliationTime == null ||
              DateTime.now().difference(lastReconciliationTime).inHours >= 1) {
            // Debug log suppressed: Triggering count reconciliation for security...
            // Don't await - let it run in background
            _reconcileCountsInBackground(uid);
          }
        } catch (e) {
          // Debug log suppressed: Failed to check reconciliation status: $e
        }
      },
      onError: (error) {
        // Debug log suppressed: User stream error: $error
      },
    );
  }

  /// Background count reconciliation to prevent quota bypass
  Future<void> _reconcileCountsInBackground(String uid) async {
    try {
      // Import the reconciliation service
      final reconciliationService = CountReconciliationService();
      final result = await reconciliationService.reconcileUserCounts();

      if (result.discrepanciesFound > 0) {
        // Debug log suppressed: Count discrepancies fixed: ${result.discrepanciesFound}
        // Debug log suppressed: ${result.discrepancies.join(', ')}
      } else {
        // Debug log suppressed: Counts verified accurate
      }

      // Update last reconciliation time in user preferences
      await _userRepository.updateUserPreferences(uid, {
        'lastCountReconciliation': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      // Debug log suppressed: Background reconciliation failed (non-critical): $e
      // Don't throw - this is a background security check
    }
  }

  Future<void> signOut() async {
    try {
      _beginOperation(AuthOperation.signingOut);

      await _authRepository.signOut();
      await OfflineAuthService.instance.clearAuthCache();
      _hydrationToken++;
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _profileHydration = ProfileHydrationStatus.unresolved;
      _resolvingImageMediaId = null;
      _discardLastKnownGood();
      _resolvedDisplayName = '';
      if (kDebugMode) {
        print('✅ AuthViewModel logout state: unauthenticated');
      }
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: e.toString(),
        originalException: e,
      );
    } finally {
      _endOperation();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userStreamSubscription?.cancel();
    super.dispose();
  }
}
