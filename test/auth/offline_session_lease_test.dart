// OFF-2b-1: the offline pass record, its protected storage, and the cold-start
// eligibility evaluator. Everything runs on injected clocks and an in-memory
// store: no real time, no device, no hosted service. The lease is dormant in
// this checkpoint (nothing in lib/ uses it), which a source guard below holds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/app_session_check_outcome.dart';
import 'package:broker_wallet/src/services/offline_session_lease.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uidA = '550e8400-e29b-41d4-a716-446655440000';
const _uidB = '660e8400-e29b-41d4-a716-446655440001';
const _sid1 = '11111111-1111-4111-8111-111111111111';
const _sid2 = '22222222-2222-4222-8222-222222222222';

final _t0 = DateTime.utc(2026, 11, 13, 9);

const _window = OfflinePassLimits.window;
const _usage = OfflinePassLimits.usage;
const _starts = OfflinePassLimits.coldStarts;
const _tol = OfflinePassLimits.clockTolerance;
const _slice = OfflinePassLimits.usageReservation;

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _token({
  String sub = _uidA,
  Object? sid = _sid1,
  Object? iat,
  bool omitIat = false,
}) {
  final issued = iat ?? _t0.millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': sub,
        'session_id': sid,
        if (!omitIat) 'iat': issued,
        'exp': (issued is int ? issued : 0) + 3600,
      })}.sig';
}

sb.Session _session({
  String uid = _uidA,
  String? tokenSub,
  Object? sid = _sid1,
  Object? iat,
  bool omitIat = false,
  String? rawToken,
}) =>
    sb.Session(
      accessToken: rawToken ??
          _token(sub: tokenSub ?? uid, sid: sid, iat: iat, omitIat: omitIat),
      tokenType: 'bearer',
      refreshToken: 'refresh-secret-value',
      user: sb.User(
        id: uid,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

int _iatOf(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// Wall clock and monotonic clock driven by the test. [advance] moves both;
/// [setWall] moves only the wall clock (the user changing the phone's time).
class _Clocks {
  _Clocks(this.wall);
  DateTime wall;
  Duration _mono = Duration.zero;

  void advance(Duration d) {
    wall = wall.add(d);
    _mono += d;
  }

  /// Time passing with the app's monotonic clock stopped (the phone asleep,
  /// or the process not running).
  void passWithoutMonotonic(Duration d) => wall = wall.add(d);

  void setWall(DateTime w) => wall = w;

  OfflineMonotonicClock startMonotonic() => _Mono(this, _mono);
}

class _Mono implements OfflineMonotonicClock {
  _Mono(this._c, this._start);
  final _Clocks _c;
  final Duration _start;
  @override
  Duration get elapsed => _c._mono - _start;
}

class _Store implements OfflinePassStore {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  /// Accepts the write but keeps the old value (a write that did not land).
  bool dropWrites = false;

  /// Models Android `apply()` at its worst: every write and delete is visible
  /// in memory (so the read-back succeeds) but none reaches the disk before
  /// the process dies; [crash] brings back the last value that did.
  bool applyLike = false;
  String? _durable;
  Completer<void>? holdWrite;
  int reads = 0;
  int writes = 0;
  int deletes = 0;
  final List<String> history = [];

  /// The process dies: memory is lost, only what reached the disk remains.
  void crash() => value = _durable;

  @override
  Future<String?> read() async {
    reads++;
    if (failRead) throw Exception('read failed');
    return value;
  }

  @override
  Future<void> write(String v) async {
    writes++;
    final hold = holdWrite;
    if (hold != null) await hold.future;
    if (failWrite) throw Exception('write failed');
    history.add(v);
    if (!dropWrites) {
      value = v;
      if (!applyLike) _durable = v;
    }
  }

  @override
  Future<void> delete() async {
    deletes++;
    if (failDelete) throw Exception('delete failed');
    value = null;
    if (!applyLike) _durable = null;
  }

  Map<String, Object?> get json => jsonDecode(value!) as Map<String, Object?>;
}

/// The Android charge journal as the disk sees it. Every call that completes
/// normally is durable (fsync returned); the failure switches model the ways
/// a write can fail or a process can die around it.
class _Journal implements OfflineChargeJournal {
  String? durable;
  bool failRead = false;
  bool failCreate = false;
  bool failTruncate = false;
  bool failDelete = false;

  /// The append fails before any byte is written.
  bool failAppend = false;

  /// fsync fails after the bytes were handed over: they reached the disk.
  bool failFlushKept = false;

  /// fsync fails and the bytes never reached the disk.
  bool failFlushLost = false;

  /// The process dies during the next append: only its first [n] characters
  /// reach the disk and the call never returns.
  int? dieDuringNextAppendAfter;

  /// The process dies before the next append writes anything.
  bool dieBeforeNextAppend = false;
  Completer<void>? holdAppend;
  int creates = 0;
  int appends = 0;
  int truncates = 0;
  int deletes = 0;

  /// The content at the moment of each delete (to model a lost unlink).
  final List<String?> deleted = [];

  List<String> get lines => durable!.split('\n')..removeLast();

  Map<String, Object?> get last =>
      jsonDecode(lines.last) as Map<String, Object?>;

  @override
  Future<String?> read() async {
    if (failRead) throw const FileSystemException('read failed');
    return durable;
  }

  void Function()? onCreate;

  @override
  Future<void> create(String content) async {
    creates++;
    onCreate?.call();
    if (failCreate) throw const FileSystemException('create failed');
    durable = content;
  }

  @override
  Future<void> append(String record) async {
    appends++;
    final hold = holdAppend;
    if (hold != null) await hold.future;
    if (dieBeforeNextAppend) {
      dieBeforeNextAppend = false;
      return Completer<void>().future; // never returns: the process is gone
    }
    final cut = dieDuringNextAppendAfter;
    if (cut != null) {
      dieDuringNextAppendAfter = null;
      durable = durable! + record.substring(0, cut);
      return Completer<void>().future;
    }
    if (failAppend) throw const FileSystemException('write failed');
    if (durable == null) throw const FileSystemException('no journal');
    if (failFlushLost) throw const FileSystemException('fsync failed');
    durable = durable! + record;
    if (failFlushKept) throw const FileSystemException('fsync failed');
  }

  @override
  Future<void> truncate(int length) async {
    truncates++;
    if (failTruncate) throw const FileSystemException('truncate failed');
    durable = durable!.substring(0, length);
  }

  @override
  Future<void> delete() async {
    deletes++;
    if (failDelete) throw const FileSystemException('delete failed');
    deleted.add(durable);
    durable = null;
  }
}

class _Harness {
  _Harness({DateTime? start, bool android = false})
      : clocks = _Clocks(start ?? _t0),
        journal = android ? _Journal() : null;
  final _Clocks clocks;
  final store = _Store();
  final _Journal? journal;
  late OfflineSessionLease lease = _newLease();

  OfflineSessionLease _newLease() => OfflineSessionLease(
        store: store,
        wallClock: () => clocks.wall,
        startMonotonic: clocks.startMonotonic,
        chargeJournal: journal,
      );

  /// The process dies and a new one starts (memory lost, storage kept).
  void restart() => lease = _newLease();

  /// The process dies abruptly (unflushed preference writes are lost) and a
  /// new one starts.
  void crash() {
    store.crash();
    restart();
  }

  Future<bool> issue({sb.Session? session}) {
    final proof = AuthoritativeConfirmation.fromCheck(
      outcome: AppSessionCheckOutcome.confirmed,
      session: session ?? _session(iat: _iatOf(clocks.wall)),
    );
    expect(proof, isNotNull);
    return lease.issue(proof!);
  }

  Future<OfflineAdmission> admit({
    AppSessionCheckOutcome outcome = AppSessionCheckOutcome.offline,
    sb.Session? session,
    bool noSession = false,
    bool recovery = false,
    bool deleting = false,
  }) =>
      lease.admitColdStart(
        outcome: outcome,
        session: noSession ? null : (session ?? _session(iat: _iatOf(_t0))),
        passwordRecoveryActive: recovery,
        accountDeletionPending: deleting,
      );

  Future<OfflinePassSession> grant({
    AppSessionCheckOutcome outcome = AppSessionCheckOutcome.offline,
    sb.Session? session,
  }) async {
    final r = await admit(outcome: outcome, session: session);
    expect(r, isA<OfflineAdmissionGranted>(), reason: '$r');
    return (r as OfflineAdmissionGranted).session;
  }
}

OfflinePassDenial? _denial(OfflineAdmission r) =>
    r is OfflineAdmissionDenied ? r.reason : null;

/// Uses the session in [step]-sized steps, checkpointing after each, until the
/// session ends or [total] has passed. Returns why it ended (or null).
Future<OfflinePassDenial?> _use(
    _Harness h, OfflinePassSession s, Duration total,
    {Duration step = const Duration(seconds: 30)}) async {
  var done = Duration.zero;
  while (done < total) {
    final d = total - done < step ? total - done : step;
    h.clocks.advance(d);
    done += d;
    final end = await s.checkpoint();
    if (end != null) return end;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. limits and protected storage', () {
    test('A1 approved limits are exactly 24 h / 8 h / 20 starts / 2 min', () {
      expect(_window, const Duration(hours: 24));
      expect(_usage, const Duration(hours: 8));
      expect(_starts, 20);
      expect(_tol, const Duration(minutes: 2));
      expect(_slice, const Duration(seconds: 60));
    });

    test(
        'A2 Android: own namespace (own prefs file and Keystore alias), '
        'authenticated cipher, reset on error', () {
      final m = SecureOfflinePassStore.androidOptions.toMap();
      expect(m['storageNamespace'], 'bw_offline_pass');
      expect(m['resetOnError'], 'true');
      expect(m['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
      expect(m['keyCipherAlgorithm'], 'RSA_ECB_OAEPwithSHA_256andMGF1Padding');
      expect(m['encryptedSharedPreferences'], 'false');
      expect(m['enforceBiometrics'], 'false');
    });

    test(
        'A3 iOS: This-Device-Only accessibility, not synchronizable, own '
        'service name', () {
      final m = SecureOfflinePassStore.iosOptions.toMap();
      expect(m['accessibility'], 'first_unlock_this_device');
      expect(m['synchronizable'], 'false');
      expect(m['accountName'], 'bw_offline_pass');
      expect(m.containsKey('groupId'), isFalse);
    });

    test('A4 the Supabase session storage and its options are unchanged', () {
      final src = File('lib/src/services/supabase_secure_storage.dart')
          .readAsStringSync();
      expect(src, contains("this.persistSessionKey = 'supabase.auth.token'"));
      expect(src, contains('aOptions: AndroidOptions(),'));
      expect(
          src,
          contains(
              'IOSOptions(accessibility: KeychainAccessibility.first_unlock)'));
      expect(src, isNot(contains('bw_offline_pass')));
      expect(SecureOfflinePassStore.storageKey, isNot('supabase.auth.token'));
    });

    test('A5 the secure store round-trips through flutter_secure_storage',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureOfflinePassStore();
      expect(await store.read(), isNull);
      await store.write('x');
      expect(await store.read(), 'x');
      await store.delete();
      expect(await store.read(), isNull);
    });

    test('A6 dormant: nothing in lib/ uses the lease yet (no Home, no router)',
        () {
      final users = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path
              .replaceAll(r'\', '/')
              .endsWith('lib/src/services/offline_session_lease.dart'))
          .where((f) => f.readAsStringSync().contains('offline_session_lease'))
          .map((f) => f.path)
          .toList();
      expect(users, isEmpty);
    });

    test('A7 the lease writes no log and makes no network call', () {
      final src = File('lib/src/services/offline_session_lease.dart')
          .readAsStringSync();
      for (final banned in [
        'debugPrint',
        'print(',
        'log(',
        'package:http',
        'HttpClient',
        'Supabase.instance',
        'package:shared_preferences',
        'SharedPreferences.getInstance',
      ]) {
        expect(src, isNot(contains(banned)), reason: banned);
      }
    });

    test(
        'A8 Android backup and device transfer exclude exactly the pass '
        "namespace's three preference files, and never the session's", () {
      final ns =
          SecureOfflinePassStore.androidOptions.toMap()['storageNamespace']!;
      // File names the installed plugin derives from the namespace, checked
      // against its own sources so an upgrade that renames them fails here.
      final config =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map<String, Object?>;
      final pkg = (config['packages'] as List)
          .cast<Map<String, Object?>>()
          .singleWhere((p) => p['name'] == 'flutter_secure_storage');
      final root = Directory('.dart_tool')
          .absolute
          .uri
          .resolve('${pkg['rootUri']}/')
          .toFilePath();
      final java = '${root}android/src/main/java/com/it_nomads/'
          'fluttersecurestorage/';
      String src(String f) => File('$java$f').readAsStringSync();
      expect(src('FlutterSecureStorageConfig.java'),
          contains('return storageNamespace != null ? storageNamespace :'));
      expect(src('FlutterSecureStorageConfig.java'),
          contains('? "FlutterSecureKeyStorage:" + storageNamespace'));
      expect(
          src('NamespacedConfigSource.java'),
          contains('return "FlutterSecureStorageConfiguration:" + '
              'sharedPreferencesName;'));
      expect(
          src('FlutterSecureStorage.java'),
          contains('new NamespacedConfigSource(context, '
              'config.getEffectiveDataPrefsName())'));
      // Every preferences file the plugin opens is one of these names.
      final opened = <String>{};
      for (final f in Directory(java)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.java'))) {
        for (final m in RegExp(r'getSharedPreferences\(\s*([^,]+),')
            .allMatches(f.readAsStringSync())) {
          opened.add(m.group(1)!.trim());
        }
      }
      expect(opened, {
        'config.getEffectiveDataPrefsName()', // the data file
        'config.getEffectiveKeyStoragePrefsName()', // the wrapped key
        'keyStoragePrefsName', // = getEffectiveKeyStoragePrefsName()
        'namespacedName', // FlutterSecureStorageConfiguration:<ns>
        'LEGACY_GLOBAL_CONFIG_NAME', // shared, read-only fallback
        'fileName', // legacy EncryptedSharedPreferences = the data file
        // Un-namespaced, but only inside the plugin's *WithBackup migrations,
        // which run only with migrateWithBackup, kept off below.
        '"FlutterSecureKeyStorage"',
      });
      expect(SecureOfflinePassStore.androidOptions.toMap()['migrateWithBackup'],
          'false');
      final plugin = src('FlutterSecureStorage.java');
      final literalUses =
          RegExp(r'getSharedPreferences\(\s*"FlutterSecureKeyStorage",')
              .allMatches(plugin)
              .toList();
      expect(literalUses, isNotEmpty);
      for (final use in literalUses) {
        final enclosing = RegExp(r'(?:private|public) \w+ (\w+)\(')
            .allMatches(plugin.substring(0, use.start))
            .last
            .group(1)!;
        expect(enclosing, endsWith('WithBackup'), reason: 'at ${use.start}');
      }
      final passFiles = {
        '$ns.xml',
        'FlutterSecureKeyStorage:$ns.xml',
        'FlutterSecureStorageConfiguration:$ns.xml',
      };
      // The default namespace holds the Supabase session: never excluded.
      const sessionFiles = {
        'FlutterSecureStorage.xml',
        'FlutterSecureKeyStorage.xml',
        'FlutterSecureStorageConfiguration.xml',
      };
      Set<String> sharedPrefExcludes(String section) => {
            for (final m
                in RegExp(r'<exclude domain="sharedpref" path="([^"]+)" />')
                    .allMatches(section))
              m.group(1)!
          };
      String section(String xml, String tag) =>
          RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml)!.group(1)!;
      final full = File('android/app/src/main/res/xml/backup_rules.xml')
          .readAsStringSync();
      final modern =
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync();
      for (final (where, body) in [
        ('full-backup-content', section(full, 'full-backup-content')),
        ('cloud-backup', section(modern, 'cloud-backup')),
        ('device-transfer', section(modern, 'device-transfer')),
      ]) {
        expect(sharedPrefExcludes(body), passFiles, reason: where);
        expect(sharedPrefExcludes(body).intersection(sessionFiles), isEmpty,
            reason: where);
        expect(body, isNot(contains('domain="sharedpref" path="."')),
            reason: where);
        // OFF-2b-1b: the Android charge journal's folder in files/
        // (getApplicationSupportDirectory), excluded exactly once.
        expect(
            '<exclude domain="file" path="'
                    '${FileOfflineChargeJournal.directoryName}" />'
                .allMatches(body)
                .length,
            1,
            reason: where);
      }
      expect(full + modern, isNot(contains('<include')));
    });
  });

  group('B. issuing: only an authoritative confirmation', () {
    test('B1 every outcome except confirmed is refused as proof', () {
      for (final o in AppSessionCheckOutcome.values) {
        final proof = AuthoritativeConfirmation.fromCheck(
            outcome: o, session: _session());
        if (o == AppSessionCheckOutcome.confirmed) {
          expect(proof, isNotNull);
        } else {
          expect(proof, isNull, reason: o.name);
        }
      }
    });

    test(
        'B2 no session, token of another user, bad session_id, no iat, '
        'malformed token: no proof', () {
      const c = AppSessionCheckOutcome.confirmed;
      expect(AuthoritativeConfirmation.fromCheck(outcome: c, session: null),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(tokenSub: _uidB)),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(sid: 'not-a-uuid')),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(sid: null)),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(omitIat: true)),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(iat: '1700000000')),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(iat: 0)),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(rawToken: 'a.b')),
          isNull);
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: c, session: _session(rawToken: 'a.%%%.c')),
          isNull);
    });

    test(
        'B3 the record is bound to account and session, anchored on the '
        "server's iat, and holds no secret", () async {
      final h = _Harness();
      final s =
          _session(iat: _iatOf(_t0.subtract(const Duration(minutes: 30))));
      expect(await h.issue(session: s), isTrue);
      final j = h.store.json;
      expect(j.keys.toSet(), {'v', 'uid', 'sid', 'a', 'h', 'u', 'n'});
      expect(j['v'], 1);
      expect(j['uid'], _uidA);
      expect(j['sid'], _sid1);
      expect(j['a'],
          _t0.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch);
      expect(j['h'], _t0.millisecondsSinceEpoch);
      expect(j['u'], 0);
      expect(j['n'], 0);
      expect(h.store.value, isNot(contains(s.accessToken)));
      expect(h.store.value, isNot(contains('refresh-secret-value')));
      expect(h.store.value, isNot(contains('http')));
    });

    test(
        'B4 iat ahead of the phone clock beyond tolerance: refused, old '
        'pass removed', () async {
      final h = _Harness();
      expect(await h.issue(), isTrue);
      final ahead =
          _session(iat: _iatOf(_t0.add(_tol + const Duration(seconds: 1))));
      expect(await h.issue(session: ahead), isFalse);
      expect(h.store.value, isNull);
      // Within tolerance it is accepted.
      final near = _session(iat: _iatOf(_t0.add(const Duration(minutes: 1))));
      expect(await h.issue(session: near), isTrue);
    });

    test('B5 a token issued a full window ago is refused', () async {
      final h = _Harness();
      final old = _session(iat: _iatOf(_t0.subtract(_window)));
      expect(await h.issue(session: old), isFalse);
      expect(h.store.value, isNull);
    });

    test('B6 a new authoritative confirmation renews the whole budget',
        () async {
      final h = _Harness();
      await h.issue();
      for (var i = 0; i < 3; i++) {
        h.restart();
        final s = await h.grant();
        expect(await _use(h, s, const Duration(hours: 1)), isNull);
      }
      expect(h.store.json['n'], 3);
      h.restart();
      h.clocks.advance(const Duration(hours: 2));
      expect(
          await h.issue(session: _session(iat: _iatOf(h.clocks.wall))), isTrue);
      final j = h.store.json;
      expect(j['n'], 0);
      expect(j['u'], 0);
      expect(j['a'], h.clocks.wall.millisecondsSinceEpoch);
    });

    test('B7 write failure or a write that did not land: false, nothing kept',
        () async {
      final h = _Harness();
      h.store.failWrite = true;
      expect(await h.issue(), isFalse);
      expect(h.store.value, isNull);
      h.store
        ..failWrite = false
        ..dropWrites = true;
      expect(await h.issue(), isFalse);
      expect(h.store.value, isNull);
    });

    test(
        'B8 issuing ends a running offline session, whose late writes cannot '
        'overwrite the renewed pass', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      h.clocks.advance(const Duration(minutes: 10));
      expect(
          await h.issue(session: _session(iat: _iatOf(h.clocks.wall))), isTrue);
      final renewed = h.store.value;
      h.clocks.advance(const Duration(minutes: 10));
      expect(await s.checkpoint(), OfflinePassDenial.replaced);
      expect(s.isActive, isFalse);
      expect(h.store.value, renewed);
    });
  });

  group('C. eligibility matrix at cold start', () {
    test(
        'C1 offline, serverUnavailable and timedOut admit a valid pass, '
        'charging one start and one reservation before the grant', () async {
      for (final o in [
        AppSessionCheckOutcome.offline,
        AppSessionCheckOutcome.serverUnavailable,
        AppSessionCheckOutcome.timedOut,
      ]) {
        final h = _Harness();
        await h.issue();
        h.restart();
        final writesBefore = h.store.writes;
        final s = await h.grant(outcome: o);
        expect(s.isActive, isTrue, reason: o.name);
        expect(s.userId, _uidA);
        expect(s.sessionId, _sid1);
        expect(h.store.writes, writesBefore + 1);
        expect(h.store.json['n'], 1);
        expect(h.store.json['u'], _slice.inMilliseconds);
      }
    });

    test(
        'C2 confirmed, inconclusive (captive portal, malformed answer) and '
        'stale do not admit and leave the pass untouched (no use, no '
        'extension)', () async {
      for (final o in [
        AppSessionCheckOutcome.confirmed,
        AppSessionCheckOutcome.inconclusive,
        AppSessionCheckOutcome.stale,
      ]) {
        final h = _Harness();
        await h.issue();
        final before = h.store.value;
        h.restart();
        expect(_denial(await h.admit(outcome: o)),
            OfflinePassDenial.outcomeNotEligible,
            reason: o.name);
        expect(h.store.value, before, reason: o.name);
      }
    });

    test(
        'C3 refused (server-confirmed supersession) and absent (SDK removed '
        'the session) delete the pass', () async {
      for (final o in [
        AppSessionCheckOutcome.refused,
        AppSessionCheckOutcome.absent,
      ]) {
        final h = _Harness();
        await h.issue();
        h.restart();
        expect(_denial(await h.admit(outcome: o)),
            OfflinePassDenial.knownInvalidation,
            reason: o.name);
        expect(h.store.value, isNull, reason: o.name);
        expect(_denial(await h.admit()), OfflinePassDenial.noPass);
      }
    });

    test(
        'C3b credentialsRejected deletes the pass; no later connectivity '
        'failure can reuse it; only a new confirmation issues one', () async {
      final h = _Harness();
      // 1. A valid pass exists.
      await h.issue();
      expect(h.store.value, isNotNull);
      // 2. The server rejects the token.
      h.restart();
      expect(
          _denial(await h.admit(
              outcome: AppSessionCheckOutcome.credentialsRejected)),
          OfflinePassDenial.credentialsRejected);
      // 3. The pass is gone.
      expect(h.store.value, isNull);
      // 4. Later offline cold starts (every eligible failure) cannot reuse it.
      for (final o in [
        AppSessionCheckOutcome.offline,
        AppSessionCheckOutcome.timedOut,
        AppSessionCheckOutcome.serverUnavailable,
      ]) {
        h.restart();
        expect(_denial(await h.admit(outcome: o)), OfflinePassDenial.noPass,
            reason: o.name);
      }
      expect(h.store.value, isNull);
      // 5. Only a fresh authoritative confirmation issues a new pass.
      h.clocks.advance(const Duration(minutes: 5));
      expect(
          AuthoritativeConfirmation.fromCheck(
              outcome: AppSessionCheckOutcome.credentialsRejected,
              session: _session(iat: _iatOf(h.clocks.wall))),
          isNull);
      expect(
          await h.issue(session: _session(iat: _iatOf(h.clocks.wall))), isTrue);
      h.restart();
      final s = await h.grant();
      expect(s.isActive, isTrue);
      expect(h.store.json['n'], 1);
    });

    test(
        'C3c credentialsRejected during a running offline session ends it '
        'and deletes the pass', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      expect(
          _denial(await h.admit(
              outcome: AppSessionCheckOutcome.credentialsRejected)),
          OfflinePassDenial.credentialsRejected);
      expect(s.isActive, isFalse);
      expect(h.store.value, isNull);
      h.clocks.advance(const Duration(minutes: 2));
      expect(await s.checkpoint(), OfflinePassDenial.credentialsRejected);
      expect(h.store.value, isNull);
    });

    test('C4 classification of raw failures decides eligibility', () async {
      final eligible = <Object>[
        const SocketException('no route'),
        TimeoutException('slow'),
        sb.AuthRetryableFetchException(statusCode: '503'),
        sb.AuthRetryableFetchException(),
        const sb.PostgrestException(message: 'down', code: '503'),
      ];
      // Authoritative token rejection: denied and the pass deleted.
      final rejected = <Object>[
        const sb.AuthException('bad jwt', statusCode: '401'),
        const sb.AuthException('forbidden', statusCode: '403'),
        const sb.PostgrestException(message: 'jwt', code: 'PGRST301'),
        const sb.PostgrestException(message: 'jwt', code: 'PGRST302'),
        const sb.PostgrestException(message: 'jwt', code: 'PGRST303'),
      ];
      for (final e in rejected) {
        final h = _Harness();
        await h.issue();
        h.restart();
        final r = await h.admit(outcome: classifySessionCheckError(e));
        expect(_denial(r), OfflinePassDenial.credentialsRejected, reason: '$e');
        expect(h.store.value, isNull, reason: '$e');
      }
      // Proves nothing (captive portal HTML, database error, unknown): denied,
      // pass kept unused (never treated as an authoritative rejection).
      final refused = <Object>[
        const sb.PostgrestException(message: 'denied', code: '42501'),
        const FormatException('garbage'),
        StateError('unknown'),
      ];
      for (final e in eligible) {
        final h = _Harness();
        await h.issue();
        h.restart();
        final r = await h.admit(outcome: classifySessionCheckError(e));
        expect(r, isA<OfflineAdmissionGranted>(), reason: '$e');
      }
      for (final e in refused) {
        final h = _Harness();
        await h.issue();
        h.restart();
        final before = h.store.value;
        final r = await h.admit(outcome: classifySessionCheckError(e));
        expect(_denial(r), OfflinePassDenial.outcomeNotEligible, reason: '$e');
        expect(h.store.value, before, reason: '$e');
      }
      // A malformed answer (not a Boolean) is never a grant either.
      for (final answer in <Object?>[null, 'true', 1, const <Object>[], {}]) {
        expect(classifySessionCheckAnswer(answer),
            AppSessionCheckOutcome.inconclusive);
      }
    });

    test('C5 no saved session: denied and the pass removed', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      expect(
          _denial(await h.admit(noSession: true)), OfflinePassDenial.noSession);
      expect(h.store.value, isNull);
    });

    test('C6 another account: denied and the pass removed', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      expect(_denial(await h.admit(session: _session(uid: _uidB))),
          OfflinePassDenial.sessionMismatch);
      expect(h.store.value, isNull);
    });

    test(
        'C7 replay of a previous session of the same account: denied and '
        'removed', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      expect(_denial(await h.admit(session: _session(sid: _sid2))),
          OfflinePassDenial.sessionMismatch);
      expect(h.store.value, isNull);
    });

    test(
        'C8 a token whose subject differs from the session user, or whose '
        'session_id is unreadable: denied and removed', () async {
      for (final s in [
        _session(tokenSub: _uidB),
        _session(sid: 'nope'),
        _session(rawToken: 'x.y'),
      ]) {
        final h = _Harness();
        await h.issue();
        h.restart();
        expect(_denial(await h.admit(session: s)),
            OfflinePassDenial.sessionMismatch);
        expect(h.store.value, isNull);
      }
    });

    test('C9 password recovery or pending account deletion: denied and removed',
        () async {
      for (final flags in [
        (recovery: true, deleting: false),
        (recovery: false, deleting: true),
      ]) {
        final h = _Harness();
        await h.issue();
        h.restart();
        expect(
            _denial(await h.admit(
                recovery: flags.recovery, deleting: flags.deleting)),
            OfflinePassDenial.recoveryOrDeletion);
        expect(h.store.value, isNull);
      }
    });

    test('C10 no pass at all: denied, nothing written', () async {
      final h = _Harness();
      expect(_denial(await h.admit()), OfflinePassDenial.noPass);
      expect(h.store.writes, 0);
    });

    test('C11 every corrupt or out-of-range record: denied and removed',
        () async {
      final good = {
        'v': 1,
        'uid': _uidA,
        'sid': _sid1,
        'a': _t0.millisecondsSinceEpoch,
        'h': _t0.millisecondsSinceEpoch,
        'u': 0,
        'n': 0,
      };
      final bad = <String>[
        '',
        'not json',
        '[]',
        'null',
        jsonEncode({...good, 'v': 2}),
        jsonEncode({...good, 'v': '1'}),
        jsonEncode({...good, 'x': 1}),
        jsonEncode(Map.of(good)..remove('n')),
        jsonEncode({...good, 'uid': 'abc'}),
        jsonEncode({...good, 'sid': 7}),
        jsonEncode({...good, 'a': 0}),
        jsonEncode({...good, 'a': 1.5}),
        jsonEncode({...good, 'h': _t0.millisecondsSinceEpoch - 1}),
        jsonEncode({...good, 'u': -1}),
        jsonEncode({...good, 'u': _usage.inMilliseconds + 1}),
        jsonEncode({...good, 'n': -1}),
        jsonEncode({...good, 'n': _starts + 1}),
        jsonEncode({...good, 'n': '0'}),
      ];
      for (final v in bad) {
        final h = _Harness();
        h.store.value = v;
        expect(_denial(await h.admit()), OfflinePassDenial.corrupt, reason: v);
        expect(h.store.value, isNull, reason: v);
      }
      // The good record itself is accepted (the list above is not vacuous).
      final h = _Harness();
      h.store.value = jsonEncode(good);
      expect(await h.admit(), isA<OfflineAdmissionGranted>());
    });

    test('C12 storage failures fail closed', () async {
      // Read fails.
      var h = _Harness();
      await h.issue();
      h.restart();
      h.store.failRead = true;
      expect(_denial(await h.admit()), OfflinePassDenial.storageFailure);
      // Charging write fails: no grant.
      h = _Harness();
      await h.issue();
      h.restart();
      h.store.failWrite = true;
      expect(_denial(await h.admit()), OfflinePassDenial.storageFailure);
      // Charging write silently does not land: no grant.
      h = _Harness();
      await h.issue();
      h.restart();
      h.store.dropWrites = true;
      expect(_denial(await h.admit()), OfflinePassDenial.storageFailure);
    });
  });

  group('D. 24-hour window from the server iat', () {
    test(
        'D1 boundary: one ms before admits, at the boundary denies and '
        'removes', () async {
      var h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.passWithoutMonotonic(_window - const Duration(milliseconds: 1));
      expect(await h.admit(), isA<OfflineAdmissionGranted>());

      h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.passWithoutMonotonic(_window);
      expect(_denial(await h.admit()), OfflinePassDenial.windowExpired);
      expect(h.store.value, isNull);
    });

    test('D2 measured from iat, not from when the pass was written', () async {
      final h = _Harness();
      final iat = _t0.subtract(const Duration(hours: 1));
      await h.issue(session: _session(iat: _iatOf(iat)));
      h.restart();
      h.clocks.passWithoutMonotonic(const Duration(hours: 23));
      expect(_denial(await h.admit()), OfflinePassDenial.windowExpired);
    });

    test('D3 the window also ends a running session', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.passWithoutMonotonic(const Duration(hours: 23, minutes: 59));
      final s = await h.grant();
      expect(await _use(h, s, const Duration(minutes: 5)),
          OfflinePassDenial.windowExpired);
      expect(s.isActive, isFalse);
      expect(h.store.value, isNull);
    });

    test('D4 a refreshed token (same session, later iat) does not extend it',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.passWithoutMonotonic(const Duration(hours: 23));
      final refreshed = _session(iat: _iatOf(h.clocks.wall));
      final s = await h.grant(session: refreshed);
      expect(h.store.json['a'], _t0.millisecondsSinceEpoch);
      expect(await _use(h, s, const Duration(hours: 2)),
          OfflinePassDenial.windowExpired);
      expect(
          h.clocks.wall.isBefore(_t0.add(_window + const Duration(minutes: 1))),
          isTrue);
    });

    test('D5 repeated network failures never renew it', () async {
      final h = _Harness();
      await h.issue();
      for (var i = 0; i < 5; i++) {
        h.restart();
        h.clocks.passWithoutMonotonic(const Duration(hours: 4));
        final r = await h.admit(
            outcome: i.isEven
                ? AppSessionCheckOutcome.offline
                : AppSessionCheckOutcome.timedOut);
        if (r is OfflineAdmissionGranted) await r.session.checkpoint();
        expect(
            h.store.value == null ||
                h.store.json['a'] == _t0.millisecondsSinceEpoch,
            isTrue);
      }
      h.restart();
      h.clocks.passWithoutMonotonic(const Duration(hours: 4)); // t0 + 24h
      expect(_denial(await h.admit()), OfflinePassDenial.windowExpired);
    });
  });

  group('E. 8-hour offline use, persisted', () {
    test('E1 use accumulates across restarts and stops at 8 h', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      var s = await h.grant();
      expect(await _use(h, s, const Duration(hours: 3)), isNull);
      h.restart(); // process killed
      s = await h.grant();
      expect(await _use(h, s, const Duration(hours: 3)), isNull);
      h.restart();
      s = await h.grant();
      final end = await _use(h, s, const Duration(hours: 3));
      expect(end, OfflinePassDenial.usageExhausted);
      expect(h.store.value, isNull);
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.noPass);
    });

    test('E2 the reservation is stored before the grant and never refunded',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      await h.grant();
      expect(h.store.json['u'], _slice.inMilliseconds);
      h.restart(); // the start was cancelled or the app was killed at once
      await h.grant();
      expect(h.store.json['u'], 2 * _slice.inMilliseconds);
      expect(h.store.json['n'], 2);
    });

    test('E3 the stored use is never below the measured use', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      var used = Duration.zero;
      for (var i = 0; i < 40; i++) {
        h.clocks.advance(const Duration(seconds: 17));
        used += const Duration(seconds: 17);
        expect(await s.checkpoint(), isNull);
        expect(h.store.json['u'] as int,
            greaterThanOrEqualTo(used.inMilliseconds));
        expect(h.store.json['u'] as int,
            lessThanOrEqualTo((used + _slice).inMilliseconds));
      }
    });

    test('E4 paused (background) time is not use; resume continues', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      h.clocks.advance(const Duration(minutes: 5));
      expect(await s.pause(), isNull);
      h.clocks.advance(const Duration(hours: 3)); // monotonic runs, not counted
      expect(await s.checkpoint(), isNull);
      expect(await s.resume(), isNull);
      h.clocks.advance(const Duration(minutes: 5));
      expect(await s.checkpoint(), isNull);
      final u = h.store.json['u'] as int;
      expect(
          u, greaterThanOrEqualTo(const Duration(minutes: 10).inMilliseconds));
      expect(u, lessThan(const Duration(minutes: 12).inMilliseconds));
    });

    test('E5 the stored use never decreases without a renewal', () async {
      final h = _Harness();
      await h.issue();
      var last = 0;
      for (var i = 0; i < 6; i++) {
        h.restart();
        final s = await h.grant();
        await _use(h, s, const Duration(minutes: 7));
        final u = h.store.json['u'] as int;
        expect(u, greaterThanOrEqualTo(last));
        last = u;
      }
    });

    test('E6 a stored record already at the budget is not admitted', () async {
      final h = _Harness();
      h.store.value = jsonEncode({
        'v': 1,
        'uid': _uidA,
        'sid': _sid1,
        'a': _t0.millisecondsSinceEpoch,
        'h': _t0.millisecondsSinceEpoch,
        'u': _usage.inMilliseconds,
        'n': 3,
      });
      expect(_denial(await h.admit()), OfflinePassDenial.usageExhausted);
      expect(h.store.value, isNull);
    });
  });

  group('F. 20 offline cold starts, persisted', () {
    test('F1 twenty starts across restarts; the 21st is denied and removes',
        () async {
      final h = _Harness();
      await h.issue();
      for (var i = 1; i <= _starts; i++) {
        h.restart();
        await h.grant();
        expect(h.store.json['n'], i);
      }
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.startsExhausted);
      expect(h.store.value, isNull);
    });

    test('F2 a Retry in the same process does not charge again', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s1 = await h.grant();
      final s2 = await h.grant(outcome: AppSessionCheckOutcome.timedOut);
      expect(identical(s1, s2), isTrue);
      expect(h.store.json['n'], 1);
    });

    test('F3 concurrent starts charge exactly once', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.store.holdWrite = Completer<void>();
      final a = h.admit();
      final b = h.admit(outcome: AppSessionCheckOutcome.serverUnavailable);
      await pumpEventQueue();
      h.store.holdWrite!.complete();
      final ra = await a;
      final rb = await b;
      expect(ra, isA<OfflineAdmissionGranted>());
      expect(rb, isA<OfflineAdmissionGranted>());
      expect(
          identical((ra as OfflineAdmissionGranted).session,
              (rb as OfflineAdmissionGranted).session),
          isTrue);
      expect(h.store.json['n'], 1);
    });

    test(
        'F4 a denial in the same process ends the running session without '
        'refunding it', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      expect(
          _denial(await h.admit(outcome: AppSessionCheckOutcome.inconclusive)),
          OfflinePassDenial.outcomeNotEligible);
      expect(s.isActive, isFalse);
      expect(h.store.json['n'], 1);
      expect(h.store.json['u'], _slice.inMilliseconds);
    });

    test('F5 a later refused answer in the same process ends and removes',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      expect(_denial(await h.admit(outcome: AppSessionCheckOutcome.refused)),
          OfflinePassDenial.knownInvalidation);
      expect(s.isActive, isFalse);
      expect(h.store.value, isNull);
      expect(await s.checkpoint(), OfflinePassDenial.knownInvalidation);
      expect(h.store.value, isNull);
    });
  });

  group('G. untrusted clock', () {
    test('G1 clock set back past the highest time seen: denied and removed',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.setWall(_t0.subtract(_tol + const Duration(seconds: 1)));
      expect(_denial(await h.admit()), OfflinePassDenial.clockRollback);
      expect(h.store.value, isNull);
    });

    test('G2 small drift inside the tolerance is accepted', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.setWall(_t0.subtract(const Duration(minutes: 1)));
      expect(await h.admit(), isA<OfflineAdmissionGranted>());
    });

    test('G3 clock before the server iat beyond tolerance: denied', () async {
      final h = _Harness();
      // iat one minute ahead of the phone (accepted at issue), then the phone
      // goes back further.
      await h.issue(
          session: _session(iat: _iatOf(_t0.add(const Duration(minutes: 1)))));
      h.restart();
      h.clocks.setWall(_t0.subtract(const Duration(minutes: 2)));
      expect(_denial(await h.admit()), OfflinePassDenial.clockRollback);
    });

    test('G4 clock set back during a session: detected by the monotonic clock',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      h.clocks.advance(const Duration(hours: 1));
      expect(await s.checkpoint(), isNull);
      h.clocks.setWall(_t0.add(const Duration(minutes: 30)));
      expect(await s.checkpoint(), OfflinePassDenial.clockRollback);
      expect(h.store.value, isNull);
    });

    test(
        'G4b clock set back before the highest time seen has moved: caught by '
        'the monotonic clock alone', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      // An hour of use with no checkpoint: the stored highest time is still t0.
      h.clocks.advance(const Duration(hours: 1));
      h.clocks.setWall(_t0.add(const Duration(minutes: 30)));
      expect(await s.checkpoint(), OfflinePassDenial.clockRollback);
      expect(h.store.value, isNull);
    });

    test(
        'G4c clock set back after paused time: caught by the highest time '
        'seen alone', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      expect(await s.pause(), isNull);
      h.clocks.advance(const Duration(hours: 3)); // backgrounded, not use
      expect(await s.checkpoint(), isNull); // stores the highest time seen
      h.clocks.setWall(_t0.add(const Duration(hours: 1)));
      expect(await s.resume(), OfflinePassDenial.clockRollback);
      expect(h.store.value, isNull);
    });

    test(
        'G8 a small set-back inside the tolerance cannot stretch the window '
        'end during a session', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.passWithoutMonotonic(const Duration(hours: 23, minutes: 58));
      final s = await h.grant();
      h.clocks.advance(const Duration(minutes: 3)); // t0 + 24h01m of time
      // Wall clock nudged back 90 s: still inside the tolerance, before 24 h.
      h.clocks.setWall(h.clocks.wall.subtract(const Duration(seconds: 90)));
      expect(await s.checkpoint(), OfflinePassDenial.windowExpired);
    });

    test('G5 clock moved forward only shortens', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.clocks.setWall(_t0.add(const Duration(hours: 25)));
      expect(_denial(await h.admit()), OfflinePassDenial.windowExpired);
    });

    test(
        'G6 the highest time seen is stored forward only and survives a '
        'restart', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      await _use(h, s, const Duration(hours: 2));
      expect(
          h.store.json['h'] as int,
          greaterThanOrEqualTo(
              _t0.add(const Duration(hours: 2)).millisecondsSinceEpoch -
                  _slice.inMilliseconds));
      h.restart();
      h.clocks.setWall(_t0.add(const Duration(minutes: 30)));
      expect(_denial(await h.admit()), OfflinePassDenial.clockRollback);
    });

    test(
        'G7 RESIDUAL R-OFF2-CLOCK (accepted 2026-11-13): a clock kept just '
        'above the highest time seen is not detectable, but use and starts '
        'still bound it', () async {
      final h = _Harness();
      await h.issue();
      var starts = 0;
      OfflinePassDenial? end;
      // Real time runs on for days; the user keeps setting the clock to just
      // after the highest time the app has seen.
      while (end == null && starts < 100) {
        h.restart();
        h.clocks.passWithoutMonotonic(const Duration(days: 1));
        final hSeen = h.store.value == null
            ? _t0
            : DateTime.fromMillisecondsSinceEpoch(h.store.json['h'] as int,
                isUtc: true);
        h.clocks.setWall(hSeen.add(const Duration(seconds: 1)));
        final r = await h.admit();
        if (r is OfflineAdmissionDenied) {
          end = r.reason;
          break;
        }
        starts++;
        await _use(h, (r as OfflineAdmissionGranted).session,
            const Duration(minutes: 1));
      }
      expect(starts, lessThanOrEqualTo(_starts));
      expect(end, isNotNull);
    });
  });

  group('H. device reboot', () {
    test(
        'H1 reboot: memory and monotonic clock reset, stored counters and '
        'window hold', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      await _use(h, s, const Duration(hours: 2));
      // Reboot: process gone, monotonic restarts from zero, wall continues.
      h.clocks.passWithoutMonotonic(const Duration(minutes: 3));
      h.restart();
      final s2 = await h.grant();
      expect(h.store.json['n'], 2);
      expect(h.store.json['u'] as int,
          greaterThanOrEqualTo(const Duration(hours: 2).inMilliseconds));
      expect(await _use(h, s2, const Duration(hours: 1)), isNull);
    });

    test('H2 reboot with the clock set back: still detected', () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      await _use(h, s, const Duration(hours: 2));
      h.restart();
      h.clocks.setWall(_t0.add(const Duration(hours: 1)));
      expect(_denial(await h.admit()), OfflinePassDenial.clockRollback);
    });
  });

  group('I. known invalidation', () {
    test('I1 invalidate removes the pass and ends a running session for good',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      expect(await h.lease.invalidate(), isTrue);
      expect(h.store.value, isNull);
      expect(s.isActive, isFalse);
      h.clocks.advance(const Duration(minutes: 5));
      expect(await s.checkpoint(), OfflinePassDenial.invalidated);
      expect(await s.resume(), OfflinePassDenial.invalidated);
      expect(h.store.value, isNull);
      expect(_denial(await h.admit()), OfflinePassDenial.noPass);
    });

    test('I2 invalidate wins over a checkpoint write that is still pending',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      final s = await h.grant();
      h.clocks.advance(const Duration(minutes: 2));
      h.store.holdWrite = Completer<void>();
      final cp = s.checkpoint();
      final inv = h.lease.invalidate();
      await pumpEventQueue();
      h.store.holdWrite!.complete();
      await cp;
      expect(await inv, isTrue);
      expect(h.store.value, isNull);
    });

    test('I3 a failed delete blocks offline use for the rest of the process',
        () async {
      final h = _Harness();
      await h.issue();
      h.restart();
      h.store.failDelete = true;
      expect(await h.lease.invalidate(), isFalse);
      expect(_denial(await h.admit()), OfflinePassDenial.storageFailure);
    });

    test(
        'I4 a pass issued for one account never opens for the next one after '
        'a switch', () async {
      final h = _Harness();
      await h.issue();
      // Account switch: B confirmed online replaces the pass entirely.
      await h.issue(
          session: _session(uid: _uidB, sid: _sid2, iat: _iatOf(_t0)));
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.sessionMismatch);
      expect(h.store.value, isNull);
    });
  });

  // OFF-2b-1b: the Android charge journal. `_Store.applyLike` reproduces the
  // flutter_secure_storage `apply()` gap (writes visible in memory, lost when
  // the process dies); the journal must keep the limits strict regardless.
  group('J. Android charge journal (OFF-2b-1b)', () {
    test('J1 the platform choice: Android gets the file journal, iOS none', () {
      expect(platformChargeJournal(isAndroid: true),
          isA<FileOfflineChargeJournal>());
      expect(platformChargeJournal(isAndroid: false), isNull);
    });

    test(
        'J2 issuing starts a journal bound to the pass, before the record, '
        'holding no identity or secret', () async {
      final h = _Harness(android: true);
      final s = _session(iat: _iatOf(_t0));
      final j = h.journal!;
      var recordWritesAtCreate = -1;
      j.onCreate = () => recordWritesAtCreate = h.store.writes;
      expect(await h.issue(session: s), isTrue);
      expect(j.creates, 1);
      expect(recordWritesAtCreate, 0, reason: 'journal first, record second');
      expect(h.store.value, isNotNull);
      expect(j.lines, hasLength(1));
      final first = j.last;
      expect(first.keys.toList(), ['v', 'b', 's', 'n', 'u', 'h', 'c']);
      expect(first['s'], 0);
      expect(first['n'], 0);
      expect(first['u'], 0);
      expect(first['b'], _bindOf(_uidA, _sid1, _t0.millisecondsSinceEpoch));
      for (final secret in [
        _uidA,
        _sid1,
        s.accessToken,
        'refresh-secret-value',
        'example',
      ]) {
        expect(j.durable, isNot(contains(secret)), reason: secret);
      }
    });

    test('J3 issuing fails closed when the journal cannot be started',
        () async {
      final h = _Harness(android: true);
      h.journal!.failCreate = true;
      expect(await h.issue(), isFalse);
      expect(h.store.value, isNull);
      expect(h.store.writes, 0, reason: 'no record before the journal');
    });

    test('J4 a grant appends exactly one durable line before it returns',
        () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      await h.grant();
      expect(h.journal!.appends, 1);
      expect(h.journal!.lines, hasLength(2));
      expect(h.journal!.last['s'], 1);
      expect(h.journal!.last['n'], 1);
      expect(h.journal!.last['u'], _slice.inMilliseconds);
      expect(h.store.json['n'], 1);
    });

    test(
        'J5 STRICT 20 starts although every preference write is lost when '
        'the process dies', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.store.applyLike = true;
      var grants = 0;
      OfflinePassDenial? end;
      for (var i = 0; i < 40; i++) {
        h.crash();
        final r = await h.admit();
        if (r is OfflineAdmissionDenied) {
          end = r.reason;
          break;
        }
        grants++;
      }
      expect(grants, _starts);
      expect(end, OfflinePassDenial.startsExhausted);
    });

    test('J5c CONTROL: without the journal the same loss exceeds 20 starts',
        () async {
      final h = _Harness();
      await h.issue();
      h.store.applyLike = true;
      var grants = 0;
      for (var i = 0; i < 40; i++) {
        h.crash();
        if (await h.admit() is OfflineAdmissionGranted) grants++;
      }
      expect(grants, 40, reason: 'the gap R-OFF2-APPLY describes');
    });

    Future<(Duration, OfflinePassDenial?)> useUntilDenied(_Harness h,
        {int cycles = 30}) async {
      var granted = Duration.zero;
      OfflinePassDenial? end;
      for (var c = 0; c < cycles && end == null; c++) {
        h.crash();
        final r = await h.admit();
        if (r is OfflineAdmissionDenied) {
          end = r.reason;
          break;
        }
        final s = (r as OfflineAdmissionGranted).session;
        for (var k = 0; k < 100; k++) {
          h.clocks.advance(const Duration(seconds: 30));
          final e = await s.checkpoint();
          if (e != null) {
            end = e;
            break;
          }
          granted += const Duration(seconds: 30);
        }
      }
      return (granted, end);
    }

    test(
        'J6 STRICT 8 h of use although every preference write is lost when '
        'the process dies', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.store.applyLike = true;
      final (granted, end) = await useUntilDenied(h);
      expect(granted, lessThanOrEqualTo(_usage));
      expect(granted, greaterThan(_usage - const Duration(minutes: 30)));
      expect(end, OfflinePassDenial.usageExhausted);
    });

    test('J6c CONTROL: without the journal the same loss exceeds 8 h',
        () async {
      final h = _Harness();
      await h.issue();
      h.store.applyLike = true;
      final (granted, _) = await useUntilDenied(h, cycles: 15);
      expect(granted, greaterThan(_usage));
    });

    test('J7 no grant when the append fails, or fsync fails (kept or lost)',
        () async {
      for (final fail in ['append', 'flushKept', 'flushLost']) {
        final h = _Harness(android: true);
        await h.issue();
        h.restart();
        final j = h.journal!;
        switch (fail) {
          case 'append':
            j.failAppend = true;
          case 'flushKept':
            j.failFlushKept = true;
          case 'flushLost':
            j.failFlushLost = true;
        }
        expect(_denial(await h.admit()), OfflinePassDenial.storageFailure,
            reason: fail);
        expect(h.store.value, isNull, reason: fail);
        j
          ..failAppend = false
          ..failFlushKept = false
          ..failFlushLost = false;
        h.restart();
        expect(await h.admit(), isA<OfflineAdmissionDenied>(), reason: fail);
      }
    });

    test('J8a killed before the journal write: nothing granted, nothing lost',
        () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      await h.grant(); // n = 1
      h.restart();
      h.journal!.dieBeforeNextAppend = true;
      unawaited(h.admit());
      await pumpEventQueue();
      h.crash();
      await h.grant();
      expect(h.journal!.last['n'], 2);
      expect(h.journal!.lines, hasLength(3));
    });

    test(
        'J8b killed during the write: the torn tail is cut and counted as '
        'the worst it could have been', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      await h.grant(); // n = 1, u = slice
      h.restart();
      h.journal!.dieDuringNextAppendAfter = 20;
      unawaited(h.admit());
      await pumpEventQueue();
      expect(h.journal!.durable!.endsWith('\n'), isFalse, reason: 'torn');
      h.crash();
      await h.grant();
      final j = h.journal!;
      expect(j.truncates, 1);
      expect(j.durable!.endsWith('\n'), isTrue);
      expect(j.lines, hasLength(3));
      expect(j.last['s'], 2);
      expect(j.last['n'], 3, reason: '1 + the torn start + this start');
      expect(j.last['u'], 3 * _slice.inMilliseconds);
    });

    test(
        'J8c killed after the durable write, before the grant returned: the '
        'charge counts', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.store.applyLike = true;
      h.restart();
      h.store.holdWrite = Completer<void>(); // the record write never ends
      unawaited(h.admit());
      await pumpEventQueue();
      expect(h.journal!.last['n'], 1);
      h.store.holdWrite = null;
      h.crash();
      await h.grant();
      expect(h.journal!.last['n'], 2);
    });

    test('J8d a torn tail that cannot be cut is never granted on', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      h.journal!.dieDuringNextAppendAfter = 15;
      unawaited(h.admit());
      await pumpEventQueue();
      h.crash();
      h.journal!.failTruncate = true;
      expect(_denial(await h.admit()), OfflinePassDenial.storageFailure);
    });

    test('J9 bytes after a torn line are corruption, not a tail', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      await h.grant();
      final j = h.journal!;
      final good = j.lines;
      j.durable = '${good[0]}\n{"v":1,"b":"x\n${good[1]}\n';
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.accountingInvalid);
      expect(h.store.value, isNull);
      expect(j.durable, isNull);
    });

    test('J10 a changed earlier line fails its checksum', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      await h.grant();
      h.restart();
      await h.grant();
      final j = h.journal!;
      final l = j.lines;
      j.durable = '${l[0]}\n${l[1].replaceFirst('"n":1', '"n":0')}\n${l[2]}\n';
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.accountingInvalid);
    });

    test('J11 duplicate, reordered, decreasing or foreign lines are refused',
        () async {
      final bind = _bindOf(_uidA, _sid1, _t0.millisecondsSinceEpoch);
      final h0 = _t0.millisecondsSinceEpoch;
      final slice = _slice.inMilliseconds;
      final l0 = _journalLine(bind, 0, 0, 0, h0);
      final l1 = _journalLine(bind, 1, 1, slice, h0);
      final cases = {
        'duplicate': l0 + l1 + l1,
        'reordered': l1 + l0,
        'gap': l0 + _journalLine(bind, 2, 1, slice, h0),
        'decreasing n': l0 + l1 + _journalLine(bind, 2, 0, slice, h0),
        'decreasing u': l0 + l1 + _journalLine(bind, 2, 1, 0, h0),
        'decreasing h': l0 + l1 + _journalLine(bind, 2, 1, slice, h0 - 1),
        'first not zero': _journalLine(bind, 0, 1, 0, h0),
        'other pass': l0 + _journalLine('ab' * 32, 1, 1, slice, h0),
        'starts out of range': l0 + _journalLine(bind, 1, 21, slice, h0),
        'empty': '',
        'no complete line': '{"v":1',
        'not ascii': '${l0.substring(0, l0.length - 1)}é\n',
      };
      for (final MapEntry(key: name, value: content) in cases.entries) {
        final h = _Harness(android: true);
        await h.issue();
        h.journal!.durable = content;
        h.restart();
        expect(_denial(await h.admit()), OfflinePassDenial.accountingInvalid,
            reason: name);
        expect(h.store.value, isNull, reason: name);
      }
      // The spec lines above are not vacuous: a well-formed history is read.
      final h = _Harness(android: true);
      await h.issue();
      h.journal!.durable = l0 + l1;
      h.restart();
      await h.grant();
      expect(h.journal!.last['n'], 2);
    });

    test('J12 a pass without its journal is never trusted or re-journaled',
        () async {
      final h = _Harness(android: true);
      await h.issue();
      h.journal!.durable = null;
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.accountingInvalid);
      expect(h.store.value, isNull);
      expect(h.journal!.creates, 1, reason: 'only issue() starts a journal');
    });

    test('J13 the journal of another account or session is refused', () async {
      final a = _Harness(android: true);
      await a.issue();
      final b = _Harness(android: true);
      await b.issue(
          session: _session(uid: _uidB, sid: _sid2, iat: _iatOf(_t0)));
      b.journal!.durable = a.journal!.durable;
      b.restart();
      expect(
          _denial(await b.admit(
              session: _session(uid: _uidB, sid: _sid2, iat: _iatOf(_t0)))),
          OfflinePassDenial.accountingInvalid);
    });

    test('J14 the larger of the record and the journal always wins', () async {
      // Journal ahead (record writes lost).
      var h = _Harness(android: true);
      await h.issue();
      h.store.applyLike = true;
      for (var i = 0; i < 3; i++) {
        h.crash();
        await h.grant();
      }
      h.crash();
      expect(h.store.json['n'], 0);
      await h.grant();
      expect(h.journal!.last['n'], 4);
      expect(h.store.json['n'], 4);
      // Record ahead.
      h = _Harness(android: true);
      await h.issue();
      h.restart();
      await h.grant();
      final r = h.store.json..['n'] = 5;
      h.store.value = jsonEncode(r);
      h.restart();
      await h.grant();
      expect(h.journal!.last['n'], 6);
      expect(h.store.json['n'], 6);
    });

    test('J15 a lost preference write cannot undo the highest time seen',
        () async {
      final h = _Harness(android: true);
      await h.issue();
      h.store.applyLike = true;
      h.crash();
      final s = await h.grant();
      await _use(h, s, const Duration(hours: 2));
      h.crash();
      expect(h.store.json['h'], _t0.millisecondsSinceEpoch);
      h.clocks.setWall(_t0.add(const Duration(minutes: 30)));
      expect(_denial(await h.admit()), OfflinePassDenial.clockRollback);
    });

    test(
        'J16 invalidation is final: a revoked journal brought back by a lost '
        'unlink or a lost preference delete never opens', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      await h.grant();
      final record = h.store.value;
      expect(await h.lease.invalidate(), isTrue);
      final j = h.journal!;
      expect(j.durable, isNull);
      expect(j.deleted.last, endsWith('$_tombstone\n'));
      // Power loss undid both deletes.
      j.durable = j.deleted.last;
      h.store.value = record;
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.accountingInvalid);
      expect(h.store.value, isNull);
      // A process kill undid only the preference delete.
      final k = _Harness(android: true);
      await k.issue();
      k.store.applyLike = true;
      expect(await k.lease.invalidate(), isTrue);
      k.crash();
      expect(k.store.value, isNotNull, reason: 'the record came back');
      expect(_denial(await k.admit()), OfflinePassDenial.accountingInvalid);
    });

    test(
        'J17 every pass deletion (401, revocation, limits) revokes the journal',
        () async {
      for (final o in [
        AppSessionCheckOutcome.credentialsRejected,
        AppSessionCheckOutcome.refused,
        AppSessionCheckOutcome.absent,
      ]) {
        final h = _Harness(android: true);
        await h.issue();
        h.store.applyLike = true;
        h.crash();
        expect(await h.admit(outcome: o), isA<OfflineAdmissionDenied>());
        expect(h.journal!.deleted.last, endsWith('$_tombstone\n'),
            reason: o.name);
        h.crash(); // the preference delete is lost too
        expect(await h.admit(), isA<OfflineAdmissionDenied>(), reason: o.name);
      }
    });

    test('J18 two lease instances racing are caught and fail closed', () async {
      final h = _Harness(android: true);
      await h.issue();
      final a = h._newLease();
      final b = h._newLease();
      h.journal!.holdAppend = Completer<void>();
      Future<OfflineAdmission> admit(OfflineSessionLease l) => l.admitColdStart(
          outcome: AppSessionCheckOutcome.offline,
          session: _session(iat: _iatOf(_t0)),
          passwordRecoveryActive: false,
          accountDeletionPending: false);
      final ra = admit(a);
      final rb = admit(b);
      await pumpEventQueue();
      h.journal!.holdAppend!.complete();
      h.journal!.holdAppend = null;
      final sa = await ra;
      await rb;
      // The duplicate line is visible to the very next check by anyone.
      if (sa is OfflineAdmissionGranted) {
        h.clocks.advance(const Duration(minutes: 2));
        expect(
            await sa.session.checkpoint(), OfflinePassDenial.accountingInvalid);
      }
      h.restart();
      expect(_denial(await h.admit()),
          anyOf(OfflinePassDenial.accountingInvalid, OfflinePassDenial.noPass));
    });

    test(
        'J18b a valid line written by another instance still ends this '
        "session: the journal must end with the session's own line", () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      final a = await h.grant(); // writes line 1
      final other = h._newLease();
      final r = await other.admitColdStart(
          outcome: AppSessionCheckOutcome.offline,
          session: _session(iat: _iatOf(_t0)),
          passwordRecoveryActive: false,
          accountDeletionPending: false);
      expect(r, isA<OfflineAdmissionGranted>(), reason: 'writes line 2');
      expect(h.journal!.lines, hasLength(3));
      h.clocks.advance(const Duration(minutes: 2));
      expect(await a.checkpoint(), OfflinePassDenial.accountingInvalid);
    });

    test('J19 exact limits with the journal: 20 starts, 8 h, 24 h', () async {
      var h = _Harness(android: true);
      await h.issue();
      for (var i = 1; i <= _starts; i++) {
        h.restart();
        await h.grant();
        expect(h.journal!.last['n'], i);
      }
      h.restart();
      expect(_denial(await h.admit()), OfflinePassDenial.startsExhausted);

      h = _Harness(android: true);
      await h.issue();
      h.restart();
      var s = await h.grant();
      expect(await _use(h, s, const Duration(hours: 4)), isNull);
      h.restart();
      s = await h.grant();
      expect(await _use(h, s, const Duration(hours: 5)),
          OfflinePassDenial.usageExhausted);

      h = _Harness(android: true);
      await h.issue();
      h.restart();
      h.clocks.passWithoutMonotonic(_window);
      expect(_denial(await h.admit()), OfflinePassDenial.windowExpired);
    });

    test('J20 reboot: memory and monotonic clock gone, the journal holds',
        () async {
      final h = _Harness(android: true);
      await h.issue();
      h.store.applyLike = true;
      h.crash();
      final s = await h.grant();
      await _use(h, s, const Duration(hours: 1));
      h.clocks.passWithoutMonotonic(const Duration(minutes: 3));
      h.crash();
      await h.grant();
      expect(h.journal!.last['n'], 2);
      expect(h.journal!.last['u'] as int,
          greaterThanOrEqualTo(const Duration(hours: 1).inMilliseconds));
    });

    test('J21 a journal that cannot be read fails closed', () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      h.journal!.failRead = true;
      expect(_denial(await h.admit()), OfflinePassDenial.storageFailure);
    });

    test('J22 a checkpoint whose journal append fails ends the session',
        () async {
      final h = _Harness(android: true);
      await h.issue();
      h.restart();
      final s = await h.grant();
      h.journal!.failFlushLost = true;
      h.clocks.advance(const Duration(minutes: 2));
      expect(await s.checkpoint(), OfflinePassDenial.storageFailure);
      expect(s.isActive, isFalse);
    });
  });

  group('K. the Android journal file', () {
    late Directory support;
    setUp(() => support = Directory.systemTemp.createTempSync('bw_journal_'));
    tearDown(() => support.deleteSync(recursive: true));

    FileOfflineChargeJournal journal(
            {List<String>? log, bool failFlush = false}) =>
        FileOfflineChargeJournal(
          directory: () async => support,
          open: log == null
              ? null
              : (file, mode) async =>
                  _RecordingRaf(await file.open(mode: mode), log, failFlush),
        );

    File file() => File('${support.path}${Platform.pathSeparator}'
        '${FileOfflineChargeJournal.directoryName}${Platform.pathSeparator}'
        '${FileOfflineChargeJournal.fileName}');

    test('K1 lives in <application support>/offline_pass/', () async {
      expect(FileOfflineChargeJournal.directoryName, 'offline_pass');
      expect(FileOfflineChargeJournal.fileName, 'charge_journal_v1.log');
      await journal().create('a\n');
      expect(file().readAsStringSync(), 'a\n');
    });

    test('K2 read, create, append, truncate and delete', () async {
      final j = journal();
      expect(await j.read(), isNull);
      await j.create('a\n');
      await j.append('b\n');
      expect(await j.read(), 'a\nb\n');
      await j.truncate(2);
      expect(await j.read(), 'a\n');
      await j.create('c\n');
      expect(await j.read(), 'c\n', reason: 'create replaces');
      await j.delete();
      expect(await j.read(), isNull);
      expect(file().existsSync(), isFalse);
      await j.delete(); // nothing to delete is fine
    });

    test('K3 an append never creates a missing journal', () async {
      await expectLater(journal().append('x\n'), throwsA(anything));
      expect(file().existsSync(), isFalse);
    });

    test('K4 every write is fsynced before the call completes', () async {
      final log = <String>[];
      final j = journal(log: log);
      await j.create('a\n');
      expect(log, ['write', 'flush', 'close']);
      log.clear();
      await j.append('b\n');
      expect(log, ['write', 'flush', 'close']);
      log.clear();
      await j.truncate(2);
      expect(log, ['truncate', 'flush', 'close']);
    });

    test('K5 a failed fsync fails the append, and the file is still closed',
        () async {
      await journal().create('a\n');
      final log = <String>[];
      await expectLater(
          journal(log: log, failFlush: true).append('b\n'), throwsA(anything));
      expect(log, ['write', 'flush', 'close']);
    });
  });
}

const _tombstone = '{"v":1,"revoked":true}';

String _bindOf(String uid, String sid, int anchorMs) => sha256
    .convert(utf8.encode('bw_offline_pass_journal_v1|$uid|$sid|$anchorMs'))
    .toString();

/// A journal line written to the specification, independently of the lease.
String _journalLine(String bind, int s, int n, int u, int h) {
  final body = {'v': 1, 'b': bind, 's': s, 'n': n, 'u': u, 'h': h};
  final c = sha256.convert(utf8.encode(jsonEncode(body))).toString();
  return '${jsonEncode({...body, 'c': c.substring(0, 16)})}\n';
}

/// Records the order of writes, fsyncs and closes on a real file.
class _RecordingRaf implements RandomAccessFile {
  _RecordingRaf(this._inner, this._log, this._failFlush);
  final RandomAccessFile _inner;
  final List<String> _log;
  final bool _failFlush;

  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) async {
    _log.add('write');
    await _inner.writeFrom(buffer, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    _log.add('flush');
    if (_failFlush) throw const FileSystemException('fsync failed');
    await _inner.flush();
    return this;
  }

  @override
  Future<RandomAccessFile> truncate(int length) async {
    _log.add('truncate');
    await _inner.truncate(length);
    return this;
  }

  @override
  Future<void> close() async {
    _log.add('close');
    await _inner.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
