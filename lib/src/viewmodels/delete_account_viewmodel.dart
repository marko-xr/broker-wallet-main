import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/services/account_deletion_state_store.dart';

/// The pending-deletion marker, behind a seam so tests can observe it.
class AccountDeletionMarkers {
  const AccountDeletionMarkers();

  Future<void> remember(String uid) => AccountDeletionStateStore.remember(uid);

  Future<void> forgetIfOwnedBy(String uid) =>
      AccountDeletionStateStore.forgetIfOwnedBy(uid);
}

/// The steps of the Delete Account flow.
enum DeleteAccountStep {
  /// What will be deleted, and that it cannot be undone.
  review,

  /// Password and the explicit final confirmation.
  confirm,

  /// The server request is running. Nothing can be changed or dismissed.
  deleting,

  /// The server deleted the account and local state has been ended.
  completed,
}

/// Runs permanent deletion of the signed-in account.
///
/// Authority is layered, and no layer trusts the one above it:
///  * the account is captured when the flow starts, and every later step
///    refuses to continue for any other account;
///  * the gateway sends only the live session's token, and refuses locally if
///    that session is no longer the captured account;
///  * the server derives the account from that token alone.
///
/// The password lives in the sheet's text controller and in the argument to
/// [submit]; nothing here stores, copies or logs it.
class DeleteAccountViewModel extends ChangeNotifier {
  DeleteAccountViewModel({
    required AccountDeletionGateway gateway,
    required AccountDeletionSession session,
    AccountDeletionMarkers markers = const AccountDeletionMarkers(),
  })  : _gateway = gateway,
        _session = session,
        _markers = markers,
        _ownerUid = session.currentUserId;

  final AccountDeletionGateway _gateway;
  final AccountDeletionSession _session;
  final AccountDeletionMarkers _markers;

  /// The account this flow was opened for. Never replaced.
  final String? _ownerUid;

  DeleteAccountStep _step = DeleteAccountStep.review;
  bool _acknowledged = false;
  String? _errorKey;
  bool _disposed = false;

  DeleteAccountStep get step => _step;
  bool get acknowledged => _acknowledged;
  String? get errorKey => _errorKey;

  /// True from the moment the request is sent until the flow ends. The sheet
  /// cannot be dismissed and no control is enabled while this is true.
  bool get isDeleting => _step == DeleteAccountStep.deleting;

  bool get isCompleted => _step == DeleteAccountStep.completed;

  /// The outcome could not be confirmed and the session was ended on this
  /// device. Reported to the user as "sign in again to check", never as a
  /// deletion.
  bool get endedUnconfirmed => _endedUnconfirmed;
  bool _endedUnconfirmed = false;

  /// The flow can only run for a real, ordinary session.
  bool get canStart =>
      (_ownerUid ?? '').isNotEmpty && !_session.isPasswordRecoveryActive;

  void continueToConfirmation() {
    if (_step != DeleteAccountStep.review) return;
    if (!canStart) {
      _fail('deleteAccountErrorSession');
      return;
    }
    _step = DeleteAccountStep.confirm;
    _errorKey = null;
    _notify();
  }

  void backToReview() {
    if (_step != DeleteAccountStep.confirm) return;
    _step = DeleteAccountStep.review;
    _acknowledged = false;
    _errorKey = null;
    _notify();
  }

  void setAcknowledged(bool value) {
    if (_step != DeleteAccountStep.confirm || _acknowledged == value) return;
    _acknowledged = value;
    _errorKey = null;
    _notify();
  }

  void clearError() {
    if (_errorKey == null) return;
    _errorKey = null;
    _notify();
  }

  /// Deletes the account. Returns true only when the account is gone — as
  /// reported by the server for this request, or by Supabase Auth when this
  /// request's outcome was unknown — and local state for it has been ended.
  Future<bool> submit({required String password}) async {
    if (_step == DeleteAccountStep.deleting) {
      // A second tap while one request is running is ignored, never sent.
      return false;
    }
    if (_step != DeleteAccountStep.confirm) return false;

    // Local refusals first: none of these reaches the network.
    if (!_acknowledged) {
      _fail('deleteAccountErrorAcknowledge');
      return false;
    }
    if (password.isEmpty) {
      _fail('deleteAccountErrorPasswordRequired');
      return false;
    }
    final ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.sessionExpired));
      return false;
    }
    if (_session.isPasswordRecoveryActive) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.recoverySession));
      return false;
    }
    if (_session.currentUserId != ownerUid) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.accountChanged));
      return false;
    }

    _errorKey = null;
    _step = DeleteAccountStep.deleting;
    _notify();

    // Written before the request, so a success whose response never arrives —
    // including one the app does not survive — is settled on the next session
    // start instead of leaving a deleted account presented as signed in.
    await _markers.remember(ownerUid);

    AccountDeletionFailureCode? failure;
    try {
      await _gateway.deleteAccount(expectedUid: ownerUid, password: password);
    } on AccountDeletionFailure catch (error) {
      failure = error.code;
    } catch (_) {
      failure = AccountDeletionFailureCode.unknown;
    }

    if (failure == null) {
      // The account is gone on the server. Local completion is keyed to the
      // captured account, not to whoever may be signed in now, so a late
      // result can never end or wipe a different account.
      await _session.completeAccountDeletion(ownerUid);
      return _complete();
    }

    if (accountDeletionNotAttempted.contains(failure)) {
      await _markers.forgetIfOwnedBy(ownerUid);
    } else {
      // The outcome is open. The session is ended either way — an uncertain
      // deletion never stays application-authenticated — and only Supabase
      // Auth's answer decides whether it may be reported as a deletion.
      final convergence = await _session.reconcileAccountDeletion(ownerUid);
      if (convergence == AccountDeletionConvergence.deleted) {
        return _complete();
      }
      if (convergence == AccountDeletionConvergence.sessionEnded) {
        _endedUnconfirmed = true;
        failure = AccountDeletionFailureCode.sessionExpired;
      }
    }

    _step = DeleteAccountStep.confirm;
    _fail(deleteAccountErrorKey(failure));
    return false;
  }

  bool _complete() {
    _step = DeleteAccountStep.completed;
    _notify();
    return true;
  }

  void _fail(String key) {
    _errorKey = key;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Maps a deletion failure to an ARB key. Server text never reaches here.
String deleteAccountErrorKey(AccountDeletionFailureCode code) {
  switch (code) {
    case AccountDeletionFailureCode.reauthenticationFailed:
      return 'deleteAccountErrorPassword';
    case AccountDeletionFailureCode.reauthenticationUnsupported:
      return 'deleteAccountErrorUnsupported';
    case AccountDeletionFailureCode.sessionExpired:
    case AccountDeletionFailureCode.recoverySession:
      return 'deleteAccountErrorSession';
    case AccountDeletionFailureCode.accountChanged:
      return 'deleteAccountErrorAccountChanged';
    case AccountDeletionFailureCode.deletionInProgress:
    case AccountDeletionFailureCode.deletionPending:
      return 'deleteAccountErrorInProgress';
    case AccountDeletionFailureCode.mediaCleanupFailed:
    case AccountDeletionFailureCode.serverDeleteFailed:
      return 'deleteAccountErrorNotDeleted';
    case AccountDeletionFailureCode.rateLimited:
      return 'deleteAccountErrorRateLimited';
    case AccountDeletionFailureCode.network:
      return 'deleteAccountErrorNetwork';
    case AccountDeletionFailureCode.unavailable:
      return 'deleteAccountErrorUnavailable';
    case AccountDeletionFailureCode.unknown:
      return 'deleteAccountErrorUnknown';
  }
}
