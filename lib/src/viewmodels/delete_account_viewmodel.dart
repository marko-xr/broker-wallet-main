import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/services/account_deletion_state_store.dart';
import 'package:broker_wallet/src/services/offline_pass_lifecycle.dart';

/// The pending-deletion marker, behind a seam so tests can observe it.
class AccountDeletionMarkers {
  const AccountDeletionMarkers();

  /// OFF-2b-3: offline access for [uid] is revoked (and the account latched)
  /// before the deletion even starts. Throws, writing nothing, when that
  /// cannot be made safe: the deletion must then not start.
  Future<void> remember(String uid) async {
    final revocation = await OfflinePassLifecycle.shared
        .invalidate(OfflinePassInvalidation.accountDeletion, uid: uid);
    if (!revocation.safe) {
      throw StateError('offline access could not be revoked');
    }
    await AccountDeletionStateStore.remember(uid);
  }

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

/// How the account proves it is the one being deleted.
enum DeleteAccountProof {
  /// The account password (email accounts; phone accounts that set one).
  password,

  /// A code Supabase sends to the account's own sign-in number (phone
  /// accounts, Model X). The number comes from the session, never from here.
  phoneCode,
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
    String? signInPhoneE164,
    bool canUsePassword = true,
  })  : _gateway = gateway,
        _session = session,
        _markers = markers,
        _ownerUid = session.currentUserId,
        _signInPhone = signInPhoneE164,
        _canUsePassword = canUsePassword,
        _proof = signInPhoneE164 != null
            ? DeleteAccountProof.phoneCode
            : DeleteAccountProof.password;

  final AccountDeletionGateway _gateway;
  final AccountDeletionSession _session;
  final AccountDeletionMarkers _markers;

  /// The account this flow was opened for. Never replaced.
  final String? _ownerUid;

  /// The account's sign-in number when it signs in by phone, else null.
  final String? _signInPhone;
  final bool _canUsePassword;
  DeleteAccountProof _proof;
  bool _codeSent = false;
  bool _sendingCode = false;

  DeleteAccountStep _step = DeleteAccountStep.review;
  bool _acknowledged = false;
  String? _errorKey;
  bool _disposed = false;

  DeleteAccountStep get step => _step;
  DeleteAccountProof get proof => _proof;

  /// Shown so the user knows where the code goes. Display only.
  String? get signInPhoneE164 => _signInPhone;

  /// A phone account that also has an email may use its password instead.
  bool get canSwitchProof => _signInPhone != null && _canUsePassword;
  bool get codeSent => _codeSent;
  bool get isSendingCode => _sendingCode;
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

  /// Switches between the code and the password (phone accounts with an
  /// email only). Never while a request runs.
  void useProof(DeleteAccountProof proof) {
    if (proof == _proof || isDeleting || _sendingCode) return;
    if (proof == DeleteAccountProof.password && !canSwitchProof) return;
    if (proof == DeleteAccountProof.phoneCode && _signInPhone == null) return;
    _proof = proof;
    _errorKey = null;
    _notify();
  }

  /// Phone accounts: asks the server to send the deletion code. Returns
  /// whether it was sent. The server applies its own limits.
  Future<bool> requestCode() async {
    if (_step != DeleteAccountStep.confirm ||
        _proof != DeleteAccountProof.phoneCode ||
        isDeleting ||
        _sendingCode) {
      return false;
    }
    final gateway = _gateway;
    if (gateway is! PhoneAccountDeletionGateway) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.unavailable));
      return false;
    }
    final ownerUid = _refuseLocally();
    if (ownerUid == null) return false;

    _sendingCode = true;
    _errorKey = null;
    _notify();
    var sent = false;
    try {
      await (gateway as PhoneAccountDeletionGateway)
          .requestDeletionCode(expectedUid: ownerUid);
      sent = true;
    } on AccountDeletionFailure catch (error) {
      _errorKey = deleteAccountErrorKey(error.code, proof: _proof);
    } catch (_) {
      _errorKey = deleteAccountErrorKey(AccountDeletionFailureCode.unknown);
    }
    _sendingCode = false;
    if (sent) _codeSent = true;
    _notify();
    return sent;
  }

  void clearError() {
    if (_errorKey == null) return;
    _errorKey = null;
    _notify();
  }

  /// Deletes the account. Returns true only when the account is gone — as
  /// reported by the server for this request, or by Supabase Auth when this
  /// request's outcome was unknown — and local state for it has been ended.
  Future<bool> submit({required String password}) {
    if (isDeleting) {
      // A second tap while one request is running is ignored, never sent.
      return Future.value(false);
    }
    return _submission = _submit(password: password);
  }

  /// Phone accounts: deletes the account with the code sent to its number.
  /// Same guarantees as [submit].
  Future<bool> submitCode({required String code}) {
    if (isDeleting || _sendingCode) return Future.value(false);
    return _submission = _submitCode(code.trim());
  }

  Future<bool> _submitCode(String code) async {
    if (_step != DeleteAccountStep.confirm ||
        _proof != DeleteAccountProof.phoneCode) {
      return false;
    }
    if (!_acknowledged) {
      _fail('deleteAccountErrorAcknowledge');
      return false;
    }
    if (!_codeSent || !RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      _fail('deleteAccountErrorCodeRequired');
      return false;
    }
    final gateway = _gateway;
    if (gateway is! PhoneAccountDeletionGateway) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.unavailable));
      return false;
    }
    final ownerUid = _refuseLocally();
    if (ownerUid == null) return false;
    return _run(
      ownerUid,
      () => (gateway as PhoneAccountDeletionGateway)
          .deleteAccountWithCode(expectedUid: ownerUid, code: code),
    );
  }

  /// The account-level refusals shared by every request. Returns the owner
  /// when the request may proceed.
  String? _refuseLocally() {
    final ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.sessionExpired));
      return null;
    }
    if (_session.isPasswordRecoveryActive) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.recoverySession));
      return null;
    }
    if (_session.currentUserId != ownerUid) {
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.accountChanged));
      return null;
    }
    return ownerUid;
  }

  Future<bool>? _submission;

  /// Completes once the last [submit] has ended, whatever its outcome.
  ///
  /// Ending the session at the end of a deletion moves the app to the
  /// logged-out entry, which can close the sheet before the flow has recorded
  /// how it ended. Callers that report the outcome wait for this first.
  Future<void> whenSettled() async {
    try {
      await _submission;
    } catch (_) {
      // The outcome is read from [isCompleted] and [endedUnconfirmed].
    }
  }

  Future<bool> _submit({required String password}) async {
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

    return _run(
      ownerUid,
      () => _gateway.deleteAccount(expectedUid: ownerUid, password: password),
    );
  }

  /// The deletion lifecycle shared by both proofs.
  Future<bool> _run(String ownerUid, Future<void> Function() request) async {
    _errorKey = null;
    _step = DeleteAccountStep.deleting;
    _notify();

    // Written before the request, so a success whose response never arrives —
    // including one the app does not survive — is settled on the next session
    // start instead of leaving a deleted account presented as signed in.
    try {
      await _markers.remember(ownerUid);
    } catch (_) {
      // Nothing was sent: the account still exists and can be retried.
      _step = DeleteAccountStep.confirm;
      _fail(deleteAccountErrorKey(AccountDeletionFailureCode.unknown));
      return false;
    }

    AccountDeletionFailureCode? failure;
    try {
      await request();
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
    if (failure == AccountDeletionFailureCode.codeExpired) _codeSent = false;
    _fail(deleteAccountErrorKey(failure, proof: _proof));
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
String deleteAccountErrorKey(
  AccountDeletionFailureCode code, {
  DeleteAccountProof proof = DeleteAccountProof.password,
}) {
  switch (code) {
    case AccountDeletionFailureCode.reauthenticationFailed:
      return proof == DeleteAccountProof.phoneCode
          ? 'deleteAccountErrorCode'
          : 'deleteAccountErrorPassword';
    case AccountDeletionFailureCode.codeExpired:
      return 'deleteAccountErrorCodeExpired';
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
