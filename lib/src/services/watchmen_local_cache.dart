import '../data/models/ScreensModel/watchmen_model.dart';
import 'encrypted_account_list_cache.dart';

/// Watchmen-cache keys in secure storage, under `watchmen_cache_key_v1_<uid>`.
class SecureWatchmenCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureWatchmenCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'watchmen_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The last Watchmen list the server returned for an account, encrypted on
/// this device so the Watchmen screen can show it when the network is
/// unavailable. See [EncryptedAccountListCache] for the rules it follows.
///
/// The box and key belong to the signed-in account (its Supabase user id);
/// each saved record's `userId` must be that account, and a record without
/// one is never saved. Only the fields the list reads are kept, as the server
/// returned them (missing values stay missing); Watchmen have no media.
class WatchmenLocalCache extends EncryptedAccountListCache<WatchmenModel> {
  const WatchmenLocalCache({
    AccountCacheKeyStore keyStore = const SecureWatchmenCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'watchmen_v1',
          logName: 'WatchmenCache',
          keyStore: keyStore,
          encode: _encode,
          decode: _decode,
          ownerOf: _accountOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'cached_watchmen_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  /// The account a record belongs to (not the Watchman record's own id). A
  /// record with no account matches none.
  static String? _idOf(WatchmenModel item) => item.id;

  static String _accountOf(WatchmenModel w) => w.userId ?? '';

  static String? _date(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _parse(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  static Map<String, Object?> _encode(WatchmenModel w) => {
        'id': w.id,
        'userId': w.userId,
        'name': w.name,
        'countryCode': w.countryCode,
        'phoneNumber': w.phoneNumber,
        'buildingName': w.buildingName,
        'notes': w.notes,
        'buildingLocation': w.buildingLocation,
        'pickUpLocation': w.pickUpLocation,
        'pickUpLatitude': w.pickUpLatitude,
        'pickUpLongitude': w.pickUpLongitude,
        'pickUpAddress': w.pickUpAddress,
        'createdAt': _date(w.createdAt),
        'updatedAt': _date(w.updatedAt),
      };

  static WatchmenModel _decode(Map<String, dynamic> m) => WatchmenModel(
        id: m['id'] as String?,
        userId: m['userId'] as String?,
        name: m['name'] as String,
        countryCode: m['countryCode'] as String,
        phoneNumber: m['phoneNumber'] as String,
        buildingName: m['buildingName'] as String,
        notes: m['notes'] as String,
        buildingLocation: m['buildingLocation'] as String,
        pickUpLocation: m['pickUpLocation'] as String,
        pickUpLatitude: (m['pickUpLatitude'] as num?)?.toDouble(),
        pickUpLongitude: (m['pickUpLongitude'] as num?)?.toDouble(),
        pickUpAddress: m['pickUpAddress'] as String,
        createdAt: _parse(m['createdAt']),
        updatedAt: _parse(m['updatedAt']),
      );
}
