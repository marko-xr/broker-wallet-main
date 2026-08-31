import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/repositories/property_repository.dart';
import 'package:broker_wallet/src/repositories/firebase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/firestore_user_repository.dart';
import 'package:broker_wallet/src/repositories/firestore_property_repository.dart';
import 'package:broker_wallet/src/repositories/firestore_notification_repository.dart';
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
  late final PropertyRepository _propertyRepository;
  late final NotificationRepository _notificationRepository;

  RepositoryProvider._internal() {
    // Identity/profile migration is feature-flagged. Property and notification
    // repositories intentionally remain on Firebase during this stage.
    if (SupabaseConfig.useSupabaseAuth) {
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
    } else {
      _userRepository = FirestoreUserRepository();
      _authRepository = FirebaseAuthRepository(
        userRepository: _userRepository,
      );
      _notificationRepository = FirestoreNotificationRepository();
    }

    _propertyRepository = FirestorePropertyRepository();
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
  PropertyRepository get propertyRepository => _propertyRepository;
  NotificationRepository get notificationRepository => _notificationRepository;

  /// Initialize repositories with custom implementations
  /// Useful for testing or using different backends
  static void initializeWithCustomRepositories({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required PropertyRepository propertyRepository,
    required NotificationRepository notificationRepository,
  }) {
    final instance = RepositoryProvider._internal();
    instance._userRepository = userRepository;
    instance._authRepository = authRepository;
    instance._propertyRepository = propertyRepository;
    instance._notificationRepository = notificationRepository;
    _instance = instance;
  }
}
