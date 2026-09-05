import 'package:broker_wallet/src/data/models/user_model.dart';
export 'auth_failure.dart';

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

  /// Sign in with Facebook
  Future<UserModel> signInWithFacebook();

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
