import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/repository_provider.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/brokers_model.dart';
import '../supabase_core_entities_service.dart';

class BrokerService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;
  static const String _collectionName = 'users';

  Future<String?> saveBroker(BrokerModel broker) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.saveBroker(broker);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final docRef = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('brokers')
        .add(broker
            .copyWith(
              userId: _currentUserId!,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toFirestore());
    return docRef.id;
  }

  Future<void> updateBroker(String brokerId, BrokerModel broker) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.updateBroker(brokerId, broker);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('brokers')
        .doc(brokerId)
        .update(broker
            .copyWith(id: brokerId, updatedAt: DateTime.now())
            .toFirestore());
  }

  Stream<List<BrokerModel>> getUserBrokers() {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getBrokers();
    if (_currentUserId == null) return Stream.value([]);
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('brokers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => BrokerModel.fromFirestore(doc)).toList());
  }

  Future<void> deleteBroker(String brokerId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.deleteBroker(brokerId);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('brokers')
        .doc(brokerId)
        .delete();
  }

  Future<BrokerModel?> getBroker(String brokerId) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getBroker(brokerId);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final doc = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('brokers')
        .doc(brokerId)
        .get();
    return doc.exists ? BrokerModel.fromFirestore(doc) : null;
  }
}
