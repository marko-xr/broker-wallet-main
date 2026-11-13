// OFF-2b-3 corrections A–C (tracker §7BD-20): durable revocation of the
// offline pass that does not depend on the secure-storage queue, bounded
// waiting only after it, and generation protection against stale issues.
//
// Deterministic: injected stores, markers and journals; a "restart" or a
// "process kill" is a fresh lease over the same persisted objects. No network.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/app_session_check_outcome.dart';
import 'package:broker_wallet/src/services/offline_pass_lifecycle.dart';
import 'package:broker_wallet/src/services/offline_session_lease.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uidA = '550e8400-e29b-41d4-a716-446655440000';
const _uidB = '660e8400-e29b-41d4-a716-446655440000';
const _s1 = '11111111-1111-4111-8111-111111111111';
const _s2 = '22222222-2222-4222-8222-222222222222';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

sb.Session _session({String uid = _uidA, String sid = _s1}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return sb.Session.fromJson({
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({
          'sub': uid,
          'session_id': sid,
          'exp': now + 3600,
          'iat': now,
          'role': 'authenticated',
          'aud': 'authenticated',
        })}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': now + 3600,
    'refresh_token': 'refresh-secret',
    'user': {
      'id': uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  })!;
}

/// The protected store (Keystore/Keychain stand-in). Survives a "restart".
class _Store implements OfflinePassStore {
  String? value;
  Completer<void>? holdWrite;
  Completer<void>? holdDelete;
  bool failDelete = false;
  int deletes = 0;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async {
    writes++;
    final hold = holdWrite;
    if (hold != null) await hold.future;
    value = v;
  }

  @override
  Future<void> delete() async {
    final hold = holdDelete;
    if (hold != null) await hold.future;
    deletes++;
    if (failDelete) throw const FileSystemException('keystore failure');
    value = null;
  }

  Map<String, Object?> get json => jsonDecode(value!) as Map<String, Object?>;
}

/// The revocation marker (a plain file). Survives a "restart".
class _Marker implements OfflinePassRevocationMarker {
  int? value;
  bool failWrite = false;
  bool failRead = false;

  /// The write "succeeds" but nothing is stored (a lying file system).
  bool loseWrites = false;
  Completer<void>? holdWrite;
  final List<int> writes = [];

  @override
  Future<int?> read() async {
    if (failRead) throw const FormatException('malformed marker');
    return value;
  }

  @override
  Future<void> write(int revocation) async {
    final hold = holdWrite;
    if (hold != null) await hold.future;
    if (failWrite) throw const FileSystemException('fsync failed');
    writes.add(revocation);
    if (!loseWrites) value = revocation;
  }
}

/// The Android charge journal (OFF-2b-1b), in memory. Survives a "restart".
class _Journal implements OfflineChargeJournal {
  String? text;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> create(String content) async => text = content;

  @override
  Future<void> append(String record) async {
    if (text == null) throw const FileSystemException('no journal');
    text = text! + record;
  }

  @override
  Future<void> truncate(int length) async => text = text!.substring(0, length);

  @override
  Future<void> delete() async => text = null;
}

OfflineSessionLease _lease(_Store store, _Marker? marker,
        {_Journal? journal}) =>
    OfflineSessionLease(
        store: store, revocationMarker: marker, chargeJournal: journal);

Future<bool> _issue(OfflineSessionLease lease, sb.Session s) =>
    lease.issue(AuthoritativeConfirmation.fromCheck(
        outcome: AppSessionCheckOutcome.confirmed, session: s)!);

Future<OfflineAdmission> _admit(OfflineSessionLease lease, sb.Session s) =>
    lease.admitColdStart(
      outcome: AppSessionCheckOutcome.offline,
      session: s,
      passwordRecoveryActive: false,
      accountDeletionPending: false,
    );

OfflinePassDenial? _denial(OfflineAdmission a) =>
    a is OfflineAdmissionDenied ? a.reason : null;

const _short = Duration(milliseconds: 20);

void main() {
  late _Store store;
  late _Marker marker;

  setUp(() {
    store = _Store();
    marker = _Marker();
  });

  group('A. durable revocation, independent of the secure-storage queue', () {
    test('1. a delete that completes: durable, deleted, nothing reusable',
        () async {
      final life = OfflinePassLifecycle(_lease(store, marker));
      final s = _session();
      expect(await life.confirmed(s, currentSession: () => s), isTrue);
      final r = await life.invalidate(OfflinePassInvalidation.signOut,
          uid: _uidA, sid: _s1);
      expect((r.durable, r.deleted, r.safe), (true, true, true));
      expect(store.value, isNull);
      expect(marker.value, 1);
    });

    test(
        '2. a delete that throws is reported, and after a restart the '
        'stale pass is refused and removed', () async {
      final life = OfflinePassLifecycle(_lease(store, marker));
      final s = _session();
      await life.confirmed(s, currentSession: () => s);
      store.failDelete = true;
      final r = await life.invalidate(OfflinePassInvalidation.signOut);
      expect(r.durable, isTrue);
      expect(r.deleted, isFalse, reason: 'a failed delete is never success');
      expect(store.value, isNotNull, reason: 'the record really survived');
      store.failDelete = false;
      final restarted = _lease(store, marker);
      expect(_denial(await _admit(restarted, s)), OfflinePassDenial.revoked);
      expect(store.value, isNull);
    });

    test(
        '3. a delete that never completes: the caller is released after the '
        'bound, the lease is blocked now, and a restart refuses the pass',
        () async {
      final lease = _lease(store, marker);
      final life = OfflinePassLifecycle(lease, deleteBound: _short);
      final s = _session();
      await life.confirmed(s, currentSession: () => s);
      store.holdDelete = Completer<void>();
      final r = await life.invalidate(OfflinePassInvalidation.superseded);
      expect(r.durable, isTrue);
      expect(r.deleted, isNull, reason: 'timed out: outcome unknown');
      expect(r.safe, isTrue, reason: 'safe because the revocation is durable');
      expect(lease.isBlocked, isTrue);
      expect(store.value, isNotNull, reason: 'still hanging');
      store.holdDelete = null; // killed: the hung call dies with the process
      final restarted = _lease(store, marker);
      expect(_denial(await _admit(restarted, s)), OfflinePassDenial.revoked);
    });

    test(
        '4. a late delete after the timeout never removes the pass of the '
        'account that signed in next', () async {
      final lease = _lease(store, marker);
      final life = OfflinePassLifecycle(lease, deleteBound: _short);
      final a = _session();
      await life.confirmed(a, currentSession: () => a);
      store.holdDelete = Completer<void>();
      await life.invalidate(OfflinePassInvalidation.signOut);
      final b = _session(uid: _uidB, sid: _s2);
      final issuingB = life.confirmed(b, currentSession: () => b);
      await pumpEventQueue();
      store.holdDelete!.complete(); // the old delete finally lands
      store.holdDelete = null;
      expect(await issuingB, isTrue);
      expect(store.json['uid'], _uidB);
      final restarted = _lease(store, marker);
      expect(await _admit(restarted, b), isA<OfflineAdmissionGranted>());
    });

    test('5. a process killed after the durable revocation keeps it', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      expect(await lease.revokeNow(), isTrue);
      // Killed here: the queued secure-storage delete never ran.
      expect(store.value, isNotNull);
      final restarted = _lease(store, marker);
      expect(_denial(await _admit(restarted, s)), OfflinePassDenial.revoked);
    });

    test(
        '6. before the marker is durable the revocation is not reported, '
        'so the caller has not gone on', () async {
      final life = OfflinePassLifecycle(_lease(store, marker));
      final s = _session();
      await life.confirmed(s, currentSession: () => s);
      marker.holdWrite = Completer<void>();
      var done = false;
      final revoking = life
          .invalidate(OfflinePassInvalidation.signOut)
          .whenComplete(() => done = true);
      await pumpEventQueue();
      expect(done, isFalse);
      expect(life.lease.isBlocked, isTrue, reason: 'blocked in memory at once');
      // A kill here leaves the pass and (in the repository) the session as
      // they were: the sign-out never proceeded (see the lifecycle test H6).
      marker.holdWrite!.complete();
      expect((await revoking).durable, isTrue);
    });

    test(
        '7. a marker write or flush failure is not durable: the caller waits '
        'for the real delete (no bound) and an unsafe result is reported',
        () async {
      final life = OfflinePassLifecycle(_lease(store, marker),
          deleteBound: _short, markerBound: _short);
      final s = _session();
      await life.confirmed(s, currentSession: () => s);
      marker.failWrite = true;
      store.holdDelete = Completer<void>();
      var done = false;
      final revoking = life
          .invalidate(OfflinePassInvalidation.signOut)
          .whenComplete(() => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(done, isFalse, reason: 'no bound without a durable revocation');
      store.failDelete = true;
      store.holdDelete!.complete();
      final r = await revoking;
      expect((r.durable, r.deleted, r.safe), (false, false, false));
      expect(life.lease.isBlocked, isTrue);
    });

    test('7b. a marker that cannot be read refuses the pass', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      marker.failRead = true;
      final restarted = _lease(store, marker);
      expect(_denial(await _admit(restarted, s)),
          OfflinePassDenial.storageFailure);
      expect(store.value, isNull);
    });

    test('8. a restart with a stale pass and a newer marker refuses it',
        () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      marker.value = 3; // revoked later, e.g. by an earlier process
      expect(_denial(await _admit(_lease(store, marker), s)),
          OfflinePassDenial.revoked);
      expect(store.value, isNull);
    });

    test('5b. a running offline pass ends at once, before any queue', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      final granted = await _admit(lease, s);
      expect(granted, isA<OfflineAdmissionGranted>());
      final running = (granted as OfflineAdmissionGranted).session;
      store.holdDelete = Completer<void>();
      unawaited(lease.invalidate()); // the queue is now stuck
      unawaited(lease.revokeNow());
      expect(running.isActive, isFalse);
      store.holdDelete!.complete();
    });

    test('7c. a marker write that was not really stored is not durable',
        () async {
      final lease = _lease(store, marker);
      marker.loseWrites = true;
      expect(await lease.revokeNow(), isFalse);
    });

    test('7d. no pass is issued over a marker that could not be created',
        () async {
      final lease = _lease(store, marker);
      marker.loseWrites = true;
      expect(await _issue(lease, _session()), isFalse);
      expect(store.value, isNull);
    });

    test(
        '8c. a marker lowered behind the process back cannot make a new '
        'revocation miss a pass this process issued', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await lease.revokeNow(); // 1
      await _issue(lease, s); // r = 1
      marker.value = 0; // lowered externally (restore, tampering)
      expect(await lease.revokeNow(), isTrue);
      expect(marker.value, greaterThan(1));
      expect(_denial(await _admit(_lease(store, marker), s)), isNot(isNull));
    });

    test('8b. two revocations at once never lower the marker', () async {
      final lease = _lease(store, marker);
      await Future.wait([lease.revokeNow(), lease.revokeNow()]);
      expect(marker.writes, [1, 2]);
      expect(marker.value, 2);
    });
  });

  group('B/C. generations: nothing older can defeat a revocation', () {
    test(
        '9. an issue that started before a revocation never leaves a usable '
        'pass, and never clears the marker', () async {
      final lease = _lease(store, marker);
      final s = _session();
      store.holdWrite = Completer<void>();
      final issuing = _issue(lease, s);
      await pumpEventQueue();
      expect(await lease.revokeNow(), isTrue);
      store.holdWrite!.complete();
      expect(await issuing, isFalse);
      expect(store.value, isNull);
      expect(marker.value, 1, reason: 'the issue never lowers or clears it');
    });

    test(
        '9c. a revocation before a queued issue runs: that issue writes '
        'nothing at all', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      store.holdDelete = Completer<void>();
      final stuck = lease.invalidate(); // blocks the queue
      final writesBefore = store.writes;
      final issuing = _issue(lease, s);
      await lease.revokeNow();
      store.holdDelete!.complete();
      await stuck;
      expect(await issuing, isFalse);
      expect(store.writes, writesBefore, reason: 'not even a transient record');
    });

    test(
        '9b. even if that stale record could not be deleted, its '
        'generation is older than the marker', () async {
      final lease = _lease(store, marker);
      final s = _session();
      store.holdWrite = Completer<void>();
      final issuing = _issue(lease, s);
      await pumpEventQueue();
      await lease.revokeNow();
      store.failDelete = true;
      store.holdWrite!.complete();
      await issuing;
      expect(store.value, isNotNull);
      store.failDelete = false;
      expect(_denial(await _admit(_lease(store, marker), s)),
          OfflinePassDenial.revoked);
    });

    test(
        '10. a later genuine confirmation for the current session issues a '
        'usable pass and ends the block', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      await lease.revokeNow();
      await lease.invalidate();
      expect(lease.isBlocked, isTrue);
      expect(await _issue(lease, s), isTrue);
      expect(lease.isBlocked, isFalse);
      expect(store.json['r'], marker.value);
      expect(await _admit(_lease(store, marker), s),
          isA<OfflineAdmissionGranted>());
    });

    test('10b. a pass is never written before the marker exists', () async {
      final lease = _lease(store, marker);
      final s = _session();
      expect(marker.value, isNull);
      expect(await _issue(lease, s), isTrue);
      expect(marker.value, 0, reason: 'created (durably) before the record');
      expect(store.json['r'], 0);
    });

    test('10c. no marker can be created: no pass is written', () async {
      final lease = _lease(store, marker);
      marker.failWrite = true;
      expect(await _issue(lease, _session()), isFalse);
      expect(store.value, isNull);
    });

    test(
        'C1. a confirmation whose check started before an invalidation is '
        'refused; one started after it is accepted', () async {
      final life = OfflinePassLifecycle(_lease(store, marker));
      final s = _session();
      final before = life.epoch;
      await life.invalidate(OfflinePassInvalidation.credentialsRejected);
      expect(
          await life.confirmed(s,
              currentSession: () => s, startedEpoch: before),
          isFalse);
      expect(store.value, isNull);
      expect(
          await life.confirmed(s,
              currentSession: () => s, startedEpoch: life.epoch),
          isTrue,
          reason: 'a 401 is not a latch: a new confirmation may issue');
    });

    test(
        'C2. sign-out, displacement, password recovery and Delete Account '
        'latch that account/session for the rest of the process', () async {
      for (final reason in [
        OfflinePassInvalidation.signOut,
        OfflinePassInvalidation.superseded,
        OfflinePassInvalidation.passwordRecovery,
      ]) {
        final life = OfflinePassLifecycle(_lease(_Store(), _Marker()));
        final s = _session();
        await life.invalidate(reason, uid: _uidA, sid: _s1);
        expect(
            await life.confirmed(s,
                currentSession: () => s, startedEpoch: life.epoch),
            isFalse,
            reason: reason.name);
        final other = _session(sid: _s2);
        expect(
            await life.confirmed(other,
                currentSession: () => other, startedEpoch: life.epoch),
            isTrue,
            reason: '${reason.name}: a new session is not latched');
      }
      final life = OfflinePassLifecycle(_lease(_Store(), _Marker()));
      await life.invalidate(OfflinePassInvalidation.accountDeletion,
          uid: _uidA);
      for (final sid in [_s1, _s2]) {
        final s = _session(sid: sid);
        expect(await life.confirmed(s, currentSession: () => s), isFalse,
            reason: 'every session of the account being deleted');
      }
      final b = _session(uid: _uidB, sid: _s2);
      expect(await life.confirmed(b, currentSession: () => b), isTrue);
    });
  });

  group('Android journal and iOS limits', () {
    test(
        '14. Android: the journal is revoked as before, the marker refuses a '
        'stale record, and a new confirmation starts a fresh journal',
        () async {
      final journal = _Journal();
      final lease = _lease(store, marker, journal: journal);
      final s = _session();
      await _issue(lease, s);
      expect(journal.text, isNotNull);
      store.failDelete = true;
      await lease.revokeNow();
      await lease.invalidate();
      expect(journal.text, isNull, reason: 'tombstone appended, then deleted');
      store.failDelete = false;
      final restarted = _lease(store, marker, journal: journal);
      expect(_denial(await _admit(restarted, s)), OfflinePassDenial.revoked);
      expect(await _issue(restarted, s), isTrue);
      expect(journal.text, isNotNull);
      expect(await _admit(_lease(store, marker, journal: journal), s),
          isA<OfflineAdmissionGranted>());
    });

    test(
        '15. iOS reinstall: the Keychain record survives but the app files '
        '(the marker) do not ⇒ refused and removed', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      final reinstalled = _lease(store, _Marker()); // files wiped
      expect(_denial(await _admit(reinstalled, s)), OfflinePassDenial.revoked);
      expect(store.value, isNull);
    });

    test('15b. a record from before markers existed is refused', () async {
      final lease = _lease(store, marker);
      final s = _session();
      await _issue(lease, s);
      final legacy = Map<String, Object?>.of(store.json)
        ..remove('r')
        ..['v'] = 1;
      store.value = jsonEncode(legacy);
      expect(_denial(await _admit(_lease(store, marker), s)),
          OfflinePassDenial.revoked);
    });
  });

  group('the file marker', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bw_marker_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes, flushes and reads back one strict line', () async {
      var flushes = 0;
      final m = FileOfflinePassRevocationMarker(
        directory: () async => dir,
        open: (file, mode) async {
          final raf = await file.open(mode: mode);
          return _CountingFile(raf, () => flushes++);
        },
      );
      expect(await m.read(), isNull);
      await m.write(7);
      expect(flushes, 1, reason: 'durable before it reports success');
      expect(await m.read(), 7);
      final f = File('${dir.path}${Platform.pathSeparator}offline_pass'
          '${Platform.pathSeparator}revoked_v1');
      expect(f.readAsStringSync(), '{"v":1,"r":7}\n');
      f.writeAsStringSync('{"v":1,"r":');
      await expectLater(m.read(), throwsA(isA<FormatException>()));
    });

    test('a failed flush is a failed write', () async {
      final m = FileOfflinePassRevocationMarker(
        directory: () async => dir,
        open: (file, mode) async =>
            _CountingFile(await file.open(mode: mode), () {
          throw const FileSystemException('fsync failed');
        }),
      );
      await expectLater(m.write(1), throwsA(isA<FileSystemException>()));
    });

    test('the platform lifecycle uses the file marker on every platform', () {
      final src = File('lib/src/services/offline_pass_lifecycle.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), '');
      expect(
          src, contains('revocationMarker:FileOfflinePassRevocationMarker()'));
    });
  });
}

/// A file whose flush is observed (or fails).
class _CountingFile implements RandomAccessFile {
  _CountingFile(this._inner, this._onFlush);
  final RandomAccessFile _inner;
  final void Function() _onFlush;

  @override
  Future<RandomAccessFile> flush() async {
    _onFlush();
    await _inner.flush();
    return this;
  }

  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) async {
    await _inner.writeFrom(buffer, start, end);
    return this;
  }

  @override
  Future<void> close() => _inner.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
