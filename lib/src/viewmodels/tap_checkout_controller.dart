import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';

enum TapCheckoutStep {
  preparing,
  ready,
  unavailable,
  paying,
  confirming,
  activated,
  cardUpdated,
  pending,
  failed,
  phoneRequired,
  alreadyPlus,
}

/// One card payment or card change. A token, a redirect or a callback never
/// activates anything here: [TapCheckoutStep.activated] is reached only when the
/// server read the charge from Tap and then reports Plus for this account.
class TapCheckoutController extends ChangeNotifier {
  TapCheckoutController({
    required BillingBackend billing,
    required SubscriptionBackend subscription,
    required Future<bool> Function(Uri) openPage,
    Future<void> Function(Duration)? wait,
    this.confirmAttempts = 6,
    this.confirmInterval = const Duration(seconds: 2),
  })  : _billing = billing,
        _subscription = subscription,
        _openPage = openPage,
        _wait = wait ?? Future<void>.delayed;

  final BillingBackend _billing;
  final SubscriptionBackend _subscription;
  final Future<bool> Function(Uri) _openPage;
  final Future<void> Function(Duration) _wait;
  final int confirmAttempts;
  final Duration confirmInterval;

  TapCheckoutStep _step = TapCheckoutStep.preparing;
  TapSession? _session;
  String? _startedId;
  bool _disposed = false;

  TapCheckoutStep get step => _step;
  TapSession? get session => _session;

  /// The charge or card change waiting for confirmation.
  String? get startedId => _startedId;

  void _go(TapCheckoutStep next) {
    _step = next;
    if (!_disposed) notifyListeners();
  }

  TapCheckoutStep _refusal(BillingRefused refusal) => switch (refusal.code) {
        'phone_required' => TapCheckoutStep.phoneRequired,
        'already_plus' => TapCheckoutStep.alreadyPlus,
        _ => TapCheckoutStep.failed,
      };

  Future<void> prepare(PlusBillingCycle cycle) async {
    _go(TapCheckoutStep.preparing);
    try {
      _session = await _billing.tapSession(cycle);
      _go(TapCheckoutStep.ready);
    } catch (_) {
      _go(TapCheckoutStep.unavailable);
    }
  }

  /// Starts the payment, with a card token or on Tap's hosted page.
  Future<void> pay(PlusBillingCycle cycle, {String? cardToken}) =>
      _begin(() => _billing.tapCheckout(cycle, cardToken: cardToken));

  Future<void> changeCard({String? cardToken}) =>
      _begin(() => _billing.tapChangeCard(cardToken: cardToken));

  Future<void> _begin(Future<TapStart> Function() start) async {
    _go(TapCheckoutStep.paying);
    final TapStart started;
    try {
      started = await start();
    } on BillingRefused catch (refusal) {
      _go(_refusal(refusal));
      return;
    } catch (_) {
      _go(TapCheckoutStep.failed);
      return;
    }
    _startedId = started.id;
    final page = started.paymentPage;
    if (page == null) {
      await confirm(started.id);
      return;
    }
    final opened = await _openPage(page).catchError((Object _) => false);
    // In a browser this page is being replaced by Tap's secure step.
    _go(opened ? TapCheckoutStep.pending : TapCheckoutStep.failed);
  }

  /// Asks the server to read [id] from Tap until it is settled.
  Future<void> confirm(String id) async {
    _startedId = id;
    _go(TapCheckoutStep.confirming);
    final isCardChange = id.startsWith('auth_');
    for (var attempt = 0; attempt < confirmAttempts; attempt++) {
      if (attempt > 0) await _wait(confirmInterval);
      if (_disposed) return;
      try {
        if (isCardChange) {
          final outcome = await _billing.tapVerifyCardChange(id);
          if (outcome == 'applied' || outcome == 'duplicate') {
            _go(TapCheckoutStep.cardUpdated);
            return;
          }
          if (outcome == 'failed' || outcome == 'needs_review') {
            _go(TapCheckoutStep.failed);
            return;
          }
          continue;
        }
        final outcome = await _billing.tapVerify(id);
        if (outcome == 'captured' || outcome == 'duplicate') {
          final state = await _subscription.fetchState();
          if (state.isPlus && !state.isTest) {
            _go(TapCheckoutStep.activated);
            return;
          }
        } else if (const {
          'failed',
          'amount_mismatch',
          'charge_mismatch',
          'no_account'
        }.contains(outcome)) {
          _go(TapCheckoutStep.failed);
          return;
        }
      } on BillingRefused catch (refusal) {
        if (refusal.code == 'not_found' || refusal.code == 'charge_rejected') {
          _go(TapCheckoutStep.failed);
          return;
        }
      } catch (_) {
        // The webhook may still settle it; the next attempt asks again.
      }
    }
    _go(TapCheckoutStep.pending);
  }

  void cardFormFailed() => _go(TapCheckoutStep.unavailable);

  void tokenFailed() => _go(TapCheckoutStep.ready);

  void beginTokenizing() => _go(TapCheckoutStep.paying);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
