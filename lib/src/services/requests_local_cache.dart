import '../data/models/ScreensModel/request_model.dart';
import '../data/models/property_status.dart';
import 'encrypted_account_list_cache.dart';

/// Where each account's Requests-cache key lives.
typedef RequestsCacheKeyStore = AccountCacheKeyStore;

/// Requests-cache keys in secure storage, under `requests_cache_key_v1_<uid>`.
class SecureRequestsCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureRequestsCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'requests_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The last Requests list the server returned for an account, encrypted on
/// this device so the Requests screen can show it when the network is
/// unavailable. See [EncryptedAccountListCache] for the rules it follows.
class RequestsLocalCache extends EncryptedAccountListCache<RequestModel> {
  const RequestsLocalCache({
    RequestsCacheKeyStore keyStore = const SecureRequestsCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'requests_v1',
          logName: 'RequestsCache',
          keyStore: keyStore,
          encode: _encode,
          decode: _decode,
          ownerOf: _ownerOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'cached_requests_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  static String? _idOf(RequestModel item) => item.id;

  static String _ownerOf(RequestModel r) => r.userId;

  static Map<String, Object?> _encode(RequestModel r) => {
        'id': r.id,
        'userId': r.userId,
        'requestType': r.requestType,
        'selectedCity': r.selectedCity,
        'selectedAreas': r.selectedAreas,
        'location': r.location,
        'phoneNumber': r.phoneNumber,
        'countryCode': r.countryCode,
        'minPrice': r.minPrice,
        'maxPrice': r.maxPrice,
        'squareFootage': r.squareFootage,
        'notes': r.notes,
        'propertyType': r.propertyType,
        'specificPropertyType': r.specificPropertyType,
        'rooms': r.rooms,
        'bathrooms': r.bathrooms,
        'status': r.status.toFirestoreString(),
        'createdAt': r.createdAt.toUtc().toIso8601String(),
        'updatedAt': r.updatedAt.toUtc().toIso8601String(),
      };

  static RequestModel _decode(Map<String, dynamic> m) => RequestModel(
        id: m['id'] as String?,
        userId: m['userId'] as String,
        requestType: m['requestType'] as String,
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
        status: PropertyStatus.fromString(m['status'] as String),
        createdAt: DateTime.parse(m['createdAt'] as String).toLocal(),
        updatedAt: DateTime.parse(m['updatedAt'] as String).toLocal(),
      );
}
