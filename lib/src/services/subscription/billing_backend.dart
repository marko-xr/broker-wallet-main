import 'package:broker_wallet/src/services/subscription/google_play_store_gateway.dart';
import 'package:broker_wallet/src/services/subscription/store_purchase_gateway.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The trusted server refused a billing request. Nothing was changed.
class BillingRefused implements Exception {
  const BillingRefused(this.code);

  final String code;

  @override
  String toString() => 'BillingRefused($code)';
}

/// A saved card as the server may show it: display fields only.
@immutable
class BillingPaymentMethod {
  const BillingPaymentMethod({
    this.brand,
    this.lastFour,
    this.expMonth,
    this.expYear,
  });

  final String? brand;
  final String? lastFour;
  final int? expMonth;
  final int? expYear;
}

enum BillingEntryStatus { processing, paid, failed, refunded }

/// A UAE tax invoice or credit note, exactly as the server issued it.
@immutable
class BillingTaxDocument {
  const BillingTaxDocument({
    required this.isCreditNote,
    required this.number,
    required this.issuedAt,
    required this.totalFils,
    required this.vatFils,
    required this.netFils,
    required this.vatRateBasisPoints,
    required this.supplier,
    required this.trn,
    required this.address,
  });

  final bool isCreditNote;
  final String number;
  final DateTime issuedAt;
  final int totalFils;
  final int vatFils;
  final int netFils;
  final int vatRateBasisPoints;
  final String supplier;
  final String trn;
  final String address;

  static BillingTaxDocument parse(Object? raw) {
    if (raw is! Map) throw const FormatException('document');
    final kind = raw['kind'];
    final issued = raw['issued_at'] is String
        ? DateTime.tryParse(raw['issued_at'] as String)?.toLocal()
        : null;
    final values = [
      raw['total_fils'],
      raw['vat_fils'],
      raw['net_fils'],
      raw['vat_rate_bp'],
    ];
    if ((kind != 'tax_invoice' && kind != 'tax_credit_note') ||
        raw['number'] is! String ||
        issued == null ||
        values.any((v) => v is! int) ||
        raw['supplier'] is! String ||
        raw['trn'] is! String ||
        raw['address'] is! String) {
      throw const FormatException('document');
    }
    final document = BillingTaxDocument(
      isCreditNote: kind == 'tax_credit_note',
      number: raw['number'] as String,
      issuedAt: issued,
      totalFils: values[0] as int,
      vatFils: values[1] as int,
      netFils: values[2] as int,
      vatRateBasisPoints: values[3] as int,
      supplier: raw['supplier'] as String,
      trn: raw['trn'] as String,
      address: raw['address'] as String,
    );
    // The amounts must add up, or this is not a document to show.
    if (document.netFils + document.vatFils != document.totalFils) {
      throw const FormatException('document');
    }
    return document;
  }

  /// Fils to "12.34", without floating point.
  static String money(int fils) =>
      '${fils ~/ 100}.${(fils % 100).toString().padLeft(2, '0')}';
}

/// One payment in the account's history.
@immutable
class BillingHistoryEntry {
  const BillingHistoryEntry({
    required this.id,
    required this.isRenewal,
    required this.cycle,
    required this.amount,
    required this.currency,
    required this.status,
    required this.at,
    this.documents = const [],
  });

  final String id;
  final bool isRenewal;
  final PlusBillingCycle cycle;
  final String amount;
  final String currency;
  final BillingEntryStatus status;
  final DateTime at;
  final List<BillingTaxDocument> documents;
}

/// The signed-in account's billing view. Parsing is strict: an answer that
/// cannot be understood throws [FormatException] and is shown as unavailable.
@immutable
class BillingOverview {
  const BillingOverview({
    required this.autoRenew,
    required this.canRenewOnFile,
    required this.history,
    this.provider,
    this.state,
    this.cycle,
    this.paidThrough,
    this.graceUntil,
    this.productId,
    this.paymentMethod,
  });

  final BillingProvider? provider;
  final String? state;
  final PlusBillingCycle? cycle;
  final bool autoRenew;
  final DateTime? paidThrough;
  final DateTime? graceUntil;
  final String? productId;
  final BillingPaymentMethod? paymentMethod;
  final bool canRenewOnFile;
  final List<BillingHistoryEntry> history;

  bool get hasPaymentIssue => state == 'billing_issue';

  factory BillingOverview.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['auto_renew'] is! bool ||
        raw['history'] is! List ||
        (raw['can_renew_on_file'] != null &&
            raw['can_renew_on_file'] is! bool)) {
      throw const FormatException('billing');
    }
    final method = raw['payment_method'];
    if (method != null && method is! Map) {
      throw const FormatException('payment_method');
    }
    final history = <BillingHistoryEntry>[];
    for (final item in raw['history'] as List) {
      if (item is! Map) throw const FormatException('history');
      final id = item['id'];
      final cycle = _cycle(item['cycle']);
      final status = _statuses[item['status']];
      final at = item['at'] is String
          ? DateTime.tryParse(item['at'] as String)?.toLocal()
          : null;
      final amount = item['amount'];
      final currency = item['currency'];
      if (id is! String ||
          cycle == null ||
          status == null ||
          at == null ||
          amount is! num ||
          currency is! String) {
        throw const FormatException('history');
      }
      final documents = item['documents'];
      if (documents != null && documents is! List) {
        throw const FormatException('documents');
      }
      history.add(BillingHistoryEntry(
        id: id,
        isRenewal: item['kind'] == 'renewal',
        cycle: cycle,
        amount: amount.toStringAsFixed(2),
        currency: currency,
        status: status,
        at: at,
        documents: [
          for (final document in (documents as List?) ?? const [])
            BillingTaxDocument.parse(document),
        ],
      ));
    }
    return BillingOverview(
      provider: switch (raw['provider']) {
        'google_play' => BillingProvider.googlePlay,
        'app_store' => BillingProvider.appStore,
        'tap' => BillingProvider.tap,
        _ => null,
      },
      state: raw['state'] is String ? raw['state'] as String : null,
      cycle: _cycle(raw['cycle']),
      autoRenew: raw['auto_renew'] as bool,
      paidThrough: _date(raw['paid_through']),
      graceUntil: _date(raw['grace_until']),
      productId:
          raw['product_id'] is String ? raw['product_id'] as String : null,
      paymentMethod: method is Map
          ? BillingPaymentMethod(
              brand:
                  method['brand'] is String ? method['brand'] as String : null,
              lastFour: method['last_four'] is String
                  ? method['last_four'] as String
                  : null,
              expMonth: method['exp_month'] is int
                  ? method['exp_month'] as int
                  : null,
              expYear:
                  method['exp_year'] is int ? method['exp_year'] as int : null,
            )
          : null,
      canRenewOnFile: raw['can_renew_on_file'] == true,
      history: List.unmodifiable(history),
    );
  }

  static const Map<String, BillingEntryStatus> _statuses = {
    'pending': BillingEntryStatus.processing,
    'captured': BillingEntryStatus.paid,
    'failed': BillingEntryStatus.failed,
    'refunded': BillingEntryStatus.refunded,
  };

  static PlusBillingCycle? _cycle(Object? value) => switch (value) {
        'monthly' => PlusBillingCycle.monthly,
        'annual' => PlusBillingCycle.annual,
        _ => null,
      };

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// What the card component needs. The public key is safe in a browser, and the
/// amount shown comes from the server.
@immutable
class TapSession {
  const TapSession({
    required this.publicKey,
    required this.amount,
    required this.currency,
  });

  final String publicKey;
  final double amount;
  final String currency;
}

/// A started payment or card change. [paymentPage] is Tap's own secure page.
@immutable
class TapStart {
  const TapStart({required this.id, this.paymentPage});

  final String id;
  final Uri? paymentPage;
}

/// Payment choices the server allows to be presented. Changed only by the
/// owner on the server, with a recorded eligibility basis.
@immutable
class BillingChannels {
  const BillingChannels({required this.androidCardChoice});

  static const BillingChannels closed =
      BillingChannels(androidCardChoice: false);

  /// Tap next to Google Play inside the Android app.
  final bool androidCardChoice;

  factory BillingChannels.fromJson(Object? raw) {
    if (raw is! Map || raw['android_card_choice'] is! bool) {
      throw const FormatException('channels');
    }
    return BillingChannels(
      androidCardChoice: raw['android_card_choice'] as bool,
    );
  }
}

/// The app's door to the trusted billing function. It names no account, price
/// or entitlement: the server takes all of them from the verified session.
abstract interface class BillingBackend {
  Future<BillingOverview> fetchOverview();

  /// Which payment choices may be presented. Unknown is [BillingChannels.closed].
  Future<BillingChannels> fetchChannels();

  /// The opaque reference a Google Play purchase is made under.
  Future<String> preparePlayPurchase();

  /// Asks the server to verify these purchase tokens with Google.
  Future<StoreSyncResult> verifyPlayPurchases(List<String> purchaseTokens);

  Future<TapSession> tapSession(PlusBillingCycle cycle);
  Future<TapStart> tapCheckout(PlusBillingCycle cycle, {String? cardToken});

  /// Asks the server to read this charge from Tap. Returns its settlement.
  Future<String> tapVerify(String chargeId);
  Future<String> tapSetAutoRenew(bool on);
  Future<TapStart> tapChangeCard({String? cardToken});
  Future<String> tapVerifyCardChange(String authorizeId);
}

class SupabaseBillingBackend implements BillingBackend {
  SupabaseBillingBackend({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<dynamic, dynamic>> _call(
    String route,
    Map<String, Object?> body,
  ) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'subscription-billing/$route',
        body: body,
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      throw BillingRefused(code is String ? code : 'unavailable');
    }
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final code = data is Map ? data['code'] : null;
      throw BillingRefused(code is String ? code : 'unavailable');
    }
    return data;
  }

  static String _name(PlusBillingCycle cycle) =>
      cycle == PlusBillingCycle.annual ? 'annual' : 'monthly';

  static TapStart _start(Map<dynamic, dynamic> data, String idKey) {
    final id = data[idKey];
    final page = data['checkoutUrl'];
    if (id is! String) throw const BillingRefused('unavailable');
    final uri = page is String ? Uri.tryParse(page) : null;
    // A payment page is only ever opened over HTTPS.
    if (page != null && uri?.scheme != 'https') {
      throw const BillingRefused('unavailable');
    }
    return TapStart(id: id, paymentPage: uri);
  }

  @override
  Future<BillingOverview> fetchOverview() async => BillingOverview.fromJson(
        await _client.rpc<dynamic>('get_billing_overview'),
      );

  @override
  Future<BillingChannels> fetchChannels() async => BillingChannels.fromJson(
        await _client.rpc<dynamic>('get_billing_channels'),
      );

  @override
  Future<String> preparePlayPurchase() async {
    final reference = (await _call('play/prepare', const {}))['accountRef'];
    if (reference is! String) throw const BillingRefused('unavailable');
    return reference;
  }

  @override
  Future<StoreSyncResult> verifyPlayPurchases(
    List<String> purchaseTokens,
  ) async {
    try {
      await _call('play/verify', {'purchaseTokens': purchaseTokens});
      return StoreSyncResult.synced;
    } on BillingRefused catch (refusal) {
      return switch (refusal.code) {
        'too_soon' => StoreSyncResult.tooSoon,
        'purchase_linked_to_another_account' ||
        'purchase_not_linked' =>
          StoreSyncResult.linkedToOtherAccount,
        _ => StoreSyncResult.unavailable,
      };
    }
  }

  @override
  Future<TapSession> tapSession(PlusBillingCycle cycle) async {
    final data = await _call('tap/session', {'cycle': _name(cycle)});
    final key = data['publicKey'];
    final amount = data['amount'];
    final currency = data['currency'];
    if (key is! String || amount is! num || currency is! String) {
      throw const BillingRefused('unavailable');
    }
    return TapSession(
      publicKey: key,
      amount: amount.toDouble(),
      currency: currency,
    );
  }

  @override
  Future<TapStart> tapCheckout(
    PlusBillingCycle cycle, {
    String? cardToken,
  }) async =>
      _start(
        await _call('tap/checkout', {
          'cycle': _name(cycle),
          if (cardToken != null) 'token': cardToken,
        }),
        'chargeId',
      );

  @override
  Future<String> tapVerify(String chargeId) async {
    final outcome =
        (await _call('tap/verify', {'chargeId': chargeId}))['outcome'];
    return outcome is String ? outcome : 'unknown';
  }

  @override
  Future<String> tapSetAutoRenew(bool on) async {
    final outcome = (await _call('tap/renewal', {'autoRenew': on}))['outcome'];
    return outcome is String ? outcome : 'unknown';
  }

  @override
  Future<TapStart> tapChangeCard({String? cardToken}) async => _start(
        await _call('tap/card', {if (cardToken != null) 'token': cardToken}),
        'authorizeId',
      );

  @override
  Future<String> tapVerifyCardChange(String authorizeId) async {
    final outcome = (await _call(
        'tap/card/verify', {'authorizeId': authorizeId}))['outcome'];
    return outcome is String ? outcome : 'unknown';
  }
}

/// Where the billing screens get their backends. Tests replace these.
abstract final class BillingServices {
  static BillingBackend Function() billing = SupabaseBillingBackend.new;
  static SubscriptionBackend Function() subscription =
      SupabaseSubscriptionBackend.new;

  /// One store gateway per process: it owns the Play purchase stream.
  static StorePurchaseGateway Function() store = _sharedStore;

  static StorePurchaseGateway? _store;
  static StorePurchaseGateway _sharedStore() =>
      _store ??= createDefaultStoreGateway();

  @visibleForTesting
  static void debugReset() {
    billing = SupabaseBillingBackend.new;
    subscription = SupabaseSubscriptionBackend.new;
    store = _sharedStore;
  }
}
