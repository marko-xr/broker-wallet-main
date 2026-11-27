import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/store_purchase_gateway.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/viewmodels/subscription_checkout_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

// Fakes on both sides: this proves that a store callback alone never grants
// Plus. It is not evidence of a working Google Play integration.

SubscriptionServerState _state({
  String plan = 'free',
  String status = 'free',
  bool isTest = false,
}) =>
    SubscriptionServerState.fromJson({
      'plan': plan,
      'status': status,
      'read_only': false,
      'is_test': isTest,
      'usage': {
        for (final s in [
          'requests',
          'offers',
          'owners',
          'offices',
          'brokers',
          'watchmen',
          'quotations',
          'scanner',
          'signature',
          'image_to_pdf',
          'combine_pdfs',
        ])
          s: 0,
      },
      'items': const <Object?>[],
      'test_mode': {'available': false, 'scenario': null, 'expires_at': null},
    });

class _Store implements StorePurchaseGateway {
  _Store(this.outcome, {this.tokens = const ['play-token']});

  StorePurchaseOutcome outcome;
  List<String> tokens;
  Object? error;
  final references = <String>[];

  @override
  bool get isAvailable => true;

  @override
  Future<List<StoreProduct>> loadProducts() async => const [];

  @override
  Future<StorePurchaseResult> purchase(
    PlusBillingCycle cycle, {
    required String accountReference,
  }) async {
    references.add(accountReference);
    final failure = error;
    if (failure != null) throw failure;
    return StorePurchaseResult(outcome, purchaseTokens: tokens);
  }

  @override
  Future<StorePurchaseResult> restore() async =>
      StorePurchaseResult(outcome, purchaseTokens: tokens);
}

class _Billing implements BillingBackend {
  StoreSyncResult verifyResult = StoreSyncResult.synced;
  final verified = <List<String>>[];

  @override
  Future<BillingChannels> fetchChannels() async => BillingChannels.closed;

  @override
  Future<String> preparePlayPurchase() async => 'server-reference';

  @override
  Future<StoreSyncResult> verifyPlayPurchases(List<String> tokens) async {
    verified.add(tokens);
    return verifyResult;
  }

  @override
  Future<BillingOverview> fetchOverview() => throw UnimplementedError();

  @override
  Future<TapSession> tapSession(PlusBillingCycle cycle) =>
      throw UnimplementedError();

  @override
  Future<TapStart> tapCheckout(PlusBillingCycle cycle, {String? cardToken}) =>
      throw UnimplementedError();

  @override
  Future<String> tapVerify(String chargeId) => throw UnimplementedError();

  @override
  Future<String> tapSetAutoRenew(bool on) => throw UnimplementedError();

  @override
  Future<TapStart> tapChangeCard({String? cardToken}) =>
      throw UnimplementedError();

  @override
  Future<String> tapVerifyCardChange(String authorizeId) =>
      throw UnimplementedError();
}

class _Backend implements SubscriptionBackend {
  _Backend(this.states);

  final List<SubscriptionServerState> states;
  StoreSyncResult sync = StoreSyncResult.synced;
  int syncs = 0;
  bool failing = false;

  @override
  Future<SubscriptionServerState> fetchState() async {
    if (failing) throw StateError('down');
    return states.length > 1 ? states.removeAt(0) : states.single;
  }

  @override
  Future<StoreSyncResult> syncWithStore() async {
    syncs++;
    return sync;
  }

  @override
  Future<SubscriptionServerState> testControl(String action) =>
      throw UnimplementedError();
}

void main() {
  final plus = _state(plan: 'plus', status: 'plus_renewing');

  SubscriptionCheckoutController controller(
    StorePurchaseGateway store,
    SubscriptionBackend backend, {
    _Billing? billing,
  }) =>
      SubscriptionCheckoutController(
        store: store,
        backend: backend,
        billing: billing ?? _Billing(),
        wait: (_) async {},
      );

  Future<CheckoutResult> buy(
    _Store store,
    _Backend backend, {
    _Billing? billing,
  }) =>
      controller(store, backend, billing: billing)
          .purchase(PlusBillingCycle.monthly);

  test('the default gateway keeps every purchase closed', () async {
    const store = UnavailableStoreGateway();
    final backend = _Backend([plus]);
    expect(store.isAvailable, isFalse);
    expect(
      await controller(store, backend).purchase(PlusBillingCycle.annual),
      CheckoutResult.unavailable,
    );
    expect(backend.syncs, 0);
  });

  test('a store success activates only when the server confirms', () async {
    final store = _Store(StorePurchaseOutcome.purchased);
    final billing = _Billing();
    expect(
      await buy(store, _Backend([_state(), plus]), billing: billing),
      CheckoutResult.activated,
    );
    expect(store.references, ['server-reference']);
    expect(billing.verified.first, ['play-token']);
  });

  test('a store success the server never confirms is not Plus', () async {
    final billing = _Billing();
    expect(
      await buy(
        _Store(StorePurchaseOutcome.purchased),
        _Backend([_state()]),
        billing: billing,
      ),
      CheckoutResult.activationPending,
    );
    expect(billing.verified.length, 5);
  });

  test('a store success without a token is never Plus', () async {
    final billing = _Billing();
    expect(
      await buy(
        _Store(StorePurchaseOutcome.purchased, tokens: const []),
        _Backend([plus]),
        billing: billing,
      ),
      CheckoutResult.activationPending,
    );
    expect(billing.verified, isEmpty);
  });

  test('a backend outage after payment is pending, never a success', () async {
    final backend = _Backend([plus])..failing = true;
    expect(
      await buy(_Store(StorePurchaseOutcome.purchased), backend),
      CheckoutResult.activationPending,
    );
  });

  test('a test entitlement never counts as a real purchase', () async {
    final backend = _Backend([
      _state(plan: 'plus', status: 'plus_renewing', isTest: true),
    ]);
    expect(
      await buy(_Store(StorePurchaseOutcome.purchased), backend),
      CheckoutResult.activationPending,
    );
  });

  test('a purchase of another account is reported, not moved', () async {
    final billing = _Billing()
      ..verifyResult = StoreSyncResult.linkedToOtherAccount;
    expect(
      await buy(
        _Store(StorePurchaseOutcome.purchased),
        _Backend([plus]),
        billing: billing,
      ),
      CheckoutResult.linkedToOtherAccount,
    );
  });

  test('each store outcome maps to its own result', () async {
    final backend = _Backend([plus]);
    final billing = _Billing();
    expect(
      await buy(_Store(StorePurchaseOutcome.cancelled), backend,
          billing: billing),
      CheckoutResult.cancelled,
    );
    expect(
      await buy(_Store(StorePurchaseOutcome.pending), backend,
          billing: billing),
      CheckoutResult.purchasePending,
    );
    expect(
      await buy(_Store(StorePurchaseOutcome.failed), backend, billing: billing),
      CheckoutResult.failed,
    );
    expect(billing.verified, isEmpty);
  });

  test('a store error is a failure', () async {
    final store = _Store(StorePurchaseOutcome.purchased)
      ..error = StateError('billing');
    expect(await buy(store, _Backend([plus])), CheckoutResult.failed);
  });

  test('a restore with nothing active says so', () async {
    final result = await controller(
      _Store(StorePurchaseOutcome.purchased),
      _Backend([_state()]),
    ).restore();
    expect(result, CheckoutResult.nothingToRestore);
  });

  test('a restore the server confirms activates', () async {
    final result = await controller(
      _Store(StorePurchaseOutcome.purchased),
      _Backend([plus]),
    ).restore();
    expect(result, CheckoutResult.activated);
  });

  test('a non-public build has no release problem', () {
    if (!SupabaseConfig.isPublicRelease) {
      expect(SupabaseConfig.publicReleaseProblem, isNull);
    }
  });

  test(
    'a public build without the backend refuses to start',
    () => expect(SupabaseConfig.publicReleaseProblem, isNotNull),
    skip: SupabaseConfig.isPublicRelease &&
            !SupabaseConfig.subscriptionBackendEnabled
        ? false
        : 'needs --dart-define=BW_PUBLIC_RELEASE=true',
  );
}
