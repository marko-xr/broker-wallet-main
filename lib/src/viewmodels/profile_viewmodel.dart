import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:broker_wallet/src/Views/Widgets/logout_confirmation_bottom_sheet.dart';
import 'package:broker_wallet/src/services/fast_profile_upload_service.dart';
import 'package:broker_wallet/src/services/auth_service.dart';
import 'package:broker_wallet/src/services/notification_service.dart';
import 'package:broker_wallet/src/common/utils/phone_utils.dart';
import 'package:broker_wallet/src/common/utils/email_validator.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';
import 'dart:async';

class ProfileViewModel extends ChangeNotifier {
  final ThemeViewModel themeVM;
  final LocaleViewModel localeVM;
  final BuildContext context;
  final AuthViewModel authVM;
  final UserRepository _userRepository =
      RepositoryProvider.instance.userRepository;
  final AuthService _authService = AuthService();

  bool _notificationsEnabled = false;
  UserModel? _currentUser;
  bool _isLoading = true;
  bool _disposed = false;
  bool _isLinkingEmail = false;
  bool _isLinkingPhone = false;
  bool _isLoggingOut = false;
  StreamSubscription<ProfileUploadCompletedEvent>?
      _uploadCompletionSubscription;
  StreamSubscription<UserModel?>? _userStreamSubscription;

  ProfileViewModel({
    required this.themeVM,
    required this.localeVM,
    required this.context,
    required this.authVM,
  }) {
    authVM.addListener(_handleAuthViewModelChanged);
    _initializeUser();
    _setupUploadCompletionListener();
  }

  void _handleAuthViewModelChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  void _subscribeToUserStream(String uid) {
    _userStreamSubscription?.cancel();

    _userStreamSubscription =
        _userRepository.getUserStream(uid).listen((userModel) {
      if (_disposed || userModel == null) {
        return;
      }

      _currentUser = userModel;
      _notificationsEnabled =
          userModel.preferences['notificationsEnabled'] as bool? ?? true;
      _isLoading = false;
      notifyListeners();
    }, onError: (error) {
      // Debug log suppressed: Failed to listen to user stream: $error
    });
  }

  void _setupUploadCompletionListener() {
    _uploadCompletionSubscription =
        FastProfileUploadService.onUploadCompleted.listen((event) async {
      // Debug log suppressed: Profile upload completed in ProfileViewModel, refreshing user data...

      if (!_disposed) {
        // Refresh user data from repository
        await _refreshUserData();

        if (context.mounted) {
          Fluttertoast.showToast(
            msg: 'Profile image updated successfully!',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        }
      }
    });
  }

  Future<void> _refreshUserData() async {
    try {
      if (authVM.currentUser?.uid != null) {
        final updatedUser =
            await _userRepository.getUserById(authVM.currentUser!.uid);
        if (updatedUser != null && !_disposed) {
          _currentUser = updatedUser;
          notifyListeners();
          // Debug log suppressed: User data refreshed with new profile image
        }
      }
    } catch (e) {
      // Debug log suppressed: Failed to refresh user data: $e
    }
  }

  // Getters
  bool get notificationsEnabled => _notificationsEnabled;
  bool get isLoading => _isLoading;
  UserModel? get currentUser => _currentUser;
  String get displayName {
    final authDisplayName = authVM.displayName.trim();
    if (authDisplayName.isNotEmpty) {
      return authDisplayName;
    }

    final primaryName = _currentUser?.name.trim() ?? '';
    if (primaryName.isNotEmpty) {
      return primaryName;
    }

    final emailCandidates = <String?>[
      _currentUser?.email,
      authVM.currentUser?.email,
    ];
    for (final email in emailCandidates) {
      if (email == null) continue;
      final trimmed = email.trim();
      if (trimmed.isEmpty) continue;
      final atIndex = trimmed.indexOf('@');
      if (atIndex > 0) {
        return trimmed.substring(0, atIndex);
      }
      return trimmed;
    }

    final phoneCandidates = <String?>[
      _currentUser?.phoneNumber,
      authVM.currentUser?.phoneNumber,
    ];
    for (final phone in phoneCandidates) {
      if (phone == null) continue;
      final trimmedPhone = phone.trim();
      if (trimmedPhone.isNotEmpty) {
        return trimmedPhone;
      }
    }

    return '';
  }

  bool get isSubscribed => _currentUser?.subscription.isActive ?? false;
  bool get isLinkingEmail => _isLinkingEmail;
  bool get isLinkingPhone => _isLinkingPhone;
  bool get isLoggingOut => _isLoggingOut;
  bool get hasLinkedEmail =>
      ((_currentUser?.email ?? '').isNotEmpty) ||
      ((authVM.currentUser?.email ?? '').isNotEmpty);
  bool get isEmailVerified =>
      _currentUser?.isEmailVerified ??
      (authVM.currentUser?.isEmailVerified ?? false);
  bool get hasLinkedPhone =>
      ((_currentUser?.phoneNumber ?? '').isNotEmpty) ||
      ((authVM.currentUser?.phoneNumber ?? '').isNotEmpty);
  bool get isPhoneVerified =>
      _currentUser?.isPhoneVerified ??
      (authVM.currentUser?.isPhoneVerified ?? false);

  @override
  void dispose() {
    _disposed = true;
    authVM.removeListener(_handleAuthViewModelChanged);
    _uploadCompletionSubscription?.cancel();
    _userStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  void _initializeUser() async {
    try {
      if (authVM.currentUser != null) {
        try {
          if (authVM.currentUser?.uid != null) {
            _subscribeToUserStream(authVM.currentUser!.uid);
          }
        } catch (e) {
          // If repository fails, use current user from auth
          _currentUser = authVM.currentUser;
          // Try to create user in repository
          if (_currentUser != null) {
            try {
              await _userRepository.createUser(_currentUser!);
              _subscribeToUserStream(_currentUser!.uid);
            } catch (e) {
              // Ignore repository errors for now
              // Debug log suppressed: Failed to save user to repository: $e
            }
          }
        }
      } else {
        // Fallback user data for testing
        _currentUser = UserModel(
          uid: '',
          name: '',
          email: '',
          phoneNumber: '',
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          subscription: UserSubscription(
            plan: 'free',
            isActive: false,
            features: [],
          ),
        );
      }
    } catch (e) {
      // Debug log suppressed: Error initializing user: $e
      // Fallback user data
      _currentUser = UserModel(
        uid: 'fallback-uid',
        name: 'User Name',
        email: 'user@example.com',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        subscription: UserSubscription(
          plan: 'free',
          isActive: false,
          features: [],
        ),
      );
    } finally {
      _notificationsEnabled =
          _currentUser?.preferences['notificationsEnabled'] as bool? ?? true;
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Methods
  void toggleTheme(bool isDark) {
    if (_disposed) return;
    themeVM.setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void toggleNotifications(bool enabled) {
    if (_disposed) return;
    _notificationsEnabled = enabled;
    // Update user preferences using repository
    if (_currentUser != null) {
      try {
        final updatedPreferences =
            Map<String, dynamic>.from(_currentUser!.preferences);
        updatedPreferences['notificationsEnabled'] = enabled;

        final updatedUser = UserModel(
          uid: _currentUser!.uid,
          name: _currentUser!.name,
          email: _currentUser!.email,
          phoneNumber: _currentUser!.phoneNumber,
          profileImageUrl: _currentUser!.profileImageUrl,
          createdAt: _currentUser!.createdAt,
          lastLoginAt: _currentUser!.lastLoginAt,
          isEmailVerified: _currentUser!.isEmailVerified,
          isPhoneVerified: _currentUser!.isPhoneVerified,
          subscription: _currentUser!.subscription,
          preferences: updatedPreferences,
        );

        _userRepository.updateUser(updatedUser);
        _currentUser = updatedUser;
      } catch (e) {
        // Debug log suppressed: Failed to update notifications preference: $e
      }
    }
    notifyListeners();
  }

  void changeLanguage(Locale locale) {
    if (_disposed) return;
    localeVM.setLocale(locale);
    // Update user preferences using repository
    if (_currentUser != null) {
      try {
        final updatedPreferences =
            Map<String, dynamic>.from(_currentUser!.preferences);
        updatedPreferences['language'] = locale.languageCode;

        final updatedUser = UserModel(
          uid: _currentUser!.uid,
          name: _currentUser!.name,
          email: _currentUser!.email,
          phoneNumber: _currentUser!.phoneNumber,
          profileImageUrl: _currentUser!.profileImageUrl,
          createdAt: _currentUser!.createdAt,
          lastLoginAt: _currentUser!.lastLoginAt,
          isEmailVerified: _currentUser!.isEmailVerified,
          isPhoneVerified: _currentUser!.isPhoneVerified,
          subscription: _currentUser!.subscription,
          preferences: updatedPreferences,
        );

        _userRepository.updateUser(updatedUser);
        _currentUser = updatedUser;
      } catch (e) {
        // Debug log suppressed: Failed to update language preference: $e
      }
    }
  }

  void editProfile() {
    if (_disposed || !context.mounted) return;
    context.push('/edit-profile');
  }

  void openNotifications() {
    if (_disposed) return;
    // Handle open notifications
  }

  void openFeedback() {
    if (_disposed || !context.mounted) return;
    context.go('/feedback');
  }

  void shareApp() {
    if (_disposed || !context.mounted) return;
    context.push('/share-app');
  }

  void logout() {
    if (_disposed || !context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LogoutConfirmationBottomSheet(
        onLogout: _handleLogout,
      ),
    );
  }

  Future<void> _handleLogout() async {
    if (_disposed) return;
    if (_isLoggingOut) return;

    _isLoggingOut = true;
    notifyListeners();

    try {
      // Debug log suppressed: Profile: Starting logout process...

      // Preserve existing logout cleanup ordering for token ownership removal.
      // Sign out
      await NotificationService.instance.clearToken();
      await authVM.signOut();
      // Debug log suppressed: Profile: Logout completed successfully
    } catch (e) {
      // Debug log suppressed: Profile: Logout error: $e

      if (!_disposed && context.mounted) {
        Fluttertoast.showToast(
          msg: 'Logout failed. Please try again.',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }
      rethrow;
    } finally {
      _isLoggingOut = false;
      notifyListeners();
    }
  }

  void checkSubscriptionStatus() {
    if (_disposed) return;
    // Subscription status is now part of user model
    notifyListeners();
  }

  // Update user data
  void updateUser(UserModel updatedUser) {
    if (_disposed) return;
    _currentUser = updatedUser;
    notifyListeners();

    // Save to repository
    try {
      _userRepository.updateUser(updatedUser);
    } catch (e) {
      // Debug log suppressed: Failed to update user in repository: $e
    }
  }

  Future<void> resendEmailVerification() async {
    if (_disposed) return;
    final loc = AppLocalizations.of(context);

    try {
      await _authService.sendEmailVerification();
      Fluttertoast.showToast(
        msg: loc.translate('verificationEmailResent'),
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString(),
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> linkEmailAccount({
    required String email,
    required String password,
  }) async {
    if (_disposed) return;
    final loc = AppLocalizations.of(context);
    final trimmedEmail = email.trim().toLowerCase();

    if (trimmedEmail.isEmpty) {
      Fluttertoast.showToast(
        msg: loc.translate('emailRequired'),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    if (!EmailValidator.isValidFormat(trimmedEmail)) {
      Fluttertoast.showToast(
        msg: loc.translate('authInvalidEmail'),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    if (password.length < 6) {
      Fluttertoast.showToast(
        msg: loc.translate('passwordTooShort'),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    if (_isLinkingEmail) return;
    _isLinkingEmail = true;
    notifyListeners();

    try {
      final alreadyRegistered =
          await _authService.isEmailRegistered(trimmedEmail);
      if (alreadyRegistered) {
        Fluttertoast.showToast(
          msg: loc.translate('authEmailExists'),
          backgroundColor: Colors.orange,
          textColor: Colors.white,
        );
        return;
      }

      await _authService.linkEmailCredential(
        email: trimmedEmail,
        password: password,
      );

      await authVM.checkEmailVerificationStatus();
      await authVM.syncUserFromRepository();

      Fluttertoast.showToast(
        msg: loc.translate('emailLinkSuccess'),
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString(),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _isLinkingEmail = false;
      notifyListeners();
    }
  }

  Future<void> startPhoneLinking(String rawPhone) async {
    if (_disposed) return;
    final loc = AppLocalizations.of(context);
    final trimmedPhone = rawPhone.trim();

    if (!PhoneUtils.isValidUaeMobile(trimmedPhone)) {
      Fluttertoast.showToast(
        msg: loc.translate('authInvalidPhone'),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    if (_isLinkingPhone) return;

    _isLinkingPhone = true;
    notifyListeners();

    final phoneE164 = PhoneUtils.toE164Uae(trimmedPhone);

    try {
      final exists = await _authService.isPhoneRegistered(phoneE164);
      if (exists) {
        Fluttertoast.showToast(
          msg: loc.translate('phoneAlreadyRegistered'),
          backgroundColor: Colors.orange,
          textColor: Colors.white,
        );
        return;
      }

      await _authService.sendOtp(
        e164: phoneE164,
        onCodeSent: (_) {},
        onCodeSentWithToken: (verificationId, resendToken) {
          if (_disposed) return;
          Fluttertoast.showToast(
            msg: loc.translate('otpSent'),
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );

          final args = PhoneOtpArgs(
            phoneNumber: phoneE164,
            verificationId: verificationId,
            isSignup: false,
            displayName:
                displayName.isNotEmpty ? displayName : authVM.displayName,
            resendToken: resendToken,
            isLinkingPhone: true,
          );

          if (!_disposed && context.mounted) {
            GoRouter.of(context).push('/phone-otp', extra: args);
          }
        },
        onAutoVerified: (credential) async {
          try {
            await _authService.linkPhoneCredential(credential);
            await authVM.markPhoneVerified(phoneNumber: phoneE164);
            await authVM.syncUserFromRepository();
            Fluttertoast.showToast(
              msg: loc.translate('phoneLinkedSuccessMessage'),
              backgroundColor: Colors.green,
              textColor: Colors.white,
            );
            if (!_disposed && context.mounted) {
              GoRouter.of(context).go('/profile');
            }
          } catch (e) {
            Fluttertoast.showToast(
              msg: e.toString(),
              backgroundColor: Colors.red,
              textColor: Colors.white,
            );
          }
        },
        onFailed: (exception) {
          final message = exception.message ?? exception.code;
          Fluttertoast.showToast(
            msg: message,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        },
        onTimeout: (_) {},
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString(),
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      _isLinkingPhone = false;
      notifyListeners();
    }
  }
}
