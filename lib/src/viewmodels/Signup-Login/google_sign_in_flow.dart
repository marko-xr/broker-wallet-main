import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/repositories/auth_failure.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Where a screen goes once "Continue with Google" ends.
enum GoogleSignInOutcome {
  /// Signed in and authorized for this device.
  home,

  /// Signed in, but the account's email is not confirmed.
  emailVerification,

  /// Nothing to show: the account picker was closed, or the app-wide
  /// "signed in on another device" dialog owns the notice.
  silent,

  /// Show [GoogleSignInResult.errorKey].
  failed,
}

class GoogleSignInResult {
  const GoogleSignInResult(this.outcome, {this.errorKey, this.email});

  final GoogleSignInOutcome outcome;

  /// A localization key, only for [GoogleSignInOutcome.failed].
  final String? errorKey;

  /// The account email, only for [GoogleSignInOutcome.emailVerification].
  final String? email;
}

/// "Continue with Google", shared by the Login and Sign-up screens.
///
/// Both buttons run the same sign-in: Supabase Auth creates the account when
/// the Google account has none and signs in to the existing one otherwise,
/// so there is no separate Google sign-up that could create a second account.
abstract final class GoogleSignInFlow {
  static Future<GoogleSignInResult> run(AuthViewModel authViewModel) async {
    try {
      final user = await authViewModel.signInWithGoogle();
      if (user == null) {
        return const GoogleSignInResult(
          GoogleSignInOutcome.failed,
          errorKey: 'googleSignInFailed',
        );
      }
      if (!user.isEmailVerified) {
        return GoogleSignInResult(
          GoogleSignInOutcome.emailVerification,
          email: user.email,
        );
      }
      return const GoogleSignInResult(GoogleSignInOutcome.home);
    } on AuthFailure catch (failure) {
      if (failure.code == AuthFailureCode.cancelled ||
          (failure.code == AuthFailureCode.sessionExpired &&
              authViewModel.wasCurrentSignInSuperseded)) {
        return const GoogleSignInResult(GoogleSignInOutcome.silent);
      }
      return GoogleSignInResult(
        GoogleSignInOutcome.failed,
        errorKey: errorKeyFor(failure.code),
      );
    } catch (_) {
      return const GoogleSignInResult(
        GoogleSignInOutcome.failed,
        errorKey: 'googleSignInFailed',
      );
    }
  }

  /// The message for a failed Google sign-in. Never provider text.
  static String errorKeyFor(AuthFailureCode code) => switch (code) {
        AuthFailureCode.providerUnavailable => 'googleSignInUnavailable',
        AuthFailureCode.network => 'googleSignInNetworkError',
        AuthFailureCode.tooManyRequests => 'authTooManyRequests',
        AuthFailureCode.appSessionUnavailable => 'appSessionCheckFailed',
        AuthFailureCode.sessionExpired => 'authSessionExpired',
        _ => 'googleSignInFailed',
      };

  /// Carries out [result] on the screen that started the sign-in, the way the
  /// email sign-in does.
  static void apply(
    BuildContext context,
    GoogleSignInResult result, {
    required void Function(String message) showError,
  }) {
    switch (result.outcome) {
      case GoogleSignInOutcome.home:
        // Non-blocking, as after an email sign-in.
        MapDataCacheService().preloadMapData().catchError((_) {});
        context.go('/home');
      case GoogleSignInOutcome.emailVerification:
        context.go('/email-verification', extra: result.email);
      case GoogleSignInOutcome.silent:
        break;
      case GoogleSignInOutcome.failed:
        showError(AppLocalizations.of(context)
            .translate(result.errorKey ?? 'googleSignInFailed'));
    }
  }
}
