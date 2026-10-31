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
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class ProfileViewModel extends ChangeNotifier {
  final ThemeViewModel themeVM;
  final LocaleViewModel localeVM;
  final BuildContext context;
  final AuthViewModel authVM;
  final UserRepository _userRepository;

  bool _notificationsEnabled = false;
  bool _isLoading = true;
  bool _disposed = false;
  bool _isLinkingEmail = false;
  bool _isLinkingPhone = false;
  bool _isLoggingOut = false;

  ProfileViewModel({
    required this.themeVM,
    required this.localeVM,
    required this.context,
    required this.authVM,
    UserRepository? userRepository,
  }) : _userRepository =
            userRepository ?? RepositoryProvider.instance.userRepository {
    authVM.addListener(_handleAuthViewModelChanged);
    _initializeUser();
  }

  // Canonical current-user is owned by AuthViewModel; Profile only relays
  // its notifications and reads through to the same object, so it can never
  // diverge from Home/Search/Favorites.
  void _handleAuthViewModelChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  // Getters
  bool get notificationsEnabled => _notificationsEnabled;
  bool get isLoading => _isLoading;
  UserModel? get currentUser => authVM.currentUser;
  String get displayName {
    final authDisplayName = authVM.displayName.trim();
    if (authDisplayName.isNotEmpty) {
      return authDisplayName;
    }

    final primaryName = authVM.currentUser?.name.trim() ?? '';
    if (primaryName.isNotEmpty) {
      return primaryName;
    }

    final email = authVM.currentUser?.email;
    if (email != null) {
      final trimmed = email.trim();
      if (trimmed.isNotEmpty) {
        final atIndex = trimmed.indexOf('@');
        if (atIndex > 0) {
          return trimmed.substring(0, atIndex);
        }
        return trimmed;
      }
    }

    final phone = authVM.currentUser?.phoneNumber;
    if (phone != null) {
      final trimmedPhone = phone.trim();
      if (trimmedPhone.isNotEmpty) {
        return trimmedPhone;
      }
    }

    return '';
  }

  bool get isSubscribed => authVM.currentUser?.subscription.isActive ?? false;
  bool get isLinkingEmail => _isLinkingEmail;
  bool get isLinkingPhone => _isLinkingPhone;
  bool get isLoggingOut => _isLoggingOut;
  bool get hasLinkedEmail => (authVM.currentUser?.email ?? '').isNotEmpty;
  bool get isEmailVerified => authVM.currentUser?.isEmailVerified ?? false;
  bool get hasLinkedPhone => (authVM.currentUser?.phoneNumber ?? '').isNotEmpty;
  bool get isPhoneVerified => authVM.currentUser?.isPhoneVerified ?? false;

  @override
  void dispose() {
    _disposed = true;
    authVM.removeListener(_handleAuthViewModelChanged);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  void _initializeUser() {
    // Canonical current-user state (including its profile realtime
    // subscription) is owned entirely by AuthViewModel now — there is
    // nothing to fetch or subscribe to here. This only derives Profile's own
    // presentation-only preference flag from whatever AuthViewModel already
    // holds.
    try {
      _notificationsEnabled =
          authVM.currentUser?.preferences['notificationsEnabled'] as bool? ??
              true;
    } catch (e) {
      // Debug log suppressed: Error initializing user: $e
    } finally {
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
    // Update user preferences using repository. AuthViewModel's own realtime
    // subscription picks up the resulting row change and updates the
    // canonical currentUser; there is no local copy to keep in sync here.
    final current = authVM.currentUser;
    if (current != null) {
      try {
        final updatedPreferences =
            Map<String, dynamic>.from(current.preferences);
        updatedPreferences['notificationsEnabled'] = enabled;

        final updatedUser = current.copyWith(preferences: updatedPreferences);
        _userRepository.updateUser(updatedUser);
      } catch (e) {
        // Debug log suppressed: Failed to update notifications preference: $e
      }
    }
    notifyListeners();
  }

  void changeLanguage(Locale locale) {
    if (_disposed) return;
    localeVM.setLocale(locale);
    // Update user preferences using repository (see toggleNotifications).
    final current = authVM.currentUser;
    if (current != null) {
      try {
        final updatedPreferences =
            Map<String, dynamic>.from(current.preferences);
        updatedPreferences['language'] = locale.languageCode;

        final updatedUser = current.copyWith(preferences: updatedPreferences);
        _userRepository.updateUser(updatedUser);
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
      useRootNavigator: true,
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
      // await NotificationService.instance.clearToken();
      await authVM.signOut();
      // Debug log suppressed: Profile: Logout completed successfully
    } catch (e) {
      // Debug log suppressed: Profile: Logout error: $e

      if (!_disposed && context.mounted) {
        Fluttertoast.showToast(
          msg: AppLocalizations.of(context).translate('logoutFailed'),
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

  // Update user data. AuthViewModel's own realtime subscription is the
  // canonical owner and will pick up the resulting row change; this just
  // persists it and lets that flow through.
  void updateUser(UserModel updatedUser) {
    if (_disposed) return;
    notifyListeners();

    // Save to repository
    try {
      _userRepository.updateUser(updatedUser);
    } catch (e) {
      // Debug log suppressed: Failed to update user in repository: $e
    }
  }
}
