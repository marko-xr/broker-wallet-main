import 'package:flutter/foundation.dart';

import 'app_session_coordinator.dart';

/// Which session a list read belongs to, and whether an empty server list
/// can be trusted.
///
/// The database's application-session gate filters rows rather than failing:
/// a session that another device has replaced reads every list as empty,
/// with no error. A list with rows proves the gate let the read through, so
/// only an empty list needs asking about. The answer comes from the existing
/// authority, [AppSessionCoordinator.validateNow] (the database's
/// `is_current_app_session`), which also starts the usual sign-out when the
/// session has been replaced. Nothing here decides access itself.
///
/// A session is the access token's `session_id`: a token refresh keeps it,
/// a new sign-in gets a new one, even for the same account.
abstract final class ListSessionCheck {
  /// Replaces [confirmFor] in tests.
  @visibleForTesting
  static Future<bool>? Function(String? session)? debugOverride;

  static Future<bool>? _inFlight;
  static String? _inFlightSession;

  /// The signed-in session now, or null when there is none or no
  /// application session at all.
  static String? currentSession() {
    final coordinator = AppSessionCoordinator.active;
    if (coordinator == null) return null;
    return AppSessionCoordinator.sessionId(
        coordinator.client.auth.currentSession);
  }

  /// True only once the database has confirmed that [session] — the session
  /// a read was made under — is still the signed-in session and the
  /// account's current one. A session that is no longer the signed-in one is
  /// never asked about, so an earlier session can neither be confirmed nor
  /// start a sign-out of a later one. Null when there is no application
  /// session to ask about (no Supabase app session): there is no gate, and
  /// an empty list is taken as it is. Throws when the check could not be
  /// made.
  static Future<bool>? confirmFor(String? session) {
    final override = debugOverride;
    if (override != null) return override(session);
    final coordinator = AppSessionCoordinator.active;
    if (coordinator == null) return null;
    return bound(
      session,
      current: AppSessionCoordinator.sessionId(
          coordinator.client.auth.currentSession),
      validate: coordinator.validateNow,
    );
  }

  /// [validate] for [session] only while it is the [current] session; any
  /// other session is answered false without asking.
  @visibleForTesting
  static Future<bool> bound(
    String? session, {
    required String? current,
    required Future<bool> Function() validate,
  }) {
    if (session != current) return Future<bool>.value(false);
    return shared(session, validate);
  }

  /// Runs [validate] for [session], sharing one check while it is in flight
  /// with every caller asking for the same session. No answer is kept once
  /// it has arrived, and none is ever shared with another session. A session
  /// with no id is never confirmed.
  @visibleForTesting
  static Future<bool> shared(
      String? session, Future<bool> Function() validate) {
    if (session == null) return Future<bool>.value(false);
    final pending = _inFlight;
    if (pending != null && _inFlightSession == session) return pending;
    late final Future<bool> check;
    check = validate().whenComplete(() {
      if (identical(_inFlight, check)) {
        _inFlight = null;
        _inFlightSession = null;
      }
    });
    _inFlight = check;
    _inFlightSession = session;
    return check;
  }
}

/// An empty server list that was not trusted: the database did not confirm
/// that this session is still the account's current one.
class ListSessionNotCurrent implements Exception {
  const ListSessionNotCurrent();

  @override
  String toString() => 'ListSessionNotCurrent';
}
