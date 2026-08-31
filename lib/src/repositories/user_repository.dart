import 'package:broker_wallet/src/data/models/user_model.dart';

/// Abstract repository interface for user data operations
/// This separates user data management from specific database implementations
abstract class UserRepository {
  /// Create a new user document
  Future<void> createUser(UserModel user);

  /// Get user by ID
  Future<UserModel?> getUserById(String uid);

  /// Update user data
  Future<void> updateUser(UserModel user);

  /// Delete user data
  Future<void> deleteUser(String uid);

  /// Check if user exists
  Future<bool> userExists(String uid);

  /// Get user by email
  Future<UserModel?> getUserByEmail(String email);

  /// Update user preferences
  Future<void> updateUserPreferences(
      String uid, Map<String, dynamic> preferences);

  /// Update user subscription
  Future<void> updateUserSubscription(
      String uid, UserSubscription subscription);

  /// Stream of user data changes
  Stream<UserModel?> getUserStream(String uid);
}
