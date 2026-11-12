import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/services/app_session_check_outcome.dart';
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
    this.onCheckSlow,
    this.onCheckProgress,
    this.softDeadline = defaultSoftDeadline,
    this.hardDeadline = defaultHardDeadline,
    @visibleForTesting Stopwatch Function()? stopwatch,
  }) : _stopwatch = stopwatch ?? Stopwatch.new {
    WidgetsBinding.instance.addObserver(this);
    _active = this;
  }

  /// A restored-session check still running after this shows Retry; it keeps
  /// running, and a current `true` still opens the application.
  static const Duration defaultSoftDeadline = Duration(seconds: 5);

  /// A restored-session check still running after this is ended and its
  /// request aborted; anything it answers later is ignored.
  static const Duration defaultHardDeadline = Duration(seconds: 30);

  final SupabaseClient client;
  final void Function() onSuperseded;
  final void Function()? onResumeWhileUnverified;

  /// The current check passed [softDeadline] without an answer.
  final void Function()? onCheckSlow;

  /// A restored-session check started (true) or ended (false).
  final void Function(bool running)? onCheckProgress;
  final Duration softDeadline;
  final Duration hardDeadline;
  final Stopwatch Function() _stopwatch;
  static AppSessionCoordinator? _active;

  /// The coordinator in use, or null when there is none (no Supabase app
  /// session). Read-only; for code that must ask [validateNow].
  static AppSessionCoordinator? get active => _active;
  StreamSubscription<List<Map<String, dynamic>>>? _watch;
  Future<bool>? _pending;
  String? _pendingId;
  bool _pendingClaim = false;
  _Check? _pendingCheck;
  _Check? _live;
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
      _pendingCheck = null;
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
    run = (claim ? _authorize(session, id, claim: claim) : _check(session, id))
        .whenComplete(() {
      if (identical(_pending, run)) {
        _pending = null;
        _pendingId = null;
        _pendingClaim = false;
        _pendingCheck = null;
      }
    });
    _pending = run;
    _pendingId = id;
    _pendingClaim = claim;
    _pendingCheck = claim ? null : _live;
    return run;
  }

  /// One bounded check of a restored session. At most one runs; it is bound
  /// to the session id it started for and ends exactly once: by its answer,
  /// at [hardDeadline], or when the session it belongs to goes away.
  Future<bool> _check(Session session, String id) {
    _detachLive();
    final attempt = _Check(id, session.user.id, _stopwatch()..start());
    _live = attempt;
    attempt.soft = Timer(softDeadline, () {
      if (identical(_live, attempt) &&
          sessionId(client.auth.currentSession) == id) {
        onCheckSlow?.call();
      }
    });
    attempt.hard = Timer(
        hardDeadline,
        () => _finish(attempt,
            error:
                const AppSessionCheckException(AppSessionCheckOutcome.timedOut),
            abort: true));
    onCheckProgress?.call(true);
    unawaited(_run(attempt));
    return attempt.result.future;
  }

  Future<void> _run(_Check attempt) async {
    Object? answer;
    Object? failure;
    try {
      answer = await client
          .rpc('is_current_app_session')
          .abortSignal(attempt.abort.future);
    } catch (error) {
      failure = error;
    }
    // Ended by its deadline or by a session change: the answer is stale.
    if (attempt.isDone) return;
    final id = attempt.sessionId;
    // Signed out, removed by the SDK, or replaced while the request ran: the
    // SDK's own events decide, and this answer decides nothing.
    if (!identical(_live, attempt) ||
        sessionId(client.auth.currentSession) != id) {
      _finish(attempt, value: false);
      return;
    }
    // A check must not reject a session that is about to claim.
    if (_pendingId == id && _pendingClaim) {
      _finish(attempt, value: false);
      return;
    }
    final outcome = failure == null
        ? classifySessionCheckAnswer(answer)
        : classifySessionCheckError(failure);
    switch (outcome) {
      case AppSessionCheckOutcome.confirmed:
        _superseded = false;
        _authorizedId = id;
        _watchOwnRow(attempt.userId, id);
        _finish(attempt, value: true);
      case AppSessionCheckOutcome.refused:
        _finish(attempt, value: false);
        supersede();
      default:
        _finish(attempt, error: AppSessionCheckException(outcome));
    }
  }

  void _finish(_Check attempt,
      {bool value = false, Object? error, bool abort = false}) {
    if (attempt.isDone) return;
    final claimWaiting = _pendingClaim && _pendingId == attempt.sessionId;
    attempt.soft?.cancel();
    attempt.hard?.cancel();
    if (identical(_live, attempt)) _live = null;
    if (identical(_pendingCheck, attempt)) {
      _pending = null;
      _pendingId = null;
      _pendingClaim = false;
      _pendingCheck = null;
    }
    if (abort && !attempt.abort.isCompleted) attempt.abort.complete();
    onCheckProgress?.call(_live != null);
    if (error == null || claimWaiting) {
      attempt.result.complete(error == null && value);
    } else {
      attempt.result.completeError(error);
    }
  }

  /// Ends the running check without a decision: its request is aborted and
  /// whatever it answers later is ignored.
  void _detachLive() {
    final live = _live;
    if (live != null) _finish(live, abort: true);
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
    if (sessionId(client.auth.currentSession) != id) return false;
    switch (classifySessionCheckAnswer(answer)) {
      case AppSessionCheckOutcome.confirmed:
        return true;
      case AppSessionCheckOutcome.refused:
        supersede();
        return false;
      default:
        // Not a Boolean: proves nothing, ends nothing.
        throw const AppSessionCheckException(
            AppSessionCheckOutcome.inconclusive);
    }
  }

  void supersede() {
    if (_superseded) return;
    _detachLive();
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
      // A check that outlived its hard deadline while the app was frozen ends
      // now, whatever order its timer and this resume arrive in, so the
      // retry below starts a fresh one instead of joining it.
      final live = _live;
      if (live != null && live.age.elapsed >= hardDeadline) {
        _finish(live,
            error:
                const AppSessionCheckException(AppSessionCheckOutcome.timedOut),
            abort: true);
      }
      onResumeWhileUnverified?.call();
      return;
    }
    unawaited(validateNow().then<void>((_) {}, onError: (Object _) {}));
  }

  void clear() {
    _detachLive();
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
    _detachLive();
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_active, this)) _active = null;
    await _watch?.cancel();
  }
}

class _Check {
  _Check(this.sessionId, this.userId, this.age);

  final String sessionId;
  final String userId;

  /// Monotonic time since the check started.
  final Stopwatch age;
  final Completer<bool> result = Completer<bool>();

  /// Completed only to abort this check's own request.
  final Completer<void> abort = Completer<void>();
  Timer? soft;
  Timer? hard;

  bool get isDone => result.isCompleted;
}
