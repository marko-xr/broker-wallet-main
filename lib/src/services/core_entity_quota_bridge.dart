import 'package:flutter/material.dart';

/// Bridge for the core-entity quota UI.
///
/// RevenueCat entitlement mapping and final paid quota limits are not yet
/// configured, so nothing here enforces a limit: [canCreate] allows creation
/// and [recordCreated] records nothing. The database remains the source of
/// truth for entity rows and RLS ownership. A server-authoritative quota must
/// replace this class; it is a known production gap, not a security control.
class CoreEntityQuotaBridge {
  const CoreEntityQuotaBridge._();

  static Future<bool> canCreate({
    required BuildContext context,
    required String section,
  }) async {
    return true;
  }

  static Future<void> recordCreated({required String section}) async {}
}
