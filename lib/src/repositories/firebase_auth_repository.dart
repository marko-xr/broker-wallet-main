import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/services/professional_email_service.dart';
import 'package:broker_wallet/src/services/offline_auth_service.dart';
import 'package:broker_wallet/src/services/quota_sync_service.dart';

/// Firebase implementation of AuthRepository
/// Contains all Firebase-specific authentication logic
class FirebaseAuthRepository implements AuthRepository {
  // Use lazy getter to avoid accessing Firebase before initialization
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  final UserRepository _userRepository;

  // Stream controller for manual auth state changes
  final StreamController<UserModel?> _authStateController =
      StreamController<UserModel?>.broadcast();

  FirebaseAuthRepository({required UserRepository userRepository})
      : _userRepository = userRepository {
    // Initialize the stream with Firebase auth changes
    _initializeAuthStream();
  }

  /// Initialize the auth state stream
  void _initializeAuthStream() {
    try {
      _auth.authStateChanges().listen((User? firebaseUser) async {
        UserModel? userModel;
        if (firebaseUser != null) {
          try {
            // Always reload to get latest verification status with timeout
            await firebaseUser.reload().timeout(
                  const Duration(seconds: 3),
                  onTimeout: () => null,
                );
            final refreshedUser = _auth.currentUser;

            // Get user data with timeout protection - don't block auth state
            try {
              userModel =
                  await _userRepository.getUserById(firebaseUser.uid).timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  // getUserById timed out during auth state change - using cached data (log removed)
                  return null;
                },
              );

              // Update user data with latest Firebase state if needed
              if (userModel != null && refreshedUser != null) {
                final updatedUser = UserModel(
                  uid: userModel.uid,
                  name: userModel.name,
                  email: userModel.email,
                  phoneNumber: userModel.phoneNumber,
                  profileImageUrl: userModel.profileImageUrl,
                  createdAt: userModel.createdAt,
                  lastLoginAt: userModel.lastLoginAt,
                  isEmailVerified: refreshedUser.emailVerified,
                  isPhoneVerified: userModel.isPhoneVerified,
                  subscription: userModel.subscription,
                  preferences: userModel.preferences,
                );
                if (updatedUser.isEmailVerified != userModel.isEmailVerified) {
                  // Update in background, don't block auth state
                  _userRepository.updateUser(updatedUser).catchError((e) {
                    // Failed to update user in background (log removed)
                  });
                  userModel = updatedUser;
                }

                // Cache the user model for offline access
                OfflineAuthService.instance
                    .cacheUserModel(userModel)
                    .catchError((e) {
                  // Failed to cache user model (log removed)
                });

                // 🔒 SECURITY: Sync quota counts from Firestore
                // This ensures quota limits cannot be bypassed by reinstalling the app
                QuotaSyncService().syncUserQuota().then((result) {
                  // Quota synced (log removed): ${result.counts}
                  if (result.sectionsAtLimit.isNotEmpty) {
                    // Sections at limit: ${result.sectionsAtLimit} (log removed)
                  }
                }).catchError((e) {
                  // Failed to sync quota (non-critical) (log removed)
                  // Don't block login if sync fails
                });
              }
            } catch (e) {
              // Failed to fetch user data during auth state change (log removed)
            }

            // If no user model from Firestore, try cached data first
            if (userModel == null && refreshedUser != null) {
              try {
                userModel =
                    await OfflineAuthService.instance.getCachedUserModel();
                if (userModel != null) {
                  // Using cached UserModel for offline access (log removed)
                  // Update email verification status from Firebase
                  if (userModel.isEmailVerified !=
                      refreshedUser.emailVerified) {
                    userModel = UserModel(
                      uid: userModel.uid,
                      name: userModel.name,
                      email: userModel.email,
                      phoneNumber: userModel.phoneNumber,
                      profileImageUrl: userModel.profileImageUrl,
                      createdAt: userModel.createdAt,
                      lastLoginAt: userModel.lastLoginAt,
                      isEmailVerified: refreshedUser.emailVerified,
                      isPhoneVerified: userModel.isPhoneVerified,
                      subscription: userModel.subscription,
                      preferences: userModel.preferences,
                    );
                  }
                }
              } catch (e) {
                // Failed to get cached user model (log removed)
              }
            }

            // CRITICAL: Always create a UserModel when Firebase user exists
            // This ensures offline users stay authenticated even without cache
            if (userModel == null && refreshedUser != null) {
              // Creating offline UserModel from Firebase Auth data (log removed)
              userModel = UserModel(
                uid: refreshedUser.uid,
                name: refreshedUser.displayName ?? '',
                email: refreshedUser.email ?? '',
                phoneNumber: refreshedUser.phoneNumber,
                profileImageUrl: refreshedUser.photoURL,
                createdAt: DateTime.now(),
                lastLoginAt: DateTime.now(),
                isEmailVerified: refreshedUser.emailVerified,
                isPhoneVerified: refreshedUser.phoneNumber != null,
                subscription: _createDefaultSubscription(),
                preferences: {},
              );
            }
          } catch (e) {
            // Auth state processing error (log removed)
            // Even if there's an error, try to create basic user model
            userModel = UserModel(
              uid: firebaseUser.uid,
              name: firebaseUser.displayName ?? '',
              email: firebaseUser.email ?? '',
              phoneNumber: firebaseUser.phoneNumber,
              profileImageUrl: firebaseUser.photoURL,
              createdAt: DateTime.now(),
              lastLoginAt: DateTime.now(),
              isEmailVerified: firebaseUser.emailVerified,
              isPhoneVerified: firebaseUser.phoneNumber != null,
              subscription: _createDefaultSubscription(),
              preferences: {},
            );
          }
        }
        _authStateController.add(userModel);
      });
    } catch (e) {
      // Failed to initialize auth stream (log removed)
      // In case of initialization failure, still provide a null state
      _authStateController.add(null);
    }
  }

  /// Create a default subscription for new users
  UserSubscription _createDefaultSubscription() {
    return UserSubscription(
      plan: 'free',
      isActive: true,
      features: ['basic_listing'],
    );
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

  @override
  Stream<UserModel?> get authStateChanges => _authStateController.stream;

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  UserModel? get currentUser {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;

    // Note: This is synchronous, so we can't fetch from repository here
    // The UI should use authStateChanges stream for complete user data
    return UserModel(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName ?? '',
      email: firebaseUser.email ?? '',
      phoneNumber: firebaseUser.phoneNumber,
      profileImageUrl: firebaseUser.photoURL,
      createdAt: DateTime
          .now(), // We'd need to fetch from repository for accurate data
      lastLoginAt: DateTime.now(),
      isEmailVerified: firebaseUser.emailVerified,
      isPhoneVerified: firebaseUser.phoneNumber != null,
      subscription: _createDefaultSubscription(),
      preferences: {},
    );
  }

  @override
  Future<UserModel> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await result.user?.updateDisplayName(name);

      // Create UserModel
      final userModel = UserModel(
        uid: result.user!.uid,
        name: name,
        email: email,
        phoneNumber: phoneNumber,
        profileImageUrl: null,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        isEmailVerified: false,
        isPhoneVerified: false,
        subscription: UserSubscription(
          plan: 'free',
          isActive: true,
          features: ['basic_listing'],
        ),
        preferences: {},
      );

      // Create user document in repository
      await _userRepository.createUser(userModel);

      // Send email verification
      await sendEmailVerification();

      return userModel;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to sign up: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last login time
      final userModel = await _userRepository.getUserById(result.user!.uid);
      if (userModel != null) {
        final updatedUser = UserModel(
          uid: userModel.uid,
          name: userModel.name,
          email: userModel.email,
          phoneNumber: userModel.phoneNumber,
          profileImageUrl: userModel.profileImageUrl,
          createdAt: userModel.createdAt,
          lastLoginAt: DateTime.now(),
          isEmailVerified: result.user!.emailVerified,
          isPhoneVerified: userModel.isPhoneVerified,
          subscription: userModel.subscription,
          preferences: userModel.preferences,
        );

        await _userRepository.updateUser(updatedUser);
        return updatedUser;
      }

      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'User data not found.',
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to sign in: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw Exception('Google sign in cancelled');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);

      // Check if user exists, if not create new user
      UserModel? existingUser =
          await _userRepository.getUserById(result.user!.uid);

      if (existingUser == null) {
        final userModel = UserModel(
          uid: result.user!.uid,
          name: result.user!.displayName ?? '',
          email: result.user!.email ?? '',
          phoneNumber: result.user!.phoneNumber,
          profileImageUrl: result.user!.photoURL,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          isEmailVerified: result.user!.emailVerified,
          isPhoneVerified: false,
          subscription: _createDefaultSubscription(),
          preferences: {},
        );

        await _userRepository.createUser(userModel);
        return userModel;
      } else {
        // Update last login
        final updatedUser = UserModel(
          uid: existingUser.uid,
          name: existingUser.name,
          email: existingUser.email,
          phoneNumber: existingUser.phoneNumber,
          profileImageUrl: existingUser.profileImageUrl,
          createdAt: existingUser.createdAt,
          lastLoginAt: DateTime.now(),
          isEmailVerified: result.user!.emailVerified,
          isPhoneVerified: existingUser.isPhoneVerified,
          subscription: existingUser.subscription,
          preferences: existingUser.preferences,
        );

        await _userRepository.updateUser(updatedUser);
        return updatedUser;
      }
    } catch (e) {
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  @override
  Future<UserModel> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login();

      if (result.status != LoginStatus.success) {
        throw Exception('Facebook sign in failed');
      }

      final OAuthCredential facebookAuthCredential =
          FacebookAuthProvider.credential(result.accessToken!.tokenString);

      UserCredential userCredential =
          await _auth.signInWithCredential(facebookAuthCredential);

      // Similar logic as Google sign in...
      UserModel? existingUser =
          await _userRepository.getUserById(userCredential.user!.uid);

      if (existingUser == null) {
        final userModel = UserModel(
          uid: userCredential.user!.uid,
          name: userCredential.user!.displayName ?? '',
          email: userCredential.user!.email ?? '',
          phoneNumber: userCredential.user!.phoneNumber,
          profileImageUrl: userCredential.user!.photoURL,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          isEmailVerified: userCredential.user!.emailVerified,
          isPhoneVerified: false,
          subscription: _createDefaultSubscription(),
          preferences: {},
        );

        await _userRepository.createUser(userModel);
        return userModel;
      } else {
        final updatedUser = UserModel(
          uid: existingUser.uid,
          name: existingUser.name,
          email: existingUser.email,
          phoneNumber: existingUser.phoneNumber,
          profileImageUrl: existingUser.profileImageUrl,
          createdAt: existingUser.createdAt,
          lastLoginAt: DateTime.now(),
          isEmailVerified: userCredential.user!.emailVerified,
          isPhoneVerified: existingUser.isPhoneVerified,
          subscription: existingUser.subscription,
          preferences: existingUser.preferences,
        );

        await _userRepository.updateUser(updatedUser);
        return updatedUser;
      }
    } catch (e) {
      throw Exception('Failed to sign in with Facebook: $e');
    }
  }

  @override
  Future<void> sendEmailVerification({String? email}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'No user signed in.',
      );
    }

    try {
      await ProfessionalEmailService.sendProfessionalVerificationEmail(user);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to send email verification: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    await user.reload();
    final isVerified = _auth.currentUser?.emailVerified ?? false;

    // If email is verified, trigger auth state update
    if (isVerified) {
      await _triggerAuthStateUpdate();
    }

    return isVerified;
  }

  @override
  Future<UserModel?> reloadUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) return null;

      final isVerified = refreshedUser.emailVerified;
      final profile = await _userRepository.getUserById(refreshedUser.uid);
      if (profile != null) {
        if (profile.isEmailVerified != isVerified) {
          final updated = profile.copyWith(isEmailVerified: isVerified);
          await _userRepository.updateUser(updated);
          return updated;
        }
        return profile;
      }
      return UserModel(
        uid: refreshedUser.uid,
        name: refreshedUser.displayName ?? '',
        email: refreshedUser.email ?? '',
        phoneNumber: refreshedUser.phoneNumber,
        createdAt: DateTime.now(),
        isEmailVerified: refreshedUser.emailVerified,
        subscription: UserSubscription(
          plan: 'free',
          isActive: true,
          features: [],
        ),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to reload user: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<bool> checkEmailVerificationAndUpdate() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      // Reload user to get latest verification status from Firebase
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        // User session lost after reload (log removed)
        return false;
      }

      final isVerified = refreshedUser.emailVerified;

      if (!isVerified) {
        // Email not yet verified in Firebase Auth (log removed)
        return false;
      }

      // Email is verified in Firebase Auth, update Firestore (log removed)

      // Validate UID before Firestore operation
      if (refreshedUser.uid.isEmpty) {
        // Fatal error: Firebase user UID is empty after reload (log removed)
        return false;
      }

      // Get current user data from Firestore
      final userModel = await _userRepository.getUserById(refreshedUser.uid);

      if (userModel != null) {
        // Only update if not already marked as verified
        if (!userModel.isEmailVerified) {
          final updatedUser = userModel.copyWith(
            isEmailVerified: true,
            lastLoginAt: DateTime.now(),
          );

          await _userRepository.updateUser(updatedUser);
          await OfflineAuthService.instance.cacheUserModel(updatedUser);
          _authStateController.add(updatedUser);
        } else {
          // Firestore already shows email as verified (log removed)
        }
      } else {
        // User document not found in Firestore (log removed)
      }

      return true;
    } catch (e) {
      // Error checking email verification (log removed)
      return false;
    }
  }

  /// Manually trigger an auth state update
  /// This is useful when Firebase auth state doesn't automatically trigger
  /// (like when email verification status changes)
  Future<void> _triggerAuthStateUpdate() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      _authStateController.add(null);
      return;
    }

    await firebaseUser.reload();
    final refreshedUser = _auth.currentUser;

    if (refreshedUser != null) {
      final userModel = await _userRepository.getUserById(refreshedUser.uid);

      if (userModel != null) {
        final updatedUser = UserModel(
          uid: userModel.uid,
          name: userModel.name,
          email: userModel.email,
          phoneNumber: userModel.phoneNumber,
          profileImageUrl: userModel.profileImageUrl,
          createdAt: userModel.createdAt,
          lastLoginAt: userModel.lastLoginAt,
          isEmailVerified: refreshedUser.emailVerified,
          isPhoneVerified: userModel.isPhoneVerified,
          subscription: userModel.subscription,
          preferences: userModel.preferences,
        );

        // Update repository and trigger stream
        await _userRepository.updateUser(updatedUser);
        _authStateController.add(updatedUser);
        // Auth state manually updated - emailVerified (log removed)
      }
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Failed to send password reset email: $e',
        originalException: e,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // Repository: Starting sign out process (log removed)

      // Clear offline auth cache first
      try {
        await OfflineAuthService.instance.clearAuthCache();
        // Repository: Offline auth cache cleared (log removed)
      } catch (e) {
        // Repository: Failed to clear auth cache (log removed)
      }

      // Always prioritize Firebase sign out
      await _auth.signOut();
      // Repository: Firebase sign out completed (log removed)

      // Google sign out (handle gracefully)
      try {
        await _googleSignIn.signOut();
        // Repository: Google sign out completed (log removed)
      } catch (e) {
        // Repository: Google sign out error (continuing) (log removed)
      }

      // Facebook sign out (handle gracefully)
      try {
        await FacebookAuth.instance.logOut();
        // Repository: Facebook sign out completed (log removed)
      } catch (e) {
        // Repository: Facebook sign out error (continuing) (log removed)
        if (e.toString().contains('MissingPluginException')) {
          // Repository: Facebook Auth plugin not properly initialized - continuing with logout (log removed)
        }
      }
      // Repository: Sign out process completed successfully (log removed)
    } catch (e) {
      // Only throw if Firebase sign out fails, as that's critical
      if (e.toString().contains('Firebase') || e.toString().contains('_auth')) {
        throw Exception('Failed to sign out from Firebase: $e');
      } else {
        // For other errors, log but don't throw
        // Repository: Non-critical sign out error (log removed)
      }
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      // Delete user data from repository first
      await _userRepository.deleteUser(user.uid);

      // Then delete Firebase Auth account
      await user.delete();
    } catch (e) {
      throw Exception('Failed to delete account: $e');
    }
  }

  @override
  Future<void> updateUserProfile({
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      // Update Firebase Auth profile
      if (name != null) {
        await user.updateDisplayName(name);
      }
      if (profileImageUrl != null) {
        await user.updatePhotoURL(profileImageUrl);
      }

      // Update user data in repository
      final existingUser = await _userRepository.getUserById(user.uid);
      if (existingUser != null) {
        final now = DateTime.now();
        final updatedUser = existingUser.copyWith(
          name: name,
          phoneNumber: phoneNumber,
          profileImageUrl: profileImageUrl,
          lastLoginAt: now,
        );

        await _userRepository.updateUser(updatedUser);

        // Keep offline cache and auth stream in sync for immediate UI updates
        OfflineAuthService.instance.cacheUserModel(updatedUser).catchError((e) {
          // Log removed
        });

        _authStateController.add(updatedUser);
      }
    } catch (e) {
      throw Exception('Failed to update user profile: $e');
    }
  }

  @override
  Future<void> updateEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      // Re-authenticate user with current password first
      final email = user.email;
      if (email == null) throw Exception('Current user email not available');

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      // Re-authenticating user for email update (log removed)
      await user.reauthenticateWithCredential(credential);
      // Re-authentication successful (log removed)

      // Update email in Firebase Auth
      // Updating email to: $newEmail (log removed)
      await user.verifyBeforeUpdateEmail(newEmail);
      // Email update initiated - verification email sent (log removed)

      // Note: We don't update the user model here because the email change
      // won't be complete until the user verifies the new email.
      // The auth state will be updated automatically when verification completes.
    } on FirebaseAuthException catch (e) {
      // Firebase auth error during email update (log removed)

      switch (e.code) {
        case 'wrong-password':
          throw Exception('Current password is incorrect');
        case 'email-already-in-use':
          throw Exception(
              'This email is already associated with another account');
        case 'invalid-email':
          throw Exception('Please enter a valid email address');
        case 'requires-recent-login':
          throw Exception(
              'For security, please sign out and sign in again before changing your email');
        case 'too-many-requests':
          throw Exception('Too many attempts. Please try again later');
        default:
          throw Exception('Failed to update email: ${e.message}');
      }
    } catch (e) {
      // General error during email update (log removed)
      throw Exception('Failed to update email: $e');
    }
  }

  @override
  Future<void> addEmailToAccount({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    try {
      final normalizedEmail = email.trim().toLowerCase();
      // Linking email $normalizedEmail to current account (uid: ${user.uid}) (log removed)

      // Check if email is already in use
      final methods = await _fetchSignInMethodsForEmail(normalizedEmail);
      if (methods.isNotEmpty) {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'This email is already associated with another account',
        );
      }

      // Create email credential
      final credential = EmailAuthProvider.credential(
        email: normalizedEmail,
        password: password,
      );

      // Link credential to current user
      final credentialResult = await user.linkWithCredential(credential);
      final linkedUser = credentialResult.user;
      if (linkedUser == null) {
        throw Exception('Failed to link email credential');
      }

      // Reload to get latest state
      await linkedUser.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        throw Exception('User session lost after linking');
      }

      // Email credential linked. Updating Firestore... (log removed)

      // Update Firestore in a transaction to maintain consistency
      final firestore = FirebaseFirestore.instance;
      await firestore.runTransaction((transaction) async {
        // Update user document
        final userRef = firestore.collection('users').doc(refreshedUser.uid);
        final userDoc = await transaction.get(userRef);

        if (userDoc.exists) {
          // Update existing user with email
          transaction.update(userRef, {
            'email': normalizedEmail,
            'isEmailVerified': refreshedUser.emailVerified,
            'lastLoginAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Create new user document if it doesn't exist
          transaction.set(userRef, {
            'uid': refreshedUser.uid,
            'name': refreshedUser.displayName ?? '',
            'email': normalizedEmail,
            'phoneNumber': refreshedUser.phoneNumber,
            'phoneE164': refreshedUser.phoneNumber,
            'profileImageUrl': refreshedUser.photoURL,
            'isEmailVerified': refreshedUser.emailVerified,
            'isPhoneVerified': refreshedUser.phoneNumber != null,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
            'subscription': _createDefaultSubscription().toMap(),
            'preferences': {},
          });
        }

        // Create email_lookup document
        final emailLookupRef =
            firestore.collection('email_lookup').doc(normalizedEmail);
        transaction.set(emailLookupRef, {
          'userId': refreshedUser.uid,
          'email': normalizedEmail,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      // Firestore updated successfully (log removed)

      // Sending verification email (log removed)
      await ProfessionalEmailService.sendProfessionalVerificationEmail(
        refreshedUser,
      );
      // Triggering auth state update (log removed)
      // Let Firebase auth state listener handle the update naturally
      // Just reload the user to trigger the stream
      await refreshedUser.reload();

      // Fetch and cache the updated user data
      try {
        final updatedUser =
            await _userRepository.getUserById(refreshedUser.uid).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            // getUserById timed out - auth state will update via listener (log removed)
            return null;
          },
        );

        if (updatedUser != null) {
          await OfflineAuthService.instance.cacheUserModel(updatedUser);
          _authStateController.add(updatedUser);
          // Email added successfully and cache updated (log removed)
        } else {
          // Email added successfully (cache update pending) (log removed)
        }
      } catch (e) {
        // Cache update failed but email was added successfully (log removed)
        // Don't throw - the email was added successfully
      }
    } on FirebaseAuthException catch (e) {
      // Firebase auth error during email link (log removed)

      switch (e.code) {
        case 'email-already-in-use':
        case 'credential-already-in-use':
          throw Exception(
              'This email is already associated with another account');
        case 'invalid-email':
          throw Exception('Please enter a valid email address');
        case 'weak-password':
          throw Exception(
              'Password is too weak. Please choose a stronger password');
        case 'requires-recent-login':
          throw Exception(
              'For security, please sign out and sign in again before linking this email');
        case 'provider-already-linked':
          throw Exception('An email/password login is already linked');
        default:
          throw Exception('Failed to add email: ${e.message ?? e.code}');
      }
    } catch (e) {
      // General error during email link (log removed)
      throw Exception('Failed to add email: $e');
    }
  }

  @override
  Future<void> sendPhoneVerificationOTP({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    try {
      // Sending phone verification OTP to: $phoneNumber (log removed)

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification completed (usually on Android)
          // Phone number auto-verified (log removed)
          try {
            // Add delay to allow UI to stabilize
            await Future.delayed(const Duration(milliseconds: 500));
            await _linkPhoneCredential(credential);
            // Auto-verification linking completed (log removed)
          } catch (e) {
            // Auto-verification failed (log removed)
            onError('Auto-verification failed');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          // Phone verification failed (log removed)

          switch (e.code) {
            case 'invalid-phone-number':
              onError('Invalid phone number format');
              break;
            case 'too-many-requests':
              onError('Too many verification attempts. Please try again later');
              break;
            case 'quota-exceeded':
              onError('SMS quota exceeded. Please try again later');
              break;
            default:
              onError('Phone verification failed: ${e.message}');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          // OTP sent successfully. Verification ID: $verificationId (log removed)
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Auto-retrieval timeout for verification ID (log removed)
          // Don't treat timeout as an error - this is normal behavior
          // The verification ID is still valid for manual OTP entry
        },
        timeout: const Duration(seconds: 120), // Increased timeout
      );
    } catch (e) {
      // General error during phone verification (log removed)
      onError('Failed to send verification code: $e');
    }
  }

  @override
  Future<void> verifyPhoneNumber({
    required String verificationId,
    required String otpCode,
  }) async {
    try {
      // Verifying phone number with OTP (log removed)

      // Create phone credential
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otpCode,
      );

      await _linkPhoneCredential(credential);
    } on FirebaseAuthException catch (e) {
      // Firebase auth error during phone verification (log removed)

      switch (e.code) {
        case 'invalid-verification-code':
          throw Exception(
              'Invalid verification code. Please check and try again');
        case 'invalid-verification-id':
        case 'session-expired':
          throw Exception(
              'Verification session expired. Please request a new code');
        case 'credential-already-in-use':
          throw Exception(
              'This phone number is already linked to another account');
        case 'provider-already-linked':
          throw Exception('A phone number is already linked to this account');
        case 'too-many-requests':
          throw Exception('Too many attempts. Please try again later');
        default:
          throw Exception('Phone verification failed: ${e.message}');
      }
    } catch (e) {
      // General error during phone verification (log removed)
      throw Exception('Phone verification failed: $e');
    }
  }

  /// Helper method to link phone credential
  Future<void> _linkPhoneCredential(PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    // Link the phone credential to existing account
    final userCredential = await user.linkWithCredential(credential);
    // Phone number linked successfully (log removed)

    // Update user data in repository with transaction (like email linking)
    final updatedUser = userCredential.user;
    if (updatedUser != null && updatedUser.phoneNumber != null) {
      final firestore = FirebaseFirestore.instance;

      // Use transaction to ensure both user and phone_lookup are updated atomically
      await firestore.runTransaction((transaction) async {
        // Update user document
        final userRef = firestore.collection('users').doc(updatedUser.uid);
        final userDoc = await transaction.get(userRef);

        if (userDoc.exists) {
          // Update existing user with phone
          transaction.update(userRef, {
            'phoneNumber': updatedUser.phoneNumber,
            'phoneE164': updatedUser.phoneNumber,
            'isPhoneVerified': true,
            'lastLoginAt': FieldValue.serverTimestamp(),
          });
        } else {
          // This should not happen in phone linking, but handle it just in case
          final existingUser =
              await _userRepository.getUserById(updatedUser.uid);
          if (existingUser != null) {
            transaction.set(userRef, {
              'uid': updatedUser.uid,
              'name': existingUser.name,
              'email': existingUser.email,
              'phoneNumber': updatedUser.phoneNumber,
              'phoneE164': updatedUser.phoneNumber,
              'profileImageUrl': existingUser.profileImageUrl,
              'isEmailVerified': existingUser.isEmailVerified,
              'isPhoneVerified': true,
              'createdAt': FieldValue.serverTimestamp(),
              'lastLoginAt': FieldValue.serverTimestamp(),
              'subscription': existingUser.subscription.toMap(),
              'preferences': existingUser.preferences,
            });
          }
        }

        // Create phone_lookup document
        final phoneLookupRef =
            firestore.collection('phone_lookup').doc(updatedUser.phoneNumber!);
        transaction.set(phoneLookupRef, {
          'userId': updatedUser.uid,
          'phoneE164': updatedUser.phoneNumber,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      // Firestore updated with phone linking (log removed)

      // Trigger auth state update to refresh cached data
      await updatedUser.reload();

      // Update cached user data
      try {
        final refreshedUserModel =
            await _userRepository.getUserById(updatedUser.uid);
        if (refreshedUserModel != null) {
          await OfflineAuthService.instance.cacheUserModel(refreshedUserModel);
          _authStateController.add(refreshedUserModel);
          // Phone linked successfully and cache updated (log removed)
        }
      } catch (e) {
        // Cache update failed but phone was linked successfully (log removed)
      }
    }
  }

  @override
  Future<UserModel?> getUserProfile(String uid) async {
    return await _userRepository.getUserById(uid);
  }

  /// Clean up resources
  void dispose() {
    _authStateController.close();
  }
}
