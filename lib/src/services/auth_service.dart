import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/professional_email_service.dart';

class AuthService {
  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _phoneLookupCollection =>
      _firestore.collection('phone_lookup');
  CollectionReference<Map<String, dynamic>> get _emailLookupCollection =>
      _firestore.collection('email_lookup');

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Normalize a UAE phone number to E.164 format used by Firebase
  String _normalizePhoneNumber(String phoneNumber) {
    final normalized = PhoneInputService.toInternationalFormat(phoneNumber);
    return normalized.startsWith('+') ? normalized : '+$normalized';
  }

  Future<List<String>> _fetchSignInMethodsForEmail(String email) async {
    try {
      final dynamic authDynamic = _auth;
      final result = await authDynamic.fetchSignInMethodsForEmail(email);
      if (result is List<String>) {
        return result;
      }
      if (result is List) {
        return result.map((e) => e.toString()).toList();
      }
    } catch (e) {
      // fetchSignInMethodsForEmail failed (log removed)
    }
    return const [];
  }

  Future<void> _runUserPhoneTransaction({
    required User user,
    required String name,
    required String phoneE164,
    bool markAsSignup = false,
  }) async {
    final trimmedName =
        name.trim().isNotEmpty ? name.trim() : (user.displayName ?? '');

    await _firestore.runTransaction((transaction) async {
      final userRef = _usersCollection.doc(user.uid);
      final phoneRef = _phoneLookupCollection.doc(phoneE164);

      final userSnap = await transaction.get(userRef);
      final now = FieldValue.serverTimestamp();

      final data = <String, dynamic>{
        'userId': user.uid,
        'name': trimmedName,
        'phoneE164': phoneE164,
        'phoneNumber': phoneE164,
        'isPhoneVerified': true,
        'updatedAt': now,
        'lastLoginAt': now,
      };

      if (user.email != null && user.email!.isNotEmpty) {
        data['email'] = user.email;
        data['isEmailVerified'] = user.emailVerified;
      }

      if (user.photoURL != null && user.photoURL!.isNotEmpty) {
        data['profileImageUrl'] = user.photoURL;
      }

      if (!userSnap.exists) {
        data['createdAt'] = now;
        data['authProvider'] = markAsSignup ? 'phone' : 'phone';
      } else if (markAsSignup) {
        // Preserve existing auth provider if already set to something else
        final existingProvider = userSnap.data()?['authProvider'];
        if (existingProvider == null ||
            (existingProvider is String && existingProvider.isEmpty)) {
          data['authProvider'] = 'phone';
        }
      }

      transaction.set(userRef, data, SetOptions(merge: true));

      final phoneData = <String, dynamic>{
        'userId': user.uid,
        'phoneE164': phoneE164,
        'updatedAt': now,
      };

      if (markAsSignup) {
        phoneData['createdAt'] = now;
      }

      transaction.set(phoneRef, phoneData, SetOptions(merge: true));
    });
  }

  Future<void> _runUserEmailTransaction({
    required User user,
    required String name,
    bool markAsSignup = false,
  }) async {
    final trimmedName =
        name.trim().isNotEmpty ? name.trim() : (user.displayName ?? '');

    await _firestore.runTransaction((transaction) async {
      final userRef = _usersCollection.doc(user.uid);
      final hasEmail = user.email != null && user.email!.isNotEmpty;
      final DocumentReference<Map<String, dynamic>>? emailRef = hasEmail
          ? _emailLookupCollection.doc(user.email!.toLowerCase())
          : null;

      final userSnap = await transaction.get(userRef);
      final now = FieldValue.serverTimestamp();

      final data = <String, dynamic>{
        'userId': user.uid,
        'name': trimmedName,
        'email': user.email ?? '',
        'isEmailVerified': user.emailVerified,
        'isPhoneVerified': user.phoneNumber != null,
        'updatedAt': now,
        'lastLoginAt': now,
      };

      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        final normalizedPhone = _normalizePhoneNumber(user.phoneNumber!);
        data['phoneE164'] = normalizedPhone;
        data['phoneNumber'] = normalizedPhone;
      }

      if (user.photoURL != null && user.photoURL!.isNotEmpty) {
        data['profileImageUrl'] = user.photoURL;
      }

      if (!userSnap.exists) {
        data['createdAt'] = now;
        data['authProvider'] = markAsSignup ? 'email' : 'email';
      } else if (markAsSignup) {
        final existingProvider = userSnap.data()?['authProvider'];
        if (existingProvider == null ||
            (existingProvider is String && existingProvider.isEmpty)) {
          data['authProvider'] = 'email';
        }
      }

      transaction.set(userRef, data, SetOptions(merge: true));

      if (hasEmail && emailRef != null) {
        final emailData = <String, dynamic>{
          'userId': user.uid,
          'email': user.email!.toLowerCase(),
          'updatedAt': now,
        };

        if (markAsSignup) {
          emailData['createdAt'] = now;
        }

        transaction.set(emailRef, emailData, SetOptions(merge: true));
      }
    });
  }

  Future<void> sendOtp({
    required String e164,
    Duration timeout = const Duration(seconds: 60),
    int? forceResendToken,
    required void Function(String verificationId) onCodeSent,
    void Function(String verificationId, int? resendToken)? onCodeSentWithToken,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException exception) onFailed,
    required void Function(String verificationId) onTimeout,
  }) async {
    final normalized = e164.trim();
    try {
      // Sending OTP to $normalized (log removed)
      await _auth.verifyPhoneNumber(
        phoneNumber: normalized,
        timeout: timeout,
        forceResendingToken: forceResendToken,
        verificationCompleted: (credential) {
          // Instant verification succeeded (log removed)
          onAutoVerified(credential);
        },
        verificationFailed: (exception) {
          // Phone verification failed (log removed)
          onFailed(exception);
        },
        codeSent: (verificationId, resendToken) {
          // OTP code sent to $normalized (log removed)
          onCodeSent(verificationId);
          onCodeSentWithToken?.call(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          // Auto-retrieval timeout (log removed)
          onTimeout(verificationId);
        },
      );
    } on FirebaseAuthException catch (e) {
      onFailed(e);
      throw _handleAuthException(e);
    } catch (e) {
      // Unexpected error sending OTP (log removed)
      throw 'Failed to start verification: $e';
    }
  }

  Future<UserCredential> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      return await signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to verify code: ${e.toString()}';
    }
  }

  Future<UserCredential> signInWithCredential(
      PhoneAuthCredential credential) async {
    try {
      final result = await _auth.signInWithCredential(credential);
      if (result.user == null) {
        throw Exception('Authentication failed. Please try again.');
      }
      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to complete phone sign in: ${e.toString()}';
    }
  }

  Future<User> linkPhoneCredential(PhoneAuthCredential credential) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No active session to link phone number');
      }

      final result = await currentUser.linkWithCredential(credential);
      final linkedUser = result.user ?? currentUser;

      final normalizedPhone = linkedUser.phoneNumber != null
          ? _normalizePhoneNumber(linkedUser.phoneNumber!)
          : '';

      if (normalizedPhone.isNotEmpty) {
        await finalizePhoneUser(
          user: linkedUser,
          phoneE164: normalizedPhone,
          displayName: linkedUser.displayName,
          markAsSignup: false,
        );
      }

      return linkedUser;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to link phone credential: ${e.toString()}';
    }
  }

  Future<void> linkEmailCredential({
    required String email,
    required String password,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('No active session to link email');
    }

    final normalizedEmail = email.trim().toLowerCase();

    try {
      final methods = await _fetchSignInMethodsForEmail(normalizedEmail);
      if (methods.isNotEmpty) {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'This email is already registered to another account',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: normalizedEmail,
        password: password,
      );

      await currentUser.linkWithCredential(credential);
      await currentUser.reload();
      final refreshedUser = _auth.currentUser ?? currentUser;

      await finalizeEmailUser(
        user: refreshedUser,
        displayName: refreshedUser.displayName,
        markAsSignup: false,
      );

      await sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to link email: ${e.toString()}';
    }
  }

  Future<UserModel?> getUserByPhoneNumber(String phoneNumber) async {
    try {
      final normalizedNumber = _normalizePhoneNumber(phoneNumber);
      final lookupDoc = await _firestore
          .collection('phone_lookup')
          .doc(normalizedNumber)
          .get();

      if (!lookupDoc.exists) {
        return null;
      }

      final lookupData = lookupDoc.data();
      final userId = lookupData?['userId'] as String?;
      if (userId == null || userId.isEmpty) {
        return null;
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return null;
      }

      return UserModel.fromFirestore(userDoc);
    } catch (e) {
      throw Exception('Failed to check phone number: $e');
    }
  }

  Future<bool> isPhoneRegistered(String phoneNumber) async {
    try {
      final normalizedNumber = _normalizePhoneNumber(phoneNumber);
      // Checking phone registration for: $normalizedNumber (log removed)

      final lookupDoc = await _firestore
          .collection('phone_lookup')
          .doc(normalizedNumber)
          .get()
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // Phone lookup timed out (log removed)
          throw TimeoutException('Phone lookup timed out');
        },
      );
      // Firestore query completed successfully (log removed)

      if (!lookupDoc.exists) {
        // Phone not found in lookup collection - phone is NOT registered (log removed)
        return false;
      }

      // Phone document found in lookup collection (log removed)
      final lookupData = lookupDoc.data();
      // Lookup data available (log removed)
      final userId = lookupData?['userId'] as String?;

      // Check if userId exists and is not empty
      // We don't need to verify the user document exists because:
      // 1. The phone_lookup document is only created when a user signs up
      // 2. Reading the users collection requires authentication (permission denied for unauthenticated users)
      // 3. If phone_lookup exists with a valid userId, the phone is registered
      if (userId != null && userId.isNotEmpty) {
        // Phone is registered with userId: $userId (log removed)
        return true;
      }
      // Invalid or missing userId in lookup document (log removed)
      return false;
    } on TimeoutException {
      // In case of timeout, throw error to prevent signup/signin
      throw Exception(
          'Network timeout. Please check your connection and try again.');
    } on FirebaseException catch (e) {
      // Firebase error checking phone registration (log removed)
      // Full error removed from logs
      // Re-throw with more specific Firebase error
      throw Exception('Firebase error: ${e.message ?? e.code}');
    } catch (e) {
      // Failed to check phone registration (log removed)
      // Re-throw the error instead of returning false
      // This prevents signup/signin when we can't verify
      throw Exception('Failed to verify phone number. Please try again.');
    }
  }

  // Debug method to check lookup collections - remove in production
  Future<void> debugLookupCollections() async {
    try {
      // Debugging lookup collections suppressed (logs removed)
    } catch (e) {
      // Error debugging lookup collections (log removed)
    }
  }

  Future<bool> isEmailRegistered(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final lookupDoc = await _firestore
          .collection('email_lookup')
          .doc(normalizedEmail)
          .get();

      if (!lookupDoc.exists) {
        return false;
      }

      final lookupData = lookupDoc.data();
      final userId = lookupData?['userId'] as String?;

      // Double-check that the user actually exists
      if (userId != null && userId.isNotEmpty) {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        return userDoc.exists;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  // Sign up with email and password
  Future<UserCredential?> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? phoneNumber, // Make phoneNumber optional
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      // Pre-check to avoid duplicate accounts and provide friendly message
      final isEmailAlreadyRegistered = await isEmailRegistered(normalizedEmail);
      if (isEmailAlreadyRegistered) {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'This email is already registered',
        );
      }

      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      // Update display name
      await result.user?.updateDisplayName(name);

      if (result.user != null) {
        // Persist user profile + lookup documents transactionally
        await _runUserEmailTransaction(
          user: result.user!,
          name: name,
          markAsSignup: true,
        );

        // Attach phone data if provided during signup
        if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
          final e164 = _normalizePhoneNumber(phoneNumber);
          await _runUserPhoneTransaction(
            user: result.user!,
            name: name,
            phoneE164: e164,
            markAsSignup: false,
          );
        }

        // Send professional email verification
        try {
          // Check rate limiting for signup emails too
          if (_lastEmailSent != null) {
            final timeSinceLastEmail =
                DateTime.now().difference(_lastEmailSent!);
            if (timeSinceLastEmail < _emailCooldown) {
              return result; // Still return successful signup
            }
          }

          await ProfessionalEmailService.sendProfessionalVerificationEmail(
              result.user!);
          _lastEmailSent = DateTime.now(); // Update timestamp
        } catch (emailError) {
          // Only try basic email if not rate limited
          if (!emailError.toString().contains('too-many-requests')) {
            try {
              await result.user!.sendEmailVerification();
              _lastEmailSent = DateTime.now(); // Update timestamp
            } catch (fallbackError) {
              // Don't throw here - account creation should still succeed
            }
          } else {}
        }
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'An unexpected error occurred: ${e.toString()}';
    }
  }

  // Sign in with email and password
  Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      // Update last login time
      if (result.user != null) {
        await _runUserEmailTransaction(
          user: result.user!,
          name: result.user!.displayName ?? '',
          markAsSignup: false,
        );
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'An unexpected error occurred: ${e.toString()}';
    }
  }

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // If user cancels the sign-in process
      if (googleUser == null) {
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      UserCredential result = await _auth.signInWithCredential(credential);

      // Create or update user document in Firestore
      if (result.user != null) {
        await _createOrUpdateUser(result.user!);
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Google sign in failed: ${e.toString()}';
    }
  }

  // Reset Password
  Future<void> resetPassword(String email) async {
    try {
      if (email.isEmpty) {
        throw Exception('Email address is required');
      }

      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to send password reset email: ${e.toString()}';
    }
  }

  // Create or update user document from social login
  Future<void> _createOrUpdateUser(User user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (doc.exists) {
        // Update existing user
        await docRef.update({
          'lastLoginAt': DateTime.now().millisecondsSinceEpoch,
          'isEmailVerified': user.emailVerified,
        });
      } else {
        // Create new user
        final userModel = UserModel(
          uid: user.uid,
          name: user.displayName ?? 'User',
          email: user.email ?? '',
          phoneNumber: '',
          profileImageUrl: user.photoURL,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          isEmailVerified: user.emailVerified,
          isPhoneVerified: false, // Phone verification disabled
          subscription: UserSubscription(
            plan: 'free',
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            isActive: true,
            features: ['basic_listing', 'basic_search'],
          ),
          preferences: {
            'language': 'en',
            'currency': 'AED',
            'notifications': {
              'email': true,
              'push': true,
              'marketing': false,
            },
            'theme': 'light',
          },
        );

        await docRef.set(userModel.toMap());
      }
    } catch (e) {
    }
  }

  // Get email verification status
  Future<Map<String, dynamic>> getEmailVerificationStatus() async {
    final user = _auth.currentUser;

    if (user == null) {
      return {
        'status': 'no_user',
        'message': 'No user is currently signed in',
      };
    }

    // Reload user to get latest verification status
    await user.reload();
    final refreshedUser = _auth.currentUser;

    return {
      'status': refreshedUser?.emailVerified == true ? 'verified' : 'pending',
      'email': refreshedUser?.email,
      'emailVerified': refreshedUser?.emailVerified,
      'uid': refreshedUser?.uid,
      'providerData': refreshedUser?.providerData
          .map((p) => {
                'providerId': p.providerId,
                'email': p.email,
                'displayName': p.displayName,
              })
          .toList(),
      'metadata': {
        'creationTime': refreshedUser?.metadata.creationTime?.toIso8601String(),
        'lastSignInTime':
            refreshedUser?.metadata.lastSignInTime?.toIso8601String(),
      },
      'message': refreshedUser?.emailVerified == true
          ? 'Email is verified'
          : 'Email verification pending - check your inbox and spam folder',
    };
  }

  // Last email sent timestamp to prevent spam
  static DateTime? _lastEmailSent;
  static const Duration _emailCooldown = Duration(minutes: 1);

  // Check if we can send email (not rate limited)
  bool canSendEmail() {
    if (_lastEmailSent == null) return true;

    final timeSinceLastEmail = DateTime.now().difference(_lastEmailSent!);
    return timeSinceLastEmail >= _emailCooldown;
  }

  // Get remaining cooldown time
  Duration getRemainingCooldown() {
    if (_lastEmailSent == null) return Duration.zero;

    final timeSinceLastEmail = DateTime.now().difference(_lastEmailSent!);
    if (timeSinceLastEmail >= _emailCooldown) return Duration.zero;

    return _emailCooldown - timeSinceLastEmail;
  }

  // Send email verification
  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user is currently signed in');
      }

      if (user.emailVerified) {
        throw Exception('Email is already verified');
      }

      // Check rate limiting
      if (!canSendEmail()) {
        final remaining = getRemainingCooldown();
        throw Exception(
            'Please wait ${remaining.inSeconds} seconds before requesting another verification email');
      }

      // Try professional email service first
      try {
        // Sending professional email verification (log removed)
        await ProfessionalEmailService.sendProfessionalVerificationEmail(user);
        _lastEmailSent = DateTime.now();
        // Professional email verification sent (log removed)
      } catch (e) {
        // Professional email failed, trying basic method (log removed)

        // Fallback to basic Firebase email
        await user.sendEmailVerification();
        _lastEmailSent = DateTime.now();
        // Basic email verification sent successfully (log removed)
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        throw Exception(
            'Too many verification emails sent. Please wait a few minutes before trying again.');
      }
      throw _handleAuthException(e);
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Failed to send verification email: ${e.toString()}');
    }
  }

  Future<User?> reloadAndGetUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    return _auth.currentUser;
  }

  Future<void> upsertUserProfile({
    required User user,
    String? name,
    String? phoneE164,
  }) async {
    try {
      final resolvedName = (name ?? user.displayName ?? '').trim();

      if (phoneE164 != null && phoneE164.trim().isNotEmpty) {
        await _runUserPhoneTransaction(
          user: user,
          name: resolvedName,
          phoneE164: phoneE164,
          markAsSignup: false,
        );
      } else {
        await _runUserEmailTransaction(
          user: user,
          name: resolvedName,
          markAsSignup: false,
        );
      }
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  Future<void> finalizePhoneUser({
    required User user,
    required String phoneE164,
    String? displayName,
    bool markAsSignup = false,
  }) async {
    // Update Firebase Auth displayName if provided
    final nameToUse = displayName ?? user.displayName ?? '';
    if (nameToUse.isNotEmpty && user.displayName != nameToUse) {
      await user.updateDisplayName(nameToUse);
      await user.reload();
    }

    await _runUserPhoneTransaction(
      user: user,
      name: nameToUse,
      phoneE164: phoneE164,
      markAsSignup: markAsSignup,
    );
  }

  Future<void> finalizeEmailUser({
    required User user,
    String? displayName,
    bool markAsSignup = false,
  }) async {
    // Update Firebase Auth displayName if provided
    final nameToUse = displayName ?? user.displayName ?? '';
    if (nameToUse.isNotEmpty && user.displayName != nameToUse) {
      await user.updateDisplayName(nameToUse);
      await user.reload();
    }

    await _runUserEmailTransaction(
      user: user,
      name: nameToUse,
      markAsSignup: markAsSignup,
    );
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      throw 'Sign out failed: ${e.toString()}';
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Delete user document from Firestore
        await _firestore.collection('users').doc(user.uid).delete();

        // Delete the user account
        await user.delete();
      }
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to delete account: ${e.toString()}';
    }
  }

  // Update display name
  Future<void> updateDisplayName(String displayName) async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        await user.updateDisplayName(displayName);
        await user.reload();
      } else {
        throw Exception('No user is currently signed in');
      }
    } catch (e) {
      throw Exception('Failed to update display name: $e');
    }
  }

  // Update email
  Future<void> updateEmail(String email) async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        await user.verifyBeforeUpdateEmail(email);
        await user.reload();
      } else {
        throw Exception('No user is currently signed in');
      }
    } catch (e) {
      throw Exception('Failed to update email: $e');
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'The account already exists for that email.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many requests. Try again later.';
      case 'operation-not-allowed':
        return 'This operation is not allowed.';
      case 'invalid-credential':
        return 'The credential is invalid or expired.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with the same email but different sign-in credentials.';
      case 'requires-recent-login':
        return 'This operation requires recent authentication. Please sign in again.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      case 'app-not-authorized':
        return 'This app is not authorized to use Firebase Authentication. Add your debug/release SHA-1 and SHA-256 fingerprints in the Firebase console and download an updated google-services.json.';
      case 'missing-client-identifier':
        return 'Client identity is missing. Ensure your app SHA fingerprints are registered in Firebase and you are using the latest google-services.json.';
      case 'invalid-phone-number':
        return 'The phone number format is invalid. Please include the correct country code (e.g. +9715xxxxxxx).';
      case 'missing-phone-number':
        return 'Please enter a phone number before requesting a code.';
      case 'captcha-check-failed':
        return 'Device verification failed. Enable Play Integrity or reCAPTCHA for Phone Auth in the Firebase console and ensure the device has Google Play services.';
      case 'app-not-installed':
        return 'The verification flow requires Google Play services or the default SMS app. Please try on a physical device with Google Play services installed.';
      case 'session-expired':
        return 'The SMS code has expired. Please request a new code.';
      case 'invalid-verification-code':
        return 'The code you entered is incorrect or has expired. Please request a new OTP.';
      case 'invalid-verification-id':
        return 'The verification session has expired. Please request a fresh OTP.';
      case 'quota-exceeded':
        return 'The SMS quota has been exceeded for today. Add the phone number as a test number in Firebase or try again later.';
      case 'internal-error':
        return 'Firebase Auth encountered an internal error. Please try again in a moment.';
      default:
        return e.message ?? 'An unknown authentication error occurred.';
    }
  }
}
