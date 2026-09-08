/// Compile-time Supabase configuration.
///
/// Values are supplied with Flutter's `--dart-define` flags so no backend
/// credentials need to be committed to the application source tree.
abstract final class SupabaseConfig {
  static const String authCallbackUri = 'brokerwallet://auth/callback';
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rbvcnvqpdqrhywcgxkne.supabase.co',
  );
  static const String publishableKey =
      String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_zGvG-mwMCkcpjtTYcscv1A_Xec0qXZz',
      );

  /// Controls the identity/profile repository backend.
  static const bool useSupabaseAuth =
      bool.fromEnvironment('USE_SUPABASE_AUTH', defaultValue: true);

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
