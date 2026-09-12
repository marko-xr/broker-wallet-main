import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// What an incoming `brokerwallet://auth/callback` deep link actually is.
///
/// Supabase's own deep-link observer only ever *exchanges* a link; everything
/// else it either drops silently or turns into a stream exception. Classifying
/// the link first is what lets the application keep Supabase as the single
/// session authority while still reacting to the callbacks Supabase cannot use.
enum AuthCallbackKind {
  /// Carries `access_token` or `code`. Supabase must exchange it for a session;
  /// the application must not touch it.
  session,

  /// Carries `error`, `error_code` or `error_description`. Exchanging it can
  /// only throw, so the application owns it.
  error,

  /// Carries an informational `message` and nothing else. Secure Email Change
  /// reports the first of its two confirmations this way.
  informational,

  /// An auth callback carrying none of the above.
  unknown,
}

/// A classified auth callback.
///
/// Only the provider's *codes* are carried. The human-readable
/// `error_description`, any token, hash or OTP in the link is deliberately
/// dropped here so it cannot reach a log, a screen or an error report.
@immutable
class AuthCallbackEvent {
  const AuthCallbackEvent({
    required this.kind,
    this.errorCode,
    this.error,
  });

  final AuthCallbackKind kind;

  /// Supabase's `error_code`, e.g. `otp_expired`. Never a message.
  final String? errorCode;

  /// Supabase's `error`, e.g. `access_denied`. Never a message.
  final String? error;

  /// Safe to log: contains no token, address or provider prose.
  @override
  String toString() =>
      'AuthCallbackEvent(${kind.name}, error: $error, errorCode: $errorCode)';
}

/// Merges the query and fragment parameters of an auth callback.
///
/// Supabase's implicit flow returns its parameters in the fragment and its PKCE
/// flow returns them in the query, so both have to be considered.
Map<String, String> _callbackParameters(Uri uri) {
  final parameters = <String, String>{...uri.queryParameters};
  if (uri.fragment.isNotEmpty) {
    try {
      parameters.addAll(Uri.splitQueryString(uri.fragment));
    } on FormatException {
      // A fragment that is not a query string carries nothing we can use.
    }
  }
  return parameters;
}

/// Classifies [uri] without performing any network call.
AuthCallbackKind classifyAuthCallback(Uri uri) {
  final parameters = _callbackParameters(uri);
  if (parameters.containsKey('access_token') ||
      parameters.containsKey('code')) {
    return AuthCallbackKind.session;
  }
  if (parameters.containsKey('error') ||
      parameters.containsKey('error_code') ||
      parameters.containsKey('error_description')) {
    return AuthCallbackKind.error;
  }
  if (parameters.containsKey('message')) {
    return AuthCallbackKind.informational;
  }
  return AuthCallbackKind.unknown;
}

/// The predicate handed to `FlutterAuthClientOptions.detectSessionInUriPredicate`.
///
/// It is deliberately *narrower* than the SDK default, which also treats
/// `error`/`error_code`/`error_description` links as exchangeable. Exchanging
/// one of those can only ever throw an `AuthException`, which the SDK then
/// republishes on `onAuthStateChange` as a stream error. Returning false for
/// them removes that failure at the source while leaving every legitimate
/// session-bearing callback — signup verification, magic link, recovery and
/// OAuth — on Supabase's normal path.
bool supabaseShouldExchangeAuthCallback(Uri uri) =>
    classifyAuthCallback(uri) == AuthCallbackKind.session;

/// Builds the application-owned event for a callback Supabase will not exchange.
AuthCallbackEvent describeAuthCallback(Uri uri) {
  final kind = classifyAuthCallback(uri);
  if (kind != AuthCallbackKind.error) {
    return AuthCallbackEvent(kind: kind);
  }
  final parameters = _callbackParameters(uri);
  return AuthCallbackEvent(
    kind: kind,
    error: parameters['error'],
    errorCode: parameters['error_code'],
  );
}

/// The single application-level listener for auth deep links.
///
/// This is *not* a second auth authority. It never creates, refreshes or
/// invalidates a session and never touches identity: Supabase still owns every
/// session-bearing callback, `AuthViewModel` still owns application identity and
/// GoRouter still owns navigation. This class only answers one question —
/// "a callback that Supabase ignored just arrived, what kind was it?" — so a
/// feature that is waiting on one can re-read authoritative state.
///
/// It subscribes to `AppLinks()`, which is itself a singleton with one shared
/// broadcast stream, so no second native listener is registered.
class AuthCallbackCoordinator {
  AuthCallbackCoordinator._() : _testLinks = null;

  /// Test seam: drives the coordinator from a plain stream instead of the
  /// platform channel.
  @visibleForTesting
  AuthCallbackCoordinator.forTesting(Stream<Uri> links) : _testLinks = links;

  static final AuthCallbackCoordinator instance = AuthCallbackCoordinator._();

  final Stream<Uri>? _testLinks;

  final StreamController<AuthCallbackEvent> _events =
      StreamController<AuthCallbackEvent>.broadcast();

  StreamSubscription<Uri>? _subscription;
  bool _started = false;
  String? _lastHandled;

  /// Callbacks Supabase did not exchange, already classified.
  Stream<AuthCallbackEvent> get events => _events.stream;

  bool get isStarted => _started;

  /// Begins observing deep links. Safe to call more than once.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final source = _testLinks ?? AppLinks().uriLinkStream;
    _subscription = source.listen(
      _handle,
      // A deep-link transport failure must never become an unhandled error.
      onError: (Object _, StackTrace __) {},
    );

    if (_testLinks != null) return;

    // On Android the launching intent is replayed on `uriLinkStream`, but a
    // cold start can deliver it before this subscription exists. Reading the
    // initial link once closes that window; `_handle` de-duplicates the overlap.
    try {
      final initial = await AppLinks().getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {
      // The platform channel may be unavailable; there is nothing to recover.
    }
  }

  void _handle(Uri uri) {
    // Supabase owns session-bearing callbacks. Touching them here would create
    // exactly the competing authority this class exists to avoid.
    if (classifyAuthCallback(uri) == AuthCallbackKind.session) return;

    // The OS can deliver the same intent twice (resume plus initial link).
    final fingerprint = uri.toString();
    if (fingerprint == _lastHandled) return;
    _lastHandled = fingerprint;

    if (!_events.isClosed) _events.add(describeAuthCallback(uri));
  }

  /// Releases the subscription. Production never calls this — the coordinator is
  /// process-lifetime — but tests need a deterministic teardown.
  @visibleForTesting
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    _lastHandled = null;
    await _events.close();
  }
}
