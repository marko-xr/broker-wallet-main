import 'package:broker_wallet/src/services/subscription/billing_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// Offline read-only: a sixth Toolkit document must never start without the
// server, and an unknown state is never Plus. Fakes only.

class _Backend implements SubscriptionBackend {
  _Backend(this.state);

  final Map<String, Object?>? state;

  @override
  Future<SubscriptionServerState> fetchState() async {
    final raw = state;
    if (raw == null) throw StateError('offline');
    return SubscriptionServerState.fromJson(raw);
  }

  @override
  Future<StoreSyncResult> syncWithStore() async => StoreSyncResult.synced;

  @override
  Future<SubscriptionServerState> testControl(String action) =>
      throw UnimplementedError();
}

Map<String, Object?> _state({
  String plan = 'free',
  String status = 'free',
  bool readOnly = false,
  int scanner = 0,
  String? paidThrough,
}) =>
    {
      'plan': plan,
      'status': status,
      'read_only': readOnly,
      'is_test': false,
      'paid_through': paidThrough,
      'usage': {
        for (final s in [
          'requests',
          'offers',
          'owners',
          'offices',
          'brokers',
          'watchmen',
          'quotations',
          'signature',
          'image_to_pdf',
          'combine_pdfs',
        ])
          s: 0,
        'scanner': scanner,
      },
      'items': const <Object?>[],
      'test_mode': {'available': false, 'scenario': null, 'expires_at': null},
    };

Future<SubscriptionStateController> _controller(
  Map<String, Object?>? state,
) async {
  final controller = SubscriptionStateController(
    backend: () => _Backend(state),
    channels: () async => BillingChannels.closed,
  )..attachUser('account-a');
  await controller.refresh();
  return controller;
}

void main() {
  test('with no confirmed state nothing new starts', () async {
    final controller = await _controller(null);
    expect(
        controller.decideWithoutServer('scanner'), QuotaDecision.unavailable);
  });

  test('Free: only the confirmed allowance, counting offline starts', () async {
    final controller = await _controller(_state(scanner: 3));
    expect(controller.decideWithoutServer('scanner'), QuotaDecision.allowed);
    expect(controller.decideWithoutServer('scanner'), QuotaDecision.allowed);
    expect(
        controller.decideWithoutServer('scanner'), QuotaDecision.limitReached);
    // Each category has its own allowance.
    expect(controller.decideWithoutServer('signature'), QuotaDecision.allowed);
  });

  test('a refresh does not forget items made offline', () async {
    final controller = await _controller(_state(scanner: 4));
    expect(controller.decideWithoutServer('scanner'), QuotaDecision.allowed);
    await controller.refresh();
    expect(
        controller.decideWithoutServer('scanner'), QuotaDecision.limitReached);
  });

  test('a new account starts from its own state', () async {
    final controller = await _controller(_state(scanner: 4));
    expect(controller.decideWithoutServer('scanner'), QuotaDecision.allowed);
    controller.attachUser('account-b');
    expect(
        controller.decideWithoutServer('scanner'), QuotaDecision.unavailable);
  });

  test('read-only stays read-only', () async {
    final controller = await _controller(
      _state(status: 'expired_over_limit', readOnly: true, scanner: 9),
    );
    expect(controller.decideWithoutServer('scanner'), QuotaDecision.readOnly);
  });

  test('Plus counts only until its confirmed date', () async {
    final now = DateTime.utc(2026, 11, 26);
    final controller = await _controller(_state(
      plan: 'plus',
      status: 'plus_renewing',
      scanner: 40,
      paidThrough: '2026-12-01T00:00:00Z',
    ));
    expect(controller.decideWithoutServer('scanner', now: now),
        QuotaDecision.allowed);
    expect(
      controller.decideWithoutServer('scanner', now: DateTime.utc(2026, 12, 2)),
      QuotaDecision.unavailable,
    );
  });

  test('an unknown section never starts', () async {
    final controller = await _controller(_state());
    expect(controller.decideWithoutServer('unknown_tool'),
        QuotaDecision.unavailable);
  });
}
