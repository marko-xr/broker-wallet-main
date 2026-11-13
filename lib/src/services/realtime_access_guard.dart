import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_access_policy.dart';

// OFF-2b-2 (Realtime): Supabase Realtime is a WebSocket, so no HTTP guard sees
// it. Three pieces close that gap:
// 1. [guardRealtimeTransport] — installed once through
//    `Supabase.initialize(realtimeClientOptions:)`, it refuses every
//    connection while offline read-only. Every channel, `.stream()`, late
//    subscription and supabase_flutter's app-resume reconnect connects through
//    it. A throwing transport takes RealtimeClient.connect()'s general error
//    path, which schedules no reconnect (realtime_client 2.13.0).
// 2. [AppAccessPolicy.onlineOnly] — the event gate on the business streams:
//    nothing is applied from the instant the app turns offline.
// 3. [RealtimeOfflineTeardown] — on that switch, closes the socket first (so
//    channels stop receiving) and then removes every channel (leaving completes
//    at once when no socket is open). Its outcome is recorded, never assumed.

/// The SDK's own default WebSocket transport. It is not exported, but a
/// RealtimeClient exposes the transport it resolved; constructing one opens no
/// connection and starts no timer.
WebSocketTransport sdkDefaultRealtimeTransport() =>
    RealtimeClient('ws://127.0.0.1').transport;

/// [inner] behind the access policy: online it is called exactly as before;
/// offline read-only it is never called.
WebSocketTransport guardRealtimeTransport(WebSocketTransport inner) =>
    (String url, Map<String, String> headers) {
      if (!AppAccessPolicy.isOnline) {
        throw OfflineReadOnlyBlockedException('realtime connect');
      }
      return inner(url, headers);
    };

enum RealtimeTeardownStatus { notStarted, inProgress, completed, failed }

/// Tears Realtime down every time the app turns offline read-only.
class RealtimeOfflineTeardown {
  RealtimeOfflineTeardown({
    required Future<void> Function() disconnect,
    required Future<void> Function() removeAllChannels,
    Duration timeout = const Duration(seconds: 10),
  })  : _disconnect = disconnect,
        _removeAllChannels = removeAllChannels,
        _timeout = timeout;

  factory RealtimeOfflineTeardown.forClient(SupabaseClient client) =>
      RealtimeOfflineTeardown(
        disconnect: () => client.realtime.disconnect(),
        removeAllChannels: () async {
          await client.removeAllChannels();
        },
      );

  final Future<void> Function() _disconnect;
  final Future<void> Function() _removeAllChannels;
  final Duration _timeout;

  RealtimeTeardownStatus _status = RealtimeTeardownStatus.notStarted;
  Future<void> _done = Future<void>.value();
  int _run = 0;

  /// Of the latest teardown. `failed` (an error or the time limit) is never
  /// reported as `completed`; OFF-2b-4 decides what a failure blocks.
  RealtimeTeardownStatus get status => _status;

  /// Completes when the latest teardown has ended (successfully or not).
  Future<void> get done => _done;

  void attach() => AppAccessPolicy.addListener(_onMode);

  void detach() => AppAccessPolicy.removeListener(_onMode);

  void _onMode(AppAccessMode mode) {
    if (mode == AppAccessMode.offlineReadOnly) _done = _teardown();
  }

  Future<void> _teardown() async {
    final run = ++_run;
    _status = RealtimeTeardownStatus.inProgress; // set synchronously
    try {
      await _disconnect().timeout(_timeout);
      await _removeAllChannels().timeout(_timeout);
      if (run == _run) _status = RealtimeTeardownStatus.completed;
    } catch (_) {
      if (run == _run) _status = RealtimeTeardownStatus.failed;
    }
  }
}
