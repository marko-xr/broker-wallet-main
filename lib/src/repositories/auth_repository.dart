import 'package:broker_wallet/src/data/models/user_model.dart';
export 'auth_failure.dart';

/// Authoritative email state for the currently signed-in account.
///
/// [confirmedEmail] is always Supabase Auth's current `auth.users.email`.
/// [pendingEmail] is the SDK's `User.newEmail` projection and is presentation
/// state only until Supabase confirms the change.
class EmailChangeState {
  const EmailChangeState({
    required this.ownerUid,
    required this.confirmedEmail,
    this.pendingEmail,
    this.requestedAt,
  });

  final String ownerUid;
  final String confirmedEmail;
  final String? pendingEmail;
  final DateTime? requestedAt;

  bool get isPending => pendingEmail != null && pendingEmail!.isNotEmpty;
}

/// Changes the email address of the **currently signed-in** Supabase account.
///
/// Implementations must derive ownership from the live session, retain the
/// confirmed address until the backend changes it, and expose pending state
/// from the backend rather than from durable client storage.
abstract class EmailChangeCapability {
  EmailChangeState? get currentEmailChange;

  Stream<EmailChangeState?> get emailChangeChanges;

  /// Starts a backend-owned email change for the current account.
  Future<EmailChangeState> requestEmailChange(String newEmail);

  /// Resends the backend-owned pending email-change confirmation message(s).
  Future<EmailChangeState> resendEmailChange();

  /// Refreshes email state from Supabase Auth for the current session.
  Future<EmailChangeState?> refreshEmailChange();
}

/// Verifies a phone number for the **currently signed-in** user.
///
/// Every operation acts on the account of the live session — never on a
/// caller-supplied user id — and a successful verification updates that same
/// account. It can neither sign anyone in nor create an account. Confirmation
/// is authoritative only when the backend reports the number as confirmed.
///
/// A separate capability rather than part of [AuthRepository]: the legacy
/// Firebase contract ([AuthRepository.sendPhoneVerificationOTP]) is shaped
/// around verification ids and callbacks and stays unchanged for that backend.
/// Only backends that can genuinely do this implement it.
abstract class PhoneVerificationCapability {
  /// Sends a verification code to [phoneE164] for the current account.
  /// Throws [AuthFailure].
  Future<void> requestPhoneVerification(String phoneE164);

  /// Sends a new code for a pending verification of [phoneE164].
  /// Throws [AuthFailure].
  Future<void> resendPhoneVerification(String phoneE164);

  /// Confirms [code] for [phoneE164]. Returns the current account as the
  /// backend now reports it, with the number confirmed. Throws [AuthFailure]
  /// when the code is rejected or confirmation is not reported.
  Future<UserModel> confirmPhoneVerification({
    required String phoneE164,
    required String code,
  });
}


/// A password-recovery session that Supabase established from a recovery deep
/// link.
///
/// Its existence means GoTrue exchanged a `type=recovery` callback and the
/// client now holds a real session for [ownerUid]. It is authoritative
/// identity, not a client guess: the uid comes from the session Supabase
/// created, never from the link.
class PasswordRecoverySession {
  const PasswordRecoverySession({
    required this.ownerUid,
    required this.startedAt,
  });

  final String ownerUid;
  final DateTime startedAt;
}

/// Password operations for a backend that owns passwords itself.
///
/// A separate capability rather than part of [AuthRepository] for the same
/// reason as [PhoneVerificationCapability]: the legacy Firebase contract is
/// shaped around its own reauthentication model and stays unchanged, and only
/// a backend that can genuinely perform these operations implements this.
abstract class PasswordCapability {
  /// Whether the backend verifies [changePassword]'s `currentPassword`.
  ///
  /// This is a *backend* property, not a UI preference. When it is false the
  /// current password is neither collected nor sent, because sending a value
  /// the server will not check — or checking it client-side with a second
  /// sign-in — would claim a guarantee that does not exist.
  bool get verifiesCurrentPassword;

  /// Requests a password-reset email for [email].
  ///
  /// Completes normally whether or not an account exists. Callers must present
  /// one message for both outcomes: the result of this call is not permitted
  /// to reveal whether an address is registered.
  Future<void> requestPasswordReset(String email);

  /// Changes the password of the **currently signed-in** account.
  ///
  /// Ownership comes from the live session, and the account the change lands
  /// on is re-checked against the account that started it. [currentPassword]
  /// is sent only when [verifiesCurrentPassword] is true. Throws
  /// [AuthFailure].
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
  });

  /// Recovery sessions Supabase established from a recovery deep link.
  ///
  /// Fed by the repository's existing single Supabase auth subscription, so
  /// observing recovery adds no second auth listener and no second session
  /// authority.
  Stream<PasswordRecoverySession> get passwordRecoverySessions;

  /// Whether the live session exists **only** to set a new password.
  ///
  /// Synchronous on purpose. A recovery session is a perfectly valid session at
  /// the transport level, so the application must be able to ask this in the
  /// same turn it learns about the session. Asking on a second stream lets the
  /// router see an authenticated session before it learns that the session is a
  /// recovery, which is exactly how a recovery link reached Home.
  ///
  /// Implementations must have this answer correct *before* they publish the
  /// identity for that session, and must bind it to the account it belongs to
  /// so it can never describe a different one.
  bool get isPasswordRecoveryActive;

  /// Ends a recovery, whether it completed or was cancelled.
  ///
  /// Clears the recovery marker and signs the recovery session out, so a
  /// session that existed only to reset a password never survives as an
  /// ordinary logged-in session. Safe to call when there is nothing to end.
  Future<void> endPasswordRecovery();
}

/// The password capability of [repository], or null when its backend has none.
///
/// Shaped like `AuthViewModel.phoneVerification` and `.emailChange`: the cast
/// is explicit because [PasswordCapability] is not a subtype of
/// [AuthRepository], so an `is` test cannot promote across the two.
PasswordCapability? passwordCapabilityOf(AuthRepository? repository) {
  if (repository is! PasswordCapability) return null;
  return repository as PasswordCapability;
}

/// Abstract repository interface for authentication operations
/// This allows us to easily switch between different authentication backends
/// (Firebase, Supabase, etc.) without changing business logic
abstract class AuthRepository {
  /// Stream of authentication state changes
  Stream<UserModel?> get authStateChanges;

  /// Get the current authenticated user
  UserModel? get currentUser;

  /// Canonical authenticated user ID (Firebase Auth UID or Supabase auth.users.id UUID).
  /// Returns null if not authenticated.
  /// Never falls back to offline cache as authority.
  String? get currentUserId => currentUser?.uid;

  /// Sign up with email and password
  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  });

  /// Sign in with email and password
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  /// Sign in with Google
  Future<UserModel> signInWithGoogle();

  /// Send email verification
  Future<void> sendEmailVerification({String? email});

  /// Check if email is verified
  Future<bool> isEmailVerified();

  /// Reload the current user from the server and return the refreshed UserModel
  Future<UserModel?> reloadUser();

  /// Check email verification and update backend user record if verified
  Future<bool> checkEmailVerificationAndUpdate();

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email);

  /// Sign out
  Future<void> signOut();

  /// Delete user account
  Future<void> deleteAccount();

  /// Update user profile
  Future<void> updateUserProfile({
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  });

  /// Update email with password verification
  Future<void> updateEmail({
    required String newEmail,
    required String currentPassword,
  });

  /// Add email to existing account (for phone-only accounts)
  Future<void> addEmailToAccount({
    required String email,
    required String password,
  });

  /// Send OTP for phone verification
  Future<void> sendPhoneVerificationOTP({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  });

  /// Verify phone number with OTP
  Future<void> verifyPhoneNumber({
    required String verificationId,
    required String otpCode,
  });

  /// Get user profile
  Future<UserModel?> getUserProfile(String uid);
}
