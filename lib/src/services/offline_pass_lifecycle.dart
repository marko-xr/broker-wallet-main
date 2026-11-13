import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session_check_outcome.dart';
import 'app_session_coordinator.dart';
import 'offline_session_lease.dart';

// OFF-2b-3 (tracker §7BD-20): the authoritative lifecycle of the offline pass.
//
// Issued ONLY when the server answered a session CHECK with a current `true`
// (AppSessionCoordinator.onConfirmed: a restored-session check or
// validateNow) — never for a sign-in claim, a refreshed token alone, a stored
// session or any failure (tracker §7BD-16 ب) — for the exact session that was
// checked, only while that session is still the current one, and only when
// no invalidation happened since that check started.
// Invalidated (before the step that follows it) on sign-out, displacement,
// 401/403, password recovery, a new sign-in, a vanished session and the start
// of Delete Account.
//
// Corrections A–C: an invalidation first revokes durably through a plain
// file (OfflineSessionLease.revokeNow, not the secure-storage queue); only
// after that succeeded is the queued secure-storage delete waited for with a
// bound. Sign-out, displacement, recovery and Delete Account also latch that
// account/session for the rest of the process.
//
// Nothing here opens Home or admits a cold start: that is OFF-2b-4.

/// Why the pass was invalidated (diagnostics; no account data).
enum OfflinePassInvalidation {
  signOut,
  signedOut,
  superseded,
  credentialsRejected,
  passwordRecovery,
  accountDeletion,
  newSignIn,
}

/// What an invalidation achieved.
class OfflinePassRevocation {
  const OfflinePassRevocation({required this.durable, required this.deleted});

  /// The revocation marker was written, flushed and read back: no pass that
  /// existed before can be used again, whatever happens to the delete.
  final bool durable;

  /// The queued secure-storage delete: true done, false failed, null still
  /// running when the bound ended (only ever after a durable revocation).
  final bool? deleted;

  /// Whether the old pass can never be used again.
  bool get safe => durable || deleted == true;
}

class OfflinePassLifecycle {
  /// Tests only; the app uses [shared].
  @visibleForTesting
  OfflinePassLifecycle(
    this.lease, {
    this.markerBound = const Duration(seconds: 5),
    this.deleteBound = const Duration(seconds: 5),
  });

  /// The one lease of the process: protected store, the durable revocation
  /// marker (every platform), and the Android crash-durable charge journal
  /// (none on iOS).
  static final OfflinePassLifecycle _platform = OfflinePassLifecycle(
    OfflineSessionLease(
      store: SecureOfflinePassStore(),
      chargeJournal: platformChargeJournal(isAndroid: Platform.isAndroid),
      revocationMarker: FileOfflinePassRevocationMarker(),
    ),
  );
  static OfflinePassLifecycle? _override;

  /// The single instance every caller uses (OFF-2b-4 admits through it).
  static OfflinePassLifecycle get shared => _override ?? _platform;

  @visibleForTesting
  static set debugShared(OfflinePassLifecycle? value) => _override = value;

  final OfflineSessionLease lease;

  /// How long the durable revocation may take before it counts as failed.
  final Duration markerBound;

  /// How long a caller waits for the secure-storage delete once the
  /// revocation is durable. Without a durable revocation there is no bound.
  final Duration deleteBound;

  int _invalidations = 0;

  /// Accounts (`uid`) and sessions (`uid|sid`) that may not get a pass again
  /// in this process.
  final Set<String> _latched = {};

  static const _latching = {
    OfflinePassInvalidation.signOut,
    OfflinePassInvalidation.superseded,
    OfflinePassInvalidation.passwordRecovery,
    OfflinePassInvalidation.accountDeletion,
  };

  /// Changes with every invalidation. A check records it when it starts; its
  /// confirmation counts only if no invalidation happened since.
  int get epoch => _invalidations;

  /// The reason of the latest invalidation (diagnostics).
  OfflinePassInvalidation? lastInvalidation;

  /// The outcome of the latest invalidation (diagnostics).
  OfflinePassRevocation? lastRevocation;

  /// Issues or renews the pass for [checked], the session whose check the
  /// server just confirmed. Nothing is issued when an invalidation happened
  /// after that check started ([startedEpoch]), when the account or session
  /// is latched, or when [currentSession] is no longer that same account and
  /// session; an invalidation that arrives while the pass is being written
  /// wins.
  Future<bool> confirmed(
    Session checked, {
    required Session? Function() currentSession,
    int? startedEpoch,
  }) async {
    if (startedEpoch != null && startedEpoch != _invalidations) return false;
    if (_isLatched(checked)) return false;
    final proof = AuthoritativeConfirmation.fromCheck(
      outcome: AppSessionCheckOutcome.confirmed,
      session: checked,
    );
    if (proof == null || !_same(checked, currentSession())) return false;
    final before = _invalidations;
    final issued = await lease.issue(proof);
    if (_invalidations != before || !_same(checked, currentSession())) {
      await lease.invalidate();
      return false;
    }
    return issued;
  }

  /// Ends offline access. At once: this process refuses offline use and
  /// every running confirmation becomes stale; [uid] (with [sid], or every
  /// session of [uid] without it) is latched for sign-out, displacement,
  /// recovery and Delete Account. Then the revocation is made durable; only
  /// if that succeeded is the secure-storage delete waited for with a bound.
  /// Never throws; callers read [OfflinePassRevocation.safe].
  Future<OfflinePassRevocation> invalidate(
    OfflinePassInvalidation reason, {
    String? uid,
    String? sid,
  }) async {
    _invalidations++;
    lastInvalidation = reason;
    if (uid != null && _latching.contains(reason)) {
      _latched.add(sid == null ? uid : '$uid|$sid');
    }
    final durableRevocation = lease.revokeNow();
    final deleting = lease.invalidate(); // queued now, in order
    final durable = await _within(durableRevocation, markerBound) ?? false;
    final bool? deleted =
        durable ? await _within(deleting, deleteBound) : await deleting;
    return lastRevocation =
        OfflinePassRevocation(durable: durable, deleted: deleted);
  }

  bool _isLatched(Session s) {
    final uid = s.user.id;
    return _latched.contains(uid) ||
        _latched.contains('$uid|${AppSessionCoordinator.sessionId(s)}');
  }

  /// [work]'s value, or null when [bound] ends first. The work itself is not
  /// cancelled (a platform call cannot be); its late result is ignored here.
  static Future<T?> _within<T>(Future<T> work, Duration bound) {
    final result = Completer<T?>();
    final timer = Timer(bound, () {
      if (!result.isCompleted) result.complete(null);
    });
    work.then((value) {
      timer.cancel();
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object _) {
      timer.cancel();
      if (!result.isCompleted) result.complete(null);
    });
    return result.future;
  }

  static bool _same(Session a, Session? b) {
    if (b == null || a.user.id != b.user.id) return false;
    final sid = AppSessionCoordinator.sessionId(a);
    return sid != null && sid == AppSessionCoordinator.sessionId(b);
  }
}
