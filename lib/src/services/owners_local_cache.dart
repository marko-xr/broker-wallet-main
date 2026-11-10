import '../data/models/ScreensModel/owners_model.dart';
import 'encrypted_account_list_cache.dart';

/// Owners-cache keys in secure storage, under `owners_cache_key_v1_<uid>`.
class SecureOwnersCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureOwnersCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'owners_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The last Owners list the server returned for an account, encrypted on this
/// device so the Owners screen can show it when the network is unavailable.
/// See [EncryptedAccountListCache] for the rules it follows.
///
/// The box and key belong to the signed-in account (its Supabase user id);
/// each saved record's `userId` must be that account. Only the fields the
/// list reads are kept. Media itself is never part of it — no signed URL, no
/// path, no bytes. Each record keeps only its trusted media identity,
/// `listedMediaObjectIds` (tracker §7AZ, M2-2): canonical lower-case UUIDs
/// in gallery order, inside the same authenticated payload. Owner media
/// keeps going through the existing on-device media cache and authorized
/// reads.
class OwnersLocalCache extends EncryptedAccountListCache<OwnerModel> {
  const OwnersLocalCache({
    AccountCacheKeyStore keyStore = const SecureOwnersCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'owners_v1',
          logName: 'OwnersCache',
          keyStore: keyStore,
          encode: _encode,
          decode: _decode,
          ownerOf: _accountOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'cached_owners_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  /// The account a record belongs to (not the Owner record's own id).
  static String? _idOf(OwnerModel item) => item.id;

  static String _accountOf(OwnerModel o) => o.userId;

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

  static Map<String, Object?> _encode(OwnerModel o) => {
        'id': o.id,
        'userId': o.userId,
        'name': o.name,
        'phoneNumber': o.phoneNumber,
        'countryCode': o.countryCode,
        'typeOfProperties': o.typeOfProperties,
        'propertyLocation': o.propertyLocation,
        'notes': o.notes,
        'pickUpLocation': o.pickUpLocation,
        'pickUpLatitude': o.pickUpLatitude,
        'pickUpLongitude': o.pickUpLongitude,
        'pickUpAddress': o.pickUpAddress,
        'uploadedFileName': o.uploadedFileName,
        'createdAt': o.createdAt.toUtc().toIso8601String(),
        'updatedAt': o.updatedAt.toUtc().toIso8601String(),
        'listedMediaObjectIds': _mediaIds(o.listedMediaObjectIds),
      };

  static OwnerModel _decode(Map<String, dynamic> m) => OwnerModel(
        id: m['id'] as String?,
        userId: m['userId'] as String,
        name: m['name'] as String,
        phoneNumber: m['phoneNumber'] as String,
        countryCode: m['countryCode'] as String,
        typeOfProperties: m['typeOfProperties'] as String,
        propertyLocation: m['propertyLocation'] as String,
        notes: m['notes'] as String,
        pickUpLocation: m['pickUpLocation'] as String,
        pickUpLatitude: (m['pickUpLatitude'] as num?)?.toDouble(),
        pickUpLongitude: (m['pickUpLongitude'] as num?)?.toDouble(),
        pickUpAddress: m['pickUpAddress'] as String,
        uploadedFileName: m['uploadedFileName'] as String?,
        // As the server list read: no media links in the list.
        mediaUrl: null,
        mediaUrls: const <String>[],
        createdAt: DateTime.parse(m['createdAt'] as String).toLocal(),
        updatedAt: DateTime.parse(m['updatedAt'] as String).toLocal(),
        // Absent in a list saved before M2-2: [] (identity unknown).
        listedMediaObjectIds: _mediaIds(m['listedMediaObjectIds']),
      );
}
