import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/repository_provider.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/request_model.dart';
import '../supabase_core_entities_service.dart';

class RequestService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;
  static const String _collectionName = 'users';

  Future<String?> saveRequest(RequestModel request) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return _supabase.saveRequest(request);
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    final docRef = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('requests')
        .add(request
            .copyWith(
              userId: _currentUserId!,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toFirestore());
    return docRef.id;
  }

  Future<void> updateRequest(String requestId, RequestModel request) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.updateRequest(requestId, request);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('requests')
        .doc(requestId)
        .update(request
            .copyWith(id: requestId, updatedAt: DateTime.now())
            .toFirestore());
  }

  Stream<List<RequestModel>> getUserRequests() {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getRequests();
    if (_currentUserId == null) return Stream.value([]);
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RequestModel.fromFirestore(doc))
            .toList());
  }

  Future<void> deleteRequest(String requestId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.deleteRequest(requestId);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('requests')
        .doc(requestId)
        .delete();
  }

  Future<RequestModel?> getRequest(String requestId) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getRequest(requestId);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final doc = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('requests')
        .doc(requestId)
        .get();
    return doc.exists ? RequestModel.fromFirestore(doc) : null;
  }
}
