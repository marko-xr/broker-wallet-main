import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session_check_outcome.dart';
import 'app_session_coordinator.dart';

// OFF-2b-1 (tracker §7BD-16/17): a bounded, read-only offline pass for an
// account and SAD session that the server confirmed on this device. This file
// only stores and evaluates the pass. It is DORMANT: nothing creates a pass
// in production yet (OFF-2b-3), nothing opens Home with it (OFF-2b-4), and
// the central read-only guards (OFF-2b-2) must exist before either.
//
// Limits, whichever ends first:
// - 24 h of wall-clock time from the server-issued `iat` of the access token
//   that was confirmed (never moved by a token refresh);
// - 8 h of offline in-app use, measured on a monotonic clock; the store is
//   asked to hold the use 60 s ahead of the measured use;
// - 20 offline cold starts; the store is asked to hold each start before it
//   is granted, and the value is read back.
// The phone clock is untrusted: going back past the highest time the app has
// seen, past `iat`, or behind the monotonic clock during a session ends the
// pass. A clock kept just above the highest time seen cannot be detected
// without a trusted clock (R-OFF2-CLOCK, accepted); use and starts still
// bound it. Any unreadable, malformed or unwritable state denies.
//
// THE PASS RECORD ALONE IS NOT CRASH-DURABLE ON ANDROID (R-OFF2-APPLY):
// flutter_secure_storage writes with SharedPreferences `apply()`, which
// updates memory at once and writes the file about 100 ms later (QueuedWork,
// then fsync); pending writes are forced only when the activity stops. The
// read-back is served from memory, so it proves nothing about the disk. A
// process killed while in the foreground (crash, `am force-stop`) or a power
// loss inside that window loses the last write.
//
// OFF-2b-1b closes that gap on Android with [OfflineChargeJournal]: every
// start charge and use reservation is appended and fsynced BEFORE the record
// is written and before the grant is returned; the larger of the journal's
// and the record's values counts; a missing, revoked, malformed or foreign
// journal denies; a torn last line (an append whose fsync never returned) is
// cut and counted as the most it could have charged. This holds within the
// platform's fsync contract (storage that honours it, no root); it is not an
// absolute physical guarantee. The lease must be given the journal on Android
// (OFF-2b-4 wiring) or the gap is open again. iOS Keychain writes are
// synchronous; their durability under power loss is not verified here.
// A same-device restore can bring back older accounting state on iOS
// (backup); on Android the pass files and the journal are excluded from
// backup and device transfer.

/// The approved limits (D-OFF-2, D-OFF-2E, D-OFF-2F).
abstract final class OfflinePassLimits {
  static const window = Duration(hours: 24);
  static const usage = Duration(hours: 8);
  static const coldStarts = 20;
  static const clockTolerance = Duration(minutes: 2);

  /// Use is stored this far ahead of the measured use.
  static const usageReservation = Duration(seconds: 60);
}

/// A clock that only moves forward while this process runs. It is not
/// meaningful across processes or reboots and is never stored.
abstract interface class OfflineMonotonicClock {
  Duration get elapsed;
}

class _StopwatchClock implements OfflineMonotonicClock {
  _StopwatchClock() : _watch = Stopwatch()..start();
  final Stopwatch _watch;
  @override
  Duration get elapsed => _watch.elapsed;
}

/// Where the one pass record lives.
abstract interface class OfflinePassStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// The pass in protected device storage, isolated from the Supabase session.
///
/// Android: its own `storageNamespace`, so its own preference files
/// (`bw_offline_pass`, `FlutterSecureKeyStorage:bw_offline_pass`,
/// `FlutterSecureStorageConfiguration:bw_offline_pass`) and its own Keystore
/// key; a decryption failure resets only this namespace, never the auth
/// session. The Keystore key does not leave the device, so a file copied to
/// another device or restored after a reinstall cannot be read and is reset
/// (no pass). A restore onto the same installed app could still read an older
/// file, so all three files are excluded from backup and device transfer
/// (`backup_rules.xml`, `data_extraction_rules.xml`). Writes are not
/// crash-durable (see the file header).
/// iOS: its own service name with `first_unlock_this_device`, so the item is
/// not synchronised and does not move to another device in a backup; a
/// restore of this same device's backup can bring an older item back.
class SecureOfflinePassStore implements OfflinePassStore {
  SecureOfflinePassStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: androidOptions,
              iOptions: iosOptions,
            );

  static const storageKey = 'bw_offline_pass_v1';
  static const androidOptions =
      AndroidOptions(storageNamespace: 'bw_offline_pass');
  static const iosOptions = IOSOptions(
    accountName: 'bw_offline_pass',
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: storageKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: storageKey, value: value);

  @override
  Future<void> delete() => _storage.delete(key: storageKey);
}

/// Why offline access was refused, or why a running offline session ended.
enum OfflinePassDenial {
  /// The check outcome does not allow offline access (D-OFF2-B): confirmed
  /// (online), inconclusive or stale. The pass is kept, unused and
  /// unextended.
  outcomeNotEligible,

  /// The server refused the session, or the SDK removed it. Pass deleted.
  knownInvalidation,

  /// The server refused the access token (401/403, PGRST301-303). Pass
  /// deleted: only a new confirmation can issue one (owner, 2026-11-13).
  credentialsRejected,

  /// No saved session. Pass deleted.
  noSession,

  /// The pass belongs to another account or session. Pass deleted.
  sessionMismatch,

  /// Password recovery or account deletion is in progress. Pass deleted.
  recoveryOrDeletion,

  /// There is no pass.
  noPass,

  /// The stored pass is not a valid record. Pass deleted.
  corrupt,

  /// The pass could not be read, written or deleted reliably.
  storageFailure,

  /// The phone clock went back. Pass deleted.
  clockRollback,

  /// 24 h since the confirmed token was issued. Pass deleted.
  windowExpired,

  /// 8 h of offline use. Pass deleted.
  usageExhausted,

  /// 20 offline cold starts. Pass deleted.
  startsExhausted,

  /// [OfflineSessionLease.invalidate] ended it. Pass deleted.
  invalidated,

  /// A new authoritative confirmation replaced the pass.
  replaced,

  /// The Android charge journal is missing, revoked, malformed, or does not
  /// match the pass (OFF-2b-1b). Pass and journal deleted.
  accountingInvalid,
}

/// The Android charge journal (OFF-2b-1b): an append-only record of every
/// start charge and use reservation, made durable with fsync BEFORE the grant
/// it covers. Every method that writes completes only after the data is
/// fsynced, and throws on any failure (including a failed fsync).
abstract interface class OfflineChargeJournal {
  /// The whole journal, or null when there is none.
  Future<String?> read();

  /// Replaces any journal with one holding exactly [content].
  Future<void> create(String content);

  /// Appends [record] to the existing journal. Never creates one.
  Future<void> append(String record);

  /// Cuts the journal to its first [length] bytes.
  Future<void> truncate(int length);

  /// Removes the journal; a missing one is fine.
  Future<void> delete();
}

/// The journal to use on this platform: a file on Android, none on iOS (the
/// Keychain write is synchronous; its behaviour is unchanged).
OfflineChargeJournal? platformChargeJournal({required bool isAndroid}) =>
    isAndroid ? FileOfflineChargeJournal() : null;

/// `getApplicationSupportDirectory()/offline_pass/charge_journal_v1.log`: on
/// Android the app's private `files/` folder (path_provider_android:
/// `Context.getFilesDir()`), excluded from backup and device transfer
/// (`<exclude domain="file" path="offline_pass" />`).
///
/// Durability: dart:io `RandomAccessFile.flush()` is `fsync(fd)` on Android
/// (Dart SDK 3.13.2 `runtime/bin/file_linux.cc` `File::Flush`), and its failure
/// is thrown. fsync makes the file's data and size durable; it relies on the
/// storage honouring it. dart:io cannot fsync a directory, so a power loss
/// right after [create] or [delete] may undo the creation or the unlink; both
/// outcomes fail closed (a missing journal, or a revocation line).
class FileOfflineChargeJournal implements OfflineChargeJournal {
  FileOfflineChargeJournal({
    Future<Directory> Function()? directory,
    Future<RandomAccessFile> Function(File file, FileMode mode)? open,
  })  : _directory = directory ?? getApplicationSupportDirectory,
        _open = open ?? _openFile;

  static const directoryName = 'offline_pass';
  static const fileName = 'charge_journal_v1.log';

  final Future<Directory> Function() _directory;
  final Future<RandomAccessFile> Function(File file, FileMode mode) _open;

  static Future<RandomAccessFile> _openFile(File file, FileMode mode) =>
      file.open(mode: mode);

  Future<File> _file() async {
    final root = await _directory();
    final sep = Platform.pathSeparator;
    return File('${root.path}$sep$directoryName$sep$fileName');
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return latin1.decode(await file.readAsBytes());
  }

  @override
  Future<void> create(String content) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await _write(file, FileMode.writeOnly, content); // truncates
  }

  @override
  Future<void> append(String record) async {
    final file = await _file();
    if (!await file.exists()) {
      throw FileSystemException('no offline charge journal', file.path);
    }
    await _write(file, FileMode.writeOnlyAppend, record);
  }

  @override
  Future<void> truncate(int length) async {
    final file = await _file();
    if (!await file.exists()) {
      throw FileSystemException('no offline charge journal', file.path);
    }
    final raf = await _open(file, FileMode.append);
    try {
      await raf.truncate(length);
      await raf.flush();
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<void> _write(File file, FileMode mode, String text) async {
    final raf = await _open(file, mode);
    try {
      await raf.writeFrom(latin1.encode(text));
      await raf.flush();
    } finally {
      await raf.close();
    }
  }
}

/// The line that revokes a journal: once present, the journal never opens.
const _journalTombstone = '{"v":1,"revoked":true}';

/// Identifies the pass without naming the account or session.
String _journalBind(_PassRecord r) => sha256
    .convert(utf8
        .encode('bw_offline_pass_journal_v1|${r.uid}|${r.sid}|${r.anchorMs}'))
    .toString();

/// One journal line: `{v, b, s, n, u, h, c}` and a newline. `s` counts lines
/// from 0; `c` is the first 16 hex digits of SHA-256 over the line without it.
String _journalLine(String bind, int seq, int starts, int usedMs, int highMs) {
  final body = <String, Object>{
    'v': 1,
    'b': bind,
    's': seq,
    'n': starts,
    'u': usedMs,
    'h': highMs,
  };
  return '${jsonEncode({...body, 'c': _journalCheck(body)})}\n';
}

String _journalCheck(Map<String, Object?> body) =>
    sha256.convert(utf8.encode(jsonEncode(body))).toString().substring(0, 16);

/// A verified journal: its last line's values, and whether a torn (incomplete)
/// last line follows the complete ones.
class _JournalState {
  const _JournalState(this.seq, this.starts, this.usedMs, this.highestMs,
      this.completeLength, this.torn, this.lastLine);

  final int seq;
  final int starts;
  final int usedMs;
  final int highestMs;

  /// Bytes up to and including the last newline.
  final int completeLength;
  final bool torn;
  final String lastLine;

  static const _keys = ['v', 'b', 's', 'n', 'u', 'h', 'c'];

  /// Null unless every complete line is a valid, checksummed entry of [bind],
  /// numbered 0, 1, 2…, starting at zero use and never going back, and no
  /// revocation line is present. Only bytes after the last newline may be
  /// incomplete.
  static _JournalState? parse(String text, String bind) {
    for (final unit in text.codeUnits) {
      if (unit > 0x7f) return null;
    }
    final end = text.lastIndexOf('\n');
    if (end < 0) return null;
    final lines = text.substring(0, end).split('\n');
    var starts = 0, used = 0, high = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line == _journalTombstone) return null;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } catch (_) {
        return null;
      }
      if (decoded is! Map<String, Object?>) return null;
      if (decoded.length != _keys.length ||
          !decoded.keys.toSet().containsAll(_keys)) {
        return null;
      }
      final s = decoded['s'], n = decoded['n'], u = decoded['u'];
      final h = decoded['h'], c = decoded['c'];
      if (decoded['v'] != 1 || decoded['b'] != bind || s != i) return null;
      if (n is! int || u is! int || h is! int || c is! String) return null;
      if (n < 0 || n > OfflinePassLimits.coldStarts) return null;
      if (u < 0 || u > OfflinePassLimits.usage.inMilliseconds) return null;
      if (h <= 0) return null;
      final body = Map<String, Object?>.of(decoded)..remove('c');
      final ordered = {for (final k in _keys.take(6)) k: body[k]};
      if (_journalCheck(ordered) != c) return null;
      if (i == 0) {
        if (n != 0 || u != 0) return null;
      } else if (n < starts || u < used || h < high) {
        return null;
      }
      starts = n;
      used = u;
      high = h;
    }
    return _JournalState(lines.length - 1, starts, used, high, end + 1,
        end + 1 < text.length, lines.last);
  }
}

/// Proof that the server answered a current `true` for this exact session.
/// The only way to issue or renew a pass; a refreshed token, a stored SDK
/// session or any failure cannot produce one.
class AuthoritativeConfirmation {
  const AuthoritativeConfirmation._(this.userId, this.sessionId, this.issuedAt);

  final String userId;
  final String sessionId;

  /// The server-issued `iat` of the confirmed access token.
  final DateTime issuedAt;

  static AuthoritativeConfirmation? fromCheck({
    required AppSessionCheckOutcome outcome,
    required Session? session,
  }) {
    if (outcome != AppSessionCheckOutcome.confirmed || session == null) {
      return null;
    }
    final binding = _binding(session);
    if (binding == null) return null;
    final iat = _issuedAt(session.accessToken);
    if (iat == null) return null;
    return AuthoritativeConfirmation._(binding.$1, binding.$2, iat);
  }
}

/// (user id, session id) when the token's subject is the session's user and
/// its `session_id` is valid; otherwise null.
(String, String)? _binding(Session session) {
  final claims = _claims(session.accessToken);
  if (claims == null) return null;
  final uid = session.user.id;
  if (!_uuid.hasMatch(uid) || claims['sub'] != uid) return null;
  final sid =
      AppSessionCoordinator.sessionIdFromAccessToken(session.accessToken);
  if (sid == null) return null;
  return (uid, sid);
}

DateTime? _issuedAt(String accessToken) {
  final iat = _claims(accessToken)?['iat'];
  if (iat is! int || iat <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(iat * 1000, isUtc: true);
}

Map<String, Object?>? _claims(String accessToken) {
  try {
    final parts = accessToken.split('.');
    if (parts.length != 3) return null;
    final body = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return body is Map<String, Object?> ? body : null;
  } catch (_) {
    return null;
  }
}

final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// The stored record: `{v, uid, sid, a, h, u, n}`. Times are UTC epoch ms.
class _PassRecord {
  const _PassRecord({
    required this.uid,
    required this.sid,
    required this.anchorMs,
    required this.highestMs,
    required this.usedMs,
    required this.starts,
  });

  final String uid;
  final String sid;

  /// Server `iat` of the confirmed token.
  final int anchorMs;

  /// Highest wall-clock time the app has seen for this pass (forward only).
  final int highestMs;

  /// Offline use stored so far, including reservations (never refunded).
  final int usedMs;

  /// Offline cold starts granted so far.
  final int starts;

  static const _keys = {'v', 'uid', 'sid', 'a', 'h', 'u', 'n'};

  _PassRecord copyWith({int? highestMs, int? usedMs, int? starts}) =>
      _PassRecord(
        uid: uid,
        sid: sid,
        anchorMs: anchorMs,
        highestMs: highestMs ?? this.highestMs,
        usedMs: usedMs ?? this.usedMs,
        starts: starts ?? this.starts,
      );

  String encode() => jsonEncode({
        'v': 1,
        'uid': uid,
        'sid': sid,
        'a': anchorMs,
        'h': highestMs,
        'u': usedMs,
        'n': starts,
      });

  /// Strict: exactly the known keys, the right types and ranges.
  static _PassRecord? decode(String raw) {
    final Object? body;
    try {
      body = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (body is! Map<String, Object?>) return null;
    if (body.length != _keys.length || !body.keys.toSet().containsAll(_keys)) {
      return null;
    }
    final v = body['v'], uid = body['uid'], sid = body['sid'];
    final a = body['a'], h = body['h'], u = body['u'], n = body['n'];
    if (v != 1) return null;
    if (uid is! String || !_uuid.hasMatch(uid)) return null;
    if (sid is! String || !_uuid.hasMatch(sid)) return null;
    if (a is! int || h is! int || u is! int || n is! int) return null;
    if (a <= 0 || h < a) return null;
    if (u < 0 || u > OfflinePassLimits.usage.inMilliseconds) return null;
    if (n < 0 || n > OfflinePassLimits.coldStarts) return null;
    return _PassRecord(
        uid: uid, sid: sid, anchorMs: a, highestMs: h, usedMs: u, starts: n);
  }
}

/// What a cold-start evaluation decided.
sealed class OfflineAdmission {
  const OfflineAdmission();
}

final class OfflineAdmissionGranted extends OfflineAdmission {
  const OfflineAdmissionGranted(this.session);
  final OfflinePassSession session;

  @override
  String toString() => 'OfflineAdmissionGranted';
}

final class OfflineAdmissionDenied extends OfflineAdmission {
  const OfflineAdmissionDenied(this.reason);
  final OfflinePassDenial reason;

  @override
  String toString() => 'OfflineAdmissionDenied(${reason.name})';
}

/// One process's offline use of the pass. The caller checkpoints at least
/// every [OfflinePassLimits.usageReservation] while in the foreground and
/// pauses in the background (wired in OFF-2b-4). Every method answers null
/// while the session is active and the reason once it has ended.
class OfflinePassSession {
  OfflinePassSession._(this._lease, this._record, this._launchWallMs,
      this._baseUsedMs, this._reservedMs, this._monotonic,
      [this._bind = '', this._seq = -1, this._lastLine = '']);

  final OfflineSessionLease _lease;

  /// Android journal: the pass binding, and the last line this session wrote
  /// (its sequence number and text). Unused without a journal.
  final String _bind;
  int _seq;
  String _lastLine;
  _PassRecord _record;
  final int _launchWallMs;

  /// Stored use before this session's first reservation.
  final int _baseUsedMs;

  /// Stored use including this session's reservation.
  int _reservedMs;

  final OfflineMonotonicClock _monotonic;
  Duration _activeBefore = Duration.zero;
  Duration? _segmentStart = Duration.zero;
  OfflinePassDenial? _end;

  String get userId => _record.uid;
  String get sessionId => _record.sid;
  bool get isActive => _end == null;
  OfflinePassDenial? get endedBecause => _end;

  Duration get _active {
    final start = _segmentStart;
    return start == null
        ? _activeBefore
        : _activeBefore + (_monotonic.elapsed - start);
  }

  Future<OfflinePassDenial?> checkpoint() =>
      _lease._serial(() => _lease._checkpoint(this));

  /// Stops counting use (the app went to the background).
  Future<OfflinePassDenial?> pause() => _lease._serial(() async {
        final end = await _lease._checkpoint(this);
        if (end != null) return end;
        final start = _segmentStart;
        if (start != null) {
          _activeBefore += _monotonic.elapsed - start;
          _segmentStart = null;
        }
        return null;
      });

  /// Counts use again (the app came back to the foreground).
  Future<OfflinePassDenial?> resume() => _lease._serial(() async {
        if (_end != null) return _end;
        _segmentStart ??= _monotonic.elapsed;
        return _lease._checkpoint(this);
      });
}

/// Stores and evaluates the offline pass. Operations of ONE instance run one
/// at a time, which is what makes a Retry or two concurrent starts charge
/// once. That guarantee holds only if the app creates exactly one instance
/// per process and never uses the pass store from another isolate or engine
/// (for example a background message handler): two instances, or two
/// processes, are not serialized and could each charge from the same record.
/// Wiring the single instance is OFF-2b-4.
class OfflineSessionLease {
  OfflineSessionLease({
    required OfflinePassStore store,
    DateTime Function()? wallClock,
    OfflineMonotonicClock Function()? startMonotonic,
    OfflineChargeJournal? chargeJournal,
  })  : _store = store,
        _wallClock = wallClock ?? DateTime.now,
        _startMonotonic = startMonotonic ?? _StopwatchClock.new,
        _journal = chargeJournal;

  final OfflinePassStore _store;

  /// Android (OFF-2b-1b): the durable record of every charge. When present it
  /// is written (and fsynced) BEFORE the pass record and before any grant, and
  /// the larger of its values and the record's is what counts. Null on iOS,
  /// whose Keychain writes are synchronous.
  final OfflineChargeJournal? _journal;
  final DateTime Function() _wallClock;
  final OfflineMonotonicClock Function() _startMonotonic;

  Future<void> _tail = Future.value();
  OfflinePassSession? _active;

  /// Set when a required delete failed: no offline use in this process.
  bool _blocked = false;

  int get _nowMs => _wallClock().toUtc().millisecondsSinceEpoch;
  static final _tolMs = OfflinePassLimits.clockTolerance.inMilliseconds;
  static final _windowMs = OfflinePassLimits.window.inMilliseconds;
  static final _usageMs = OfflinePassLimits.usage.inMilliseconds;
  static final _sliceMs = OfflinePassLimits.usageReservation.inMilliseconds;

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Issues or renews the pass after an authoritative confirmation (OFF-2b-3
  /// calls this). A fresh record: new anchor, no use, no starts. False, with
  /// no pass left, when it cannot be stored reliably or the phone clock does
  /// not agree with the server time.
  Future<bool> issue(AuthoritativeConfirmation confirmation) =>
      _serial(() async {
        _endActive(OfflinePassDenial.replaced);
        final now = _nowMs;
        final anchor = confirmation.issuedAt.millisecondsSinceEpoch;
        if (anchor > now + _tolMs || now >= anchor + _windowMs) {
          await _delete();
          return false;
        }
        final record = _PassRecord(
          uid: confirmation.userId,
          sid: confirmation.sessionId,
          anchorMs: anchor,
          highestMs: now > anchor ? now : anchor,
          usedMs: 0,
          starts: 0,
        );
        // The only place a journal is ever started: an authoritative
        // confirmation. Journal first, so a record never exists without it.
        final journal = _journal;
        if (journal != null) {
          try {
            await journal.create(
                _journalLine(_journalBind(record), 0, 0, 0, record.highestMs));
          } catch (_) {
            await _delete();
            return false;
          }
        }
        if (await _persist(record)) {
          _blocked = false;
          return true;
        }
        await _delete();
        return false;
      });

  /// Decides whether this cold start may open offline. A grant has already
  /// stored one more start and a use reservation.
  Future<OfflineAdmission> admitColdStart({
    required AppSessionCheckOutcome outcome,
    required Session? session,
    required bool passwordRecoveryActive,
    required bool accountDeletionPending,
  }) =>
      _serial(() async {
        if (passwordRecoveryActive || accountDeletionPending) {
          return _deny(OfflinePassDenial.recoveryOrDeletion, delete: true);
        }
        switch (outcome) {
          case AppSessionCheckOutcome.offline:
          case AppSessionCheckOutcome.serverUnavailable:
          case AppSessionCheckOutcome.timedOut:
            break;
          case AppSessionCheckOutcome.refused:
          case AppSessionCheckOutcome.absent:
            return _deny(OfflinePassDenial.knownInvalidation, delete: true);
          case AppSessionCheckOutcome.credentialsRejected:
            // An authoritative token rejection: a later network failure must
            // never turn it back into offline access (owner, 2026-11-13).
            return _deny(OfflinePassDenial.credentialsRejected, delete: true);
          case AppSessionCheckOutcome.confirmed:
          // inconclusive proves nothing (a captive portal's page, a malformed
          // answer): never treated as a rejection, never as eligible.
          case AppSessionCheckOutcome.inconclusive:
          case AppSessionCheckOutcome.stale:
            return _deny(OfflinePassDenial.outcomeNotEligible);
        }
        if (session == null) {
          return _deny(OfflinePassDenial.noSession, delete: true);
        }
        final binding = _binding(session);
        if (binding == null) {
          return _deny(OfflinePassDenial.sessionMismatch, delete: true);
        }
        if (_blocked) return _deny(OfflinePassDenial.storageFailure);

        final running = _active;
        if (running != null && running.isActive) {
          if (running.userId == binding.$1 && running.sessionId == binding.$2) {
            return OfflineAdmissionGranted(running);
          }
          return _deny(OfflinePassDenial.sessionMismatch, delete: true);
        }

        final String? raw;
        try {
          raw = await _store.read();
        } catch (_) {
          return _deny(OfflinePassDenial.storageFailure, delete: true);
        }
        if (raw == null) return _deny(OfflinePassDenial.noPass);
        final stored = _PassRecord.decode(raw);
        if (stored == null) {
          return _deny(OfflinePassDenial.corrupt, delete: true);
        }
        if (stored.uid != binding.$1 || stored.sid != binding.$2) {
          return _deny(OfflinePassDenial.sessionMismatch, delete: true);
        }

        // Android: the journal is the durable truth; the record may have lost
        // its last writes (apply()). A journal is never created here.
        var record = stored;
        final bind = _journalBind(stored);
        final journal = _journal;
        _JournalState? state;
        if (journal != null) {
          final String? text;
          try {
            text = await journal.read();
          } catch (_) {
            return _deny(OfflinePassDenial.storageFailure, delete: true);
          }
          state = text == null ? null : _JournalState.parse(text, bind);
          if (state == null) {
            return _deny(OfflinePassDenial.accountingInvalid, delete: true);
          }
          // A torn last line is an append whose fsync never returned, so no
          // grant was made on it; it is still counted as the most it could
          // have charged (one start and one reservation).
          final tornStarts = state.torn ? 1 : 0;
          final tornUse = state.torn ? _sliceMs : 0;
          record = stored.copyWith(
            highestMs: _max(stored.highestMs, state.highestMs),
            usedMs: _cap(_max(stored.usedMs, state.usedMs + tornUse)),
            starts: _max(stored.starts, state.starts + tornStarts),
          );
        }

        final now = _nowMs;
        if (now < record.highestMs - _tolMs || now < record.anchorMs - _tolMs) {
          return _deny(OfflinePassDenial.clockRollback, delete: true);
        }
        if (now >= record.anchorMs + _windowMs) {
          return _deny(OfflinePassDenial.windowExpired, delete: true);
        }
        if (record.usedMs >= _usageMs) {
          return _deny(OfflinePassDenial.usageExhausted, delete: true);
        }
        if (record.starts >= OfflinePassLimits.coldStarts) {
          return _deny(OfflinePassDenial.startsExhausted, delete: true);
        }

        final reserved = _cap(record.usedMs + _sliceMs);
        final charged = record.copyWith(
          highestMs: now > record.highestMs ? now : record.highestMs,
          usedMs: reserved,
          starts: record.starts + 1,
        );
        var seq = -1;
        var line = '';
        if (journal != null) {
          seq = state!.seq + 1;
          line = _journalLine(
              bind, seq, charged.starts, charged.usedMs, charged.highestMs);
          try {
            if (state.torn) await journal.truncate(state.completeLength);
            await journal.append(line);
          } catch (_) {
            return _deny(OfflinePassDenial.storageFailure, delete: true);
          }
        }
        if (!await _persist(charged)) {
          return _deny(OfflinePassDenial.storageFailure, delete: true);
        }
        final granted = OfflinePassSession._(this, charged, now, record.usedMs,
            reserved, _startMonotonic(), bind, seq, _withoutNewline(line));
        _active = granted;
        return OfflineAdmissionGranted(granted);
      });

  /// Deletes the pass after a known invalidation (sign-out, supersession,
  /// account switch, recovery, deletion — wired in OFF-2b-3) and ends any
  /// running session. False when the delete failed; offline use then stays
  /// refused for the rest of this process.
  Future<bool> invalidate() => _serial(() async {
        _endActive(OfflinePassDenial.invalidated);
        return _delete();
      });

  Future<OfflinePassDenial?> _checkpoint(OfflinePassSession s) async {
    if (s._end != null) return s._end;
    final now = _nowMs;
    final activeMs = s._active.inMilliseconds;
    final lowerBound = s._launchWallMs + activeMs;
    if (now < lowerBound - _tolMs || now < s._record.highestMs - _tolMs) {
      return _endSession(s, OfflinePassDenial.clockRollback);
    }
    final effective = now > lowerBound ? now : lowerBound;
    final used = s._baseUsedMs + activeMs;
    if (used >= _usageMs) {
      return _endSession(s, OfflinePassDenial.usageExhausted);
    }
    if (effective >= s._record.anchorMs + _windowMs) {
      return _endSession(s, OfflinePassDenial.windowExpired);
    }
    final reserve = used >= s._reservedMs;
    final highest =
        effective > s._record.highestMs ? effective : s._record.highestMs;
    if (reserve || highest - s._record.highestMs >= _sliceMs) {
      final reserved = reserve ? _cap(used + _sliceMs) : s._reservedMs;
      final next = s._record.copyWith(highestMs: highest, usedMs: reserved);
      final journal = _journal;
      if (journal != null) {
        // The journal must still end with this session's own last line;
        // anything else (another instance, a foreign write) fails closed.
        final String? text;
        try {
          text = await journal.read();
        } catch (_) {
          return _endSession(s, OfflinePassDenial.storageFailure);
        }
        final state = text == null ? null : _JournalState.parse(text, s._bind);
        if (state == null ||
            state.torn ||
            state.seq != s._seq ||
            state.lastLine != s._lastLine) {
          return _endSession(s, OfflinePassDenial.accountingInvalid);
        }
        final seq = s._seq + 1;
        final line = _journalLine(
            s._bind, seq, next.starts, next.usedMs, next.highestMs);
        try {
          await journal.append(line);
        } catch (_) {
          return _endSession(s, OfflinePassDenial.storageFailure);
        }
        s._seq = seq;
        s._lastLine = _withoutNewline(line);
      }
      if (!await _persist(next)) {
        return _endSession(s, OfflinePassDenial.storageFailure);
      }
      s._record = next;
      s._reservedMs = reserved;
    }
    return null;
  }

  Future<OfflinePassDenial> _endSession(
      OfflinePassSession s, OfflinePassDenial reason) async {
    s._end = reason;
    if (identical(_active, s)) _active = null;
    await _delete();
    return reason;
  }

  void _endActive(OfflinePassDenial reason) {
    final running = _active;
    if (running != null && running.isActive) running._end = reason;
    _active = null;
  }

  Future<OfflineAdmission> _deny(OfflinePassDenial reason,
      {bool delete = false}) async {
    _endActive(reason);
    if (delete) await _delete();
    return OfflineAdmissionDenied(reason);
  }

  /// Writes and reads back; anything else counts as not stored. On Android the
  /// read-back is served from memory: it proves the store accepted the value,
  /// not that it reached the disk (R-OFF2-APPLY).
  Future<bool> _persist(_PassRecord record) async {
    final encoded = record.encode();
    try {
      await _store.write(encoded);
      return await _store.read() == encoded;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the pass. On Android a durable revocation line is appended to
  /// the journal first, so a delete undone by a power loss (the unlink, or the
  /// preference delete under `apply()`) still never reopens the pass.
  Future<bool> _delete() async {
    var ok = true;
    final journal = _journal;
    if (journal != null) {
      try {
        await journal.append('$_journalTombstone\n');
      } catch (_) {
        // No journal, or none writable: the deletes below still apply.
      }
      try {
        await journal.delete();
      } catch (_) {
        ok = false;
      }
    }
    try {
      await _store.delete();
    } catch (_) {
      ok = false;
    }
    if (!ok) _blocked = true;
    return ok;
  }

  static int _cap(int ms) => ms > _usageMs ? _usageMs : ms;
  static int _max(int a, int b) => a > b ? a : b;
  static String _withoutNewline(String line) =>
      line.endsWith('\n') ? line.substring(0, line.length - 1) : line;
}
