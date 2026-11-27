import 'package:broker_wallet/src/config/supabase_config.dart';

/// What this build's configuration allows the billing screens to offer. Build
/// flags only widen what the screens try; the server still decides everything.
abstract final class BillingAvailability {
  static bool get backendEnabled => SupabaseConfig.subscriptionBackendEnabled;

  /// True only on a build pointed at the isolated Staging project.
  static bool get isStagingBackend => SupabaseConfig.isStagingBackend;
}
