import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_notification_repository.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/supabase_bootstrap_service.dart';

/// Service locator for repository instances
/// This class manages the creation and access to repository instances
/// Following the Repository pattern and Dependency Injection principles
class RepositoryProvider {
  static RepositoryProvider? _instance;

  // Repository instances
  late final UserRepository _userRepository;
  late final AuthRepository _authRepository;
  late final NotificationRepository _notificationRepository;

  RepositoryProvider._internal() {
    // Supabase is the only identity/profile/notification backend. The Firebase
    // repositories were retired; a build that sets USE_SUPABASE_AUTH=false has
    // no repository to fall back to and must fail loudly, not run half-wired.
    if (!SupabaseConfig.useSupabaseAuth) {
      throw StateError(
        'USE_SUPABASE_AUTH=false is no longer supported: the Firebase '
        'repositories were removed.',
      );
    }

    if (!SupabaseConfig.isConfigured ||
        !SupabaseBootstrapService.isInitialized) {
      throw StateError(
        'USE_SUPABASE_AUTH requires an initialized Supabase client. '
        'Provide SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
      );
    }

    _userRepository = SupabaseUserRepository();
    _authRepository = SupabaseAuthRepository(
      userRepository: _userRepository,
    );
    _notificationRepository = SupabaseNotificationRepository();
  }

  /// Get singleton instance
  static RepositoryProvider get instance {
    _instance ??= RepositoryProvider._internal();
    return _instance!;
  }

  /// Reset instance (useful for testing)
  static void reset() {
    _instance = null;
  }

  // Repository getters
  AuthRepository get authRepository => _authRepository;
  UserRepository get userRepository => _userRepository;
  NotificationRepository get notificationRepository => _notificationRepository;

  /// Initialize repositories with custom implementations
  /// Useful for testing or using different backends
  static void initializeWithCustomRepositories({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required NotificationRepository notificationRepository,
  }) {
    final instance = RepositoryProvider._internal();
    instance._userRepository = userRepository;
    instance._authRepository = authRepository;
    instance._notificationRepository = notificationRepository;
    _instance = instance;
  }
}
