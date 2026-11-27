import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:flutter/foundation.dart';

/// The account's payment method, renewal and history, as the server reports
/// them. A failed read is [hasFailed]; it is never shown as "no payments".
class BillingCenterController extends ChangeNotifier {
  BillingCenterController({required BillingBackend billing})
      : _billing = billing;

  final BillingBackend _billing;

  BillingOverview? _overview;
  bool _loading = false;
  bool _busy = false;
  bool _failed = false;
  bool _actionFailed = false;
  bool _disposed = false;

  BillingOverview? get overview => _overview;
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  bool get hasFailed => _failed;
  bool get actionFailed => _actionFailed;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _failed = false;
    _notify();
    try {
      _overview = await _billing.fetchOverview();
    } catch (_) {
      _overview = null;
      _failed = true;
    }
    _loading = false;
    _notify();
  }

  /// Returns true when the server applied the change.
  Future<bool> setAutoRenew(bool on) async {
    if (_busy) return false;
    _busy = true;
    _actionFailed = false;
    _notify();
    var applied = false;
    try {
      final outcome = await _billing.tapSetAutoRenew(on);
      applied =
          const {'renewal_on', 'renewal_off', 'unchanged'}.contains(outcome);
    } catch (_) {
      applied = false;
    }
    _actionFailed = !applied;
    _busy = false;
    if (applied) {
      await load();
    } else {
      _notify();
    }
    return applied;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
