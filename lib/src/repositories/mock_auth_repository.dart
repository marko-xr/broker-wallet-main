import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';

/// Mock implementation of AuthRepository for testing
/// This shows how easy it is to switch implementations using the Repository pattern
class MockAuthRepository implements AuthRepository {
  UserModel? _currentUser;
  bool _isSignedIn = false;

  @override
  Stream<UserModel?> get authStateChanges {
    return Stream.value(_currentUser);
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 500));

    final user = UserModel(
      uid: 'mock_uid_123',
      name: name,
      email: email,
      phoneNumber: phoneNumber,
      profileImageUrl: null,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      isEmailVerified: true, // Mock as verified for testing
      isPhoneVerified: phoneNumber != null,
      subscription: UserSubscription(
        plan: 'free',
        isActive: true,
        features: ['basic_listing'],
      ),
      preferences: {},
    );

    _currentUser = user;
    _isSignedIn = true;
    return user;
  }

  @override
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 500));

    // Mock successful sign in
    final user = UserModel(
      uid: 'mock_uid_123',
      name: 'Mock User',
      email: email,
      phoneNumber: null,
      profileImageUrl: null,
      createdAt: DateTime.now().subtract(Duration(days: 30)),
      lastLoginAt: DateTime.now(),
      isEmailVerified: true,
      isPhoneVerified: false,
      subscription: UserSubscription(
        plan: 'free',
        isActive: true,
        features: ['basic_listing'],
      ),
      preferences: {},
    );

    _currentUser = user;
    _isSignedIn = true;
    return user;
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    await Future.delayed(Duration(milliseconds: 500));

    final user = UserModel(
      uid: 'mock_google_uid_123',
      name: 'Mock Google User',
      email: 'mockuser@gmail.com',
      phoneNumber: null,
      profileImageUrl: 'https://via.placeholder.com/150',
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      isEmailVerified: true,
      isPhoneVerified: false,
      subscription: UserSubscription(
        plan: 'free',
        isActive: true,
        features: ['basic_listing'],
      ),
      preferences: {},
    );

    _currentUser = user;
    _isSignedIn = true;
    return user;
  }

  @override
  Future<UserModel> signInWithFacebook() async {
    await Future.delayed(Duration(milliseconds: 500));

    final user = UserModel(
      uid: 'mock_facebook_uid_123',
      name: 'Mock Facebook User',
      email: 'mockuser@facebook.com',
      phoneNumber: null,
      profileImageUrl: 'https://via.placeholder.com/150',
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      isEmailVerified: true,
      isPhoneVerified: false,
      subscription: UserSubscription(
        plan: 'free',
        isActive: true,
        features: ['basic_listing'],
      ),
      preferences: {},
    );

    _currentUser = user;
    _isSignedIn = true;
    return user;
  }

  @override
  Future<void> sendEmailVerification({String? email}) async {
    await Future.delayed(Duration(milliseconds: 200));
    // Mock: do nothing, just simulate delay
  }

  @override
  Future<UserModel?> reloadUser() async {
    await Future.delayed(Duration(milliseconds: 100));
    return _currentUser;
  }

  @override
  Future<bool> isEmailVerified() async {
    await Future.delayed(Duration(milliseconds: 200));
    return _currentUser?.isEmailVerified ?? false;
  }

  @override
  Future<bool> checkEmailVerificationAndUpdate() async {
    await Future.delayed(Duration(milliseconds: 300));

    // Mock: Simulate checking email verification status
    if (_currentUser == null) {
      // Mock: No user signed in (log removed)
      return false;
    }

    // In mock mode, we'll simulate that the email is verified
    // In real usage, this would check Firebase Auth
    // Mock: Checking email verification status (log removed)

    // Simulate email verification being complete
    if (_currentUser!.email.isNotEmpty && !_currentUser!.isEmailVerified) {
      _currentUser = _currentUser!.copyWith(
        isEmailVerified: true,
        lastLoginAt: DateTime.now(),
      );
      // Mock: Email verified and Firestore updated (log removed)
      return true;
    } else if (_currentUser!.isEmailVerified) {
      // Mock: Email already verified (log removed)
      return true;
    } else {
      // Mock: No email to verify (log removed)
      return false;
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await Future.delayed(Duration(milliseconds: 500));
    // Mock: do nothing, just simulate delay
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(Duration(milliseconds: 200));
    _currentUser = null;
    _isSignedIn = false;
  }

  @override
  Future<void> deleteAccount() async {
    await Future.delayed(Duration(milliseconds: 500));
    _currentUser = null;
    _isSignedIn = false;
  }

  @override
  Future<void> updateUserProfile({
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  }) async {
    await Future.delayed(Duration(milliseconds: 300));

    if (_currentUser != null) {
      _currentUser = UserModel(
        uid: _currentUser!.uid,
        name: name ?? _currentUser!.name,
        email: _currentUser!.email,
        phoneNumber: phoneNumber ?? _currentUser!.phoneNumber,
        profileImageUrl: profileImageUrl ?? _currentUser!.profileImageUrl,
        createdAt: _currentUser!.createdAt,
        lastLoginAt: _currentUser!.lastLoginAt,
        isEmailVerified: _currentUser!.isEmailVerified,
        isPhoneVerified: _currentUser!.isPhoneVerified,
        subscription: _currentUser!.subscription,
        preferences: _currentUser!.preferences,
      );
    }
  }

  @override
  Future<void> updateEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    await Future.delayed(Duration(milliseconds: 500));

    // Mock password validation
    if (currentPassword.isEmpty) {
      throw Exception('Current password is required');
    }

    if (_currentUser != null) {
      // Update user with new email (mock as unverified until verification)
      _currentUser = UserModel(
        uid: _currentUser!.uid,
        name: _currentUser!.name,
        email: newEmail,
        phoneNumber: _currentUser!.phoneNumber,
        profileImageUrl: _currentUser!.profileImageUrl,
        createdAt: _currentUser!.createdAt,
        lastLoginAt: _currentUser!.lastLoginAt,
        isEmailVerified: false, // Reset verification status
        isPhoneVerified: _currentUser!.isPhoneVerified,
        subscription: _currentUser!.subscription,
        preferences: _currentUser!.preferences,
      );
    }
  }

  @override
  Future<UserModel?> getUserProfile(String uid) async {
    await Future.delayed(Duration(milliseconds: 200));
    return _currentUser;
  }

  @override
  Future<void> addEmailToAccount({
    required String email,
    required String password,
  }) async {
    await Future.delayed(Duration(milliseconds: 500));

    // Mock: Just simulate sending verification email
    // In mock, we don't actually add the email until "verification" is complete (logs removed)

    // Note: The email is NOT added to the user model here
    // It should only be added after verification is completed
  }

  /// Mock method to simulate completing email verification
  Future<void> completeEmailVerification({
    required String email,
  }) async {
    await Future.delayed(Duration(milliseconds: 300));

    if (_currentUser != null) {
      // Update user with the verified email
      _currentUser = UserModel(
        uid: _currentUser!.uid,
        name: _currentUser!.name,
        email: email,
        phoneNumber: _currentUser!.phoneNumber,
        profileImageUrl: _currentUser!.profileImageUrl,
        createdAt: _currentUser!.createdAt,
        lastLoginAt: DateTime.now(),
        isEmailVerified: true, // Mark as verified
        isPhoneVerified: _currentUser!.isPhoneVerified,
        subscription: _currentUser!.subscription,
        preferences: _currentUser!.preferences,
      );

      // Mock: Email verified and added to account: $email (log removed)
    }
  }

  @override
  Future<void> sendPhoneVerificationOTP({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    await Future.delayed(Duration(milliseconds: 1000));

    // Mock validation
    if (!phoneNumber.startsWith('+971')) {
      onError('Invalid UAE phone number');
      return;
    }

    // Simulate sending OTP
    onCodeSent('mock_verification_id_123');
  }

  @override
  Future<void> verifyPhoneNumber({
    required String verificationId,
    required String otpCode,
  }) async {
    await Future.delayed(Duration(milliseconds: 500));

    // Mock OTP validation
    if (otpCode != '123456') {
      throw Exception('Invalid verification code');
    }

    if (_currentUser != null) {
      // Update user with verified phone
      _currentUser = UserModel(
        uid: _currentUser!.uid,
        name: _currentUser!.name,
        email: _currentUser!.email,
        phoneNumber: '+971501234567', // Mock phone number
        profileImageUrl: _currentUser!.profileImageUrl,
        createdAt: _currentUser!.createdAt,
        lastLoginAt: DateTime.now(),
        isEmailVerified: _currentUser!.isEmailVerified,
        isPhoneVerified: true,
        subscription: _currentUser!.subscription,
        preferences: _currentUser!.preferences,
      );
    }
  }
}
