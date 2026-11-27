import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a provider's own secure page. In a browser it replaces this page, so
/// Tap can bring the customer back to the return route.
Future<bool> openPaymentPage(Uri page) async {
  if (page.scheme != 'https') return false;
  return launchUrl(
    page,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
}

/// Google Play's own subscription center. Only Google can cancel, change or
/// refund a subscription it bills.
Future<bool> openGooglePlaySubscriptions({String? productId}) {
  const package = String.fromEnvironment(
    'GOOGLE_PLAY_PACKAGE_NAME',
    defaultValue: 'com.nmodigital.brokerwallet',
  );
  return launchUrl(
    Uri.https('play.google.com', '/store/account/subscriptions', {
      if (productId != null) 'sku': productId,
      'package': package,
    }),
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
  );
}

/// A browser's return from Tap's secure page.
///
/// The redirect through sign-in and the startup gate would lose the query, so
/// the id is taken once at startup. It proves nothing: it only says which charge
/// the trusted server should read from Tap.
abstract final class PaymentReturnStore {
  static final RegExp _id = RegExp(r'^(chg|auth)_[A-Za-z0-9_-]{4,128}$');
  static String? _pending;

  static String? get pendingId => _pending;

  static void capture(Uri location) {
    if (location.path != SubscriptionRoutes.paymentReturn) return;
    final id = location.queryParameters['tap_id'];
    if (id != null && _id.hasMatch(id)) _pending = id;
  }

  /// The id for the return screen, once.
  static String? take() {
    final id = _pending;
    _pending = null;
    return id;
  }

  /// Where a signed-in browser with a pending return must go.
  static String? redirectFor(String path, {required bool isAuthenticated}) {
    if (_pending == null || !isAuthenticated) return null;
    return path == SubscriptionRoutes.paymentReturn
        ? null
        : SubscriptionRoutes.paymentReturn;
  }

  @visibleForTesting
  static void debugReset() => _pending = null;
}
