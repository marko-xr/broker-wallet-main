import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:flutter/material.dart';

/// Bridge for the core-entity quota UI.
///
/// With the subscription backend on, [canCreate] asks the server first so the
/// user gets the right message before filling nothing in vain; the database
/// function that performs the write is still what enforces the limit. With it
/// off, nothing here enforces a limit and creation is allowed as before.
class CoreEntityQuotaBridge {
  const CoreEntityQuotaBridge._();

  static Future<bool> canCreate({
    required BuildContext context,
    required String section,
  }) async {
    if (!SupabaseConfig.subscriptionBackendEnabled) return true;
    return QuotaHelper.checkOnServer(context: context, section: section);
  }

  /// The database counts a creation in the same transaction that saves it.
  static Future<void> recordCreated({required String section}) async {}
}
