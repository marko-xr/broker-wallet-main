import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';

class FirestoreService {
  // Use lazy getter to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // Users Collection
  CollectionReference get _users => _firestore.collection('users');

  // Create or update user
  Future<void> createUser(UserModel user) async {
    try {
      await _users.doc(user.uid).set(user.toMap());
    } catch (e) {
      throw 'Failed to create user: ${e.toString()}';
    }
  }

  // Get user by ID
  Future<UserModel?> getUser(String uid) async {
    try {
      DocumentSnapshot doc = await _users.doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      throw 'Failed to get user: ${e.toString()}';
    }
  }

  // Update user
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      await _users.doc(uid).update(data);
    } catch (e) {
      throw 'Failed to update user: ${e.toString()}';
    }
  }

  // Update last login
  Future<void> updateLastLogin(String uid) async {
    try {
      await _users.doc(uid).update({
        'lastLoginAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      throw 'Failed to update last login: ${e.toString()}';
    }
  }

  // Delete user
  Future<void> deleteUser(String uid) async {
    try {
      await _users.doc(uid).delete();
    } catch (e) {
      throw 'Failed to delete user: ${e.toString()}';
    }
  }

  // Stream user data
  Stream<UserModel?> getUserStream(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    });
  }
}
