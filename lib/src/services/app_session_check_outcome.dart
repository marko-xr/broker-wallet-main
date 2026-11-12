import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What one check of a restored session against `is_current_app_session`
/// established. Only [confirmed] may open the application; only [refused]
/// may end the session through this check.
enum AppSessionCheckOutcome {
  /// A valid Boolean `true` for the session that is still current.
  confirmed,

  /// A valid Boolean `false` for the session that is still current.
  refused,

  /// The session was gone when the answer arrived (signed out, or removed by
  /// the SDK after a rejected refresh). The SDK's own events decide.
  absent,

  /// The answer belongs to an attempt that is no longer the current one.
  stale,

  /// The server was not reached: no network, DNS, socket, TLS.
  offline,

  /// The server answered with a 5xx.
  serverUnavailable,

  /// The check did not finish in time, or was aborted at its deadline.
  timedOut,

  /// An answer that is not a Boolean, or a failure that proves nothing.
  inconclusive,

  /// The token was refused by the database API. Not a session refusal: the
  /// SDK refreshes it in time; the application never does.
  credentialsRejected,
}

/// Implemented by an auth repository that can say whether a restored-session
/// check is running, so Retry can show it is waiting for that check.
abstract class AppSessionCheckProgress {
  Stream<bool> get sessionCheckInProgressEvents;
}

/// A session check that ended without a decision. The session is kept.
class AppSessionCheckException implements Exception {
  const AppSessionCheckException(this.outcome);

  final AppSessionCheckOutcome outcome;

  @override
  String toString() => 'AppSessionCheckException(${outcome.name})';
}

/// Only a real Boolean decides; anything else proves nothing.
AppSessionCheckOutcome classifySessionCheckAnswer(Object? answer) {
  if (answer is! bool) return AppSessionCheckOutcome.inconclusive;
  return answer
      ? AppSessionCheckOutcome.confirmed
      : AppSessionCheckOutcome.refused;
}

/// Classifies a failed check by the error's type, never by its text.
AppSessionCheckOutcome classifySessionCheckError(Object error) {
  if (error is AppSessionCheckException) return error.outcome;
  if (error is AuthRetryableFetchException) {
    final status = int.tryParse(error.statusCode ?? '');
    return _isServerError(status)
        ? AppSessionCheckOutcome.serverUnavailable
        : AppSessionCheckOutcome.offline;
  }
  if (error is AuthException) return AppSessionCheckOutcome.credentialsRejected;
  if (error is TimeoutException || error is http.RequestAbortedException) {
    return AppSessionCheckOutcome.timedOut;
  }
  if (error is SocketException ||
      error is http.ClientException ||
      error is TlsException ||
      error is HttpException) {
    return AppSessionCheckOutcome.offline;
  }
  if (error is PostgrestException) {
    const rejectedToken = {'PGRST301', 'PGRST302', 'PGRST303'};
    if (rejectedToken.contains(error.code)) {
      return AppSessionCheckOutcome.credentialsRejected;
    }
    // PostgREST puts the HTTP status here when the body has no code of its
    // own; a database error code (such as 42501) is not a status.
    final status = int.tryParse(error.code ?? '');
    if (_isServerError(status)) {
      return AppSessionCheckOutcome.serverUnavailable;
    }
  }
  return AppSessionCheckOutcome.inconclusive;
}

bool _isServerError(int? status) =>
    status != null && status >= 500 && status < 600;
