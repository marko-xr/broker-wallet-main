import 'package:broker_wallet/src/common/utils/email_validator.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';

/// Requests a password-reset email.
///
/// Used by "Forgot password?" on the email Login screen and by the recovery
/// screen's "send a new link" action, so both produce byte-identical behaviour.
///
/// Anti-enumeration is a property of this class, not of the screens that use
/// it: a successful request reports one fixed message whether or not an account
/// exists, and the backend is never asked to confirm that it does. Supabase's
/// own `resetPasswordForEmail` answers the same way for both cases; this view
/// model is what guarantees the application does not undo that by, for example,
/// looking the address up first.
class PasswordResetRequestViewModel extends ChangeNotifier {
  PasswordResetRequestViewModel({required PasswordCapability? gateway})
      : _gateway = gateway;

  final PasswordCapability? _gateway;

  bool _submitting = false;
  bool _sent = false;
  String? _errorKey;
  bool _disposed = false;

  bool get isAvailable => _gateway != null;
  bool get isSubmitting => _submitting;

  /// True once a request has been accepted. The screen shows the same
  /// confirmation for a registered and an unregistered address.
  bool get hasSent => _sent;
  String? get errorKey => _errorKey;

  /// Requests a reset email for [email].
  ///
  /// Returns true when the request was accepted. A local format failure returns
  /// false **without any network call**, so an obviously malformed address
  /// never reaches the provider and never consumes the send rate limit.
  Future<bool> submit(String email) async {
    if (_submitting) return false;

    final gateway = _gateway;
    if (gateway == null) {
      _fail(AuthFailureCode.providerUnavailable);
      return false;
    }

    final normalized = email.trim().toLowerCase();
    if (!EmailValidator.isValidFormat(normalized)) {
      _fail(AuthFailureCode.invalidEmail);
      return false;
    }

    _errorKey = null;
    _submitting = true;
    _notify();
    try {
      await gateway.requestPasswordReset(normalized);
      _sent = true;
      return true;
    } on AuthFailure catch (failure) {
      _fail(failure.code);
      return false;
    } catch (_) {
      _fail(AuthFailureCode.unknown);
      return false;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  void reset() {
    if (!_sent && _errorKey == null) return;
    _sent = false;
    _errorKey = null;
    _notify();
  }

  void _fail(AuthFailureCode code) {
    _sent = false;
    _errorKey = passwordResetRequestErrorKey(code);
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

/// Maps a reset-request failure to an ARB key.
///
/// Deliberately coarse. A password-reset form is the classic account-discovery
/// surface, so every outcome that could distinguish a registered address from
/// an unregistered one — a user lookup failure, a provider "no such user" —
/// collapses into the generic failure rather than being described.
String passwordResetRequestErrorKey(AuthFailureCode code) {
  switch (code) {
    case AuthFailureCode.invalidEmail:
      return 'passwordResetInvalidEmail';
    case AuthFailureCode.tooManyRequests:
      return 'passwordResetRateLimited';
    case AuthFailureCode.network:
      return 'passwordResetNetworkError';
    case AuthFailureCode.providerUnavailable:
    case AuthFailureCode.operationNotAllowed:
      return 'passwordResetUnavailable';
    default:
      return 'passwordResetFailed';
  }
}
