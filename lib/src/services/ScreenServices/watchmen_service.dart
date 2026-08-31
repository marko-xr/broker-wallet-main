import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/watchmen_model.dart';
import '../map_data_cache_service.dart';
import '../supabase_core_entities_service.dart';

class WatchmenService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final _mapDataCache = MapDataCacheService();
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  String? get _currentUserId => _auth.currentUser?.uid;
  static const String _collectionName = 'users';

  Future<String?> saveWatchmen(WatchmenModel watchmen) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.saveWatchman(watchmen);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final docRef = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('watchmen')
        .add(watchmen
            .copyWith(
              userId: _currentUserId!,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toFirestore());
    return docRef.id;
  }

  Future<void> updateWatchmen(String watchmenId, WatchmenModel watchmen) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.updateWatchman(watchmenId, watchmen);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('watchmen')
        .doc(watchmenId)
        .update(watchmen
            .copyWith(id: watchmenId, updatedAt: DateTime.now())
            .toFirestore());
    _mapDataCache.invalidateCache();
  }

  Stream<List<WatchmenModel>> getUserWatchmen() {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getWatchmen();
    if (_currentUserId == null) return Stream.value([]);
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('watchmen')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WatchmenModel.fromFirestore(doc))
            .toList());
  }

  Future<void> deleteWatchmen(String watchmenId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.deleteWatchman(watchmenId);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('watchmen')
        .doc(watchmenId)
        .delete();
    _mapDataCache.invalidateCache();
  }

  Future<WatchmenModel?> getWatchmen(String watchmenId) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getWatchman(watchmenId);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final doc = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('watchmen')
        .doc(watchmenId)
        .get();
    return doc.exists ? WatchmenModel.fromFirestore(doc) : null;
  }
}
