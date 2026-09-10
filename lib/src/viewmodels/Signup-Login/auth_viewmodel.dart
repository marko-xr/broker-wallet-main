import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/count_reconciliation_service.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';

/// Additive, three-state session/bootstrap status. This is deliberately
/// separate from the existing `isLoading` (operation-in-progress) semantics
/// used by login/signup/signout UI — see auth_viewmodel.dart's `status`
/// getter. Router/AuthWrapper wiring to this enum is a Batch B follow-up;
/// nothing in this batch changes what `isLoading` means or when it flips.
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isAuthenticated = false;
  StreamSubscription<UserModel?>? _authSubscription;
  StreamSubscription<UserModel?>? _userStreamSubscription;

  String _resolvedDisplayName = '';

  // Additive session/bootstrap tracking (see AuthStatus doc comment above).
  // Set true only at the three existing points that already resolve the
  // initial session state; never reset to false afterward.
  bool _bootstrapKnown = false;

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

  bool get isLoading => _isLoading;
  bool get isAuthenticated {
    final u = _currentUser;
    if (u == null) return false;
    return (u.isEmailVerified == true) || (u.isPhoneVerified == true);
  }

  bool get isEmailVerified => _currentUser?.isEmailVerified ?? false;
  String get displayName => _resolvedDisplayName;

  /// Additive three-state session/bootstrap status. Does not replace
  /// [isLoading]/[isAuthenticated] and is not yet consumed by the router or
  /// AuthWrapper (Batch B follow-up).
  AuthStatus get status {
    if (!_bootstrapKnown) return AuthStatus.unknown;
    return isAuthenticated ? AuthStatus.authenticated : AuthStatus.unauthenticated;
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

  String _computeDisplayName({UserModel? user}) {
    final candidates = <String?>[
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

  bool _refreshDisplayName(UserModel? candidate) {
    final user = candidate ?? _currentUser;
    final resolved = _computeDisplayName(user: user);
    final sanitized = resolved.trim();
    final changed = sanitized != _resolvedDisplayName;

    if (changed) {
      _resolvedDisplayName = sanitized;
    }

    if (user != null && user.uid.isNotEmpty && user.name.trim().isEmpty) {
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
      _isLoading = true;
      notifyListeners();

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
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UserModel?> signInWithEmail(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

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
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

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
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UserModel?> signInWithFacebook() async {
    try {
      _isLoading = true;
      notifyListeners();

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
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UserModel?> reloadUser() async {
    try {
      final reloaded = await _authRepository.reloadUser();
      if (reloaded != null) {
        final resolved = _applyEmailAuthority(reloaded);
        _currentUser = resolved;
        _isAuthenticated = resolved.isEmailVerified || resolved.isPhoneVerified;
        _refreshDisplayName(resolved);
        await OfflineAuthService.instance.updateCachedUserModel(resolved);
        notifyListeners();
        return resolved;
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
        _isAuthenticated = isVerified;
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
        final resolved = _applyEmailAuthority(userDoc);
        _currentUser = resolved;
        _isAuthenticated =
            resolved.isEmailVerified == true || resolved.isPhoneVerified == true;
        _refreshDisplayName(resolved);
        notifyListeners();

        try {
          await OfflineAuthService.instance.updateCachedUserModel(resolved);
        } catch (e) {
          // Debug log suppressed: Failed to sync cached user model: $e
        }
      }
    } catch (e) {
      // Debug log suppressed: Failed to sync user from repository: $e
    }
  }

  Future<void> markPhoneVerified({String? phoneNumber}) async {
    UserModel? baseUser = _currentUser ?? _authRepository.currentUser;

    if (baseUser == null) {
      _isAuthenticated = true;
      notifyListeners();
      return;
    }

    final updatedUser = baseUser.copyWith(
      phoneNumber: phoneNumber ?? baseUser.phoneNumber,
      isPhoneVerified: true,
    );

    _currentUser = updatedUser;
    _isAuthenticated = true;
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
      // Listen to authentication state changes from repository with error handling
      _authSubscription =
          _authRepository.authStateChanges.listen((UserModel? user) {
        // Debug log suppressed: Auth state changed: ${user?.uid} - ${user?.email}

        final wasAuthenticated = _currentUser != null;
        final isNowAuthenticated = user != null;
        final previousUid = _currentUser?.uid;
        final resolved = user == null ? null : _applyEmailAuthority(user);

        _currentUser = resolved;
        _refreshDisplayName(resolved);

        // Set loading to false only after first auth state change
        // This prevents premature redirects to login during app startup
        if (_isLoading) {
          _isLoading = false;
        }
        // Additive: mark bootstrap resolved (see AuthStatus doc comment).
        // Never reset to false afterward.
        _bootstrapKnown = true;

        // Cache ownership: session state is authoritative.
        // Cache never overrides a logged out session.
        if (resolved != null) {
          if (previousUid != null && previousUid != resolved.uid) {
            OfflineAuthService.instance.clearAuthCache();
          }
          _isAuthenticated = resolved.isEmailVerified || resolved.isPhoneVerified;
          OfflineAuthService.instance.cacheUserModel(resolved);
        } else {
          _isAuthenticated = false;
          OfflineAuthService.instance.clearAuthCache();
        }

        // Always notify listeners when auth state changes
        notifyListeners();

        // Start listening to live user document updates when uid changes
        if (previousUid != resolved?.uid) {
          _subscribeToUserUpdates(resolved?.uid);
        }

        // Log the transition for debugging (suppressed in production)
        if (!wasAuthenticated && isNowAuthenticated) {
          // Debug log suppressed: User just signed in: ${user.email.isNotEmpty ? user.email : (user.phoneNumber ?? 'Unknown')}
          // Debug log suppressed: Email verified: ${user.isEmailVerified}
          // Debug log suppressed: Phone verified: ${user.isPhoneVerified}
        } else if (wasAuthenticated && !isNowAuthenticated) {
          // Debug log suppressed: User just signed out
        } else if (user != null) {
          // Debug log suppressed: User state updated: ${user.email.isNotEmpty ? user.email : (user.phoneNumber ?? 'Unknown')}
          // Debug log suppressed: Email verified: ${user.isEmailVerified}
          // Debug log suppressed: Phone verified: ${user.isPhoneVerified}
        }
      }, onError: (error) {
        // Auth stream error - continue with unauthenticated state
        if (_isLoading) {
          _isLoading = false;
          _isAuthenticated = false;
          notifyListeners();
        }
        // Additive: bootstrap is resolved (to unauthenticated) even on error.
        _bootstrapKnown = true;
      });

      // Safety timeout - if no auth state received in 3 seconds, stop loading
      Future.delayed(const Duration(seconds: 3), () {
        if (_isLoading) {
          _isLoading = false;
          _isAuthenticated = false;
          notifyListeners();
        }
        // Additive: bootstrap is resolved (to unauthenticated) even on timeout.
        _bootstrapKnown = true;
      });
    } catch (e) {
      // Failed to initialize auth stream
      _isLoading = false;
      _isAuthenticated = false;
      _bootstrapKnown = true;
      notifyListeners();
    }
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

        final resolved = _applyEmailAuthority(userDoc);

        final hasChanged = _currentUser == null ||
            resolved.profileImageUrl != _currentUser!.profileImageUrl ||
            resolved.profileMediaId != _currentUser!.profileMediaId ||
            resolved.name != _currentUser!.name ||
            resolved.email != _currentUser!.email ||
            resolved.phoneNumber != _currentUser!.phoneNumber ||
            resolved.isEmailVerified != _currentUser!.isEmailVerified ||
            resolved.isPhoneVerified != _currentUser!.isPhoneVerified;

        _currentUser = resolved;
        _isAuthenticated =
            resolved.isEmailVerified == true || resolved.isPhoneVerified == true;
        final displayNameChanged = _refreshDisplayName(resolved);

        if (hasChanged || displayNameChanged) {
          notifyListeners();
        }

        try {
          await OfflineAuthService.instance.updateCachedUserModel(resolved);
        } catch (e) {}

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
      _isLoading = true;
      notifyListeners();

      await _authRepository.signOut();
      await OfflineAuthService.instance.clearAuthCache();
      _currentUser = null;
      _isAuthenticated = false;
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
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userStreamSubscription?.cancel();
    super.dispose();
  }
}
