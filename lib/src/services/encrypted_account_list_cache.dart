import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'list_refresh_signals.dart';
import 'list_session_check.dart';

/// Where each account's cache encryption key lives.
abstract class AccountCacheKeyStore {
  /// The account's key, or null when it has none. Throws when the store
  /// cannot be read.
  Future<List<int>?> read(String uid);
  Future<void> write(String uid, List<int> key);
  Future<void> delete(String uid);
}

/// Keys in the platform's secure storage (Android Keystore / iOS Keychain),
/// with the same options the Supabase session uses. Never in
/// SharedPreferences, never in the app. [prefix] names one kind of cache.
class SecureAccountCacheKeyStore implements AccountCacheKeyStore {
  const SecureAccountCacheKeyStore({
    required this.prefix,
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  }) : _storage = storage;

  final String prefix;
  final FlutterSecureStorage _storage;

  String keyNameFor(String uid) => '$prefix$uid';

  @override
  Future<List<int>?> read(String uid) async {
    final value = await _storage.read(key: keyNameFor(uid));
    if (value == null) return null;
    final key = base64.decode(value);
    // A damaged key is not a key: the caller treats it as unavailable.
    if (key.length != 32) throw const FormatException('bad cache key');
    return key;
  }

  @override
  Future<void> write(String uid, List<int> key) =>
      _storage.write(key: keyNameFor(uid), value: base64.encode(key));

  @override
  Future<void> delete(String uid) => _storage.delete(key: keyNameFor(uid));
}

/// Whether a list holds every record the account has on the server.
///
/// The six list reads ask for all of an account's rows with no count and no
/// paging, and the server may cap how many rows one read returns, so a list
/// is never known to be complete. A later version that can prove it would
/// add a value here; until then every list is [unknown].
enum ListCompleteness { unknown }

/// What is known about a saved list. Local, indicative information only:
/// it never grants access, and nothing decides what an account may see
/// from it.
@immutable
class SavedListInfo {
  const SavedListInfo({
    required this.authenticated,
    this.serverReadAt,
    this.hidesConfirmedDeletions = false,
  });

  /// Records the server confirmed deleted were left out of the list. The
  /// list's time is still that of the server list it came from.
  final bool hidesConfirmedDeletions;

  /// True for an authenticated (v2) list; false for an earlier untagged (v1)
  /// list, which is shown only until the first server list replaces it.
  final bool authenticated;

  /// When the server last returned this exact list for this account, by this
  /// device's clock (UTC). Null when that is not known: an earlier list, a
  /// list saved before this was recorded, or a record that does not match
  /// the list or fails its check.
  final DateTime? serverReadAt;

  ListCompleteness get completeness => ListCompleteness.unknown;

  /// How long ago [serverReadAt] was at [now]; null when it is not known or
  /// lies after [now] (the clock was set back), so no age is made up.
  Duration? ageAt(DateTime now) {
    final at = serverReadAt;
    if (at == null) return null;
    final age = now.toUtc().difference(at);
    return age.isNegative ? null : age;
  }
}

/// A saved list and what is known about it.
@immutable
class SavedList<T> {
  const SavedList(this.items, this.info);
  final List<T> items;
  final SavedListInfo info;
}

/// What a signed-in account's list screen is showing.
enum LocalListSource {
  /// No list yet: no saved copy, and no server list so far.
  nothing,

  /// The copy saved on this device; the server has not answered since.
  savedCopy,

  /// A list the server returned during this screen's life. An empty one is
  /// the server's authoritative answer, not a missing copy.
  server,
}

/// Internal status of a signed-in account's list (see `localFirstList`).
/// Not shown on screen; nothing decides access from it.
@immutable
class LocalListStatus {
  const LocalListStatus({
    required this.showing,
    required this.refreshing,
    required this.lastReadFailed,
    this.lastServerReadAt,
  });

  final LocalListSource showing;

  /// A server read is in flight.
  final bool refreshing;

  /// The last server read failed; whatever is shown stays as it was.
  final bool lastReadFailed;

  /// When the list shown came from the server, by this device's clock (UTC):
  /// this screen's own last successful read, or the saved copy's
  /// [SavedListInfo.serverReadAt]. Null when not known.
  final DateTime? lastServerReadAt;

  ListCompleteness get completeness => ListCompleteness.unknown;
}

/// The last list of one kind of record the server returned for an account,
/// kept on this device so its screen can show it when the network is
/// unavailable.
///
/// Each account has its own Hive box (`<boxPrefix><Supabase user id>`),
/// encrypted (AES-256) with that account's own key from secure storage. A
/// list is only ever written to and read from the box of the account it
/// belongs to: records owned by anyone else are dropped on both sides. The
/// copy is a convenience, never an authority — the server list always
/// replaces it, and nothing here decides what an account may see.
///
/// The boxes live in their own directory, [directoryName], under the app's
/// documents directory, which Android backup and device transfer exclude: a
/// box restored without its key could never be read. A box an earlier version
/// kept directly in the documents directory is moved there on first use.
///
/// Everything fails closed: when the key cannot be read, is missing for a box
/// that already exists, or does not open the box, or the box is damaged,
/// nothing is read and nothing is written. A key is created only for a box
/// that does not exist yet, and nothing is ever stored unencrypted. An
/// unreadable box is replaced only by the verified recovery in [write], never
/// on a read, never because storage was briefly unavailable, and never for
/// another account.
class EncryptedAccountListCache<T> {
  const EncryptedAccountListCache({
    required this.boxPrefix,
    required this.listKey,
    required this.logName,
    required AccountCacheKeyStore keyStore,
    required Map<String, Object?> Function(T) encode,
    required T Function(Map<String, dynamic>) decode,
    required String Function(T) ownerOf,
    required String? Function(T) idOf,
  })  : _keys = keyStore,
        _encode = encode,
        _decode = decode,
        _ownerOf = ownerOf,
        _idOf = idOf;

  final String boxPrefix;
  final String listKey;

  /// A fixed name for debug lines; never user data.
  final String logName;

  final AccountCacheKeyStore _keys;
  final Map<String, Object?> Function(T) _encode;
  final T Function(Map<String, dynamic>) _decode;
  final String Function(T) _ownerOf;
  final String? Function(T) _idOf;

  String boxNameOf(String uid) => '$boxPrefix$uid';

  /// How many confirmed deletions are remembered per list and account.
  static const int defaultMaxConfirmedDeletions = 1000;

  /// [defaultMaxConfirmedDeletions]; tests lower it.
  @visibleForTesting
  static int maxConfirmedDeletions = defaultMaxConfirmedDeletions;

  /// Forgets everything this process keeps in memory, as a restart does.
  @visibleForTesting
  static void debugForgetProcessState() {
    _thisRun.clear();
    _stored.clear();
    _blocked.clear();
  }

  /// Remembers that the server confirmed deleting [id] from [uid]'s list
  /// (call only after that confirmation; see [deleteThenRemember]).
  ///
  /// The deletion counts at once for this run — a save of a server list that
  /// still holds it is refused, and it is left out of what is shown — and is
  /// stored as an authenticated marker in [uid]'s box when there is a box to
  /// store it in (with no saved list there is nothing to hide later).
  ///
  /// No marker is ever dropped. When [maxConfirmedDeletions] are stored, a
  /// saved list that holds [id] is removed instead, so it is never shown;
  /// this run will not save it back, and the next server list replaces it.
  /// Markers that cannot be read are left exactly as they are and the list
  /// is blocked ([isIntegrityBlocked]).
  Future<void> rememberConfirmedDeletion(String uid, String id) async {
    if (uid.isEmpty || id.isEmpty) return;
    final name = boxNameOf(uid);
    (_thisRun[name] ??= <String>{}).add(id);
    await _oneAtATime(name, () async {
      try {
        final dir = await _prepare(uid);
        final key = await _keys.read(uid);
        if (key == null || !await Hive.boxExists(name, path: dir)) return;
        final box = await _open(uid, key, dir);
        final stored = _deletedIds(uid, key, box.get(_deletedKey));
        if (stored == null) {
          _block(uid); // never replaced: this run keeps the deletion in memory
          return;
        }
        if (stored.contains(id)) return;
        if (stored.length >= maxConfirmedDeletions) {
          if (_savedCopyHolds(box, uid, key, id)) {
            await _dropSavedCopy(box);
            _log('saved list removed', StateError('marker limit reached'));
          } else {
            _log('deletion not stored', StateError('marker limit reached'));
          }
          return;
        }
        await _putMarkers(box, uid, key, {...stored, id});
      } catch (error) {
        _log('marking failed', error);
      }
    });
  }

  /// The directory, under the app's documents directory, that holds every
  /// offline list. Android backup and device transfer exclude it.
  static const String directoryName = 'offline_lists';

  /// Inside [directoryName]: where a replacement is built during recovery.
  static const String recoveryDirectoryName = '.recovery';

  /// The app's documents directory; tests point it at a temporary one.
  @visibleForTesting
  static String? debugStorageRoot;

  static Future<String> _root() async =>
      debugStorageRoot ?? (await getApplicationDocumentsDirectory()).path;

  // Hive keeps box files under the lower-cased box name.
  String _fileName(String uid) => '${boxNameOf(uid).toLowerCase()}.hive';
  String _lockName(String uid) => '${boxNameOf(uid).toLowerCase()}.lock';

  static Future<bool> _sameBytes(File a, File b) async =>
      listEquals(await a.readAsBytes(), await b.readAsBytes());

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  /// Renames [file]. Hive closes a box whose open failed without waiting, so
  /// on some platforms its file stays locked for a moment: a few short
  /// retries, then the error.
  static Future<File> _rename(File file, String to) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await file.rename(to);
      } on FileSystemException {
        if (attempt >= 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  /// The lists directory, ready for [uid]'s box, which is moved there from
  /// where an earlier version kept it if it is still there.
  Future<String> _prepare(String uid) async {
    final root = await _root();
    final dir = p.join(root, directoryName);
    await Directory(dir).create(recursive: true);
    await _moveEarlierBox(uid, root, dir);
    return dir;
  }

  /// Moves [uid]'s box from the documents directory into [dir], untouched:
  /// same name, same key, same bytes. An open box is never moved. The old
  /// file is removed only once an identical copy is in place; a copy that is
  /// not identical is discarded and the old file stays where it is. An
  /// interrupted move is finished, or started again, on the next use.
  Future<void> _moveEarlierBox(String uid, String root, String dir) async {
    final earlier = File(p.join(root, _fileName(uid)));
    if (!await earlier.exists()) return;
    if (Hive.isBoxOpen(boxNameOf(uid))) return;
    final moved = File(p.join(dir, _fileName(uid)));
    if (!await moved.exists()) {
      final copying = File('${moved.path}.moving');
      await earlier.copy(copying.path);
      if (!await _sameBytes(earlier, copying)) {
        await copying.delete();
        _log('move skipped', StateError('copy differs'));
        return;
      }
      await _rename(copying, moved.path);
    }
    if (await _sameBytes(earlier, moved)) {
      await earlier.delete();
      await _deleteIfExists(File(p.join(root, _lockName(uid))));
    } else {
      // Only after an interrupted move and a later write: the moved box is
      // the current one, and the earlier copy is left untouched.
      _log('earlier copy kept', StateError('differs from moved box'));
    }
  }

  // One operation at a time per box, so two first writes can never create
  // two keys for one box.
  static final Map<String, Future<void>> _queues = {};

  static Future<R> _oneAtATime<R>(String box, Future<R> Function() action) {
    final previous = _queues[box] ?? Future<void>.value();
    final run = previous.then((_) => action());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _queues[box] = done;
    unawaited(done.whenComplete(() {
      if (identical(_queues[box], done)) _queues.remove(box);
    }));
    return run;
  }

  /// Opens [uid]'s box in [dir] with its key. A box that does not decrypt
  /// (another key, damage) fails here with a [HiveError] and is left exactly
  /// as it is, never "repaired" by truncation.
  Future<Box<String>> _open(String uid, List<int> key, String dir) =>
      guardedOpen(() => Hive.openBox<String>(
            boxNameOf(uid),
            encryptionCipher: HiveAesCipher(key),
            crashRecovery: false,
            path: dir,
          ));

  /// Runs [open] and returns its result or its error.
  ///
  /// Hive 2.2.3 reports a failed open twice: it throws the error to the
  /// caller, and also fails an internal completer nobody listens to, which
  /// surfaces the very same error object as an unhandled error. Exactly that
  /// one duplicate — identical to the error [open] threw, whichever arrives
  /// first — is dropped. Every other unhandled error raised in this zone,
  /// during the open or at any time after it, is passed on unchanged to the
  /// zone that called this.
  @visibleForTesting
  static Future<R> guardedOpen<R>(Future<R> Function() open) {
    final outer = Zone.current;
    final result = Completer<R>();
    final beforeResult = <(Object, StackTrace)>[];
    Object? thrown;
    var duplicateDropped = false;

    bool isDuplicate(Object error) {
      if (duplicateDropped || thrown == null || !identical(error, thrown)) {
        return false;
      }
      duplicateDropped = true;
      return true;
    }

    runZonedGuarded(() async {
      try {
        result.complete(await open());
      } catch (error, stackTrace) {
        thrown = error;
        result.completeError(error, stackTrace);
      }
      // Errors that came before the result: only now can a duplicate be told
      // apart from anything else.
      for (final (error, stackTrace) in beforeResult) {
        if (!isDuplicate(error)) outer.handleUncaughtError(error, stackTrace);
      }
      beforeResult.clear();
    }, (error, stackTrace) {
      if (!result.isCompleted) {
        beforeResult.add((error, stackTrace));
      } else if (!isDuplicate(error)) {
        outer.handleUncaughtError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _log(String what, Object error) {
    if (kDebugMode) {
      debugPrint('[$logName] $what (${error.runtimeType})');
    }
  }

  // ---------------------------------------------------------------------
  // Authenticated lists (v2)
  //
  // A list is stored as {"v":2,"p":<list JSON>,"t":<HMAC-SHA256 tag>} under
  // [_v2Key], inside the encrypted box. The tag covers, each part
  // length-prefixed, a fixed label, the format version, this list's name
  // ([listKey]), the account and the exact payload bytes; its key is derived
  // from the account's box key, never the box key itself. This authenticates
  // the list inside the encrypted box. It is not AES-GCM and not an
  // encrypt-then-MAC of the whole file (Hive's AES-CBC frames stay as they
  // are), and it cannot tell an older, once-valid copy of the same list from
  // the current one.
  //
  // The earlier, untagged list under [listKey] (v1) is read only while no
  // v2 list exists, is never re-tagged, and is removed once a v2 list written
  // from a server list reads back as authentic.
  // ---------------------------------------------------------------------

  String get _baseKey => listKey.endsWith('_v1')
      ? listKey.substring(0, listKey.length - 3)
      : listKey;

  String get _v2Key => '${_baseKey}_v2';

  // ---------------------------------------------------------------------
  // When the server last returned the saved list (sync record, v1)
  //
  // Stored beside the v2 list, in the same encrypted box, under [_syncKey]
  // as {"v":1,"p":<record JSON>,"t":<HMAC-SHA256 tag>}. The tag uses the
  // list's tag key with its own label, so a record and a list can never be
  // taken for each other. The record names the tag of the exact v2 list it
  // describes: once the list changes, an old record no longer matches it and
  // the time is unknown, never carried over. Earlier versions ignore the
  // key; a missing or invalid record only makes the time unknown and never
  // affects whether the list is read.
  // ---------------------------------------------------------------------

  String get _syncKey => '${_baseKey}_sync_v1';

  static const String _syncLabel = 'bw-offline-list-sync';

  List<int> _syncTag(String uid, List<int> boxKey, String record) {
    final input =
        _tagged(uid, utf8.encode(record), label: _syncLabel, version: '1');
    return Hmac(sha256, _macKey(boxKey)).convert(input).bytes;
  }

  String _sealSync(
    String uid,
    List<int> boxKey,
    String listTag,
    DateTime serverReadAt,
  ) {
    final record = json.encode({
      'serverReadAt': serverReadAt.toUtc().toIso8601String(),
      // Written for later versions; this one always reads it as unknown.
      'completeness': 'unknown',
      'list': listTag,
    });
    return json.encode({
      'v': 1,
      'p': record,
      't': base64Url.encode(_syncTag(uid, boxKey, record)),
    });
  }

  /// The time in [sealed] once its tag has matched and it names [listTag];
  /// null otherwise.
  DateTime? _syncedAt(
      String uid, List<int> boxKey, Object? sealed, String listTag) {
    if (sealed is! String) return null;
    try {
      final decoded = json.decode(sealed);
      if (decoded is! Map || decoded.length != 3 || decoded['v'] != 1) {
        return null;
      }
      final record = decoded['p'];
      final tag = decoded['t'];
      if (record is! String || tag is! String) return null;
      if (!_sameTag(base64Url.decode(tag), _syncTag(uid, boxKey, record))) {
        return null;
      }
      final fields = json.decode(record);
      if (fields is! Map || fields['list'] != listTag) return null;
      final at = fields['serverReadAt'];
      final parsed = at is String ? DateTime.tryParse(at) : null;
      return parsed != null && parsed.isUtc ? parsed : null;
    } on FormatException {
      return null;
    }
  }

  static final List<int> _macLabel =
      utf8.encode('broker_wallet/offline_lists/v2/mac');

  /// The tag key: HMAC-SHA256 of a fixed label under the box key (a one-block
  /// PRF key derivation), so the box key is never used as the MAC key.
  static List<int> _macKey(List<int> boxKey) =>
      Hmac(sha256, boxKey).convert(_macLabel).bytes;

  /// Exactly what the tag covers. Every part is length-prefixed, so no two
  /// different inputs encode the same bytes.
  List<int> _tagged(
    String uid,
    List<int> payload, {
    String label = 'bw-offline-list',
    String version = '2',
  }) {
    final out = BytesBuilder(copy: false);
    void part(List<int> bytes) {
      out
        ..add((ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List())
        ..add(bytes);
    }

    part(utf8.encode(label));
    part(utf8.encode(version));
    part(utf8.encode(listKey));
    part(utf8.encode(uid));
    part(payload);
    return out.takeBytes();
  }

  List<int> _tag(String uid, List<int> boxKey, String payload) =>
      Hmac(sha256, _macKey(boxKey))
          .convert(_tagged(uid, utf8.encode(payload)))
          .bytes;

  String _seal(String uid, List<int> boxKey, String payload) => json.encode({
        'v': 2,
        'p': payload,
        't': base64Url.encode(_tag(uid, boxKey, payload)),
      });

  /// The payload of [sealed] once its whole tag has matched, or null when it
  /// is missing, malformed, or does not match this account and list.
  String? _verify(String uid, List<int> boxKey, Object? sealed) =>
      _verified(uid, boxKey, sealed)?.payload;

  /// As [_verify], with the matched tag in its canonical encoding.
  ({String payload, String tag})? _verified(
      String uid, List<int> boxKey, Object? sealed) {
    if (sealed is! String) return null;
    try {
      final decoded = json.decode(sealed);
      if (decoded is! Map || decoded.length != 3 || decoded['v'] != 2) {
        return null;
      }
      final payload = decoded['p'];
      final tag = decoded['t'];
      if (payload is! String || tag is! String) return null;
      final expected = _tag(uid, boxKey, payload);
      return _sameTag(base64Url.decode(tag), expected)
          ? (payload: payload, tag: base64Url.encode(expected))
          : null;
    } on FormatException {
      return null;
    }
  }

  /// Compares every byte whatever the first difference, so the time taken
  /// does not tell how much of a tag was right.
  static bool _sameTag(List<int> given, List<int> expected) {
    if (given.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= given[i] ^ expected[i];
    }
    return difference == 0;
  }

  /// The stored form of [items], to tell whether two lists differ.
  String fingerprintOf(List<T> items) =>
      json.encode([for (final item in items) _encode(item)]);

  /// [uid]'s records in [payload]; anyone else's are dropped.
  List<T>? _items(String uid, String payload) {
    final decoded = json.decode(payload);
    if (decoded is! List) return null;
    final items = <T>[];
    for (final row in decoded) {
      if (row is! Map) continue;
      final item = _decode(Map<String, dynamic>.from(row));
      if (_ownerOf(item) == uid) items.add(item);
    }
    return items;
  }

  /// Saves [payload] as [uid]'s authenticated list and, only once it reads
  /// back as authentic, records [serverReadAt] for it (when given) and
  /// removes the earlier untagged list from the box.
  Future<bool> _store(
    Box<String> box,
    String uid,
    List<int> boxKey,
    String payload,
    DateTime? serverReadAt,
  ) async {
    await box.put(_v2Key, _seal(uid, boxKey, payload));
    final stored = _verified(uid, boxKey, box.get(_v2Key));
    if (stored == null || stored.payload != payload) return false;
    if (serverReadAt != null) {
      await box.put(_syncKey, _sealSync(uid, boxKey, stored.tag, serverReadAt));
    }
    if (box.containsKey(listKey)) {
      await box.delete(listKey);
      await box.compact();
    }
    return true;
  }

  /// The list last saved for [uid], or null when there is none or it cannot
  /// be read safely.
  ///
  /// An authenticated (v2) list is returned only after its tag matched; one
  /// that does not match reads as nothing — never as the earlier list. The
  /// earlier untagged list is read only while no v2 list exists.
  Future<List<T>?> read(String uid) async => (await readSaved(uid))?.items;

  /// Whether [uid] has a box of this list on this device, readable or not —
  /// including one a recovery cut off between its two renames left only in
  /// [recoveryDirectoryName]. Creates, moves and opens nothing. True when
  /// that cannot be found out, so a caller choosing between this copy and an
  /// older one never takes the older one because storage was briefly
  /// unavailable.
  Future<bool> hasSavedBox(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final dir = p.join(await _root(), directoryName);
      if (await Hive.boxExists(boxNameOf(uid), path: dir)) return true;
      final spare = p.join(dir, recoveryDirectoryName);
      for (final name in [_fileName(uid), '${_fileName(uid)}.unreadable']) {
        if (await File(p.join(spare, name)).exists()) return true;
      }
      return false;
    } catch (error) {
      _log('box check failed', error);
      return true;
    }
  }

  /// As [read], with what is known about the list (see [SavedListInfo]).
  /// Null means there is no saved list, or none that can be read safely —
  /// never the same as a saved empty list.
  Future<SavedList<T>?> readSaved(String uid) async {
    if (uid.isEmpty) return null;
    return _oneAtATime(boxNameOf(uid), () async {
      try {
        final dir = await _prepare(uid);
        // Reading never creates a key, never tags and never recovers.
        final key = await _keys.read(uid);
        if (key == null) return null;
        final box = await _open(uid, key, dir);
        final List<T>? items;
        final bool authenticated;
        DateTime? at;
        final sealed = box.get(_v2Key);
        if (sealed != null) {
          final stored = _verified(uid, key, sealed);
          if (stored == null) {
            _log('integrity check failed', StateError('list not authentic'));
            return null;
          }
          items = _items(uid, stored.payload);
          authenticated = true;
          final record = box.get(_syncKey);
          at = _syncedAt(uid, key, record, stored.tag);
          if (record != null && at == null) {
            _log('read time unknown', StateError('sync record not used'));
          }
        } else {
          final earlier = box.get(listKey);
          items = earlier == null ? null : _items(uid, earlier);
          authenticated = false;
        }
        // Records the server confirmed deleted are never shown again. When
        // the markers cannot be trusted, the list might hold such a record:
        // it is blocked (see [isIntegrityBlocked]), with or without a copy.
        final marks = _deletedIds(uid, key, box.get(_deletedKey));
        if (marks == null) {
          _block(uid);
          return null;
        }
        _stored[boxNameOf(uid)] = marks;
        if (items == null) return null;
        final visible = withoutConfirmedDeletions(uid, items);
        return SavedList(
          visible,
          SavedListInfo(
            authenticated: authenticated,
            serverReadAt: at,
            hidesConfirmedDeletions: visible.length != items.length,
          ),
        );
      } catch (error) {
        _log('read failed', error);
        return null;
      }
    });
  }

  /// Saves [items] as [uid]'s list, encrypted. Records owned by another
  /// account are never saved.
  ///
  /// When [uid]'s box exists but cannot be read — its key is missing, or the
  /// box does not decrypt — nothing is written unless [mayRecover] says the
  /// list just came from a successful server read for [uid], still the
  /// signed-in account. Only then is the verified recovery run (see
  /// [_recover]). A key store or file error is never taken for an unreadable
  /// box.
  ///
  /// [serverReadAt] is given only for a list the server just returned for
  /// [uid]; it is recorded with that exact list (see [SavedListInfo]). A
  /// write without it leaves the list's time unknown unless the list is
  /// unchanged.
  Future<void> write(
    String uid,
    List<T> items, {
    bool Function()? mayRecover,
    DateTime? serverReadAt,
  }) async {
    if (uid.isEmpty) return;
    await _oneAtATime(boxNameOf(uid), () async {
      try {
        final dir = await _prepare(uid);
        // A list holding a record whose deletion the server confirmed during
        // this run started before that delete: it is stale, and saving it
        // would bring the record back. (Checked here, in the box's queue, so
        // a save waiting behind the confirmation sees it.)
        if (_holdsDeletedThisRun(uid, items)) {
          _log(
              'write skipped', StateError('stale: holds a confirmed deletion'));
          return;
        }
        if (isIntegrityBlocked(uid)) {
          _log('write skipped', StateError('list blocked'));
          return;
        }
        final value = json.encode([
          for (final item in items)
            if (_ownerOf(item) == uid) _encode(item),
        ]);
        var key = await _keys.read(uid);
        if (key == null) {
          if (await Hive.boxExists(boxNameOf(uid), path: dir)) {
            await _recover(uid, dir, value, mayRecover, null, serverReadAt);
            return;
          }
          final created = Hive.generateSecureKey();
          await _keys.write(uid, created);
          final stored = await _keys.read(uid);
          if (!listEquals(stored, created)) {
            _log('write skipped', StateError('key not stored'));
            return;
          }
          key = created;
        }
        final Box<String> box;
        try {
          box = await _open(uid, key, dir);
        } on HiveError {
          await _recover(uid, dir, value, mayRecover, key, serverReadAt);
          return;
        }
        // A list that fails its check is an integrity failure: it is
        // replaced only by a list the server just returned for this account.
        final existing = box.get(_v2Key);
        if (existing != null &&
            _verify(uid, key, existing) == null &&
            !(mayRecover?.call() ?? false)) {
          _log('write skipped', StateError('list not authentic'));
          return;
        }
        // Markers that cannot be read block the list: nothing is saved over
        // them, and they are left exactly as they are.
        if (_deletedIds(uid, key, box.get(_deletedKey)) == null) {
          _block(uid);
          return;
        }
        if (!await _store(box, uid, key, value, serverReadAt)) {
          _log('write not verified', StateError('list not authentic'));
        }
      } catch (error) {
        _log('write failed', error);
      }
    });
  }

  // ---------------------------------------------------------------------
  // Confirmed deletions (markers, v1)
  //
  // Stored beside the list, in the same encrypted box, under [_deletedKey]
  // as {"v":1,"p":"{\"ids\":[...]}","t":<HMAC-SHA256 tag>}. The tag uses
  // the list's tag key with its own label, covering the version, this
  // list's name, the account and the exact record, so markers can never be
  // taken for a list, a time record, another list or another account. A
  // marker only hides a record the server confirmed deleted for this
  // account (P3.1a): it grants nothing and decides no access. The saved
  // list itself stays exactly what the server returned (D-3).
  //
  // Markers are not retired: the list reads return no count, so a server
  // list may be cut short by the row cap and a record's absence proves
  // nothing. A soft delete is final (nothing clears deleted_at), so a
  // marker is never wrong, only kept. At most [maxConfirmedDeletions] are
  // stored per list and account; none is ever dropped to make room (see
  // [rememberConfirmedDeletion]).
  // ---------------------------------------------------------------------

  String get _deletedKey => '${_baseKey}_deleted_v1';

  /// Whether [uid]'s list is blocked because its markers cannot be read.
  ///
  /// Strict policy (owner decision): unreadable markers might have recorded
  /// a deletion that any server list — a lagging read among them — could
  /// still hold, so for that account and list nothing is shown, saved or
  /// marked, and the markers are never replaced, reset or removed
  /// automatically. Only Delete Account (or a separately approved recovery)
  /// clears it. Other lists and accounts are not affected.
  bool isIntegrityBlocked(String uid) => _blocked.contains(boxNameOf(uid));

  /// Boxes whose markers were found unreadable (kept for this run; the
  /// damaged record itself stays in storage, so a restart finds it again).
  static final Set<String> _blocked = {};

  void _block(String uid) {
    _blocked.add(boxNameOf(uid));
    _log('list blocked', StateError('deletion markers invalid'));
  }

  static const String _deletedLabel = 'bw-offline-list-deleted';

  /// Per box: deletions confirmed during this run, whose late answers may
  /// still arrive, and the markers last read from storage.
  static final Map<String, Set<String>> _thisRun = {};
  static final Map<String, Set<String>> _stored = {};

  List<int> _deletedTag(String uid, List<int> boxKey, String record) {
    final input =
        _tagged(uid, utf8.encode(record), label: _deletedLabel, version: '1');
    return Hmac(sha256, _macKey(boxKey)).convert(input).bytes;
  }

  String _sealDeleted(String uid, List<int> boxKey, Set<String> ids) {
    final record = json.encode({'ids': ids.toList()..sort()});
    return json.encode({
      'v': 1,
      'p': record,
      't': base64Url.encode(_deletedTag(uid, boxKey, record)),
    });
  }

  /// The ids marked in [sealed]: none when there is no record, null when
  /// there is one that is malformed or fails its check.
  Set<String>? _deletedIds(String uid, List<int> boxKey, Object? sealed) {
    if (sealed == null) return <String>{};
    if (sealed is! String) return null;
    try {
      final decoded = json.decode(sealed);
      if (decoded is! Map || decoded.length != 3 || decoded['v'] != 1) {
        return null;
      }
      final record = decoded['p'];
      final tag = decoded['t'];
      if (record is! String || tag is! String) return null;
      if (!_sameTag(base64Url.decode(tag), _deletedTag(uid, boxKey, record))) {
        return null;
      }
      final fields = json.decode(record);
      if (fields is! Map || fields.length != 1) return null;
      final ids = fields['ids'];
      if (ids is! List || ids.any((id) => id is! String || id.isEmpty)) {
        return null;
      }
      return ids.cast<String>().toSet();
    } on FormatException {
      return null;
    }
  }

  /// [items] without the records whose deletion the server confirmed for
  /// [uid] (stored, or confirmed during this run).
  List<T> withoutConfirmedDeletions(String uid, List<T> items) {
    final name = boxNameOf(uid);
    final hidden = {...?_stored[name], ...?_thisRun[name]};
    if (hidden.isEmpty) return items;
    return [
      for (final item in items)
        if (!hidden.contains(_idOf(item))) item,
    ];
  }

  bool _holdsDeletedThisRun(String uid, List<T> items) {
    final run = _thisRun[boxNameOf(uid)];
    if (run == null || run.isEmpty) return false;
    return items.any((item) => run.contains(_idOf(item)));
  }

  Future<void> _putMarkers(
      Box<String> box, String uid, List<int> key, Set<String> ids) async {
    if (ids.isEmpty) {
      await box.delete(_deletedKey);
    } else {
      await box.put(_deletedKey, _sealDeleted(uid, key, ids));
    }
    final back = _deletedIds(uid, key, box.get(_deletedKey));
    if (back == null || back.length != ids.length) {
      _log('markers not verified', StateError('read back differs'));
    }
    _stored[boxNameOf(uid)] = back ?? <String>{};
  }

  /// Removes the saved list (both formats and its time), keeping its
  /// markers: nothing is shown until the next server list.
  Future<void> _dropSavedCopy(Box<String> box) async {
    for (final key in [_v2Key, listKey, _syncKey]) {
      if (box.containsKey(key)) await box.delete(key);
    }
    await box.compact();
  }

  /// Whether the saved list may show [id]. A list that cannot be read is
  /// taken as holding it.
  bool _savedCopyHolds(Box<String> box, String uid, List<int> key, String id) {
    final sealed = box.get(_v2Key);
    final String? payload;
    if (sealed != null) {
      final stored = _verified(uid, key, sealed);
      if (stored == null) return true;
      payload = stored.payload;
    } else {
      payload = box.get(listKey);
    }
    if (payload == null) return false;
    final items = _items(uid, payload);
    return items == null || items.any((item) => _idOf(item) == id);
  }

  /// Replaces [uid]'s unreadable box with [value] under a new key — only for
  /// a list the server just returned for [uid], still signed in.
  ///
  /// The unreadable state is confirmed a second time first: the key store
  /// gives the same answer ([observedKey]: still missing, or the same key)
  /// and, with a key, the box still fails to decrypt. The replacement is
  /// built and read back in [recoveryDirectoryName] before anything else
  /// changes; the new key is stored and read back; the unreadable file is
  /// set aside, not deleted, while the replacement moves in; and it is
  /// deleted only once the box opens with the new key and holds [value]. Any
  /// failure stops the recovery with the data still encrypted.
  Future<void> _recover(
    String uid,
    String dir,
    String value,
    bool Function()? mayRecover,
    List<int>? observedKey,
    DateTime? serverReadAt,
  ) async {
    if (mayRecover == null || !mayRecover()) {
      _log('write skipped', StateError('unreadable box, no verified list'));
      return;
    }
    final name = boxNameOf(uid);
    final keyNow = await _keys.read(uid);
    if (!listEquals(keyNow, observedKey) ||
        !await Hive.boxExists(name, path: dir)) {
      _log('recovery skipped', StateError('state changed'));
      return;
    }
    if (keyNow != null) {
      try {
        // Readable after all: a passing problem, not an unreadable box.
        await _store(
            await _open(uid, keyNow, dir), uid, keyNow, value, serverReadAt);
        return;
      } on HiveError {
        // Confirmed: still does not decrypt.
      }
    }

    // The box may still be open in this process (its key vanished after it
    // was opened). Hive hands back an open box by name whatever the path or
    // key, so it is closed first — only this account's box of this list,
    // under this box's operation queue, which every read and write of it
    // goes through — and the replacement really is built beside it.
    if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();

    final spare = p.join(dir, recoveryDirectoryName);
    await Directory(spare).create(recursive: true);
    final spareFile = File(p.join(spare, _fileName(uid)));
    await _deleteIfExists(spareFile); // a replacement left by a cut-off run
    await _deleteIfExists(File(p.join(spare, _lockName(uid))));

    final fresh = Hive.generateSecureKey();
    final built = await _open(uid, fresh, spare);
    await built.put(_v2Key, _seal(uid, fresh, value));
    if (serverReadAt != null) {
      final listTag = base64Url.encode(_tag(uid, fresh, value));
      await built.put(_syncKey, _sealSync(uid, fresh, listTag, serverReadAt));
    }
    await built.close();
    final check = await _open(uid, fresh, spare);
    final builtOk = _verify(uid, fresh, check.get(_v2Key)) == value;
    await check.close();
    if (!builtOk) {
      await _deleteIfExists(spareFile);
      _log('recovery stopped', StateError('replacement not verified'));
      return;
    }

    await _keys.write(uid, fresh);
    if (!listEquals(await _keys.read(uid), fresh)) {
      await _deleteIfExists(spareFile);
      _log('recovery stopped', StateError('key not stored'));
      return;
    }

    final current = File(p.join(dir, _fileName(uid)));
    final setAside = File('${spareFile.path}.unreadable');
    await _rename(current, setAside.path);
    try {
      await _rename(spareFile, current.path);
    } catch (_) {
      await _rename(setAside, current.path);
      rethrow;
    }
    final box = await _open(uid, fresh, dir);
    if (_verify(uid, fresh, box.get(_v2Key)) != value) {
      _log('recovery stopped', StateError('swap not verified'));
      return;
    }
    await setAside.delete();
    _log('recovered', StateError('unreadable box replaced'));
  }

  /// Removes [uid]'s saved list and its key. Used when that account is
  /// deleted. Covers the lists directory, where an earlier version kept the
  /// box, and anything a recovery left; nothing else is touched.
  Future<void> forgetAccount(String uid) async {
    if (uid.isEmpty) return;
    _thisRun.remove(boxNameOf(uid));
    _stored.remove(boxNameOf(uid));
    _blocked.remove(boxNameOf(uid)); // the damaged record goes with the box
    await _oneAtATime(boxNameOf(uid), () async {
      try {
        final root = await _root();
        final dir = p.join(root, directoryName);
        final spare = p.join(dir, recoveryDirectoryName);
        await Hive.deleteBoxFromDisk(boxNameOf(uid), path: dir);
        for (final file in [
          File(p.join(root, _fileName(uid))),
          File(p.join(root, _lockName(uid))),
          File(p.join(dir, '${_fileName(uid)}.moving')),
          File(p.join(spare, _fileName(uid))),
          File(p.join(spare, _lockName(uid))),
          File(p.join(spare, '${_fileName(uid)}.unreadable')),
        ]) {
          await _deleteIfExists(file);
        }
      } catch (error) {
        _log('box removal failed', error);
      }
      try {
        await _keys.delete(uid);
      } catch (error) {
        _log('key removal failed', error);
      }
    });
  }
}

/// A list that cannot be shown: its deletion markers cannot be read, so it
/// might hold a record the server confirmed deleted (see
/// [EncryptedAccountListCache.isIntegrityBlocked]).
class ListIntegrityBlocked implements Exception {
  const ListIntegrityBlocked();

  @override
  String toString() => 'ListIntegrityBlocked';
}

/// Deletes record [id] through [delete] and, once the server has confirmed
/// it (P3.1a: [delete] returns only then, and throws otherwise), remembers
/// the deletion for the account's saved list — only for the account and
/// session the delete was made under.
Future<void> deleteThenRemember<T>({
  required EncryptedAccountListCache<T> cache,
  required String id,
  required String? Function() currentUserId,
  required Future<void> Function() delete,
  String? Function()? sessionOf,
}) async {
  final sessionNow = sessionOf ?? ListSessionCheck.currentSession;
  final uid = currentUserId();
  final session = sessionNow();
  await delete(); // throws unless the server confirmed it: nothing marked
  if (uid == null || currentUserId() != uid || sessionNow() != session) {
    return; // another account or session now: not theirs to mark
  }
  try {
    await cache.rememberConfirmedDeletion(uid, id);
  } catch (_) {
    // The delete itself succeeded; a marker that could not be kept is the
    // behaviour before markers existed.
  }
}

/// After a network failure: wait this long before each further read, then
/// stop until the next refresh hint (the app resuming).
const List<Duration> defaultListRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 45),
  Duration(minutes: 2),
];

/// Whether [error] is a network failure worth reading again for. Anything
/// else — no session, a refused or superseded session, a server error — is
/// not retried: the server decides about sessions, not the client.
bool isRetryableListError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is HttpException ||
    error is http.ClientException;

/// A screen's list: the signed-in account's saved copy at once (when there is
/// one), then the server's list, which replaces it and is saved for next time.
///
/// The saved copy is only ever this account's own. A server failure is passed
/// on as before; a screen that already shows the saved copy keeps it. Nothing
/// is saved for an account that is no longer signed in, and a screen closed
/// while the copy is read never asks the server. Each server list replaces
/// the saved one whole, so an empty list is saved as empty. Whether a server
/// list holds every record is not known ([ListCompleteness]).
///
/// For a signed-in account the list also reads again by itself, through the
/// same server read and the same encrypted save:
/// - after a network failure, at most once per entry of [retryDelays]; a
///   failed first read no longer ends the screen's list;
/// - on a [refreshSignals] hint (the app resuming, or the network coming
///   back), when the last read failed or is older than [minRefreshInterval];
///   hints closer together than [minHintGap] count once.
/// A retry or hint that comes while the app is not in the foreground
/// ([isAppActive]) reads nothing; the next resume reads instead. Once the
/// retries are used up, nothing reads again until a hint; the Internet coming
/// back without a visible network change sends none.
/// Only one read is ever in flight. Any error that is not a network failure
/// stops these extra reads. They also stop for good once the signed-in
/// account is no longer the one the list was opened for, and a read that ends
/// after that is dropped. A list identical to the one last shown is not shown
/// again, and a repeated failure is passed on once.
///
/// Each server list is saved with the time it arrived ([now], recorded with
/// that exact list; see [SavedListInfo]). That time is indicative: the
/// device clock can be wrong, and it never stands in for the server.
/// [onStatus], when given, is told what a signed-in account's screen is
/// showing ([LocalListStatus]) each time that changes; it is internal and
/// is not shown on screen.
///
/// Every answer — a list, empty or not, or a failure — belongs to the
/// session its read was made under ([sessionOf], by default
/// [ListSessionCheck.currentSession], taken as the read starts). It counts
/// only while that is still the signed-in account's session: after a
/// sign-out and a sign-in, even to the same account, a late answer is
/// dropped unseen and unsaved and the list stops. A token refresh keeps the
/// session.
///
/// An empty server list for a signed-in account is trusted only once
/// [confirmEmptyList] (by default [ListSessionCheck.confirmFor], given the
/// read's session) confirms that session is still the account's current
/// one: the database answers a
/// replaced session's reads with no rows, not with an error. Until then the
/// screen keeps what it shows. Confirmed, the empty list is shown and saved
/// as usual. Not confirmed, it is neither shown nor saved, the saved list and
/// its time stay as they are, a [ListSessionNotCurrent] is passed on and the
/// list stops (the check itself starts the usual sign-out). A check that
/// fails on the network counts as a network failure. A newer list, a closed
/// screen or another account makes the answer moot. A list with rows is
/// never checked: the database let that read through.
Stream<List<T>> localFirstList<T>({
  required Stream<List<T>> Function() server,
  required EncryptedAccountListCache<T> cache,
  required String? Function() currentUserId,
  Stream<void>? refreshSignals,
  List<Duration> retryDelays = defaultListRetryDelays,
  Duration minRefreshInterval = const Duration(seconds: 30),
  Duration minHintGap = const Duration(seconds: 2),
  DateTime Function() now = DateTime.now,
  bool Function()? isAppActive,
  void Function(LocalListStatus status)? onStatus,
  Future<bool>? Function(String? session)? confirmEmptyList,
  String? Function()? sessionOf,
}) {
  final appIsActive =
      isAppActive ?? () => ListRefreshSignals.instance.appIsActive;
  late final StreamController<List<T>> controller;
  StreamSubscription<List<T>>? subscription;
  StreamSubscription<void>? hints;
  Timer? retryTimer;
  var cancelled = false;
  String? uid;

  // Only for a signed-in account.
  var stopped = false; // the account changed, or a non-network failure
  var inFlight = false; // a read has started and not yet answered
  var answered = false; // the current read delivered a list
  var failed = false; // the last read failed
  var retries = 0;
  DateTime? lastSuccess;
  DateTime? lastStart;
  String? lastShown;
  var errorShown = false;
  var showing = LocalListSource.nothing;
  DateTime? shownServerReadAt;
  var deliveries = 0; // server lists received; the newest one counts
  var checking = false; // an empty list waits for its session check
  var closeAfterCheck = false; // the source ended during that check
  final confirmEmpty = confirmEmptyList ?? ListSessionCheck.confirmFor;
  final sessionNow = sessionOf ?? ListSessionCheck.currentSession;
  String? readSession; // the session the current read was made under

  bool stillTheAccount() => uid != null && currentUserId() == uid;

  /// The account the list was opened for, under the session the current
  /// read was made in. A sign-out and a sign-in to the same account is a new
  /// session; a token refresh is not.
  bool stillTheReader() => stillTheAccount() && sessionNow() == readSession;

  void report() {
    if (uid == null || cancelled || stopped) return;
    onStatus?.call(LocalListStatus(
      showing: showing,
      refreshing: inFlight,
      lastReadFailed: failed,
      lastServerReadAt: shownServerReadAt,
    ));
  }

  void stop() {
    stopped = true;
    retryTimer?.cancel();
    retryTimer = null;
    unawaited(hints?.cancel());
    hints = null;
  }

  late void Function() readAgain;

  void scheduleRetry() {
    if (cancelled || stopped || retryTimer != null) return;
    if (retries >= retryDelays.length) return;
    retryTimer = Timer(retryDelays[retries++], () {
      retryTimer = null;
      // In the background no read is made; the resume hint reads instead.
      if (!appIsActive()) return;
      readAgain();
    });
  }

  /// A server list for the signed-in account, trusted: shown and saved.
  void accept(List<T> items) {
    // A list whose deletion markers cannot be read shows nothing (it might
    // show a record the server confirmed deleted): one error, then stop.
    if (cache.isIntegrityBlocked(uid!)) {
      failed = true;
      report();
      if (!errorShown) {
        errorShown = true;
        controller.addError(const ListIntegrityBlocked(), StackTrace.current);
      }
      stop();
      return;
    }
    failed = false;
    retries = 0;
    final at = now();
    lastSuccess = at;
    errorShown = false;
    // Records the server confirmed deleted are not shown, even from a late
    // answer that started before the delete; the list is saved as the server
    // sent it (a stale one is not saved at all).
    final visible = cache.withoutConfirmedDeletions(uid!, items);
    final shown = cache.fingerprintOf(visible);
    if (shown != lastShown) {
      lastShown = shown;
      controller.add(visible);
    }
    showing = LocalListSource.server;
    shownServerReadAt = at.toUtc();
    report();
    // This list is a successful server read for the signed-in account:
    // the one case in which an unreadable box may be recovered.
    unawaited(
        cache.write(uid!, items, mayRecover: stillTheReader, serverReadAt: at));
  }

  /// A failed read for the signed-in account: what is shown stays.
  void fail(Object error, StackTrace stackTrace) {
    failed = true;
    report();
    if (!errorShown) {
      errorShown = true;
      controller.addError(error, stackTrace);
    }
    if (isRetryableListError(error)) {
      scheduleRetry();
    } else {
      stop();
    }
  }

  void closeIfEnded() {
    if (!closeAfterCheck || checking) return;
    closeAfterCheck = false;
    unawaited(controller.close());
  }

  /// Accepts the empty [items] once [check] confirms the session, unless a
  /// newer list, a closed screen or another account has made it moot.
  Future<void> acceptOnceConfirmed(
    List<T> items,
    int delivery,
    Future<bool> check,
  ) async {
    Object? failure;
    StackTrace? trace;
    try {
      if (!await check) failure = const ListSessionNotCurrent();
    } catch (error, stackTrace) {
      failure = error;
      trace = stackTrace;
    }
    if (delivery != deliveries) return; // a newer list took over
    checking = false;
    inFlight = false;
    if (!cancelled && !stopped) {
      if (!stillTheReader()) {
        stop(); // another account or session: the answer is not theirs
      } else if (failure == null) {
        accept(items);
      } else {
        fail(failure, trace ?? StackTrace.current);
      }
    }
    closeIfEnded();
  }

  void listenToServer() {
    if (cancelled) return;
    if (uid != null && !stillTheAccount()) {
      stop();
      return;
    }
    inFlight = true;
    answered = false;
    lastStart = now();
    readSession = sessionNow();
    report();
    subscription = server().listen(
      (items) {
        inFlight = false;
        answered = true;
        if (uid == null) {
          controller.add(items);
          return;
        }
        checking = false;
        final delivery = ++deliveries;
        if (!stillTheReader()) {
          // A list read for an account, or a session, that has gone.
          stop();
          return;
        }
        final check = items.isEmpty ? confirmEmpty(readSession) : null;
        if (check == null) {
          accept(items);
          return;
        }
        // Still refreshing until the database answers.
        inFlight = true;
        checking = true;
        unawaited(acceptOnceConfirmed(items, delivery, check));
      },
      onError: (Object error, StackTrace stackTrace) {
        inFlight = false;
        if (uid == null) {
          controller.addError(error, stackTrace);
          return;
        }
        if (!stillTheReader()) {
          stop(); // a failure of a read for an account or session gone
          return;
        }
        fail(error, stackTrace);
      },
      onDone: () {
        if (!checking) inFlight = false;
        // As before: with no account, or once the source has answered and
        // ended, the screen's list ends too — after a pending session check.
        // A signed-in list whose read failed stays open for the next read.
        if (uid == null || answered) {
          closeAfterCheck = true;
          closeIfEnded();
        }
      },
    );
  }

  readAgain = () {
    if (cancelled || stopped || inFlight) return;
    if (!stillTheAccount()) {
      stop();
      return;
    }
    final previous = subscription;
    subscription = null;
    unawaited(previous?.cancel());
    listenToServer();
  };

  void onHint(void _) {
    if (cancelled || stopped || inFlight) return;
    // A hint in the background (the network returning) reads nothing; the
    // resume that follows reads instead.
    if (!appIsActive()) return;
    final at = now();
    final started = lastStart;
    if (started != null && at.difference(started) < minHintGap) return;
    final succeeded = lastSuccess;
    if (!failed &&
        succeeded != null &&
        at.difference(succeeded) < minRefreshInterval) {
      return;
    }
    retryTimer?.cancel();
    retryTimer = null;
    retries = 0;
    readAgain();
  }

  Future<void> showSavedThenListen() async {
    final saved = await cache.readSaved(uid!);
    if (cancelled) return;
    if (cache.isIntegrityBlocked(uid!) && stillTheAccount()) {
      // Nothing to show it in: no server read, no retries, no endless
      // loading — the screen's existing load-error state.
      failed = true;
      controller.addError(const ListIntegrityBlocked(), StackTrace.current);
      stop();
      return;
    }
    if (saved != null && stillTheAccount()) {
      lastShown = cache.fingerprintOf(saved.items);
      showing = LocalListSource.savedCopy;
      shownServerReadAt = saved.info.serverReadAt;
      controller.add(saved.items);
    }
    hints =
        (refreshSignals ?? ListRefreshSignals.instance.hints).listen(onHint);
    listenToServer();
  }

  controller = StreamController<List<T>>(
    onListen: () {
      uid = currentUserId();
      if (uid == null) {
        listenToServer();
      } else {
        unawaited(showSavedThenListen());
      }
    },
    onCancel: () {
      cancelled = true;
      retryTimer?.cancel();
      retryTimer = null;
      final pending = [hints?.cancel(), subscription?.cancel()];
      hints = null;
      return Future.wait([
        for (final p in pending)
          if (p != null) p
      ]);
    },
  );
  return controller.stream;
}
