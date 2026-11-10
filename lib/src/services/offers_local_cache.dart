import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/property_status.dart';
import 'encrypted_account_list_cache.dart';

/// Offers-cache keys in secure storage, under `offers_cache_key_v1_<uid>`.
class SecureOffersCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureOffersCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'offers_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The last Offers list the server returned for an account, encrypted on this
/// device so the Offers screen can show it when the network is unavailable.
/// See [EncryptedAccountListCache] for the rules it follows.
///
/// Only the fields the list reads are kept. Media itself is never part of
/// it — no signed URL, no `mediaObjectIds` (ids aligned with Worker links),
/// no path, no bytes. Each record keeps only its trusted media identity,
/// `listedMediaObjectIds` (tracker §7AZ, M2-2): canonical lower-case UUIDs
/// in gallery order, inside the same authenticated payload. Cards keep
/// reaching media through the existing on-device media cache and authorized
/// reads.
class OffersLocalCache extends EncryptedAccountListCache<OfferModel> {
  const OffersLocalCache({
    AccountCacheKeyStore keyStore = const SecureOffersCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'offers_v1',
          logName: 'OffersCache',
          keyStore: keyStore,
          encode: _encode,
          decode: _decode,
          ownerOf: _ownerOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'cached_offers_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  static String? _idOf(OfferModel item) => item.id;

  static String _ownerOf(OfferModel o) => o.userId;

  static final RegExp _mediaId =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  /// A record's media identity as it is saved and read: every entry a
  /// canonical lower-case UUID, each once, in the given order — otherwise
  /// `[]` for that record alone. Never throws, so a wrong field can never
  /// make the rest of the list unreadable.
  static List<String> _mediaIds(Object? ids) {
    if (ids is! List) return const <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (id is! String || !_mediaId.hasMatch(id) || !seen.add(id)) {
        return const <String>[];
      }
    }
    return List<String>.unmodifiable(ids);
  }

  static Map<String, Object?> _encode(OfferModel o) => {
        'id': o.id,
        'userId': o.userId,
        'offerType': o.offerType,
        'selectedCity': o.selectedCity,
        'selectedAreas': o.selectedAreas,
        'location': o.location,
        'phoneNumber': o.phoneNumber,
        'countryCode': o.countryCode,
        'minPrice': o.minPrice,
        'maxPrice': o.maxPrice,
        'squareFootage': o.squareFootage,
        'notes': o.notes,
        'propertyType': o.propertyType,
        'specificPropertyType': o.specificPropertyType,
        'rooms': o.rooms,
        'bathrooms': o.bathrooms,
        'pickUpLocation': o.pickUpLocation,
        'pickUpLatitude': o.pickUpLatitude,
        'pickUpLongitude': o.pickUpLongitude,
        'pickUpAddress': o.pickUpAddress,
        'uploadedFileName': o.uploadedFileName,
        'status': o.status.toFirestoreString(),
        'createdAt': o.createdAt.toUtc().toIso8601String(),
        'updatedAt': o.updatedAt.toUtc().toIso8601String(),
        'listedMediaObjectIds': _mediaIds(o.listedMediaObjectIds),
      };

  static OfferModel _decode(Map<String, dynamic> m) => OfferModel(
        id: m['id'] as String?,
        userId: m['userId'] as String,
        offerType: m['offerType'] as String,
        selectedCity: m['selectedCity'] as String,
        selectedAreas: List<String>.from(m['selectedAreas'] as List),
        location: m['location'] as String,
        phoneNumber: m['phoneNumber'] as String,
        countryCode: m['countryCode'] as String,
        minPrice: m['minPrice'] as String,
        maxPrice: m['maxPrice'] as String,
        squareFootage: m['squareFootage'] as String,
        notes: m['notes'] as String,
        propertyType: m['propertyType'] as String?,
        specificPropertyType: m['specificPropertyType'] as String,
        rooms: m['rooms'] as int,
        bathrooms: m['bathrooms'] as int,
        pickUpLocation: m['pickUpLocation'] as String,
        pickUpLatitude: (m['pickUpLatitude'] as num?)?.toDouble(),
        pickUpLongitude: (m['pickUpLongitude'] as num?)?.toDouble(),
        pickUpAddress: m['pickUpAddress'] as String,
        uploadedFileName: m['uploadedFileName'] as String,
        // As the server list read: no media links in the list.
        mediaUrl: null,
        mediaUrls: const <String>[],
        status: PropertyStatus.fromString(m['status'] as String),
        createdAt: DateTime.parse(m['createdAt'] as String).toLocal(),
        updatedAt: DateTime.parse(m['updatedAt'] as String).toLocal(),
        // Absent in a list saved before M2-2: [] (identity unknown).
        listedMediaObjectIds: _mediaIds(m['listedMediaObjectIds']),
      );
}
