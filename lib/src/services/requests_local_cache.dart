import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../data/models/ScreensModel/request_model.dart';
import '../data/models/property_status.dart';

/// Where each account's Requests-cache encryption key lives.
abstract class RequestsCacheKeyStore {
  /// The account's key, or null when it has none. Throws when the store
  /// cannot be read.
  Future<List<int>?> read(String uid);
  Future<void> write(String uid, List<int> key);
  Future<void> delete(String uid);
}

/// Keys in the platform's secure storage (Android Keystore / iOS Keychain),
/// with the same options the Supabase session uses. Never in
/// SharedPreferences, never in the app.
class SecureRequestsCacheKeyStore implements RequestsCacheKeyStore {
  const SecureRequestsCacheKeyStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  static String storageKeyFor(String uid) => 'requests_cache_key_v1_$uid';

  @override
  Future<List<int>?> read(String uid) async {
    final value = await _storage.read(key: storageKeyFor(uid));
    if (value == null) return null;
    final key = base64.decode(value);
    // A damaged key is not a key: the caller treats it as unavailable.
    if (key.length != 32) throw const FormatException('bad cache key');
    return key;
  }

  @override
  Future<void> write(String uid, List<int> key) =>
      _storage.write(key: storageKeyFor(uid), value: base64.encode(key));

  @override
  Future<void> delete(String uid) => _storage.delete(key: storageKeyFor(uid));
}

/// The last Requests list the server returned, kept on this device so the
/// Requests screen can show it when the network is unavailable.
///
/// Each account has its own Hive box, named by its Supabase user id and
/// encrypted (AES-256) with that account's own key from secure storage. A
/// list is only ever written to and read from the box of the account it
/// belongs to: rows owned by anyone else are dropped on both sides. The copy
/// is a convenience, never an authority — the server list always replaces it,
/// and nothing here decides what an account may see.
///
/// Everything fails closed: when the key cannot be read, is missing for a box
/// that already exists, or does not open the box, or the box is damaged,
/// nothing is read and nothing is written. A key is created only for a box
/// that does not exist yet, is never replaced, and nothing is ever stored
/// unencrypted.
class RequestsLocalCache {
  const RequestsLocalCache({
    RequestsCacheKeyStore keyStore = const SecureRequestsCacheKeyStore(),
  }) : _keys = keyStore;

  final RequestsCacheKeyStore _keys;

  /// Also used by tests to find an account's box.
  static String boxNameForUid(String uid) => 'cached_requests_$uid';

  static const String _listKey = 'requests_v1';

  // One operation at a time per account, so two first writes can never
  // create two keys for one box.
  static final Map<String, Future<void>> _queues = {};

  static Future<T> _oneAtATime<T>(String uid, Future<T> Function() action) {
    final previous = _queues[uid] ?? Future<void>.value();
    final run = previous.then((_) => action());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _queues[uid] = done;
    unawaited(done.whenComplete(() {
      if (identical(_queues[uid], done)) _queues.remove(uid);
    }));
    return run;
  }

  /// Opens [uid]'s box with its key. A box that does not decrypt (another
  /// key, damage) fails here and is left exactly as it is, never "repaired"
  /// by truncation.
  ///
  static Future<Box<String>> _open(String uid, List<int> key) =>
      guardedOpen(() => Hive.openBox<String>(
            boxNameForUid(uid),
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
  static Future<T> guardedOpen<T>(Future<T> Function() open) {
    final outer = Zone.current;
    final result = Completer<T>();
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

  static void _log(String what, Object error) {
    if (kDebugMode) {
      debugPrint('[RequestsCache] $what (${error.runtimeType})');
    }
  }

  /// The list last saved for [uid], or null when there is none or it cannot
  /// be read safely.
  Future<List<RequestModel>?> read(String uid) async {
    if (uid.isEmpty) return null;
    return _oneAtATime(uid, () async {
      try {
        // Reading never creates a key.
        final key = await _keys.read(uid);
        if (key == null) return null;
        final raw = (await _open(uid, key)).get(_listKey);
        if (raw == null) return null;
        final decoded = json.decode(raw);
        if (decoded is! List) return null;
        return [
          for (final row in decoded)
            if (row is Map && row['userId'] == uid)
              _decode(Map<String, dynamic>.from(row)),
        ];
      } catch (error) {
        _log('read failed', error);
        return null;
      }
    });
  }

  /// Saves [requests] as [uid]'s list, encrypted. Rows owned by another
  /// account are never saved.
  Future<void> write(String uid, List<RequestModel> requests) async {
    if (uid.isEmpty) return;
    await _oneAtATime(uid, () async {
      try {
        var key = await _keys.read(uid);
        if (key == null) {
          if (await Hive.boxExists(boxNameForUid(uid))) {
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
          for (final request in requests)
            if (request.userId == uid) _encode(request),
        ];
        await (await _open(uid, key)).put(_listKey, json.encode(rows));
      } catch (error) {
        _log('write failed', error);
      }
    });
  }

  /// Removes [uid]'s saved list and its key. Used when that account is
  /// deleted.
  Future<void> forgetAccount(String uid) async {
    if (uid.isEmpty) return;
    await _oneAtATime(uid, () async {
      try {
        await Hive.deleteBoxFromDisk(boxNameForUid(uid));
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

  static Map<String, Object?> _encode(RequestModel r) => {
        'id': r.id,
        'userId': r.userId,
        'requestType': r.requestType,
        'selectedCity': r.selectedCity,
        'selectedAreas': r.selectedAreas,
        'location': r.location,
        'phoneNumber': r.phoneNumber,
        'countryCode': r.countryCode,
        'minPrice': r.minPrice,
        'maxPrice': r.maxPrice,
        'squareFootage': r.squareFootage,
        'notes': r.notes,
        'propertyType': r.propertyType,
        'specificPropertyType': r.specificPropertyType,
        'rooms': r.rooms,
        'bathrooms': r.bathrooms,
        'status': r.status.toFirestoreString(),
        'createdAt': r.createdAt.toUtc().toIso8601String(),
        'updatedAt': r.updatedAt.toUtc().toIso8601String(),
      };

  static RequestModel _decode(Map<String, dynamic> m) => RequestModel(
        id: m['id'] as String?,
        userId: m['userId'] as String,
        requestType: m['requestType'] as String,
        selectedCity: m['selectedCity'] as String,
        selectedAreas: List<String>.from(m['selectedAreas'] as List),
        location: m['location'] as String,
        phoneNumber: m['phoneNumber'] as String,
        countryCode: m['countryCode'] as String,
        minPrice: m['minPrice'] as String,
        maxPrice: m['maxPrice'] as String,
        squareFootage: m['squareFootage'] as String,
        notes: m['notes'] as String,
        propertyType: m['propertyType'] as String?,
        specificPropertyType: m['specificPropertyType'] as String,
        rooms: m['rooms'] as int,
        bathrooms: m['bathrooms'] as int,
        status: PropertyStatus.fromString(m['status'] as String),
        createdAt: DateTime.parse(m['createdAt'] as String).toLocal(),
        updatedAt: DateTime.parse(m['updatedAt'] as String).toLocal(),
      );
}
