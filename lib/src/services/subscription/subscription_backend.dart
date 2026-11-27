import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server refused a Staging test-mode request. The state is unchanged.
class SubscriptionTestControlRefused implements Exception {
  const SubscriptionTestControlRefused(this.code);

  final String code;

  @override
  String toString() => 'SubscriptionTestControlRefused($code)';
}

/// What the server found when it re-read this account from the store.
enum StoreSyncResult { synced, tooSoon, linkedToOtherAccount, unavailable }

/// The app's only door to the subscription backend.
///
/// It holds the signed-in user's session and nothing else. The account is
/// always the one in the verified token: no call here names an account, a plan
/// or an entitlement.
abstract interface class SubscriptionBackend {
  Future<SubscriptionServerState> fetchState();

  /// Asks the server to re-read this account from the store. It decides and
  /// records the result; the app only learns how it went.
  Future<StoreSyncResult> syncWithStore();

  /// Asks the protected Staging endpoint for a test-state change. The endpoint
  /// refuses everywhere but on a verified Staging project.
  Future<SubscriptionServerState> testControl(String action);
}

class SupabaseSubscriptionBackend implements SubscriptionBackend {
  SupabaseSubscriptionBackend({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<SubscriptionServerState> fetchState() async {
    final answer = await _client.rpc<dynamic>('get_subscription_state');
    return SubscriptionServerState.fromJson(answer);
  }

  @override
  Future<StoreSyncResult> syncWithStore() async {
    try {
      await _client.functions.invoke('subscription-billing/sync');
      return StoreSyncResult.synced;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      return switch (code) {
        'too_soon' => StoreSyncResult.tooSoon,
        'purchase_linked_to_another_account' =>
          StoreSyncResult.linkedToOtherAccount,
        _ => StoreSyncResult.unavailable,
      };
    }
  }

  @override
  Future<SubscriptionServerState> testControl(String action) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'subscription-test-control',
        body: {'action': action},
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      throw SubscriptionTestControlRefused(
        code is String ? code : 'unavailable',
      );
    }
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final code = data is Map ? data['code'] : null;
      throw SubscriptionTestControlRefused(
        code is String ? code : 'unavailable',
      );
    }
    return SubscriptionServerState.fromJson(data['state']);
  }
}
