import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'dart:async';

/// Firestore implementation of UserRepository
/// Contains all Firestore-specific user data operations
class FirestoreUserRepository implements UserRepository {
  // Use lazy getter to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const String _collection = 'users';

  @override
  Future<void> createUser(UserModel user) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(user.uid)
          .set(user.toFirestore());
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  @override
  Future<UserModel?> getUserById(String uid) async {
    try {
      // Try cache first for offline support
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection(_collection)
            .doc(uid)
            .get(const GetOptions(source: Source.cache));

        if (doc.exists && doc.data() != null) {
          return UserModel.fromFirestore(doc);
        }
      } catch (e) {
        // Cache failed, try server with timeout
        // Cache read failed for user $uid, will fallback to server (log removed)
      }

      // Fallback to server with timeout
      doc = await _firestore
          .collection(_collection)
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException(
                'getUserById timeout', const Duration(seconds: 5)),
          );

      if (doc.exists && doc.data() != null) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      if (e is TimeoutException) {
        // getUserById timeout for $uid - offline mode (log removed)
        return null;
      }
      throw Exception('Failed to get user: $e');
    }
  }

  @override
  Future<void> updateUser(UserModel user) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(user.uid)
          .update(user.toFirestore());
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  @override
  Future<void> deleteUser(String uid) async {
    try {
      await _firestore.collection(_collection).doc(uid).delete();
    } catch (e) {
      throw Exception('Failed to delete user: $e');
    }
  }

  @override
  Future<bool> userExists(String uid) async {
    try {
      // Try cache first
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection(_collection)
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        return doc.exists;
      } catch (e) {
        // Cache failed, try server with timeout
        // Cache read failed for userExists $uid, will fallback to server (log removed)
      }

      // Fallback to server with timeout
      doc = await _firestore
          .collection(_collection)
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException(
                'userExists timeout', const Duration(seconds: 5)),
          );

      return doc.exists;
    } catch (e) {
      if (e is TimeoutException) {
        // userExists timeout for $uid - assuming false (log removed)
        return false;
      }
      throw Exception('Failed to check if user exists: $e');
    }
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return UserModel.fromFirestore(querySnapshot.docs.first);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get user by email: $e');
    }
  }

  @override
  Future<void> updateUserPreferences(
      String uid, Map<String, dynamic> preferences) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(uid)
          .update({'preferences': preferences});
    } catch (e) {
      throw Exception('Failed to update user preferences: $e');
    }
  }

  @override
  Future<void> updateUserSubscription(
      String uid, UserSubscription subscription) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(uid)
          .update({'subscription': subscription.toFirestore()});
    } catch (e) {
      throw Exception('Failed to update user subscription: $e');
    }
  }

  @override
  Stream<UserModel?> getUserStream(String uid) {
    try {
      return _firestore
          .collection(_collection)
          .doc(uid)
          .snapshots()
          .map((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          return UserModel.fromFirestore(snapshot);
        }
        return null;
      });
    } catch (e) {
      throw Exception('Failed to get user stream: $e');
    }
  }
}
