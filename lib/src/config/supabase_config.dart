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

  /// Whether the Login/Sign-up Phone tabs call Supabase phone OTP.
  ///
  /// Off by default: the tabs keep their existing "not available yet"
  /// messages. This is a client switch only and protects nothing on its own —
  /// whether a phone number can create an account or sign in is decided by
  /// the server (the hosted Phone provider setting and the Before User Created
  /// policy hook). Build with `--dart-define=PHONE_AUTH_ENABLED=true` only for
  /// a build that is meant to reach a server where phone auth is enabled.
  static const bool phoneAuthEnabled =
      bool.fromEnvironment('PHONE_AUTH_ENABLED');

  /// Whether saves and quota checks use the server-authoritative subscription
  /// functions. Off by default because no hosted database has that migration
  /// yet. It must be turned on in the same rollout that applies it, since the
  /// migration removes the direct client writes the off path uses.
  static const bool subscriptionBackendEnabled =
      bool.fromEnvironment('SUBSCRIPTION_BACKEND');

  /// The hosted production project. A build pointing at it is never Staging,
  /// whatever its flags say.
  static const String productionProjectRef = 'rbvcnvqpdqrhywcgxkne';

  static const String deploymentEnvironment =
      String.fromEnvironment('BW_DEPLOYMENT_ENV');

  /// Only decides whether the debug test control is drawn. The Staging backend
  /// makes the real decision and refuses everywhere else.
  static bool get isStagingBackend =>
      deploymentEnvironment == 'staging' &&
      !url.contains(productionProjectRef);

  /// Set only on the build that goes to the public stores.
  static const bool isPublicRelease = bool.fromEnvironment('BW_PUBLIC_RELEASE');

  /// Why this build must not start as a public release, or null. A public build
  /// must never silently fall back to the old client-side quota paths or point
  /// at Staging, so the app refuses to start instead.
  static String? get publicReleaseProblem {
    if (!isPublicRelease) return null;
    if (!subscriptionBackendEnabled) return 'SUBSCRIPTION_BACKEND must be true';
    if (deploymentEnvironment != 'production') {
      return 'BW_DEPLOYMENT_ENV must be production';
    }
    if (!url.contains(productionProjectRef)) {
      return 'SUPABASE_URL must be the production project';
    }
    return null;
  }

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
