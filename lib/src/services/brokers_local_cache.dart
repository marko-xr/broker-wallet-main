import '../data/models/ScreensModel/brokers_model.dart';
import 'encrypted_account_list_cache.dart';

/// Brokers-cache keys in secure storage, under `brokers_cache_key_v1_<uid>`.
class SecureBrokersCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureBrokersCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'brokers_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The last Brokers list the server returned for an account, encrypted on
/// this device so the Brokers screen can show it when the network is
/// unavailable. See [EncryptedAccountListCache] for the rules it follows.
///
/// The box and key belong to the signed-in account (its Supabase user id);
/// each saved record's `userId` must be that account, and a record without
/// one is never saved. Only the fields the list reads are kept, as the server
/// returned them (a missing date stays missing); Brokers have no media.
class BrokersLocalCache extends EncryptedAccountListCache<BrokerModel> {
  const BrokersLocalCache({
    AccountCacheKeyStore keyStore = const SecureBrokersCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'brokers_v1',
          logName: 'BrokersCache',
          keyStore: keyStore,
          encode: _encode,
          decode: _decode,
          ownerOf: _accountOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'cached_brokers_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  /// The account a record belongs to (not the Broker record's own id). A
  /// record with no account matches none.
  static String? _idOf(BrokerModel item) => item.id;

  static String _accountOf(BrokerModel b) => b.userId ?? '';

  static String? _date(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _parse(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  static Map<String, Object?> _encode(BrokerModel b) => {
        'id': b.id,
        'userId': b.userId,
        'name': b.name,
        'countryCode': b.countryCode,
        'phoneNumber': b.phoneNumber,
        'notes': b.notes,
        'createdAt': _date(b.createdAt),
        'updatedAt': _date(b.updatedAt),
      };

  static BrokerModel _decode(Map<String, dynamic> m) => BrokerModel(
        id: m['id'] as String?,
        userId: m['userId'] as String?,
        name: m['name'] as String,
        countryCode: m['countryCode'] as String,
        phoneNumber: m['phoneNumber'] as String,
        notes: m['notes'] as String,
        createdAt: _parse(m['createdAt']),
        updatedAt: _parse(m['updatedAt']),
      );
}
