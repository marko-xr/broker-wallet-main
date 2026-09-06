import 'auth_viewmodel.dart';

/// Shared by the real verification screen's auth listener and verification
/// checks. Claim completion before scheduling navigation so concurrent signals
/// cannot leave the screen twice.
class EmailVerificationCompletion {
  bool _claimed = false;

  bool get isClaimed => _claimed;

  bool tryClaim(AuthViewModel auth) {
    if (_claimed ||
        auth.currentUserId == null ||
        auth.currentUserId != auth.currentUser?.uid ||
        !auth.isAuthenticated ||
        !auth.isEmailVerified) {
      return false;
    }
    _claimed = true;
    return true;
  }
}
