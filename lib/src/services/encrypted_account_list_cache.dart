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
  })  : _keys = keyStore,
        _encode = encode,
        _decode = decode,
        _ownerOf = ownerOf;

  final String boxPrefix;
  final String listKey;

  /// A fixed name for debug lines; never user data.
  final String logName;

  final AccountCacheKeyStore _keys;
  final Map<String, Object?> Function(T) _encode;
  final T Function(Map<String, dynamic>) _decode;
  final String Function(T) _ownerOf;

  String boxNameOf(String uid) => '$boxPrefix$uid';

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

  String get _v2Key => listKey.endsWith('_v1')
      ? '${listKey.substring(0, listKey.length - 3)}_v2'
      : '${listKey}_v2';

  static final List<int> _macLabel =
      utf8.encode('broker_wallet/offline_lists/v2/mac');

  /// The tag key: HMAC-SHA256 of a fixed label under the box key (a one-block
  /// PRF key derivation), so the box key is never used as the MAC key.
  static List<int> _macKey(List<int> boxKey) =>
      Hmac(sha256, boxKey).convert(_macLabel).bytes;

  /// Exactly what the tag covers. Every part is length-prefixed, so no two
  /// different inputs encode the same bytes.
  List<int> _tagged(String uid, List<int> payload) {
    final out = BytesBuilder(copy: false);
    void part(List<int> bytes) {
      out
        ..add((ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List())
        ..add(bytes);
    }

    part(utf8.encode('bw-offline-list'));
    part(utf8.encode('2'));
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
  String? _verify(String uid, List<int> boxKey, Object? sealed) {
    if (sealed is! String) return null;
    try {
      final decoded = json.decode(sealed);
      if (decoded is! Map || decoded.length != 3 || decoded['v'] != 2) {
        return null;
      }
      final payload = decoded['p'];
      final tag = decoded['t'];
      if (payload is! String || tag is! String) return null;
      return _sameTag(base64Url.decode(tag), _tag(uid, boxKey, payload))
          ? payload
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
  /// back as authentic, removes the earlier untagged list from the box.
  Future<bool> _store(
    Box<String> box,
    String uid,
    List<int> boxKey,
    String payload,
  ) async {
    await box.put(_v2Key, _seal(uid, boxKey, payload));
    if (_verify(uid, boxKey, box.get(_v2Key)) != payload) return false;
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
  Future<List<T>?> read(String uid) async {
    if (uid.isEmpty) return null;
    return _oneAtATime(boxNameOf(uid), () async {
      try {
        final dir = await _prepare(uid);
        // Reading never creates a key, never tags and never recovers.
        final key = await _keys.read(uid);
        if (key == null) return null;
        final box = await _open(uid, key, dir);
        final sealed = box.get(_v2Key);
        if (sealed != null) {
          final payload = _verify(uid, key, sealed);
          if (payload == null) {
            _log('integrity check failed', StateError('list not authentic'));
            return null;
          }
          return _items(uid, payload);
        }
        final earlier = box.get(listKey);
        return earlier == null ? null : _items(uid, earlier);
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
  Future<void> write(
    String uid,
    List<T> items, {
    bool Function()? mayRecover,
  }) async {
    if (uid.isEmpty) return;
    await _oneAtATime(boxNameOf(uid), () async {
      try {
        final dir = await _prepare(uid);
        final value = json.encode([
          for (final item in items)
            if (_ownerOf(item) == uid) _encode(item),
        ]);
        var key = await _keys.read(uid);
        if (key == null) {
          if (await Hive.boxExists(boxNameOf(uid), path: dir)) {
            await _recover(uid, dir, value, mayRecover, null);
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
          await _recover(uid, dir, value, mayRecover, key);
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
        if (!await _store(box, uid, key, value)) {
          _log('write not verified', StateError('list not authentic'));
        }
      } catch (error) {
        _log('write failed', error);
      }
    });
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
        await _store(await _open(uid, keyNow, dir), uid, keyNow, value);
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
/// while the copy is read never asks the server. Each server list is one
/// complete read, so an empty list is saved as empty.
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

  bool stillTheAccount() => uid != null && currentUserId() == uid;

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

  void listenToServer() {
    if (cancelled) return;
    if (uid != null && !stillTheAccount()) {
      stop();
      return;
    }
    inFlight = true;
    answered = false;
    lastStart = now();
    subscription = server().listen(
      (items) {
        inFlight = false;
        answered = true;
        if (uid == null) {
          controller.add(items);
          return;
        }
        if (!stillTheAccount()) {
          stop(); // a list read for the account that has gone
          return;
        }
        failed = false;
        retries = 0;
        lastSuccess = now();
        errorShown = false;
        final shown = cache.fingerprintOf(items);
        if (shown != lastShown) {
          lastShown = shown;
          controller.add(items);
        }
        // This list is a successful server read for the signed-in account:
        // the one case in which an unreadable box may be recovered.
        unawaited(cache.write(uid!, items, mayRecover: stillTheAccount));
      },
      onError: (Object error, StackTrace stackTrace) {
        inFlight = false;
        if (uid == null) {
          controller.addError(error, stackTrace);
          return;
        }
        if (!stillTheAccount()) {
          stop();
          return;
        }
        failed = true;
        if (!errorShown) {
          errorShown = true;
          controller.addError(error, stackTrace);
        }
        if (isRetryableListError(error)) {
          scheduleRetry();
        } else {
          stop();
        }
      },
      onDone: () {
        inFlight = false;
        // As before: with no account, or once the source has answered and
        // ended, the screen's list ends too. A signed-in list whose read
        // failed stays open for the next read.
        if (uid == null || answered) unawaited(controller.close());
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
    final saved = await cache.read(uid!);
    if (cancelled) return;
    if (saved != null && stillTheAccount()) {
      lastShown = cache.fingerprintOf(saved);
      controller.add(saved);
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
