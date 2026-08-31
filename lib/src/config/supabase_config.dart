/// Compile-time Supabase configuration.
///
/// Values are supplied with Flutter's `--dart-define` flags so no backend
/// credentials need to be committed to the application source tree.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Migration-only switch for the identity/profile repositories.
  ///
  /// It defaults to false so normal runs continue using Firebase until the
  /// Supabase email-auth path has been verified end-to-end in the Flutter UI.
  static const bool useSupabaseAuth =
      bool.fromEnvironment('USE_SUPABASE_AUTH', defaultValue: false);

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
