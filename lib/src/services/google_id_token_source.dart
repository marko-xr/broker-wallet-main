import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The tokens Google issued for one sign-in. They are handed to Supabase Auth
/// once and never stored or logged.
class GoogleIdTokens {
  const GoogleIdTokens({required this.idToken, this.accessToken});

  final String idToken;
  final String? accessToken;
}

/// Why Google gave the app no ID token.
enum GoogleTokenFailure {
  /// This build or platform has no Google sign-in configuration.
  notConfigured,

  /// Google could not be reached.
  network,

  /// Anything else: a refused or misconfigured client (Android
  /// `DEVELOPER_ERROR`, a missing SHA-1), an account problem, or no ID token.
  failed,
}

class GoogleTokenException implements Exception {
  const GoogleTokenException(this.reason);

  final GoogleTokenFailure reason;

  @override
  String toString() => 'GoogleTokenException(${reason.name})';
}

/// Obtains a Google ID token through the platform's own Google sign-in.
///
/// Google only proves which Google account the user chose. Whether that
/// account may sign in, which Broker Wallet account it is, and whether this
/// device may use it are decided by Supabase Auth and the app session check.
abstract class GoogleIdTokenSource {
  /// Whether Google sign-in can start on this build and platform.
  bool get isConfigured;

  /// Shows Google's account picker. Returns null when the user closes it.
  /// Throws [GoogleTokenException].
  Future<GoogleIdTokens?> obtain();
}

/// [GoogleIdTokenSource] on the `google_sign_in` plugin (6.x).
///
/// Android only for now. iOS needs its own client ID and URL scheme, and the
/// web plugin does not return an ID token from a button of the app's own;
/// both report "not configured" rather than starting a flow that cannot end.
///
/// The plugin's own signed-in state is not kept: Supabase holds the session.
/// It is cleared after every attempt, so the next sign-in shows the account
/// picker again and a different Google account can be chosen.
class PluginGoogleIdTokenSource implements GoogleIdTokenSource {
  PluginGoogleIdTokenSource({
    String? webClientId,
    bool? platformSupported,
    @visibleForTesting GoogleSignIn? googleSignIn,
  })  : _webClientId = (webClientId ?? SupabaseConfig.googleWebClientId).trim(),
        _platformSupported = platformSupported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
        _googleSignInOverride = googleSignIn;

  final String _webClientId;
  final bool _platformSupported;
  final GoogleSignIn? _googleSignInOverride;

  // Created only when used, so an unconfigured build never touches the
  // plugin. The default scopes (`openid`, email, profile) are all an ID token
  // for Supabase needs.
  late final GoogleSignIn _google =
      _googleSignInOverride ?? GoogleSignIn(serverClientId: _webClientId);

  @override
  bool get isConfigured => _platformSupported && _webClientId.isNotEmpty;

  @override
  Future<GoogleIdTokens?> obtain() async {
    if (!isConfigured) {
      throw const GoogleTokenException(GoogleTokenFailure.notConfigured);
    }
    final google = _google;
    try {
      // `signIn` silently reuses an account that is still signed in to the
      // plugin, so a leftover one is cleared first: the user always chooses.
      if (google.currentUser != null) await google.signOut();
      final account = await google.signIn();
      if (account == null) return null;
      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleTokenException(GoogleTokenFailure.failed);
      }
      return GoogleIdTokens(
        idToken: idToken,
        accessToken: authentication.accessToken,
      );
    } on GoogleTokenException {
      rethrow;
    } on PlatformException catch (error) {
      if (error.code == GoogleSignIn.kSignInCanceledError) return null;
      final reason = classify(error);
      if (kDebugMode) {
        // Codes only: never a token, an account or the raw message.
        debugPrint('[google-sign-in] ${error.code} '
            'status=${androidStatusOf(error) ?? '-'} -> ${reason.name}');
      }
      throw GoogleTokenException(reason);
    } catch (_) {
      throw const GoogleTokenException(GoogleTokenFailure.failed);
    } finally {
      try {
        await google.signOut();
      } catch (_) {
        // Nothing depends on it: the plugin state only decides whether the
        // next sign-in shows the picker, and the next attempt clears it too.
      }
    }
  }

  /// The plugin's error codes (cancel aside) as an outcome. The Android
  /// plugin already reports Play services `NETWORK_ERROR` as `network_error`.
  @visibleForTesting
  static GoogleTokenFailure classify(PlatformException error) =>
      error.code == GoogleSignIn.kNetworkError
          ? GoogleTokenFailure.network
          : GoogleTokenFailure.failed;

  /// The Google Play services status in an Android failure
  /// (`ApiException: 10` is `DEVELOPER_ERROR`: the package name or SHA-1 has
  /// no OAuth client), or null.
  @visibleForTesting
  static int? androidStatusOf(PlatformException error) {
    final match =
        RegExp(r'ApiException: (\d+)').firstMatch(error.message ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
