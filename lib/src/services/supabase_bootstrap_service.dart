import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

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
        ),
      ).timeout(const Duration(seconds: 10));
      _initialized = true;
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
