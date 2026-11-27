import 'dart:async';

import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/google_play_store_gateway.dart';
import 'package:broker_wallet/src/services/subscription/store_purchase_gateway.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// A fake Play Billing seam: this proves the gateway's own decisions, never a
// working Google Play purchase.

class _Play implements PlayBillingApi {
  bool ready = true;
  bool launches = true;
  List<PlayOffer> offers = const [
    PlayOffer(
      productId: 'broker_wallet_plus',
      basePlanId: 'monthly',
      isBasePlan: true,
      priceLabel: 'AED 20.00',
    ),
    PlayOffer(
      productId: 'broker_wallet_plus',
      basePlanId: 'annual',
      isBasePlan: true,
      priceLabel: 'AED 180.00',
    ),
    PlayOffer(
      productId: 'broker_wallet_plus',
      basePlanId: 'annual',
      isBasePlan: false,
      priceLabel: 'AED 1.00',
    ),
    PlayOffer(
      productId: 'broker_wallet_plus',
      basePlanId: 'weekly',
      isBasePlan: true,
      priceLabel: 'AED 5.00',
    ),
  ];
  List<PlayPurchaseUpdate> active = const [];
  final controller = StreamController<List<PlayPurchaseUpdate>>.broadcast();
  List<PlayPurchaseUpdate>? answer;
  final launched = <(String, String)>[];

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<List<PlayOffer>> offersFor(String productId) async =>
      offers.where((o) => o.productId == productId).toList();

  @override
  Stream<List<PlayPurchaseUpdate>> get updates => controller.stream;

  @override
  Future<bool> launch(PlayOffer offer,
      {required String accountReference}) async {
    launched.add((offer.basePlanId, accountReference));
    final reply = answer;
    if (reply != null) scheduleMicrotask(() => controller.add(reply));
    return launches;
  }

  @override
  Future<List<PlayPurchaseUpdate>> activePurchases() async => active;
}

GooglePlayStoreGateway _gateway(_Play play) => GooglePlayStoreGateway(
      api: play,
      config: const PlayBillingConfig(
        productId: 'broker_wallet_plus',
        monthlyBasePlanId: 'monthly',
        annualBasePlanId: 'annual',
      ),
    );

PlayPurchaseUpdate _update(
  PlayPurchaseState state, {
  String product = 'broker_wallet_plus',
  String? token = 'token-1',
}) =>
    PlayPurchaseUpdate(productId: product, state: state, purchaseToken: token);

class _Subscription implements SubscriptionBackend {
  @override
  Future<SubscriptionServerState> fetchState() async =>
      SubscriptionServerState.fromJson({
        'plan': 'free',
        'status': 'free',
        'read_only': false,
        'is_test': false,
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

  @override
  Future<StoreSyncResult> syncWithStore() async => StoreSyncResult.synced;

  @override
  Future<SubscriptionServerState> testControl(String action) =>
      throw UnimplementedError();
}

void main() {
  group('Google Play gateway', () {
    test('only the configured plain base plans are offered, at Play\'s price',
        () async {
      final products = await _gateway(_Play()).loadProducts();
      expect(
        {for (final p in products) p.cycle: p.priceLabel},
        {
          PlusBillingCycle.monthly: 'AED 20.00',
          PlusBillingCycle.annual: 'AED 180.00',
        },
      );
    });

    test('an unready store offers nothing', () async {
      expect(await _gateway(_Play()..ready = false).loadProducts(), isEmpty);
    });

    test('a purchase runs under the server reference and returns its token',
        () async {
      final play = _Play()..answer = [_update(PlayPurchaseState.purchased)];
      final result = await _gateway(play).purchase(
        PlusBillingCycle.annual,
        accountReference: 'server-ref',
      );
      expect(play.launched, [('annual', 'server-ref')]);
      expect(result.outcome, StorePurchaseOutcome.purchased);
      expect(result.purchaseTokens, ['token-1']);
    });

    test('each store answer keeps its meaning', () async {
      for (final (state, outcome) in [
        (PlayPurchaseState.pending, StorePurchaseOutcome.pending),
        (PlayPurchaseState.cancelled, StorePurchaseOutcome.cancelled),
        (PlayPurchaseState.failed, StorePurchaseOutcome.failed),
      ]) {
        final play = _Play()..answer = [_update(state, product: '')];
        final result = await _gateway(play).purchase(
          PlusBillingCycle.monthly,
          accountReference: 'r',
        );
        expect(result.outcome, outcome, reason: '$state');
        expect(result.purchaseTokens, isEmpty);
      }
    });

    test('an answer about another product is not this purchase', () async {
      final play = _Play()
        ..answer = [
          _update(PlayPurchaseState.purchased, product: 'other', token: 'x'),
          _update(PlayPurchaseState.purchased),
        ];
      final result = await _gateway(play).purchase(
        PlusBillingCycle.monthly,
        accountReference: 'r',
      );
      expect(result.purchaseTokens, ['token-1']);
    });

    test('a sheet that cannot open is a failure', () async {
      final result = await _gateway(_Play()..launches = false).purchase(
        PlusBillingCycle.monthly,
        accountReference: 'r',
      );
      expect(result.outcome, StorePurchaseOutcome.failed);
    });

    test('a plan Play does not have is unavailable, and nothing opens',
        () async {
      final play = _Play()..offers = const [];
      final result = await _gateway(play).purchase(
        PlusBillingCycle.annual,
        accountReference: 'r',
      );
      expect(result.outcome, StorePurchaseOutcome.unavailable);
      expect(play.launched, isEmpty);
    });

    test('no answer is pending, never success', () async {
      final result = await GooglePlayStoreGateway(
        api: _Play(),
        purchaseTimeout: const Duration(milliseconds: 10),
        config: const PlayBillingConfig(
          productId: 'broker_wallet_plus',
          monthlyBasePlanId: 'monthly',
          annualBasePlanId: 'annual',
        ),
      ).purchase(PlusBillingCycle.monthly, accountReference: 'r');
      expect(result.outcome, StorePurchaseOutcome.pending);
    });

    test('restore hands only this product\'s completed tokens to the server',
        () async {
      final play = _Play()
        ..active = [
          _update(PlayPurchaseState.purchased, token: 'mine'),
          _update(PlayPurchaseState.pending, token: 'waiting'),
          _update(PlayPurchaseState.purchased, product: 'other', token: 'x'),
          _update(PlayPurchaseState.purchased, token: ''),
        ];
      final result = await _gateway(play).restore();
      expect(result.purchaseTokens, ['mine']);
    });

    test('the identifiers match the documented Play Console setup', () {
      const config = PlayBillingConfig.fromBuild;
      expect(config.productId, 'broker_wallet_plus');
      expect(config.cycleOf('monthly'), PlusBillingCycle.monthly);
      expect(config.cycleOf('annual'), PlusBillingCycle.annual);
      expect(config.cycleOf('weekly'), isNull);
    });

    test('outside the Android app the default gateway stays closed', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(createDefaultStoreGateway().isAvailable, isFalse,
            reason: '$platform');
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(createDefaultStoreGateway().isAvailable, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('server-controlled payment choices', () {
    test('the card choice is off unless the server turns it on', () async {
      final closed = SubscriptionStateController(
        backend: _Subscription.new,
        channels: () async => BillingChannels.closed,
      )..attachUser('a');
      await Future<void>.delayed(Duration.zero);
      await closed.refresh();
      expect(closed.presentation.tapCardEligibilityVerified, isFalse);

      final open = SubscriptionStateController(
        backend: _Subscription.new,
        channels: () async => const BillingChannels(androidCardChoice: true),
      )..attachUser('a');
      await open.refresh();
      expect(open.presentation.tapCardEligibilityVerified, isTrue);
    });

    test('a failed read keeps the card choice off', () async {
      final controller = SubscriptionStateController(
        backend: _Subscription.new,
        channels: () async => throw StateError('down'),
      )..attachUser('a');
      await controller.refresh();
      expect(controller.presentation.tapCardEligibilityVerified, isFalse);
    });

    test('channels parse strictly', () {
      expect(
        BillingChannels.fromJson({'android_card_choice': true})
            .androidCardChoice,
        isTrue,
      );
      for (final bad in <Object?>[
        null,
        {},
        {'android_card_choice': 'yes'}
      ]) {
        expect(() => BillingChannels.fromJson(bad), throwsFormatException);
      }
    });
  });

  group('tax documents', () {
    Map<String, Object?> invoice() => {
          'kind': 'tax_invoice',
          'number': 'BW-INV-2026-000001',
          'issued_at': '2026-11-26T10:00:00Z',
          'total_fils': 2000,
          'vat_fils': 95,
          'net_fils': 1905,
          'vat_rate_bp': 500,
          'supplier': 'NMO Digital LLC',
          'trn': '100000000000003',
          'address': 'Dubai',
        };

    test('an issued invoice is read exactly', () {
      final document = BillingTaxDocument.parse(invoice());
      expect(document.isCreditNote, isFalse);
      expect(BillingTaxDocument.money(document.netFils), '19.05');
      expect(BillingTaxDocument.money(document.vatFils), '0.95');
      expect(BillingTaxDocument.money(document.totalFils), '20.00');
    });

    test('a document whose amounts do not add up is refused', () {
      for (final bad in [
        {...invoice(), 'vat_fils': 96},
        {...invoice(), 'kind': 'receipt'},
        {...invoice(), 'trn': null},
        {...invoice(), 'total_fils': 20.0},
      ]) {
        expect(() => BillingTaxDocument.parse(bad), throwsFormatException);
      }
    });

    test('the billing view carries its documents', () {
      final overview = BillingOverview.fromJson({
        'provider': 'tap',
        'state': 'active',
        'auto_renew': true,
        'can_renew_on_file': true,
        'history': [
          {
            'id': '22222222-2222-4222-8222-222222222222',
            'kind': 'initial',
            'cycle': 'monthly',
            'amount': 20,
            'currency': 'AED',
            'status': 'captured',
            'at': '2026-11-26T10:00:00Z',
            'documents': [invoice()],
          },
        ],
      });
      expect(overview.history.single.documents.single.number,
          'BW-INV-2026-000001');
    });
  });
}
