import 'dart:async';

import 'package:broker_wallet/src/services/subscription/store_purchase_gateway.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

/// The Play Console identifiers. They must equal the Play Console product and
/// base plans, and the server's GOOGLE_PLAY_PRODUCT_ID / GOOGLE_PLAY_BASE_PLANS.
/// None of them depends on a price.
@immutable
class PlayBillingConfig {
  const PlayBillingConfig({
    required this.productId,
    required this.monthlyBasePlanId,
    required this.annualBasePlanId,
  });

  static const PlayBillingConfig fromBuild = PlayBillingConfig(
    productId: String.fromEnvironment(
      'GOOGLE_PLAY_PRODUCT_ID',
      defaultValue: 'broker_wallet_plus',
    ),
    monthlyBasePlanId: String.fromEnvironment(
      'GOOGLE_PLAY_MONTHLY_BASE_PLAN',
      defaultValue: 'monthly',
    ),
    annualBasePlanId: String.fromEnvironment(
      'GOOGLE_PLAY_ANNUAL_BASE_PLAN',
      defaultValue: 'annual',
    ),
  );

  final String productId;
  final String monthlyBasePlanId;
  final String annualBasePlanId;

  PlusBillingCycle? cycleOf(String basePlanId) =>
      basePlanId == monthlyBasePlanId
          ? PlusBillingCycle.monthly
          : basePlanId == annualBasePlanId
              ? PlusBillingCycle.annual
              : null;
}

/// A base plan as Google Play returned it.
@immutable
class PlayOffer {
  const PlayOffer({
    required this.productId,
    required this.basePlanId,
    required this.isBasePlan,
    required this.priceLabel,
    this.handle,
  });

  final String productId;
  final String basePlanId;

  /// False for a promotional offer on top of the base plan.
  final bool isBasePlan;
  final String priceLabel;

  /// The plugin's own object, passed back when buying.
  final Object? handle;
}

enum PlayPurchaseState { purchased, pending, cancelled, failed }

@immutable
class PlayPurchaseUpdate {
  const PlayPurchaseUpdate({
    required this.productId,
    required this.state,
    this.purchaseToken,
  });

  /// Empty when Play reports a failure or cancellation without a purchase.
  final String productId;
  final PlayPurchaseState state;
  final String? purchaseToken;
}

/// The narrow part of the Play Billing plugin this app uses.
abstract interface class PlayBillingApi {
  Future<bool> isReady();
  Future<List<PlayOffer>> offersFor(String productId);
  Stream<List<PlayPurchaseUpdate>> get updates;

  /// Opens Google Play's own purchase sheet.
  Future<bool> launch(PlayOffer offer, {required String accountReference});

  /// Purchases Google Play holds for this device's Google account.
  Future<List<PlayPurchaseUpdate>> activePurchases();
}

/// Google Play Billing directly. It never acknowledges a purchase and never
/// decides access: it hands purchase tokens to the trusted server, which
/// verifies them with Google, binds them to one account and acknowledges.
class GooglePlayStoreGateway implements StorePurchaseGateway {
  GooglePlayStoreGateway({
    PlayBillingApi? api,
    this.config = PlayBillingConfig.fromBuild,
    this.purchaseTimeout = const Duration(minutes: 15),
  }) : _api = api;

  /// True only in the Android app.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final PlayBillingConfig config;
  final Duration purchaseTimeout;
  PlayBillingApi? _api;
  final Map<PlusBillingCycle, PlayOffer> _offers = {};

  PlayBillingApi get _billing => _api ??= _PluginPlayBillingApi();

  @override
  bool get isAvailable => _api != null || supported;

  @override
  Future<List<StoreProduct>> loadProducts() async {
    if (!isAvailable || !await _billing.isReady()) return const [];
    final offers = await _billing.offersFor(config.productId);
    _offers.clear();
    for (final offer in offers) {
      final cycle = config.cycleOf(offer.basePlanId);
      // The plain base plan only: no promotional offer has been approved.
      if (cycle == null ||
          !offer.isBasePlan ||
          offer.productId != config.productId) {
        continue;
      }
      _offers[cycle] = offer;
    }
    return [
      for (final MapEntry(:key, :value) in _offers.entries)
        StoreProduct(cycle: key, priceLabel: value.priceLabel),
    ];
  }

  @override
  Future<StorePurchaseResult> purchase(
    PlusBillingCycle cycle, {
    required String accountReference,
  }) async {
    if (!isAvailable) {
      return const StorePurchaseResult(StorePurchaseOutcome.unavailable);
    }
    if (!_offers.containsKey(cycle)) await loadProducts();
    final offer = _offers[cycle];
    if (offer == null) {
      return const StorePurchaseResult(StorePurchaseOutcome.unavailable);
    }

    final result = Completer<StorePurchaseResult>();
    late final StreamSubscription<List<PlayPurchaseUpdate>> listening;
    listening = _billing.updates.listen((updates) {
      for (final update in updates) {
        // An answer about another product is not this purchase's answer.
        if (update.productId.isNotEmpty &&
            update.productId != config.productId) {
          continue;
        }
        if (result.isCompleted) return;
        result.complete(switch (update.state) {
          PlayPurchaseState.purchased => StorePurchaseResult(
              StorePurchaseOutcome.purchased,
              purchaseTokens: [
                if (update.purchaseToken case final token?
                    when token.isNotEmpty)
                  token,
              ],
            ),
          PlayPurchaseState.pending =>
            const StorePurchaseResult(StorePurchaseOutcome.pending),
          PlayPurchaseState.cancelled =>
            const StorePurchaseResult(StorePurchaseOutcome.cancelled),
          PlayPurchaseState.failed =>
            const StorePurchaseResult(StorePurchaseOutcome.failed),
        });
        return;
      }
    });
    try {
      final launched =
          await _billing.launch(offer, accountReference: accountReference);
      if (!launched) {
        return const StorePurchaseResult(StorePurchaseOutcome.failed);
      }
      return await result.future.timeout(
        purchaseTimeout,
        // Google may still finish it; its notification reaches the server.
        onTimeout: () =>
            const StorePurchaseResult(StorePurchaseOutcome.pending),
      );
    } finally {
      await listening.cancel();
    }
  }

  @override
  Future<StorePurchaseResult> restore() async {
    if (!isAvailable) {
      return const StorePurchaseResult(StorePurchaseOutcome.unavailable);
    }
    final purchases = await _billing.activePurchases();
    final tokens = [
      for (final purchase in purchases)
        if (purchase.productId == config.productId &&
            purchase.state == PlayPurchaseState.purchased &&
            (purchase.purchaseToken ?? '').isNotEmpty)
          purchase.purchaseToken!,
    ];
    return StorePurchaseResult(
      StorePurchaseOutcome.purchased,
      purchaseTokens: tokens,
    );
  }
}

/// The official plugin behind [PlayBillingApi].
class _PluginPlayBillingApi implements PlayBillingApi {
  _PluginPlayBillingApi() {
    if (InAppPurchasePlatform.instance is! InAppPurchaseAndroidPlatform) {
      InAppPurchaseAndroidPlatform.registerPlatform();
    }
  }

  InAppPurchaseAndroidPlatform get _platform =>
      InAppPurchasePlatform.instance as InAppPurchaseAndroidPlatform;

  @override
  Future<bool> isReady() => _platform.isAvailable();

  @override
  Future<List<PlayOffer>> offersFor(String productId) async {
    final response = await _platform.queryProductDetails({productId});
    return [
      for (final details in response.productDetails)
        if (details is GooglePlayProductDetails)
          if (details.subscriptionIndex case final index?)
            if (details.productDetails.subscriptionOfferDetails?[index]
                case final offer?)
              PlayOffer(
                productId: details.id,
                basePlanId: offer.basePlanId,
                isBasePlan: offer.offerId == null,
                priceLabel: details.price,
                handle: details,
              ),
    ];
  }

  @override
  Stream<List<PlayPurchaseUpdate>> get updates => _platform.purchaseStream
      .map((purchases) => purchases.map(_update).toList());

  @override
  Future<bool> launch(PlayOffer offer, {required String accountReference}) {
    final details = offer.handle;
    if (details is! GooglePlayProductDetails) return Future.value(false);
    return _platform.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: details,
        // Becomes Google's obfuscatedExternalAccountId: the server's link to
        // exactly one Broker Wallet account.
        applicationUserName: accountReference,
      ),
    );
  }

  @override
  Future<List<PlayPurchaseUpdate>> activePurchases() async {
    final addition = InAppPurchasePlatformAddition.instance;
    if (addition is! InAppPurchaseAndroidPlatformAddition) return const [];
    final response = await addition.queryPastPurchases();
    if (response.error != null) throw StateError('play_query_failed');
    return response.pastPurchases.map(_update).toList();
  }

  static PlayPurchaseUpdate _update(PurchaseDetails purchase) =>
      PlayPurchaseUpdate(
        productId: purchase.productID,
        state: switch (purchase.status) {
          PurchaseStatus.purchased ||
          PurchaseStatus.restored =>
            PlayPurchaseState.purchased,
          PurchaseStatus.pending => PlayPurchaseState.pending,
          PurchaseStatus.canceled => PlayPurchaseState.cancelled,
          PurchaseStatus.error => PlayPurchaseState.failed,
        },
        purchaseToken: purchase.verificationData.serverVerificationData,
      );
}

/// The store gateway for this build: Google Play in the Android app, closed
/// everywhere else.
StorePurchaseGateway createDefaultStoreGateway() =>
    GooglePlayStoreGateway.supported
        ? GooglePlayStoreGateway()
        : const UnavailableStoreGateway();
