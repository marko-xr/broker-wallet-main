// P4.7c preflight (test-only probe; no production code).
//
// MEASURED on the machine running `flutter test` (desktop VM, JIT, the
// secure-storage TEST store). These numbers compare options with each other;
// they are NOT phone timings.
//
// "Longest block" = the longest gap between ticks of a 1 ms timer on this
// isolate while the operation runs: how long the UI isolate could not run a
// frame. It is the number that matters for jank; total time is the other.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/offers_local_cache.dart';
import 'package:broker_wallet/src/services/owners_local_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../search/search_fixtures.dart';

const _uid = 'u1';

List<OwnerModel> _owners(int n) => [
      for (var i = 0; i < n; i++)
        owner(
          id: 'owner-$i',
          name: 'Owner number $i',
          phone: '50${i.toString().padLeft(7, '0')}',
          typeOfProperties: 'Villa, Apartment',
          propertyLocation: 'Palm Jumeirah Frond $i',
          notes: 'Prefers calls after 6pm; keys with watchman $i',
        ),
    ];

List<OfferModel> _offers(int n) => [
      for (var i = 0; i < n; i++)
        offer(
          id: 'offer-$i',
          type: i.isEven ? 'rent' : 'sell',
          areas: const ['Dubai Marina', 'JBR'],
          location: 'Tower $i',
          phone: '55${i.toString().padLeft(7, '0')}',
          minPrice: '${100000 + i}',
          maxPrice: '${150000 + i}',
          squareFootage: '${900 + i}',
          notes: 'Sea view, high floor, chiller free, unit $i',
          propertyType: 'residential',
          specific: 'apartment',
          pickUpAddress: 'Marina Walk $i',
        ),
    ];

/// Runs [op] and reports its total time and the longest stretch during which
/// this isolate could not run a 1 ms timer.
Future<({int totalMs, int blockMs, R result})> _timed<R>(
    Future<R> Function() op) async {
  final clock = Stopwatch()..start();
  var last = 0;
  var longest = 0;
  final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = clock.elapsedMicroseconds;
    if (now - last > longest) longest = now - last;
    last = now;
  });
  // Let the ticker start before the work begins.
  await Future<void>.delayed(const Duration(milliseconds: 3));
  last = clock.elapsedMicroseconds;
  longest = 0;
  final start = clock.elapsedMicroseconds;
  final result = await op();
  final end = clock.elapsedMicroseconds;
  // One more tick, so a block that ran to the end is counted.
  await Future<void>.delayed(const Duration(milliseconds: 2));
  ticker.cancel();
  final tail = clock.elapsedMicroseconds - last;
  if (tail > longest && last < end) longest = tail;
  return (
    totalMs: (end - start) ~/ 1000,
    blockMs: longest ~/ 1000,
    result: result
  );
}

int _rssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  String listsDir() => '${tempDir.path}${Platform.pathSeparator}'
      '${EncryptedAccountListCache.directoryName}';

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('main_isolate_probe');
    Hive.init(tempDir.path);
    EncryptedAccountListCache.debugStorageRoot = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDownAll(() async {
    await Hive.close();
    EncryptedAccountListCache.debugStorageRoot = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> probe<T>(
    String label,
    EncryptedAccountListCache<T> cache,
    AccountCacheKeyStore keys,
    String boxName,
    String v2Key,
    List<T> items,
    List<T> changed,
  ) async {
    Future<void> close() async {
      if (Hive.isBoxOpen(boxName)) await Hive.box<String>(boxName).close();
      EncryptedAccountListCache.debugForgetProcessState();
    }

    await cache.write(_uid, items, serverReadAt: DateTime.now().toUtc());
    final sealed = Hive.box<String>(boxName).get(v2Key)!;
    final payload = (json.decode(sealed) as Map)['p'] as String;
    final key = (await keys.read(_uid))!;
    await close();

    // --- the whole read, as a screen does it -----------------------------
    final cold = await _timed(() => cache.readSaved(_uid));
    final warm = await _timed(() => cache.readSaved(_uid));
    final items2 = warm.result!.items;

    // --- its parts, each on its own --------------------------------------
    await close();
    final open = await _timed(() => Hive.openBox<String>(boxName,
        encryptionCipher: HiveAesCipher(key), path: listsDir()));
    final envelope = await _timed(() async => json.decode(sealed));
    final hmac = await _timed(() async =>
        Hmac(sha256, List<int>.filled(32, 7)).convert(utf8.encode(payload)));
    final decode = await _timed(() async => json.decode(payload));
    final fingerprint = await _timed(() async => cache.fingerprintOf(items2));

    // --- saves, as after a server answer --------------------------------
    final unchanged = await _timed(
        () => cache.write(_uid, items, serverReadAt: DateTime.now().toUtc()));
    final change = await _timed(
        () => cache.write(_uid, changed, serverReadAt: DateTime.now().toUtc()));
    await cache.write(_uid, items, serverReadAt: DateTime.now().toUtc());

    // --- a server answer through the screen stream, after a restart -----
    Future<({int totalMs, int blockMs, Object? result})> serverAnswer(
        List<T> list) async {
      await close();
      final server = StreamController<List<T>>();
      var shown = 0;
      final sub = localFirstList<T>(
        server: () => server.stream,
        cache: cache,
        currentUserId: () => _uid,
        refreshSignals: const Stream<void>.empty(),
        isAppActive: () => true,
        confirmEmptyList: (_) => null,
        sessionOf: () => null,
      ).listen((_) => shown++, onError: (Object _) {});
      for (var i = 0; i < 4000 && shown == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await cache.debugSettled(_uid);
      final r = await _timed(() async {
        server.add(list);
        await Future<void>.delayed(Duration.zero);
        await cache.debugSettled(_uid);
      });
      await sub.cancel();
      await server.close();
      return r;
    }

    final answerSame = await serverAnswer([...items]);
    final answerChanged = await serverAnswer(changed);
    await cache.write(_uid, items, serverReadAt: DateTime.now().toUtc());

    // --- Option A: the pure parts on a background isolate ----------------
    final spawn = await _timed(() => Isolate.run(() => 0));
    final isoDecode =
        await _timed(() => Isolate.run(() => json.decode(payload)));
    final isoDecodeHmac = await _timed(() => Isolate.run(() {
          final tag = Hmac(sha256, List<int>.filled(32, 7))
              .convert(utf8.encode(payload));
          return (tag.bytes.length, json.decode(payload));
        }));
    final isoEncode = await _timed(() => Isolate.run(() => json
        .encode((json.decode(payload) as List).cast<Map<String, dynamic>>())));
    final rssBefore = _rssMb();
    final big = await Isolate.run(() => json.decode(payload));
    final rssAfter = _rssMb();

    // --- Option C (chunked, same isolate): HMAC fed in 64 KiB pieces with a
    // yield between them; same bytes, same tag.
    final chunked = await _timed(() async {
      final bytes = utf8.encode(payload);
      final out = _DigestSink();
      final sink =
          Hmac(sha256, List<int>.filled(32, 7)).startChunkedConversion(out);
      for (var i = 0; i < bytes.length; i += 65536) {
        sink.add(bytes.sublist(i, (i + 65536).clamp(0, bytes.length)));
        await Future<void>.delayed(Duration.zero);
      }
      sink.close();
      return out.value;
    });
    final direct =
        Hmac(sha256, List<int>.filled(32, 7)).convert(utf8.encode(payload));

    expect(chunked.result.bytes, direct.bytes, reason: 'chunked = same tag');
    expect((big as List).length, items.length);
    expect(isoDecodeHmac.result.$2, isA<List<dynamic>>());

    String t(({int totalMs, int blockMs, Object? result}) r) =>
        '${r.totalMs}/${r.blockMs}';
    debugPrint('[P47c] $label n=${items.length} '
        'payload=${(payload.length / 1024).toStringAsFixed(0)}KiB '
        '(total/longestBlock ms) | read cold=${t(cold)} warm=${t(warm)} | '
        'open=${t(open)} envelopeDecode=${t(envelope)} hmac=${t(hmac)} '
        'jsonDecode=${t(decode)} fingerprint=${t(fingerprint)} | '
        'save unchanged=${t(unchanged)} changed=${t(change)} | '
        'serverAnswer identical=${t(answerSame)} changed=${t(answerChanged)} | '
        'isolate: spawn=${t(spawn)} decode=${t(isoDecode)} '
        'decode+hmac=${t(isoDecodeHmac)} encode=${t(isoEncode)} '
        'rssDelta=${rssAfter - rssBefore}MB | chunkedHmac=${t(chunked)}');
  }

  test('Hive hands back the very String that was put, until the box closes',
      () async {
    final box = await Hive.openBox<String>('probe_identity',
        encryptionCipher: HiveAesCipher(List<int>.filled(32, 3)),
        path: listsDir());
    final value = json.encode({'v': 2, 'p': 'x' * 1000, 't': 'tag'});
    await box.put('k', value);
    final sameObject = identical(box.get('k'), value);
    await box.close();
    final reopened = await Hive.openBox<String>('probe_identity',
        encryptionCipher: HiveAesCipher(List<int>.filled(32, 3)),
        path: listsDir());
    final afterReopen = identical(reopened.get('k'), value);
    final stable = identical(reopened.get('k'), reopened.get('k'));
    await reopened.deleteFromDisk();
    debugPrint('[P47c] identity: afterPut=$sameObject afterReopen=$afterReopen '
        'stableWhileOpen=$stable');
    expect(sameObject, isTrue);
    expect(afterReopen, isFalse);
    expect(stable, isTrue);
  });

  for (final n in [100, 1000, 5000, 20000]) {
    test('Owners n=$n', () async {
      final items = _owners(n);
      final changed = [...items]..[0] = items[0].copyWith(name: 'Changed');
      await probe(
          'owners',
          const OwnersLocalCache(),
          const SecureOwnersCacheKeyStore(),
          OwnersLocalCache.boxNameForUid(_uid),
          'owners_v2',
          items,
          changed);
      await Hive.deleteBoxFromDisk(OwnersLocalCache.boxNameForUid(_uid),
          path: listsDir());
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('Offers n=$n', () async {
      final items = _offers(n);
      final changed = [...items]..[0] = items[0].copyWith(notes: 'Changed');
      await probe(
          'offers',
          const OffersLocalCache(),
          const SecureOffersCacheKeyStore(),
          OffersLocalCache.boxNameForUid(_uid),
          'offers_v2',
          items,
          changed);
      await Hive.deleteBoxFromDisk(OffersLocalCache.boxNameForUid(_uid),
          path: listsDir());
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
