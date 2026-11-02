import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

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
/// Everything fails closed: when the key cannot be read, is missing for a box
/// that already exists, or does not open the box, or the box is damaged,
/// nothing is read and nothing is written. A key is created only for a box
/// that does not exist yet, is never replaced, and nothing is ever stored
/// unencrypted. An unreadable box is never deleted or regenerated here.
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

  /// Opens [uid]'s box with its key. A box that does not decrypt (another
  /// key, damage) fails here and is left exactly as it is, never "repaired"
  /// by truncation.
  Future<Box<String>> _open(String uid, List<int> key) =>
      guardedOpen(() => Hive.openBox<String>(
            boxNameOf(uid),
            encryptionCipher: HiveAesCipher(key),
            crashRecovery: false,
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

  /// The list last saved for [uid], or null when there is none or it cannot
  /// be read safely.
  Future<List<T>?> read(String uid) async {
    if (uid.isEmpty) return null;
    return _oneAtATime(boxNameOf(uid), () async {
      try {
        // Reading never creates a key.
        final key = await _keys.read(uid);
        if (key == null) return null;
        final raw = (await _open(uid, key)).get(listKey);
        if (raw == null) return null;
        final decoded = json.decode(raw);
        if (decoded is! List) return null;
        final items = <T>[];
        for (final row in decoded) {
          if (row is! Map) continue;
          final item = _decode(Map<String, dynamic>.from(row));
          if (_ownerOf(item) == uid) items.add(item);
        }
        return items;
      } catch (error) {
        _log('read failed', error);
        return null;
      }
    });
  }

  /// Saves [items] as [uid]'s list, encrypted. Records owned by another
  /// account are never saved.
  Future<void> write(String uid, List<T> items) async {
    if (uid.isEmpty) return;
    await _oneAtATime(boxNameOf(uid), () async {
      try {
        var key = await _keys.read(uid);
        if (key == null) {
          if (await Hive.boxExists(boxNameOf(uid))) {
            // Its key is gone: the box stays as it is and nothing is written.
            _log('write skipped', StateError('box without key'));
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
        final rows = [
          for (final item in items)
            if (_ownerOf(item) == uid) _encode(item),
        ];
        await (await _open(uid, key)).put(listKey, json.encode(rows));
      } catch (error) {
        _log('write failed', error);
      }
    });
  }

  /// Removes [uid]'s saved list and its key. Used when that account is
  /// deleted.
  Future<void> forgetAccount(String uid) async {
    if (uid.isEmpty) return;
    await _oneAtATime(boxNameOf(uid), () async {
      try {
        await Hive.deleteBoxFromDisk(boxNameOf(uid));
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

/// A screen's list: the signed-in account's saved copy at once (when there is
/// one), then the server's list, which replaces it and is saved for next time.
///
/// The saved copy is only ever this account's own. A server failure is passed
/// on as before; a screen that already shows the saved copy keeps it. Nothing
/// is saved for an account that is no longer signed in, and a screen closed
/// while the copy is read never asks the server. Each server list is one
/// complete read, so an empty list is saved as empty.
Stream<List<T>> localFirstList<T>({
  required Stream<List<T>> Function() server,
  required EncryptedAccountListCache<T> cache,
  required String? Function() currentUserId,
}) {
  late final StreamController<List<T>> controller;
  StreamSubscription<List<T>>? subscription;
  var cancelled = false;

  void listenToServer(String? uid) {
    if (cancelled) return;
    subscription = server().listen(
      (items) {
        controller.add(items);
        if (uid != null && currentUserId() == uid) {
          unawaited(cache.write(uid, items));
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );
  }

  Future<void> showSavedThenListen(String uid) async {
    final saved = await cache.read(uid);
    if (cancelled) return;
    if (saved != null && currentUserId() == uid) controller.add(saved);
    listenToServer(uid);
  }

  controller = StreamController<List<T>>(
    onListen: () {
      final uid = currentUserId();
      if (uid == null) {
        listenToServer(null);
      } else {
        unawaited(showSavedThenListen(uid));
      }
    },
    onCancel: () {
      cancelled = true;
      return subscription?.cancel();
    },
  );
  return controller.stream;
}
