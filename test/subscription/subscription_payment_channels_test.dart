import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/payment_navigation.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/services/web_start_route.dart';
import 'package:broker_wallet/src/viewmodels/billing_center_controller.dart';
import 'package:broker_wallet/src/viewmodels/tap_checkout_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

// Fakes on every side: this proves that the app grants nothing by itself and
// follows each provider's rules. It is not evidence of a working Tap or Play
// integration.

SubscriptionServerState _state({String plan = 'free', bool isTest = false}) =>
    SubscriptionServerState.fromJson({
      'plan': plan,
      'status': plan == 'plus' ? 'plus_renewing' : 'free',
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

class _Subscription implements SubscriptionBackend {
  _Subscription(this.state);

  SubscriptionServerState state;

  @override
  Future<SubscriptionServerState> fetchState() async => state;

  @override
  Future<StoreSyncResult> syncWithStore() async => StoreSyncResult.synced;

  @override
  Future<SubscriptionServerState> testControl(String action) =>
      throw UnimplementedError();
}

class _Billing implements BillingBackend {
  List<String> verifyAnswers = ['captured'];
  List<String> cardAnswers = ['applied'];
  Object? startError;
  Object? verifyError;
  Uri? page = Uri.https('checkout.test', '/1');
  String? lastToken;
  int verifies = 0;
  String renewalAnswer = 'renewal_off';
  bool overviewFails = false;

  @override
  Future<BillingOverview> fetchOverview() async {
    if (overviewFails) throw StateError('down');
    return BillingOverview.fromJson({
      'provider': 'tap',
      'state': 'active',
      'auto_renew': true,
      'can_renew_on_file': true,
      'history': const <Object?>[],
    });
  }

  @override
  Future<BillingChannels> fetchChannels() async => BillingChannels.closed;

  @override
  Future<String> preparePlayPurchase() async => 'reference';

  @override
  Future<StoreSyncResult> verifyPlayPurchases(List<String> tokens) async =>
      StoreSyncResult.synced;

  @override
  Future<TapSession> tapSession(PlusBillingCycle cycle) async => TapSession(
        publicKey: 'pk_test_1',
        amount: cycle == PlusBillingCycle.annual ? 180 : 20,
        currency: 'AED',
      );

  @override
  Future<TapStart> tapCheckout(PlusBillingCycle cycle,
      {String? cardToken}) async {
    lastToken = cardToken;
    final error = startError;
    if (error != null) throw error;
    return TapStart(id: 'chg_abcd', paymentPage: page);
  }

  @override
  Future<String> tapVerify(String chargeId) async {
    verifies++;
    final error = verifyError;
    if (error != null) throw error;
    return verifyAnswers.length > 1
        ? verifyAnswers.removeAt(0)
        : verifyAnswers.single;
  }

  @override
  Future<String> tapSetAutoRenew(bool on) async => renewalAnswer;

  @override
  Future<TapStart> tapChangeCard({String? cardToken}) async {
    lastToken = cardToken;
    return TapStart(id: 'auth_abcd', paymentPage: page);
  }

  @override
  Future<String> tapVerifyCardChange(String authorizeId) async =>
      cardAnswers.length > 1 ? cardAnswers.removeAt(0) : cardAnswers.single;
}

void main() {
  TapCheckoutController flow(
    _Billing billing,
    SubscriptionServerState state, {
    bool opens = true,
    List<Uri>? opened,
  }) =>
      TapCheckoutController(
        billing: billing,
        subscription: _Subscription(state),
        openPage: (uri) async {
          opened?.add(uri);
          return opens;
        },
        wait: (_) async {},
      );

  group('card checkout grants nothing by itself', () {
    test('a token and a redirect never activate Plus', () async {
      final billing = _Billing();
      final opened = <Uri>[];
      final controller = flow(billing, _state(), opened: opened);
      await controller.pay(PlusBillingCycle.monthly, cardToken: 'tok_abcd');
      expect(billing.lastToken, 'tok_abcd');
      expect(opened, [billing.page]);
      expect(controller.step, TapCheckoutStep.pending);
      expect(billing.verifies, 0);
    });

    test('a captured charge activates only if the server reports Plus',
        () async {
      final activated = flow(_Billing(), _state(plan: 'plus'));
      await activated.confirm('chg_abcd');
      expect(activated.step, TapCheckoutStep.activated);

      final notYet = flow(_Billing(), _state());
      await notYet.confirm('chg_abcd');
      expect(notYet.step, TapCheckoutStep.pending);
    });

    test('a test entitlement is never a completed payment', () async {
      final controller = flow(_Billing(), _state(plan: 'plus', isTest: true));
      await controller.confirm('chg_abcd');
      expect(controller.step, TapCheckoutStep.pending);
    });

    test('a charge still open is polled, then reported as pending', () async {
      final billing = _Billing()..verifyAnswers = ['pending'];
      final controller = flow(billing, _state(plan: 'plus'));
      await controller.confirm('chg_abcd');
      expect(controller.step, TapCheckoutStep.pending);
      expect(billing.verifies, controller.confirmAttempts);
    });

    test('a charge that settles during polling activates', () async {
      final billing = _Billing()
        ..verifyAnswers = ['pending', 'pending', 'captured'];
      final controller = flow(billing, _state(plan: 'plus'));
      await controller.confirm('chg_abcd');
      expect(controller.step, TapCheckoutStep.activated);
      expect(billing.verifies, 3);
    });

    for (final outcome in [
      'failed',
      'amount_mismatch',
      'charge_mismatch',
      'no_account',
    ]) {
      test('$outcome ends the flow as failed', () async {
        final billing = _Billing()..verifyAnswers = [outcome];
        final controller = flow(billing, _state(plan: 'plus'));
        await controller.confirm('chg_abcd');
        expect(controller.step, TapCheckoutStep.failed);
        expect(billing.verifies, 1);
      });
    }

    test('a charge of another account is a failure', () async {
      final billing = _Billing()
        ..verifyError = const BillingRefused('not_found');
      final controller = flow(billing, _state(plan: 'plus'));
      await controller.confirm('chg_abcd');
      expect(controller.step, TapCheckoutStep.failed);
    });

    test('an outage while confirming stays pending, never a failure', () async {
      final billing = _Billing()
        ..verifyError = const BillingRefused('provider_unavailable');
      final controller = flow(billing, _state());
      await controller.confirm('chg_abcd');
      expect(controller.step, TapCheckoutStep.pending);
    });

    test('server refusals keep their meaning', () async {
      for (final (code, step) in [
        ('phone_required', TapCheckoutStep.phoneRequired),
        ('already_plus', TapCheckoutStep.alreadyPlus),
        ('provider_unavailable', TapCheckoutStep.failed),
      ]) {
        final billing = _Billing()..startError = BillingRefused(code);
        final controller = flow(billing, _state());
        await controller.pay(PlusBillingCycle.annual);
        expect(controller.step, step, reason: code);
      }
    });

    test('a payment page that cannot open is a failure', () async {
      final controller = flow(_Billing(), _state(), opens: false);
      await controller.pay(PlusBillingCycle.annual);
      expect(controller.step, TapCheckoutStep.failed);
    });

    test('a card change is confirmed by the server', () async {
      final applied = flow(_Billing(), _state());
      await applied.confirm('auth_abcd');
      expect(applied.step, TapCheckoutStep.cardUpdated);

      final refused =
          flow(_Billing()..cardAnswers = ['needs_review'], _state());
      await refused.confirm('auth_abcd');
      expect(refused.step, TapCheckoutStep.failed);
    });
  });

  group('platform rules', () {
    const free = SubscriptionPresentation(status: SubscriptionStatus.free);

    test('a production Android build never offers Tap', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.android,
          free,
          debugBuild: false,
          cardTestAllowed: false,
        ),
        [PaymentOption.googlePlay],
      );
      expect(
        SubscriptionPlatformPolicy.canStartCheckout(
          SubscriptionPlatform.android,
          PaymentOption.tapCard,
          backendEnabled: true,
          cardTestAllowed: false,
        ),
        isFalse,
      );
    });

    test('a debug build on isolated Staging may test the Tap choice', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.android,
          free,
          cardTestAllowed: true,
        ),
        [PaymentOption.googlePlay, PaymentOption.tapCard],
      );
    });

    test('this test build is not allowed the Android Tap choice', () {
      expect(SubscriptionPlatformPolicy.androidCardTestAllowed, isFalse);
    });

    test('iPhone has no payment option and no checkout at all', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.ios,
          free,
          cardTestAllowed: true,
        ),
        isEmpty,
      );
      for (final option in PaymentOption.values) {
        expect(
          SubscriptionPlatformPolicy.canStartCheckout(
            SubscriptionPlatform.ios,
            option,
            backendEnabled: true,
            cardTestAllowed: true,
            storeAvailable: true,
          ),
          isFalse,
        );
      }
      expect(
        SubscriptionPlatformPolicy.showsPurchaseJourney(
          SubscriptionPlatform.ios,
        ),
        isFalse,
      );
    });

    test('the iPhone web-activation sheet is gone outside debug', () {
      expect(
        SubscriptionPlatformPolicy.canShowIosWebActivationPreview(
          debugBuild: false,
        ),
        isFalse,
      );
    });

    test('the web app pays by card, and only with the backend on', () {
      expect(
        SubscriptionPlatformPolicy.paymentOptions(
          SubscriptionPlatform.web,
          free,
        ),
        [PaymentOption.tapCard],
      );
      expect(
        SubscriptionPlatformPolicy.canStartCheckout(
          SubscriptionPlatform.web,
          PaymentOption.tapCard,
          backendEnabled: true,
        ),
        isTrue,
      );
      expect(
        SubscriptionPlatformPolicy.canStartCheckout(
          SubscriptionPlatform.web,
          PaymentOption.tapCard,
          backendEnabled: false,
        ),
        isFalse,
      );
    });

    test('Google Play starts only when the store is really connected', () {
      bool play(bool connected) => SubscriptionPlatformPolicy.canStartCheckout(
            SubscriptionPlatform.android,
            PaymentOption.googlePlay,
            backendEnabled: true,
            storeAvailable: connected,
          );
      expect(play(false), isFalse);
      expect(play(true), isTrue);
    });

    test('the web cannot act on a Google subscription', () {
      expect(
        SubscriptionPlatformPolicy.managementPath(
          SubscriptionPlatform.web,
          BillingProvider.googlePlay,
        ),
        ManagementPath.otherStore,
      );
      expect(
        SubscriptionPlatformPolicy.managementPath(
          SubscriptionPlatform.web,
          BillingProvider.tap,
        ),
        ManagementPath.tapBilling,
      );
      expect(
        SubscriptionPlatformPolicy.showsRestore(SubscriptionPlatform.web),
        isFalse,
      );
    });
  });

  group('browser return', () {
    setUp(PaymentReturnStore.debugReset);
    tearDown(PaymentReturnStore.debugReset);

    Uri back(String id) => Uri.parse(
          'https://app.test${SubscriptionRoutes.paymentReturn}?tap_id=$id',
        );

    test('only a well-formed id on the return route is kept', () {
      PaymentReturnStore.capture(
          Uri.parse('https://app.test/home?tap_id=chg_abcd'));
      expect(PaymentReturnStore.pendingId, isNull);
      PaymentReturnStore.capture(back('javascript:alert(1)'));
      expect(PaymentReturnStore.pendingId, isNull);
      PaymentReturnStore.capture(back('chg_abcd'));
      expect(PaymentReturnStore.pendingId, 'chg_abcd');
    });

    test('it is used once', () {
      PaymentReturnStore.capture(back('auth_abcd'));
      expect(PaymentReturnStore.take(), 'auth_abcd');
      expect(PaymentReturnStore.take(), isNull);
    });

    test('it waits for sign-in', () {
      PaymentReturnStore.capture(back('chg_abcd'));
      expect(
        PaymentReturnStore.redirectFor('/welcome', isAuthenticated: false),
        isNull,
      );
      expect(
        PaymentReturnStore.redirectFor('/home', isAuthenticated: true),
        SubscriptionRoutes.paymentReturn,
      );
      expect(
        PaymentReturnStore.redirectFor(
          SubscriptionRoutes.paymentReturn,
          isAuthenticated: true,
        ),
        isNull,
      );
    });
  });

  group('browser refresh', () {
    setUp(WebStartRoute.debugReset);
    tearDown(WebStartRoute.debugReset);

    test('an inner page is kept until it is reached', () {
      WebStartRoute.capture(
        Uri.parse('https://app.test/subscription-checkout?cycle=annual'),
      );
      expect(WebStartRoute.pending, '/subscription-checkout?cycle=annual');
      // The router may evaluate its redirect several times first.
      WebStartRoute.arrived('/');
      expect(WebStartRoute.pending, '/subscription-checkout?cycle=annual');
      WebStartRoute.arrived('/subscription-checkout');
      expect(WebStartRoute.pending, isNull);
    });

    test('entry pages and foreign-looking paths are not kept', () {
      for (final path in ['/', '/home', '/welcome', '/sign-in']) {
        WebStartRoute.capture(Uri.parse('https://app.test$path'));
        expect(WebStartRoute.pending, isNull, reason: path);
      }
      WebStartRoute.capture(Uri.parse('https://app.test//evil.test/x'));
      expect(WebStartRoute.pending, isNull);
    });
  });

  group('billing overview', () {
    Map<String, Object?> valid() => {
          'provider': 'tap',
          'state': 'billing_issue',
          'cycle': 'annual',
          'auto_renew': true,
          'paid_through': '2027-01-01T00:00:00Z',
          'payment_method': {
            'brand': 'VISA',
            'last_four': '4242',
            'exp_month': 1,
            'exp_year': 2030,
          },
          'can_renew_on_file': true,
          'history': [
            {
              'id': '22222222-2222-4222-8222-222222222222',
              'kind': 'renewal',
              'cycle': 'annual',
              'amount': 180,
              'currency': 'AED',
              'status': 'captured',
              'at': '2026-11-01T00:00:00Z',
            },
          ],
        };

    test('parses the server answer', () {
      final overview = BillingOverview.fromJson(valid());
      expect(overview.provider, BillingProvider.tap);
      expect(overview.hasPaymentIssue, isTrue);
      expect(overview.paymentMethod?.lastFour, '4242');
      expect(overview.history.single.amount, '180.00');
      expect(overview.history.single.status, BillingEntryStatus.paid);
      expect(overview.history.single.isRenewal, isTrue);
    });

    test('an account with no subscription is valid', () {
      final overview = BillingOverview.fromJson({
        'provider': null,
        'state': null,
        'auto_renew': false,
        'payment_method': null,
        'can_renew_on_file': null,
        'history': const <Object?>[],
      });
      expect(overview.provider, isNull);
      expect(overview.canRenewOnFile, isFalse);
    });

    test('an answer it cannot read is refused', () {
      for (final broken in <Object?>[
        null,
        'x',
        {...valid(), 'auto_renew': 'yes'},
        {...valid(), 'history': 'none'},
        {...valid(), 'payment_method': 'card'},
        {
          ...valid(),
          'history': [
            {'id': 1},
          ],
        },
        {
          ...valid(),
          'history': [
            {
              ...(valid()['history'] as List).single as Map<String, Object?>,
              'status': 'created',
            },
          ],
        },
      ]) {
        expect(() => BillingOverview.fromJson(broken), throwsFormatException);
      }
    });

    test('a failed read is not an empty account', () async {
      final controller = BillingCenterController(
        billing: _Billing()..overviewFails = true,
      );
      await controller.load();
      expect(controller.hasFailed, isTrue);
      expect(controller.overview, isNull);
    });

    test('a renewal change counts only when the server applied it', () async {
      final applied = BillingCenterController(billing: _Billing());
      expect(await applied.setAutoRenew(false), isTrue);
      expect(applied.actionFailed, isFalse);

      final refused = BillingCenterController(
        billing: _Billing()..renewalAnswer = 'not_active',
      );
      expect(await refused.setAutoRenew(false), isFalse);
      expect(refused.actionFailed, isTrue);
    });
  });
}
