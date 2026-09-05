import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/repository_provider.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/offices_model.dart';
import '../map_data_cache_service.dart';
import '../supabase_core_entities_service.dart';

class OfficeService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final _mapDataCache = MapDataCacheService();
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;
  static const String _collectionName = 'users';

  Future<String?> saveOffice(OfficeModel office) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.saveOffice(office);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final docRef = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offices')
        .add(office
            .copyWith(
              userId: _currentUserId!,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toFirestore());
    return docRef.id;
  }

  Future<void> updateOffice(String officeId, OfficeModel office) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.updateOffice(officeId, office);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offices')
        .doc(officeId)
        .update(office
            .copyWith(id: officeId, updatedAt: DateTime.now())
            .toFirestore());
    _mapDataCache.invalidateCache();
  }

  Stream<List<OfficeModel>> getUserOffices() {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOffices();
    if (_currentUserId == null) return Stream.value([]);
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offices')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => OfficeModel.fromFirestore(doc)).toList());
  }

  Future<void> deleteOffice(String officeId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.deleteOffice(officeId);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offices')
        .doc(officeId)
        .delete();
    _mapDataCache.invalidateCache();
  }

  Future<OfficeModel?> getOffice(String officeId) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOffice(officeId);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final doc = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offices')
        .doc(officeId)
        .get();
    return doc.exists ? OfficeModel.fromFirestore(doc) : null;
  }
}
