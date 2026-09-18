import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/repository_provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../data/models/ScreensModel/offers_model.dart';
import '../fast_media_upload_service.dart';
import '../map_data_cache_service.dart';
import '../r2_offer_media_upload_service.dart';
import '../supabase_core_entities_service.dart';

class OfferService {
  static const String _collectionName = 'users';
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final _mapDataCache = MapDataCacheService();
  final FastMediaUploadService _fastUploadService = FastMediaUploadService();
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();
  final R2OfferMediaUploadService _offerMediaUpload =
      R2OfferMediaUploadService();

  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;

  String generateNewOfferId() {
    if (SupabaseConfig.useSupabaseAuth) return const Uuid().v4();
    if (_currentUserId == null) throw Exception('User not authenticated');
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offers')
        .doc()
        .id;
  }

  Future<String?> saveOffer(OfferModel offer, {String? offerId}) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return _supabase.saveOffer(offer, offerId: offerId);
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    final String docId = offerId ?? generateNewOfferId();
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offers')
        .doc(docId)
        .set(offer
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

  Future<String> saveOfferWithMediaFast({
    required OfferModel offer,
    required List<File> mediaFiles,
    String? offerId,
  }) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return _saveOfferWithMediaSupabase(
        offer: offer,
        mediaFiles: mediaFiles,
        offerId: offerId,
      );
    }

    if (_currentUserId == null) throw Exception('User not authenticated');
    final offerData = {
      'userId': offer.userId,
      'offerType': offer.offerType,
      'selectedCity': offer.selectedCity,
      'selectedAreas': offer.selectedAreas,
      'location': offer.location,
      'phoneNumber': offer.phoneNumber,
      'countryCode': offer.countryCode,
      'minPrice': offer.minPrice,
      'maxPrice': offer.maxPrice,
      'squareFootage': offer.squareFootage,
      'notes': offer.notes,
      'propertyType': offer.propertyType,
      'specificPropertyType': offer.specificPropertyType,
      'rooms': offer.rooms,
      'bathrooms': offer.bathrooms,
      'pickUpLocation': offer.pickUpLocation,
      'pickUpLatitude': offer.pickUpLatitude,
      'pickUpLongitude': offer.pickUpLongitude,
      'pickUpAddress': offer.pickUpAddress,
      'uploadedFileName': offer.uploadedFileName,
      'status': offer.status.toFirestoreString(),
      'createdAt': offer.createdAt,
      'updatedAt': offer.updatedAt,
      'mediaUrls': offer.mediaUrls,
    };
    return _fastUploadService.saveDataWithMedia(
      data: offerData,
      mediaFiles: mediaFiles,
      collection: 'offers',
      documentId: offerId,
    );
  }

  /// Saves (creates or updates) the Offer row itself first — exactly the
  /// same path as [saveOffer]/[updateOffer], so an Offer with no attached
  /// media always behaves as before — then uploads any attached files
  /// through the private R2 Worker one at a time.
  ///
  /// The Offer row's own success is never rolled back for a media failure:
  /// losing already-entered Offer data because one photo failed to upload
  /// would be worse than losing the photo. Instead, any file that fails to
  /// upload or confirm is collected and surfaced as a thrown exception after
  /// the Offer itself is safely saved, so the caller's existing error UI
  /// (`add_offers_viewmodel.dart`'s save handler) shows a clear failure
  /// rather than a false "saved successfully" for attachments that did not
  /// actually save. The user can re-open Edit and retry just the media.
  Future<String> _saveOfferWithMediaSupabase({
    required OfferModel offer,
    required List<File> mediaFiles,
    String? offerId,
  }) async {
    final resolvedId = offerId ?? _supabase.generateId();
    final existing = await _supabase.getOffer(resolvedId);

    final String savedOfferId;
    if (existing == null) {
      savedOfferId = await _supabase.saveOffer(offer, offerId: resolvedId);
    } else {
      await _supabase.updateOffer(resolvedId, offer);
      savedOfferId = resolvedId;
    }

    if (mediaFiles.isEmpty) return savedOfferId;

    // New uploads are appended after whatever this offer already has, so a
    // second edit session's attachments do not collide on ordinal with the
    // first's.
    var nextOrdinal = 0;
    try {
      final currentMedia = await _offerMediaUpload.getOfferMedia(savedOfferId);
      nextOrdinal = currentMedia.length;
    } catch (_) {
      // Best-effort only: worst case a collision fails that one file closed
      // (rejected, not silently dropped) rather than corrupting anything.
    }

    final failedFileNames = <String>[];
    for (final file in mediaFiles) {
      try {
        await _offerMediaUpload.uploadOfferMediaFile(
          offerId: savedOfferId,
          file: file,
          ordinal: nextOrdinal,
        );
        nextOrdinal += 1;
      } catch (e) {
        failedFileNames.add(file.path.split(Platform.pathSeparator).last);
      }
    }

    if (failedFileNames.isNotEmpty) {
      throw StateError(
        'Offer saved, but ${failedFileNames.length} of ${mediaFiles.length} '
        'photo(s) failed to upload (${failedFileNames.join(', ')}). '
        'Edit the offer to retry.',
      );
    }

    return savedOfferId;
  }

  Future<void> removeMediaUrls(String offerId, List<String> urlsToRemove) async {
    if (SupabaseConfig.useSupabaseAuth) {
      if (urlsToRemove.isNotEmpty) {
        throw StateError(
          'Media mutation is disabled until the Cloudflare R2 migration batch is applied.',
        );
      }
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    if (urlsToRemove.isEmpty) return;
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offers')
        .doc(offerId)
        .update({
      'mediaUrls': FieldValue.arrayRemove(urlsToRemove),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateOffer(String offerId, OfferModel offer) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.updateOffer(offerId, offer);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offers')
        .doc(offerId)
        .update(offer
            .copyWith(id: offerId, updatedAt: DateTime.now())
            .toFirestore());
    _mapDataCache.invalidateCache();
  }

  Stream<List<OfferModel>> getUserOffers() {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOffers();
    if (_currentUserId == null) return Stream.value([]);
    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => OfferModel.fromFirestore(doc)).toList());
  }

  Future<void> deleteOffer(String offerId) async {
    if (SupabaseConfig.useSupabaseAuth) {
      await _supabase.deleteOffer(offerId);
      return;
    }
    if (_currentUserId == null) throw Exception('User not authenticated');
    await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offers')
        .doc(offerId)
        .delete();
    _mapDataCache.invalidateCache();
  }

  Future<OfferModel?> getOffer(String offerId) async {
    if (SupabaseConfig.useSupabaseAuth) return _supabase.getOffer(offerId);
    if (_currentUserId == null) throw Exception('User not authenticated');
    final doc = await _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('offers')
        .doc(offerId)
        .get();
    return doc.exists ? OfferModel.fromFirestore(doc) : null;
  }
}
