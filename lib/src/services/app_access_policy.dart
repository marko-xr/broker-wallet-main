import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// OFF-2b-2 (tracker §7BD-18): the one access policy of the application.
//
// `online` is today's behaviour. `offlineReadOnly` is for a bounded offline
// grant (OFF-2b-1 pass): the user browses what this phone already holds, and
// NOTHING leaves it — no Supabase read, write or RPC, no Worker call, no media
// or file download, no upload, no sync. A stored session is not authority, and
// connectivity coming back is not authority either: only the session
// coordinator, after an authoritative check, may return the app to `online`.
//
// DORMANT in this checkpoint: nothing enters `offlineReadOnly` yet (OFF-2b-4
// will, before Home and before any background job may run).

enum AppAccessMode { online, offlineReadOnly }

/// The only server operations the session coordinator may run while offline
/// (wired in OFF-2b-5), each limited to one exact endpoint.
enum CoordinatorNetworkCapability {
  /// `POST /rest/v1/rpc/is_current_app_session` — read-only verification.
  sessionCheck,

  /// `POST /auth/v1/token?grant_type=refresh_token` — renews the access token
  /// for that verification; writes no business data.
  tokenRefresh,

  /// `POST /rest/v1/rpc/release_current_app_session` and
  /// `POST /auth/v1/logout?scope=local` — give up authority on sign-out.
  sessionRelease,
}

/// A request or operation refused by the offline read-only policy. It is not
/// a network failure, not a server refusal and not a Worker answer: it proves
/// nothing about the server, so nothing held on the phone may be deleted or
/// replaced because of it. It extends [http.ClientException] so that existing
/// callers treat it as "no answer" (keep local data, keep queued work).
class OfflineReadOnlyBlockedException extends http.ClientException {
  OfflineReadOnlyBlockedException(this.operation, [Uri? uri])
      : super('Not available offline (read-only): $operation', uri);

  /// What was refused, for diagnostics (never a URL query or a token).
  final String operation;
}

/// Held by the session coordinator only (claimed once per isolate).
final class CoordinatorKey {
  CoordinatorKey._();
}

/// A key the policy never issued (tests only).
@visibleForTesting
CoordinatorKey debugForgeCoordinatorKey() => CoordinatorKey._();

abstract final class AppAccessPolicy {
  static AppAccessMode _mode = AppAccessMode.online;
  static int _epoch = 0;
  static CoordinatorKey? _key;
  static Uri? _origin;
  static final List<void Function(AppAccessMode mode)> _listeners = [];
  static final Object _capabilityZoneKey = Object();
  static http.Client? _shared;

  static AppAccessMode get mode => _mode;
  static bool get isOnline => _mode == AppAccessMode.online;

  /// Changes on every mode change; a response begun in another epoch is stale.
  static int get epoch => _epoch;

  /// Restricts the app. Anyone may restrict; nothing else happens here.
  static void enterOfflineReadOnly() => _set(AppAccessMode.offlineReadOnly);

  /// Lifts the restriction: only with the coordinator's key, after an
  /// authoritative online confirmation (OFF-2b-5).
  static void enterOnline(CoordinatorKey key) {
    _requireKey(key);
    _set(AppAccessMode.online);
  }

  /// Issued once; a second claim is a programming error.
  static CoordinatorKey claimCoordinatorKey() {
    if (_key != null) {
      throw StateError('The coordinator key was already claimed.');
    }
    return _key = CoordinatorKey._();
  }

  /// The Supabase origin the coordinator capabilities may reach (set once by
  /// the bootstrap). Without it, nothing is allowed offline.
  static void configureSupabaseOrigin(Uri url) {
    _origin ??= Uri(scheme: url.scheme, host: url.host, port: url.port);
  }

  static void addListener(void Function(AppAccessMode mode) listener) =>
      _listeners.add(listener);

  static void removeListener(void Function(AppAccessMode mode) listener) =>
      _listeners.remove(listener);

  /// Service-level guard for work that is not a single HTTP request (a toggle,
  /// a queue, a counter): throws the typed denial when offline.
  static void ensureOnline(String operation) {
    if (!isOnline) throw OfflineReadOnlyBlockedException(operation);
  }

  /// The event gate for a server-backed business stream (Realtime profile,
  /// notifications, Favorites ids). The decision is taken when the stream is
  /// LISTENED to, not when it is created: offline, [open] is never called
  /// (no channel, no request) and the stream stays silent. Online, events flow
  /// as before until the app turns offline; from that instant nothing more is
  /// delivered (not even an event already queued), and the source
  /// subscription is cancelled. Coming back online does not resubscribe: that
  /// needs an authoritative revalidation and a new listen (OFF-2b-5).
  static Stream<T> onlineOnly<T>(Stream<T> Function() open) {
    return Stream<T>.multi((controller) {
      if (!isOnline) return;
      final opened = _epoch;
      bool live() => isOnline && _epoch == opened;
      StreamSubscription<T>? source;
      late final void Function(AppAccessMode mode) onMode;
      void stop() {
        removeListener(onMode);
        final s = source;
        source = null;
        if (s != null) {
          unawaited(s.cancel().then<void>((_) {}, onError: (Object _) {}));
        }
      }

      onMode = (mode) {
        if (mode == AppAccessMode.offlineReadOnly) stop();
      };
      addListener(onMode);
      source = open().listen(
        (event) {
          if (live()) controller.add(event);
        },
        onError: (Object error, StackTrace stack) {
          if (live()) controller.addError(error, stack);
        },
        onDone: () {
          if (live()) controller.close();
        },
      );
      controller.onCancel = stop;
    });
  }

  /// Runs [body] with one coordinator capability. Requests made inside it may
  /// reach exactly that capability's endpoint while offline; nothing else.
  static Future<T> runWithCapability<T>(CoordinatorKey key,
      CoordinatorNetworkCapability capability, Future<T> Function() body) {
    _requireKey(key);
    return runZoned(body, zoneValues: {_capabilityZoneKey: capability});
  }

  /// [inner] behind the policy (never wrapped twice).
  static http.Client guard(http.Client inner) =>
      inner is PolicyGuardedClient ? inner : PolicyGuardedClient(inner);

  /// The client factory for `http.runWithClient` in `main()`: every
  /// `http.Client()` and top-level `http.get` in the app's zone is guarded.
  /// Its transport is an [IOClient], so it never recurses into the zone.
  static http.Client newZoneClient() => PolicyGuardedClient(IOClient());

  /// A shared guarded client for one-off requests (replaces top-level
  /// `http.get`).
  static http.Client get shared => _shared ??= guard(http.Client());

  static void _set(AppAccessMode next) {
    if (_mode == next) return;
    _mode = next;
    _epoch++;
    for (final listener in List.of(_listeners)) {
      try {
        listener(next);
      } catch (_) {
        // One listener must not stop the switch or the others.
      }
    }
  }

  static void _requireKey(CoordinatorKey key) {
    if (_key == null || !identical(key, _key)) {
      throw StateError('Not the coordinator key.');
    }
  }

  /// Whether a request may leave the phone now, and whether it does so under
  /// a coordinator capability (exempt from the stale-response rule).
  static ({bool allowed, bool capability}) _decide(String method, Uri url) {
    if (isOnline) return (allowed: true, capability: false);
    final cap = Zone.current[_capabilityZoneKey];
    final origin = _origin;
    if (cap is! CoordinatorNetworkCapability ||
        origin == null ||
        method != 'POST' ||
        url.scheme != origin.scheme ||
        url.host != origin.host ||
        url.port != origin.port ||
        url.fragment.isNotEmpty) {
      return (allowed: false, capability: false);
    }
    final q = url.queryParameters;
    final ok = switch (cap) {
      CoordinatorNetworkCapability.sessionCheck =>
        url.path == '/rest/v1/rpc/is_current_app_session' && q.isEmpty,
      CoordinatorNetworkCapability.tokenRefresh =>
        url.path == '/auth/v1/token' &&
            q.length == 1 &&
            q['grant_type'] == 'refresh_token',
      CoordinatorNetworkCapability.sessionRelease =>
        (url.path == '/rest/v1/rpc/release_current_app_session' && q.isEmpty) ||
            (url.path == '/auth/v1/logout' &&
                (q.isEmpty || (q.length == 1 && q['scope'] == 'local'))),
    };
    return (allowed: ok, capability: ok);
  }

  @visibleForTesting
  static void debugReset() {
    _mode = AppAccessMode.online;
    _epoch = 0;
    _key = null;
    _origin = null;
    _listeners.clear();
    _shared = null;
  }
}

/// Every request checks the policy at send time; a response that arrives
/// after a mode change is discarded (a capability request excepted). Online,
/// the request object is passed through untouched.
class PolicyGuardedClient extends http.BaseClient {
  PolicyGuardedClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final started = AppAccessPolicy.epoch;
    final decision = AppAccessPolicy._decide(request.method, request.url);
    if (!decision.allowed) {
      throw OfflineReadOnlyBlockedException(
          '${request.method} ${request.url.host}${request.url.path}',
          _withoutQuery(request.url));
    }
    final response = await _inner.send(request);
    if (!decision.capability && AppAccessPolicy.epoch != started) {
      unawaited(response.stream.listen(null).cancel());
      throw OfflineReadOnlyBlockedException(
          'response after the access mode changed', _withoutQuery(request.url));
    }
    return response;
  }

  @override
  void close() => _inner.close();

  /// Scheme, host, port and path only: a signed link's query never travels
  /// in a diagnostic.
  static Uri _withoutQuery(Uri u) =>
      Uri(scheme: u.scheme, host: u.host, port: u.port, path: u.path);
}
