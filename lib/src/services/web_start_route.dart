import 'package:flutter/foundation.dart';

/// The page a browser was on when it loaded or refreshed the app.
///
/// The startup gate sends everyone through `/` until the session is known,
/// which would otherwise turn every refresh into a visit to Home. Only an
/// in-app path is kept, and the route guards still decide whether it may open.
abstract final class WebStartRoute {
  static const Set<String> _entryPaths = {
    '/',
    '/home',
    '/welcome',
    '/sign-in',
    '/sign-up',
    '/phone-otp',
    '/email-verification',
    '/reset-password',
    '/subscription-return',
  };

  static String? _pending;

  /// Kept until the page is reached: the router may evaluate a redirect several
  /// times before it commits to one.
  static String? get pending => _pending;

  static void capture(Uri location) {
    final path = location.path;
    if (!path.startsWith('/') || path.startsWith('//')) return;
    if (_entryPaths.contains(path)) return;
    _pending = location.hasQuery ? '$path?${location.query}' : path;
  }

  /// The router allowed [path]; a kept page that matches is done.
  static void arrived(String path) {
    final route = _pending;
    if (route != null && Uri.parse(route).path == path) _pending = null;
  }

  @visibleForTesting
  static void debugReset() => _pending = null;
}
