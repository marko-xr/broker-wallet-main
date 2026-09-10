import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/media_upload_service_compat.dart';
import 'package:broker_wallet/src/services/fast_profile_upload_service.dart';
import 'package:broker_wallet/src/services/r2_profile_upload_service.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';

class EditProfileViewModel extends ChangeNotifier {
  final ThemeViewModel themeVM;
  final LocaleViewModel localeVM;
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  R2ProfileUploadService? _r2ProfileUploadService;

  String _name;
  String _email;
  String _phone;
  bool _isLoading = false;
  String? _uploadProgress;
  double _uploadPercentage = 0.0;

  EditProfileViewModel({
    required this.themeVM,
    required this.localeVM,
    required String name,
    required String email,
    required String phone,
    UserRepository? userRepository,
    AuthRepository? authRepository,
    R2ProfileUploadService? r2ProfileUploadService,
  })  : _name = name,
        _email = email,
        _phone = phone,
        _userRepository =
            userRepository ?? RepositoryProvider.instance.userRepository,
        _authRepository =
            authRepository ?? RepositoryProvider.instance.authRepository,
        _r2ProfileUploadService = r2ProfileUploadService;

  // Getters
  String get name => _name;
  String get email => _email;
  String get phone => _phone;
  bool get isLoading => _isLoading;
  String? get uploadProgress => _uploadProgress;
  double get uploadPercentage => _uploadPercentage;

  // Setters
  set name(String value) {
    _name = value;
    notifyListeners();
  }

  set email(String value) {
    _email = value;
    notifyListeners();
  }

  set phone(String value) {
    _phone = value;
    notifyListeners();
  }

  Future<String?> uploadProfileImage(XFile imageFile) async {
    try {
      _uploadProgress = "Preparing upload...";
      _uploadPercentage = 0.0;
      notifyListeners();

      final downloadURL = SupabaseConfig.useSupabaseAuth
          ? await _uploadProfileImageThroughR2(imageFile)
          : await _mediaUploadService.uploadProfileImage(
              imageFile,
              onProgress: (progress) {
                _uploadPercentage = progress;
                _uploadProgress = "Uploading... ${(progress * 100).toInt()}%";
                notifyListeners();
              },
            );

      _uploadProgress = "Upload complete!";
      _uploadPercentage = 1.0;
      notifyListeners();

      // Clear progress after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        _uploadProgress = null;
        _uploadPercentage = 0.0;
        notifyListeners();
      });

      return downloadURL;
    } catch (e) {
      _uploadProgress = null;
      _uploadPercentage = 0.0;
      notifyListeners();
      // Debug log suppressed: Error uploading profile image: $e

      // Re-throw with user-friendly message
      if (e.toString().contains('unauthorized')) {
        throw Exception(
            'Permission denied. Please check your account permissions.');
      } else if (e.toString().contains('network')) {
        throw Exception(
            'Network error. Please check your internet connection.');
      } else {
        throw Exception('Upload failed. Please try again.');
      }
    }
  }

  /// Fast upload profile image - saves immediately and uploads in background
  Future<String?> uploadProfileImageFast(XFile imageFile) async {
    try {
      // No progress indicators needed - the UI will handle the overlay
      final currentUser = _authRepository.currentUser;
      if (currentUser == null) {
        throw Exception('You must be signed in to update your profile');
      }

      // Supabase profile media is confirmed by the Worker. Do not route this
      // mode through the Firebase/Firestore background-upload path.
      if (SupabaseConfig.useSupabaseAuth) {
        return await _uploadProfileImageThroughR2(imageFile);
      }

      // Prepare user data for fast save (serialize complex objects for Firestore)
      final userData = {
        'name': _name.trim(),
        'email': _email.trim(),
        'phoneNumber': _formatPhoneNumber(),
        'createdAt': currentUser.createdAt,
        'lastLoginAt': DateTime.now(),
        'isEmailVerified': currentUser.isEmailVerified,
        'isPhoneVerified': currentUser.isPhoneVerified,
        'subscription':
            currentUser.subscription.toMap(), // Serialize to Map for Firestore
        'preferences': currentUser.preferences,
      };

      // Use fast profile upload service for immediate save + background upload
      final tempUrl = await FastProfileUploadService().saveProfileImageFast(
        imageFile: imageFile,
        userData: userData,
      );

      // Return immediately - no artificial delays
      return tempUrl;
    } catch (e) {
      // Debug log suppressed: Error with fast profile upload: $e

      // Re-throw with user-friendly message
      if (e.toString().contains('unauthorized')) {
        throw Exception(
            'Permission denied. Please check your account permissions.');
      } else if (e.toString().contains('network')) {
        throw Exception('Network error. Saved locally, will sync when online.');
      } else {
        throw Exception('Upload failed. Please try again.');
      }
    }
  }

  MediaUploadServiceCompat get _mediaUploadService =>
      MediaUploadServiceCompat();

  R2ProfileUploadService get _r2ProfileUploadServiceOrCreate =>
      _r2ProfileUploadService ??= R2ProfileUploadService();

  Future<String?> _uploadProfileImageThroughR2(XFile imageFile) async {
    await _r2ProfileUploadServiceOrCreate.uploadProfileImage(
      imageFile: imageFile,
    );

    // This re-reads the canonical profile after Worker confirmation so the
    // signed read URL is resolved through the existing repository flow.
    final refreshedUser = await _authRepository.reloadUser();
    return refreshedUser?.profileImageUrl;
  }

  /// Format phone number for storage
  String _formatPhoneNumber() {
    String formattedPhone = _phone.trim();
    if (formattedPhone.isNotEmpty && !formattedPhone.startsWith('+')) {
      // Add UAE country code if not present
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '+971${formattedPhone.substring(1)}';
      } else if (formattedPhone.length == 9) {
        formattedPhone = '+971$formattedPhone';
      } else {
        formattedPhone = '+971$formattedPhone';
      }
    }
    return formattedPhone;
  }

  /// Update user's email with password verification
  Future<void> updateEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    try {
      await _authRepository.updateEmail(
        newEmail: newEmail,
        currentPassword: currentPassword,
      );

      // Update local email value for UI consistency
      _email = newEmail;
      notifyListeners();
    } catch (e) {
      // Debug log suppressed: Error updating email: $e
      rethrow;
    }
  }

  Future<void> saveChanges({XFile? profileImage}) async {
    // Debug log suppressed: PROFILE SAVE PROCESS STARTED
    // No loading state needed - the view handles the overlay

    try {
      final currentUser = _authRepository.currentUser;
      if (currentUser == null) {
        throw Exception('You must be signed in to update your profile');
      }

      // Debug log suppressed: Current user ID: ${currentUser.uid}
      // Debug log suppressed: Current user email: ${currentUser.email}
      // Debug log suppressed: Profile image selected: ${profileImage != null}

      String? profileImageUrl;

      // Upload profile image before saving profile fields. In Supabase mode
      // the Worker owns confirmation and profile_media_id linking.
      if (profileImage != null) {
        if (SupabaseConfig.useSupabaseAuth) {
          await _uploadProfileImageThroughR2(profileImage);
        } else {
          profileImageUrl = await uploadProfileImageFast(profileImage);
        }
      }

      // Format phone number for storage
      String formattedPhone = _formatPhoneNumber();

      // Debug log suppressed: Formatted phone: $formattedPhone

      final sanitizedName = _name.trim();
      final sanitizedPhone = formattedPhone.isEmpty ? null : formattedPhone;
      // Supabase profiles link media by ID in the Worker, never by a signed
      // URL. Firebase mode keeps its legacy URL-based save behavior.
      final resolvedImageUrl = SupabaseConfig.useSupabaseAuth
          ? null
          : profileImageUrl ?? currentUser.profileImageUrl;

      // Debug log suppressed: User model created, updating via auth repository...
      // Debug log suppressed: Updated user data (preview): {uid: ${currentUser.uid}, name: $sanitizedName, email: ${_email.trim()}, phoneNumber: $sanitizedPhone, profileImageUrl: $resolvedImageUrl}

      await _authRepository.updateUserProfile(
        name: sanitizedName,
        phoneNumber: sanitizedPhone,
        profileImageUrl: resolvedImageUrl,
      );
      // Debug log suppressed: User updated successfully via auth repository

      // Debug log suppressed: PROFILE SAVE PROCESS COMPLETED SUCCESSFULLY
    } catch (e) {
      // Debug log suppressed: PROFILE SAVE ERROR
      // Debug log suppressed: Error saving profile changes: $e
      // Debug log suppressed: Error type: ${e.runtimeType}
      rethrow;
    }
  }

  /// Add email to account (for phone-only accounts)
  Future<void> addEmailToAccount({
    required String email,
    required String password,
  }) async {
    try {
      await _authRepository.addEmailToAccount(
        email: email,
        password: password,
      );

      // Update local email value for UI consistency
      _email = email;
      notifyListeners();
    } catch (e) {
      // Debug log suppressed: Error adding email to account: $e
      rethrow;
    }
  }

  /// Send phone verification OTP
  Future<String> sendPhoneVerificationOTP({
    required String phoneNumber,
  }) async {
    final completer = Completer<String>();

    try {
      await _authRepository.sendPhoneVerificationOTP(
        phoneNumber: phoneNumber,
        onCodeSent: (verificationId) {
          completer.complete(verificationId);
        },
        onError: (error) {
          completer.completeError(Exception(error));
        },
      );

      return await completer.future;
    } catch (e) {
      // Debug log suppressed: Error sending phone verification OTP: $e
      rethrow;
    }
  }

  /// Verify phone number with OTP
  Future<void> verifyPhoneNumber({
    required String verificationId,
    required String otpCode,
  }) async {
    try {
      await _authRepository.verifyPhoneNumber(
        verificationId: verificationId,
        otpCode: otpCode,
      );

      // Phone number will be updated by auth state changes
      notifyListeners();
    } catch (e) {
      // Debug log suppressed: Error verifying phone number: $e
      rethrow;
    }
  }
}
