import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/splash_screen.dart';

/// Bootstrap gate rendered at `/` while [AuthStatus] is still `unknown`.
///
/// This is a pure state renderer. It does not navigate: the GoRouter redirect
/// in `app.dart` is the single authentication navigation authority, and it
/// moves off `/` as soon as bootstrap resolves in either direction.
///
/// It previously drove its own `context.go` from a post-frame callback behind a
/// `_hasNavigated` latch that `didChangeDependencies` re-armed on every
/// dependency change. That made a second status transition able to schedule a
/// second navigation, which is how an authenticated user could be sent to
/// `/welcome` and then immediately on to `/home`.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    if (!auth.isSessionCheckUnavailable) return const SplashScreen();
    final loc = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(height: 16),
              Text(
                loc.translate('appSessionCheckFailed'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: auth.retryAppSessionValidation,
                child: Text(loc.translate('retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
