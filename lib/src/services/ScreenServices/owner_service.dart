import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/owners_model.dart';
import '../fast_media_upload_service.dart';
import '../map_data_cache_service.dart';
import '../supabase_core_entities_service.dart';

class OwnerService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final FastMediaUploadService _fastUploadService = FastMediaUploadService();
  final _mapDataCache = MapDataCacheService();
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  String? get _currentUserId => _auth.currentUser?.uid;
  static const String _collectionName = 'users';

  String generateNewOwnerId() {
    if (SupabaseConfig.useSupabaseAuth) return const Uuid().v4();
    if (_currentUserId == null) throw Exception('User not authenticated');
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc()
        .id;
  }

  Future<String?> saveOwner(OwnerModel owner, {String? ownerId}) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return _supabase.saveOwner(owner, ownerRecordId: ownerId);
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    final String docId = ownerId ?? generateNewOwnerId();
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(docId)
        .set(owner
            .copyWith(
              id: docId,
              userId: _currentUserId!,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toFirestore());
    _mapDataCache.invalidateCache();
    return docId;
  }

  Future<String> saveOwnerWithMediaFast({
    required OwnerModel owner,
    required List<File> mediaFiles,
    String? ownerId,
  }) async {
    if (SupabaseConfig.useSupabaseAuth) {
      if (mediaFiles.isNotEmpty) {
        throw StateError(
          'Media upload is disabled until the Cloudflare R2 migration batch is applied.',
        );
      }
      return _supabase.saveOwner(owner, ownerRecordId: ownerId);
    }

    if (_currentUserId == null) throw Exception('User not authenticated');
    final ownerData = {
      'userId': owner.userId,
      'name': owner.name,
      'phoneNumber': owner.phoneNumber,
      'countryCode': owner.countryCode,
      'typeOfProperties': owner.typeOfProperties,
      'propertyLocation': owner.propertyLocation,
      'notes': owner.notes,
      'pickUpLocation': owner.pickUpLocation,
      'pickUpLatitude': owner.pickUpLatitude,
      'pickUpLongitude': owner.pickUpLongitude,
      'pickUpAddress': owner.pickUpAddress,
      'uploadedFileName': owner.uploadedFileName,
      'mediaUrl': owner.mediaUrl,
      'createdAt': owner.createdAt,
      'updatedAt': owner.updatedAt,
    };
    return _fastUploadService.saveDataWithMedia(
      data: ownerData,
      mediaFiles: mediaFiles,
      collection: 'owners',
      documentId: ownerId,
    );
  }

  Future<void> updateOwner(String ownerId, OwnerModel owner) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.updateOwner(ownerId, owner);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(ownerId)
        .update(owner
            .copyWith(id: ownerId, updatedAt: DateTime.now())
            .toFirestore());
    _mapDataCache.invalidateCache();
  }

  Stream<List<OwnerModel>> getUserOwners() {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOwners();
    if (_currentUserId == null) return Stream.value([]);
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => OwnerModel.fromFirestore(doc)).toList());
  }

  Future<void> deleteOwner(String ownerId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.deleteOwner(ownerId);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(ownerId)
        .delete();
    _mapDataCache.invalidateCache();
  }

  Future<OwnerModel?> getOwner(String ownerId) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOwner(ownerId);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final doc = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('owners')
        .doc(ownerId)
        .get();
    return doc.exists ? OwnerModel.fromFirestore(doc) : null;
  }
}
