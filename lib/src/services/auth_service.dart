import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';

class AuthService {
  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _phoneLookupCollection =>
      _firestore.collection('phone_lookup');

  // Normalize a UAE phone number to E.164 format used by Firebase
  String _normalizePhoneNumber(String phoneNumber) {
    final normalized = PhoneInputService.toInternationalFormat(phoneNumber);
    return normalized.startsWith('+') ? normalized : '+$normalized';
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
