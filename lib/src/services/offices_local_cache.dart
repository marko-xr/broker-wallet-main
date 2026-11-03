import '../data/models/ScreensModel/offices_model.dart';
import 'encrypted_account_list_cache.dart';

/// Offices-cache keys in secure storage, under `offices_cache_key_v1_<uid>`.
class SecureOfficesCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureOfficesCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'offices_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The last Offices list the server returned for an account, encrypted on
/// this device so the Offices screen can show it when the network is
/// unavailable. See [EncryptedAccountListCache] for the rules it follows.
///
/// The box and key belong to the signed-in account (its Supabase user id);
/// each saved record's `userId` must be that account, and a record without
/// one is never saved. Only the fields the list reads are kept; Offices have
/// no media.
class OfficesLocalCache extends EncryptedAccountListCache<OfficeModel> {
  const OfficesLocalCache({
    AccountCacheKeyStore keyStore = const SecureOfficesCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'offices_v1',
          logName: 'OfficesCache',
          keyStore: keyStore,
          encode: _encode,
          decode: _decode,
          ownerOf: _accountOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'cached_offices_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  /// The account a record belongs to (not the Office record's own id). A
  /// record with no account matches none.
  static String? _idOf(OfficeModel item) => item.id;

  static String _accountOf(OfficeModel o) => o.userId ?? '';

  static String? _date(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _parse(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  static Map<String, Object?> _encode(OfficeModel o) => {
        'id': o.id,
        'userId': o.userId,
        'officeName': o.officeName,
        'managerName': o.managerName,
        'countryCode': o.countryCode,
        'phoneNumber': o.phoneNumber,
        'officeLocation': o.officeLocation,
        'notes': o.notes,
        'pickUpLocation': o.pickUpLocation,
        'pickUpLatitude': o.pickUpLatitude,
        'pickUpLongitude': o.pickUpLongitude,
        'pickUpAddress': o.pickUpAddress,
        'createdAt': _date(o.createdAt),
        'updatedAt': _date(o.updatedAt),
      };

  static OfficeModel _decode(Map<String, dynamic> m) => OfficeModel(
        id: m['id'] as String?,
        userId: m['userId'] as String?,
        officeName: m['officeName'] as String,
        managerName: m['managerName'] as String,
        countryCode: m['countryCode'] as String,
        phoneNumber: m['phoneNumber'] as String,
        officeLocation: m['officeLocation'] as String,
        notes: m['notes'] as String,
        pickUpLocation: m['pickUpLocation'] as String,
        pickUpLatitude: (m['pickUpLatitude'] as num?)?.toDouble(),
        pickUpLongitude: (m['pickUpLongitude'] as num?)?.toDouble(),
        pickUpAddress: m['pickUpAddress'] as String,
        createdAt: _parse(m['createdAt']),
        updatedAt: _parse(m['updatedAt']),
      );
}
