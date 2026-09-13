import 'package:broker_wallet/src/common/utils/password_policy.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';

/// Changes the password of the signed-in account.
///
/// The current password is collected, and sent, only when the backend actually
/// verifies it ([PasswordCapability.verifiesCurrentPassword]). There is no
/// client-side substitute: re-signing in to "check" the old password would
/// mutate the very session the change is about, and would prove nothing the
/// server had not already been asked.
///
/// The password values live in the caller's text controllers and in the
/// arguments below. Nothing here stores, caches, copies into state, or logs
/// them, and no failure path carries a password or a provider message.
class ChangePasswordViewModel extends ChangeNotifier {
  ChangePasswordViewModel({
    required PasswordCapability? gateway,
    required AuthRepository? authRepository,
  })  : _gateway = gateway,
        _authRepository = authRepository;

  final PasswordCapability? _gateway;
  final AuthRepository? _authRepository;

  bool _submitting = false;
  bool _succeeded = false;
  String? _errorKey;
  bool _disposed = false;

  bool get isAvailable => _gateway != null;

  /// Whether this configuration asks for the current password.
  bool get requiresCurrentPassword =>
      _gateway?.verifiesCurrentPassword ?? false;

  bool get isSubmitting => _submitting;
  bool get hasSucceeded => _succeeded;
  String? get errorKey => _errorKey;

  /// Requirements [password] has not met yet, for the on-screen checklist.
  Set<PasswordRequirement> unmetRequirements(String password) =>
      PasswordPolicy.unmetRequirements(password);

  /// Attempts the change. Returns true only when Supabase confirmed it.
  ///
  /// A duplicate submit is refused while one is in flight, so a double tap
  /// cannot produce two `updateUser` calls.
  Future<bool> submit({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (_submitting) return false;

    final gateway = _gateway;
    if (gateway == null) {
      _fail('passwordChangeUnavailable');
      return false;
    }

    // Local policy runs first, so an invalid password never reaches the
    // network and never spends the account's rate limit.
    if (requiresCurrentPassword && currentPassword.isEmpty) {
      _fail('currentPasswordRequired');
      return false;
    }
    final validation = PasswordPolicy.validatePair(
      password: newPassword,
      confirmation: confirmPassword,
    );
    if (!validation.isValid) {
      _fail(validation.messageKey!);
      return false;
    }
    if (requiresCurrentPassword && currentPassword == newPassword) {
      _fail('passwordChangeSame');
      return false;
    }

    // Identity is captured before the call and re-checked after it. A sign-out
    // or an account switch that lands mid-request must never be reported as a
    // successful change.
    final ownerUid = _authRepository?.currentUserId;
    if (ownerUid == null || ownerUid.isEmpty) {
      _fail(changePasswordErrorKey(AuthFailureCode.sessionExpired));
      return false;
    }

    _errorKey = null;
    _submitting = true;
    _notify();
    try {
      await gateway.changePassword(
        newPassword: newPassword,
        currentPassword: requiresCurrentPassword ? currentPassword : null,
      );
      if (_authRepository?.currentUserId != ownerUid) {
        _fail(changePasswordErrorKey(AuthFailureCode.accountChanged));
        return false;
      }
      _succeeded = true;
      return true;
    } on AuthFailure catch (failure) {
      _fail(changePasswordErrorKey(failure.code));
      return false;
    } catch (_) {
      _fail(changePasswordErrorKey(AuthFailureCode.unknown));
      return false;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  void clearError() {
    if (_errorKey == null) return;
    _errorKey = null;
    _notify();
  }

  void _fail(String key) {
    _succeeded = false;
    _errorKey = key;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Maps a password failure to an ARB key. Raw provider text never leaves the
/// repository, and never reaches this function at all.
String changePasswordErrorKey(AuthFailureCode code) {
  switch (code) {
    case AuthFailureCode.invalidCurrentPassword:
    case AuthFailureCode.invalidCredentials:
      return 'passwordChangeWrongCurrent';
    case AuthFailureCode.weakPassword:
      return 'passwordChangeWeak';
    case AuthFailureCode.samePassword:
      return 'passwordChangeSame';
    case AuthFailureCode.reauthenticationRequired:
      return 'passwordChangeReauthRequired';
    case AuthFailureCode.tooManyRequests:
      return 'passwordChangeRateLimited';
    case AuthFailureCode.network:
      return 'passwordChangeNetworkError';
    case AuthFailureCode.sessionExpired:
      return 'passwordChangeSessionExpired';
    case AuthFailureCode.accountChanged:
      return 'passwordChangeAccountChanged';
    case AuthFailureCode.otpInvalidOrExpired:
      return 'resetLinkExpiredMessage';
    case AuthFailureCode.providerUnavailable:
    case AuthFailureCode.operationNotAllowed:
      return 'passwordChangeUnavailable';
    default:
      return 'passwordChangeFailed';
  }
}
