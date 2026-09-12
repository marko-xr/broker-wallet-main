import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

import 'auth_callback_coordinator.dart';
import 'supabase_secure_storage.dart';

/// Initializes the Supabase client alongside the existing Firebase backend.
///
/// During the migration period this service is intentionally optional:
/// without the two required `--dart-define` values, initialization is skipped
/// and the existing Firebase application continues unchanged.
abstract final class SupabaseBootstrapService {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient? get client =>
      _initialized ? Supabase.instance.client : null;

  static Future<bool> initialize() async {
    if (_initialized) return true;
    if (!SupabaseConfig.isConfigured) return false;

    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SupabaseSecureStorage(),
          // Automatic URI detection stays ON: Supabase remains the only thing
          // that exchanges a session-bearing callback. The predicate only
          // narrows *which* links it tries, so an error-only or message-only
          // callback is no longer fed to `getSessionFromUrl` — that call can
          // only throw for those, and the SDK republishes the throw as an
          // `onAuthStateChange` stream error.
          detectSessionInUriPredicate: supabaseShouldExchangeAuthCallback,
        ),
      ).timeout(const Duration(seconds: 10));
      _initialized = true;
      // Owns the one application-level listener for the callbacks Supabase
      // just declined. Started after initialization so a link that arrives
      // during startup is still classified.
      await AuthCallbackCoordinator.instance.start();
      return true;
    } on TimeoutException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Supabase initialization timed out: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return false;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Supabase initialization failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return false;
    }
  }
}
