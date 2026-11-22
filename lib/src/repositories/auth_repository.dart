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

/// The live session's sign-in phone number, from Supabase Auth itself.
///
/// Under Model X only an account created by phone holds one: an email
/// account's phone is a contact number on its profile and never appears here.
/// This is how the app tells a phone account (Delete Account by code, Change
/// Phone) from an email account; the server decides again on every request.
abstract class SignInPhoneSource {
  /// `+9715XXXXXXXX`, or null for an account that does not sign in by phone.
  String? get currentSignInPhoneE164;
}

/// Changes the sign-in number of a phone account (Model X, Worker routes).
///
/// Possession of the CURRENT number is proven with a code Supabase sends to
/// it, and of the NEW number with a code the verification provider sends; the
/// server checks both for this account's current app session, then changes
/// the number itself. No session is created for either number.
abstract class PhoneNumberChangeCapability {
  /// Sends a code to the current number and one to [newPhoneE164].
  /// Throws [AuthFailure].
  Future<void> requestPhoneNumberChange(String newPhoneE164);

  /// Whether the server already accepted the current-number code for the
  /// pending change (a mistyped new code does not spend it again).
  bool get currentNumberProven;

  /// Confirms the change. [currentCode] is ignored once
  /// [currentNumberProven]. Returns the account as the server now reports it.
  /// Throws [AuthFailure].
  Future<UserModel> confirmPhoneNumberChange({
    required String newPhoneE164,
    required String newCode,
    String? currentCode,
  });
}

/// How Add Email ended once the user came back from the confirmation email.
enum AddEmailCompletion {
  /// The server does not yet report the new address as confirmed.
  notConfirmed,

  /// The address is confirmed and the chosen password is set.
  completed,

  /// The address is confirmed but the chosen password could not be set (or
  /// is no longer held, e.g. after an app restart). The account has the email
  /// and no usable password: the user sets one with "Forgot password".
  passwordNotSet,
}

/// Finishes Add Email for an account without an email (phone accounts).
///
/// Add Email asks only for the address change. The password the user chose is
/// held in memory, never stored, and is set only after the server reports the
/// new address as confirmed for the same account, so a password is never set
/// on an account whose email was not added.
abstract class AddEmailCapability {
  Future<AddEmailCompletion> completeAddEmail();
}

/// The account a completed phone sign-in landed on.
class PhoneSignInResult {
  const PhoneSignInResult({required this.user, required this.accountExisted});

  final UserModel user;

  /// The profile already had a name before this sign-in: the number belonged
  /// to an account that existed before this flow started.
  final bool accountExisted;
}

/// Signs in to, or creates, an account with a phone number.
///
/// Supabase Auth generates, sends and verifies the code; implementations never
/// store it. A verified code is not access by itself: access is granted only
/// once the resulting session passes the same Single Active Device claim as
/// every other sign-in, and only then is the identity published.
///
/// Separate from [PhoneVerificationCapability], which changes the phone of an
/// account that is already signed in and can never sign anyone in.
abstract class PhoneSignInCapability {
  /// Asks Supabase Auth to send a sign-in code to [phoneE164]. With
  /// [createAccount] false an unknown number is refused instead of creating an
  /// account. Calling it again is how a code is resent. Throws [AuthFailure].
  Future<void> requestPhoneSignInCode({
    required String phoneE164,
    required bool createAccount,
  });

  /// Verifies [code] for [phoneE164] and completes the sign-in. Returns only
  /// after the session has been authorized for this device. Throws
  /// [AuthFailure].
  Future<PhoneSignInResult> verifyPhoneSignInCode({
    required String phoneE164,
    required String code,
  });

  /// Saves [name] as the profile name of the signed-in account [expectedUid]
  /// when that profile has no name yet; an existing name is never replaced.
  /// Returns the profile as stored. Throws [AuthFailure].
  Future<UserModel> completePhoneSignUpName({
    required String expectedUid,
    required String name,
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

/// The two ordered stages of an authoritative app-session displacement.
enum AppSessionSupersededPhase { accessRevoked, localSignOutCompleted }

/// Optional application-session displacement signal in Supabase mode.
abstract class AppSessionEvents {
  Stream<AppSessionSupersededPhase> get sessionSupersededEvents;
  Stream<bool> get sessionCheckUnavailableEvents;
  Future<void> retryAppSessionValidation();
}
