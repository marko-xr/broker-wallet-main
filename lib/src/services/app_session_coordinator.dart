import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Process-wide Supabase application-session gate. The database, never this
/// decoded token, makes the authorization decision. The token claim is used
/// only to correlate a Realtime row with the current local session.
class AppSessionCoordinator with WidgetsBindingObserver {
  AppSessionCoordinator(
    this.client, {
    required this.onSuperseded,
    this.onResumeWhileUnverified,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _active = this;
  }

  final SupabaseClient client;
  final void Function() onSuperseded;
  final void Function()? onResumeWhileUnverified;
  static AppSessionCoordinator? _active;
  StreamSubscription<List<Map<String, dynamic>>>? _watch;
  Future<bool>? _pending;
  String? _pendingId;
  bool _pendingClaim = false;
  String? _authorizedId;
  bool _superseded = false;
  DateTime? _lastResumeCheck;

  static String? sessionId(Session? session) {
    if (session == null) return null;
    return sessionIdFromAccessToken(session.accessToken);
  }

  static String? sessionIdFromAccessToken(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) return null;
      final body = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final id = body is Map ? body['session_id'] : null;
      return id is String &&
              RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                  .hasMatch(id)
          ? id
          : null;
    } catch (_) {
      return null;
    }
  }

  bool isAuthorized(Session? session) =>
      !_superseded && sessionId(session) == _authorizedId && _authorizedId != null;

  /// A fresh sign-in claims once. A restored or refreshed session only checks;
  /// it must never turn a displaced old session into a new claimant.
  Future<bool> authorize(Session session, {required bool claim}) {
    final id = sessionId(session);
    if (id == null) {
      supersede();
      return Future.value(false);
    }
    if (_pendingId == id && _pending != null) {
      if (!claim || _pendingClaim) return _pending!;
      // A signedIn event can arrive while bootstrap is checking this same
      // session. The check must not reject a session that is about to claim.
      _pendingClaim = true;
      final previous = _pending!;
      Future<bool> claimAfterCheck() async {
        await previous;
        return _authorize(session, id, claim: true);
      }
      late final Future<bool> upgraded;
      upgraded = claimAfterCheck().whenComplete(() {
        if (identical(_pending, upgraded)) {
          _pending = null;
          _pendingId = null;
          _pendingClaim = false;
        }
      });
      _pending = upgraded;
      return upgraded;
    }
    if (!claim && isAuthorized(session)) return Future.value(true);
    late final Future<bool> run;
    run = _authorize(session, id, claim: claim).whenComplete(() {
      if (identical(_pending, run)) {
        _pending = null;
        _pendingId = null;
        _pendingClaim = false;
      }
    });
    _pending = run;
    _pendingId = id;
    _pendingClaim = claim;
    return run;
  }

  Future<bool> _authorize(Session session, String id, {required bool claim}) async {
    late final Object? answer;
    try {
      answer = await client.rpc(
        claim ? 'claim_current_app_session' : 'is_current_app_session',
      );
    } catch (_) {
      if (!claim && _pendingId == id && _pendingClaim) return false;
      rethrow;
    }
    if (!claim && _pendingId == id && _pendingClaim) return false;
    if (answer != true || sessionId(client.auth.currentSession) != id) {
      if (sessionId(client.auth.currentSession) == id) supersede();
      return false;
    }
    _superseded = false;
    _authorizedId = id;
    _watchOwnRow(session.user.id, id);
    // Do not call `signOut(others)` here. A second new session can claim
    // between this RPC and that Auth API call; the now-displaced caller would
    // then revoke the actual winner's refresh token. The database gate is
    // immediate and remains the authority.
    return true;
  }

  void _watchOwnRow(String userId, String id) {
    _watch?.cancel();
    _watch = client
        .from('user_active_sessions')
        .stream(primaryKey: const ['user_id'])
        .eq('user_id', userId)
        .listen((rows) {
          if (_authorizedId != id ||
              sessionId(client.auth.currentSession) != id) return;
          if (rows.isNotEmpty && rows.first['active_session_id'] != id) supersede();
        }, onError: (Object _) {
          // A refused/disconnected channel is not proof of displacement.
          // Resume and protected-request checks remain authoritative.
        });
  }

  Future<bool> validateNow() async {
    final session = client.auth.currentSession;
    if (session == null || !isAuthorized(session)) return false;
    final id = _authorizedId;
    final answer = await client.rpc('is_current_app_session');
    if (answer == true && sessionId(client.auth.currentSession) == id) return true;
    if (sessionId(client.auth.currentSession) == id) supersede();
    return false;
  }

  void supersede() {
    if (_superseded) return;
    _superseded = true;
    _authorizedId = null;
    _watch?.cancel();
    _watch = null;
    onSuperseded();
  }

  /// Shared fallback for services that receive a fixed Worker/RPC code.
  static void reportBackendError(Object error, {required String accessToken}) {
    final code = error is PostgrestException ? error.message : error.toString();
    final coordinator = _active;
    if (code.contains('session_superseded') &&
        coordinator != null &&
        sessionIdFromAccessToken(accessToken) == coordinator._authorizedId &&
        coordinator.isAuthorized(coordinator.client.auth.currentSession)) {
      coordinator.supersede();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _superseded) return;
    final now = DateTime.now();
    if (_lastResumeCheck != null &&
        now.difference(_lastResumeCheck!) < const Duration(seconds: 5)) return;
    _lastResumeCheck = now;
    if (_authorizedId == null) {
      onResumeWhileUnverified?.call();
      return;
    }
    unawaited(validateNow().then<void>((_) {}, onError: (Object _) {}));
  }

  void clear() {
    _authorizedId = null;
    _superseded = false;
    _watch?.cancel();
    _watch = null;
  }

  Future<void> release() async {
    if (_authorizedId == null) return;
    await client.rpc('release_current_app_session');
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_active, this)) _active = null;
    await _watch?.cancel();
  }
}
