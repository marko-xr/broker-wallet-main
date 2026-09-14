import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:broker_wallet/src/config/r2_config.dart';

/// Why an account deletion did not complete.
///
/// Every value is a fixed domain outcome. Nothing from the server response —
/// provider text, a token, an object key — is carried, so no failure can put
/// backend detail in front of the user.
enum AccountDeletionFailureCode {
  /// The password did not match the account. Nothing was deleted.
  reauthenticationFailed,

  /// The account has no way to be confirmed by password (for example a future
  /// Google, Apple or phone-only account). Nothing was deleted.
  reauthenticationUnsupported,

  /// There is no usable session, or Supabase Auth rejected it. On its own this
  /// says nothing about whether the account still exists.
  sessionExpired,

  /// The signed-in account is not the one the deletion was started for.
  accountChanged,

  /// Another deletion request for this account is already past its point of
  /// no return. The outcome is not known yet.
  deletionInProgress,

  /// The server could not confirm whether the account was deleted and will
  /// settle it itself. The outcome is not known yet.
  deletionPending,

  /// A password-recovery session may not delete an account.
  recoverySession,

  /// Stored media could not be removed. The account was not deleted.
  mediaCleanupFailed,

  /// The server confirmed the account was not deleted. Retrying is safe.
  serverDeleteFailed,

  rateLimited,

  /// The request did not complete. The deletion may or may not have happened.
  network,

  /// Account deletion is not available from this server. Nothing was deleted.
  unavailable,

  unknown,
}

/// Failures after which the account is known NOT to have been deleted.
///
/// Every other failure leaves the outcome open, and only Supabase Auth itself
/// can settle it (see [AccountExistenceProbe]).
const Set<AccountDeletionFailureCode> accountDeletionNotAttempted = {
  AccountDeletionFailureCode.reauthenticationFailed,
  AccountDeletionFailureCode.reauthenticationUnsupported,
  AccountDeletionFailureCode.accountChanged,
  AccountDeletionFailureCode.recoverySession,
  AccountDeletionFailureCode.mediaCleanupFailed,
  AccountDeletionFailureCode.serverDeleteFailed,
  AccountDeletionFailureCode.rateLimited,
  AccountDeletionFailureCode.unavailable,
};

class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.code);

  final AccountDeletionFailureCode code;

  @override
  String toString() => 'AccountDeletionFailure(${code.name})';
}

/// Performs the server-side deletion of the signed-in account.
abstract class AccountDeletionGateway {
  /// Deletes the account of the live session, which must be [expectedUid].
  ///
  /// Completes normally only when the server reported the account deleted.
  /// [expectedUid] is used only to refuse locally when the session has
  /// changed. It is never sent: the server derives the account from the
  /// session token alone. Throws [AccountDeletionFailure].
  Future<void> deleteAccount({
    required String expectedUid,
    required String password,
  });
}

/// What Supabase Auth says about the live session's account.
enum AccountExistence {
  /// Supabase Auth returned the account for this session.
  exists,

  /// Supabase Auth reports that the account in this session does not exist.
  deleted,

  /// Supabase Auth rejected the session for another reason. The session is
  /// unusable either way.
  sessionInvalid,

  /// The question could not be answered (offline, server error).
  unknown,
}

/// Asks Supabase Auth — not the app, not the Worker — whether the live
/// session's account still exists.
abstract class AccountExistenceProbe {
  /// Answers for the account the live session belongs to at call time.
  /// [AccountExistence.exists] is only returned for that same account id.
  Future<AccountExistence> probeCurrentAccount();
}

/// How a deletion whose outcome was unknown was settled on this device.
enum AccountDeletionConvergence {
  /// Nothing to settle, or the account still exists, or the answer is not
  /// available yet.
  none,

  /// Supabase Auth reports the account gone; local state has been ended.
  deleted,

  /// Supabase Auth rejected the session; local state has been ended without
  /// claiming the account was deleted.
  sessionEnded,
}

/// The application-side owner of the session a deletion acts on.
///
/// Implemented by `AuthViewModel`, which remains the single owner of the
/// authenticated application identity.
abstract class AccountDeletionSession {
  String? get currentUserId;

  /// A password-recovery session is never allowed to delete an account.
  bool get isPasswordRecoveryActive;

  /// Ends local state for an account the server has already deleted.
  Future<void> completeAccountDeletion(String deletedUid);

  /// Settles a deletion of [uid] whose outcome is unknown, by asking Supabase
  /// Auth about the live session. Acts only while the live session is [uid].
  Future<AccountDeletionConvergence> reconcileAccountDeletion(String uid);
}

/// The live session's account and access token, read together.
class AccountDeletionCredentials {
  const AccountDeletionCredentials({
    required this.userId,
    required this.accessToken,
  });

  final String userId;
  final String accessToken;
}

/// Calls `POST /account/delete` on the Broker Wallet media Worker.
///
/// The Worker holds the only credentials that can remove R2 objects and delete
/// a Supabase Auth user. This client sends the live session's access token and
/// the password the user just typed, and nothing else — no user id, no object
/// key. The password is neither stored nor logged.
class WorkerAccountDeletionGateway implements AccountDeletionGateway {
  WorkerAccountDeletionGateway({
    http.Client? httpClient,
    AccountDeletionCredentials? Function()? readCredentials,
  })  : _http = httpClient ?? http.Client(),
        _readCredentials = readCredentials ?? _liveSupabaseCredentials;

  /// Deletion removes media and then the account, so it is allowed longer than
  /// an ordinary metadata call. A timeout is reported as [network]: the
  /// outcome is then unknown and is settled through Supabase Auth.
  static const Duration requestTimeout = Duration(seconds: 45);

  final http.Client _http;
  final AccountDeletionCredentials? Function() _readCredentials;

  static AccountDeletionCredentials? _liveSupabaseCredentials() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    return AccountDeletionCredentials(
      userId: session.user.id,
      accessToken: session.accessToken,
    );
  }

  @override
  Future<void> deleteAccount({
    required String expectedUid,
    required String password,
  }) async {
    if (!R2Config.isConfigured) {
      throw const AccountDeletionFailure(
        AccountDeletionFailureCode.unavailable,
      );
    }

    // The user id and the token are read from the same session in the same
    // turn, so the token that is sent is known to belong to [expectedUid].
    final credentials = _readCredentials();
    final token = credentials?.accessToken;
    if (credentials == null || token == null || token.isEmpty) {
      throw const AccountDeletionFailure(
        AccountDeletionFailureCode.sessionExpired,
      );
    }
    if (credentials.userId != expectedUid) {
      throw const AccountDeletionFailure(
        AccountDeletionFailureCode.accountChanged,
      );
    }

    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('${R2Config.workerUrl}/account/delete'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'password': password}),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const AccountDeletionFailure(AccountDeletionFailureCode.network);
    } catch (_) {
      throw const AccountDeletionFailure(AccountDeletionFailureCode.network);
    }

    interpretAccountDeletionResponse(response.statusCode, response.body);
  }
}

/// Accepts only the exact success response; anything else becomes a fixed
/// failure read from the `error` code alone.
void interpretAccountDeletionResponse(int statusCode, String body) {
  String? status;
  String? error;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final rawStatus = decoded['status'];
      final rawError = decoded['error'];
      if (rawStatus is String) status = rawStatus;
      if (rawError is String) error = rawError;
    }
  } catch (_) {}

  if (statusCode == 200 && status == 'deleted') return;
  throw AccountDeletionFailure(_failureCodeFor(statusCode, error));
}

AccountDeletionFailureCode _failureCodeFor(int statusCode, String? error) {
  switch (error) {
    case 'reauthentication_failed':
      return AccountDeletionFailureCode.reauthenticationFailed;
    case 'reauthentication_unsupported':
      return AccountDeletionFailureCode.reauthenticationUnsupported;
    case 'session_expired':
      return AccountDeletionFailureCode.sessionExpired;
    case 'account_mismatch':
      return AccountDeletionFailureCode.accountChanged;
    case 'recovery_session':
      return AccountDeletionFailureCode.recoverySession;
    case 'deletion_in_progress':
      return AccountDeletionFailureCode.deletionInProgress;
    case 'deletion_pending':
      return AccountDeletionFailureCode.deletionPending;
    case 'media_cleanup_failed':
      return AccountDeletionFailureCode.mediaCleanupFailed;
    case 'server_delete_failed':
      return AccountDeletionFailureCode.serverDeleteFailed;
    case 'rate_limited':
      return AccountDeletionFailureCode.rateLimited;
    case 'service_unavailable':
      return AccountDeletionFailureCode.network;
  }
  if (statusCode == 401) return AccountDeletionFailureCode.sessionExpired;
  if (statusCode == 429) return AccountDeletionFailureCode.rateLimited;
  // The endpoint is not deployed on this Worker yet.
  if (statusCode == 404) return AccountDeletionFailureCode.unavailable;
  if (statusCode >= 500) return AccountDeletionFailureCode.network;
  return AccountDeletionFailureCode.unknown;
}
