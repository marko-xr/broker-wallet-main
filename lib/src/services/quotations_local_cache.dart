import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';

import 'encrypted_account_list_cache.dart';

/// Quotations-cache keys in secure storage, under
/// `quotations_cache_key_v1_<uid>`.
class SecureQuotationsCacheKeyStore extends SecureAccountCacheKeyStore {
  const SecureQuotationsCacheKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'quotations_cache_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The last Quotations list the server returned for an account, encrypted on
/// this device so the Quotations screen can show it when the network is
/// unavailable. See [EncryptedAccountListCache] for the rules it follows.
///
/// Only the 12 fields a list card reads are kept (tracker §7AX): no fees,
/// downpayments, notes, welcome messages, logo, version, link or file path.
/// The amounts are the server's values as it last returned them — a
/// historical snapshot that nothing calculates, saves or decides from.
/// Each saved record's `userId` must be the signed-in account.
class QuotationsLocalCache extends EncryptedAccountListCache<QuotationModel> {
  const QuotationsLocalCache({
    AccountCacheKeyStore keyStore = const SecureQuotationsCacheKeyStore(),
  }) : super(
          boxPrefix: _boxPrefix,
          listKey: 'quotations_v1',
          logName: 'QuotationsCache',
          keyStore: keyStore,
          encode: _encode,
          decode: _decode,
          ownerOf: _accountOf,
          idOf: _idOf,
        );

  static const String _boxPrefix = 'cached_quotations_';

  /// The account's box name; also used by tests.
  static String boxNameForUid(String uid) => '$_boxPrefix$uid';

  static String? _idOf(QuotationModel item) => item.id;

  static String _accountOf(QuotationModel q) => q.userId;

  static String _date(DateTime value) => value.toUtc().toIso8601String();

  static DateTime _parse(Object? value) =>
      DateTime.parse(value as String).toLocal();

  static Map<String, Object?> _encode(QuotationModel q) => {
        'id': q.id,
        'userId': q.userId,
        'propertyTitle': q.propertyTitle,
        'propertyType': q.propertyType,
        'date': q.date,
        'totalAmount': q.totalAmount,
        'numberOfInstallments': q.numberOfInstallments,
        'currencyCode': q.currencyCode,
        'officeName': q.officeName,
        'pdfMediaId': q.pdfMediaId,
        'createdAt': _date(q.createdAt),
        'updatedAt': _date(q.updatedAt),
      };

  static QuotationModel _decode(Map<String, dynamic> m) => QuotationModel(
        id: m['id'] as String?,
        userId: m['userId'] as String,
        propertyTitle: m['propertyTitle'] as String,
        propertyType: m['propertyType'] as String?,
        date: m['date'] as String?,
        totalAmount: (m['totalAmount'] as num?)?.toDouble(),
        numberOfInstallments: m['numberOfInstallments'] as int?,
        currencyCode: m['currencyCode'] as String?,
        officeName: m['officeName'] as String,
        pdfMediaId: m['pdfMediaId'] as String?,
        createdAt: _parse(m['createdAt']),
        updatedAt: _parse(m['updatedAt']),
      );
}
