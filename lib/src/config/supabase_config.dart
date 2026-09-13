/// Compile-time Supabase configuration.
///
/// Values are supplied with Flutter's `--dart-define` flags so no backend
/// credentials need to be committed to the application source tree.
abstract final class SupabaseConfig {
  /// The general auth callback: signup verification, magic link and Email
  /// Change. Its behaviour is VERIFIED_RUNTIME and must not change.
  static const String authCallbackUri = 'brokerwallet://auth/callback';

  /// The dedicated password-recovery callback.
  ///
  /// Password recovery gets its own exact address so a recovery callback can be
  /// recognised from the link itself rather than inferred. This matters most
  /// when the link has expired: GoTrue then redirects back carrying only
  /// `error` and `error_code`, with no guaranteed `type`, so an expired
  /// recovery link and an expired Email Change link are otherwise
  /// indistinguishable. Separate addresses make the distinction structural.
  ///
  /// Same scheme and host as [authCallbackUri], so the existing Android
  /// intent filter and iOS URL scheme already accept it; only the path
  /// differs. Supabase's own deep-link observer never inspects the path, so
  /// the exchange itself is unaffected.
  ///
  /// This exact URL must be present in the hosted Supabase redirect allowlist.
  static const String passwordRecoveryCallbackUri =
      'brokerwallet://auth/reset-password';
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

  /// Mirrors the hosted GoTrue setting
  /// `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD`
  /// ("Require current password" in the Supabase Dashboard).
  ///
  /// It defaults to false because that is the hosted project's state. The app
  /// asks for, and sends, a current password only when this is true, so the
  /// field can never appear while the server would silently ignore it — and
  /// the current password is never "verified" by a second sign-in, which would
  /// mutate session state to answer a question the server already answers.
  ///
  /// Turning this on is a two-part change: enable the hosted setting first,
  /// then build with `--dart-define=REQUIRE_CURRENT_PASSWORD=true`.
  static const bool requireCurrentPasswordOnChange =
      bool.fromEnvironment('REQUIRE_CURRENT_PASSWORD');

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
