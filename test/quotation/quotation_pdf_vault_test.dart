// Q-2c-1b (Option E, tracker §7AY): one encrypt-then-MAC file per Quotation
// PDF, sealed with keys derived from a per-account master key.
//
// File: "BWQP" | 0x01 | tag (32) | IV (16) | AES-256-CBC-PKCS7 ciphertext,
// at quotation_pdfs/<account>/<quotation id>_<media id>.bwqp. The tag is
// HMAC-SHA256 under the MAC key over the length-prefixed label, version,
// header, account, Quotation id, media id and IV + ciphertext, checked in
// constant time before anything is decrypted.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:broker_wallet/src/services/quotation_pdf_vault.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _q1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const _q2 = 'aaaaaaaa-0000-4000-8000-000000000002';
const _m1 = 'dddddddd-0000-4000-8000-000000000001';
const _m2 = 'dddddddd-0000-4000-8000-000000000002';

Uint8List _pdf(int size, {int seed = 1}) {
  final random = Random(seed);
  final bytes = Uint8List(size);
  for (var i = 0; i < size; i++) {
    bytes[i] = random.nextInt(256);
  }
  bytes.setAll(0, utf8.encode('%PDF-1.7\n'));
  bytes.setAll(size - 6, utf8.encode('%%EOF\n'));
  return bytes;
}

class _Keys implements AccountCacheKeyStore {
  final Map<String, List<int>> keys = {};
  bool broken = false;

  @override
  Future<List<int>?> read(String uid) async {
    if (broken) throw PlatformException(code: 'keystore-unavailable');
    return keys[uid];
  }

  @override
  Future<void> write(String uid, List<int> key) async {
    if (broken) throw PlatformException(code: 'keystore-unavailable');
    keys[uid] = key;
  }

  void Function(String uid)? onDelete;

  @override
  Future<void> delete(String uid) async {
    onDelete?.call(uid);
    keys.remove(uid);
  }
}

class _Guard implements ScannerBackupGuard {
  final List<String> excluded = [];
  @override
  Future<bool> exclude(String path) async {
    excluded.add(path);
    return true;
  }
}

String _sep(List<String> parts) => parts.join(Platform.pathSeparator);

void main() {
  late Directory docs;
  late Directory temp;
  late _Keys keys;
  late _Guard guard;
  late DateTime clock;

  QuotationPdfVault vault() => QuotationPdfVault(
        documents: () async => docs,
        temporary: () async => temp,
        keys: keys,
        backup: guard,
        now: () => clock,
      );

  setUp(() {
    docs = Directory.systemTemp.createTempSync('q2c1b_docs_');
    temp = Directory.systemTemp.createTempSync('q2c1b_tmp_');
    keys = _Keys();
    guard = _Guard();
    clock = DateTime.now();
    QuotationPdfVault.debugWrite = null;
    QuotationPdfVault.debugAfterWrite = null;
    QuotationPdfVault.debugNewProcess();
  });

  tearDown(() {
    QuotationPdfVault.debugWrite = null;
    QuotationPdfVault.debugAfterWrite = null;
    for (final d in [docs, temp]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  File sealedFile(String uid, String q, String m) => File(_sep([
        docs.path,
        'quotation_pdfs',
        uid,
        '${q}_$m${QuotationPdfVault.fileExtension}'
      ]));

  // -----------------------------------------------------------------------
  group('the format', () {
    test('a round trip gives back exactly the PDF', () async {
      final pdf = _pdf(250000);
      await vault().store(_alice, _q1, _m1, pdf);
      expect(await vault().read(_alice, _q1, _m1), pdf);
    });

    test('the bytes on disk are header, tag, IV and whole AES blocks',
        () async {
      final pdf = _pdf(1000);
      await vault().store(_alice, _q1, _m1, pdf);
      final file = sealedFile(_alice, _q1, _m1).readAsBytesSync();
      expect(file.sublist(0, 4), ascii.encode('BWQP'));
      expect(file[4], 1);
      final body = file.length - 4 - 1 - 32;
      expect(body, 16 + (pdf.length ~/ 16 + 1) * 16, reason: 'IV + PKCS7');
      expect(utf8.decode(file, allowMalformed: true), isNot(contains('%PDF')),
          reason: 'no plaintext on disk');
    });

    test('a fresh random IV every time: same PDF, different files', () async {
      final pdf = _pdf(4096);
      final ivs = <String>{};
      final tags = <String>{};
      for (var i = 0; i < 200; i++) {
        await vault().store(_alice, _q1, _m1, pdf);
        final file = sealedFile(_alice, _q1, _m1).readAsBytesSync();
        tags.add(base64.encode(file.sublist(5, 37)));
        ivs.add(base64.encode(file.sublist(37, 53)));
      }
      expect(ivs, hasLength(200));
      expect(tags, hasLength(200));
      expect(await vault().read(_alice, _q1, _m1), pdf);
    });

    test('keys: one master per account, separate derived keys', () async {
      await vault().store(_alice, _q1, _m1, _pdf(100));
      await vault().store(_bob, _q1, _m1, _pdf(100));
      expect(keys.keys.keys.toSet(), {_alice, _bob});
      expect(keys.keys[_alice], hasLength(32));
      expect(keys.keys[_alice], isNot(keys.keys[_bob]));
      final derived = QuotationPdfVault.debugDerive(keys.keys[_alice]!);
      expect(derived.enc, hasLength(32));
      expect(derived.mac, hasLength(32));
      expect(derived.enc, isNot(derived.mac));
      expect(derived.enc, isNot(keys.keys[_alice]));
      expect(derived.mac, isNot(keys.keys[_alice]));
      expect(SecureQuotationPdfKeyStore.storageKeyFor(_alice),
          'quotation_pdfs_key_v1_$_alice');
    });

    test('the secure key store is used under its own prefix', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final real = QuotationPdfVault(
        documents: () async => docs,
        temporary: () async => temp,
        backup: guard,
      );
      await real.store(_alice, _q1, _m1, _pdf(100));
      expect(
          await const FlutterSecureStorage()
              .read(key: 'quotation_pdfs_key_v1_$_alice'),
          isNotNull);
      expect(await real.read(_alice, _q1, _m1), _pdf(100));
    });

    test('the folder is backup-excluded on iPhone', () async {
      await vault().store(_alice, _q1, _m1, _pdf(100));
      expect(guard.excluded, contains(_sep([docs.path, 'quotation_pdfs'])));
    });
  });

  // -----------------------------------------------------------------------
  group('nothing that is not authentic is opened', () {
    late Uint8List original;

    setUp(() async {
      await vault().store(_alice, _q1, _m1, _pdf(5000));
      original = sealedFile(_alice, _q1, _m1).readAsBytesSync();
    });

    Future<Uint8List?> readAfter(Uint8List Function(Uint8List) change) async {
      sealedFile(_alice, _q1, _m1).writeAsBytesSync(change(original));
      return vault().read(_alice, _q1, _m1);
    }

    for (final (label, at) in [
      ('magic', 0),
      ('version', 4),
      ('tag', 5),
      ('IV', 40),
      ('first ciphertext block', 60),
      ('last ciphertext block', -1),
    ]) {
      test('one flipped bit in the $label ⇒ nothing', () async {
        expect(
            await readAfter((b) {
              final copy = Uint8List.fromList(b);
              final i = at < 0 ? copy.length + at : at;
              copy[i] ^= 0x01;
              return copy;
            }),
            isNull);
      });
    }

    for (final (label, keep) in [
      ('one byte short', -1),
      ('header only', 37),
      ('IV only', 53),
      ('empty', 0),
    ]) {
      test('truncated ($label) ⇒ nothing', () async {
        expect(
            await readAfter((b) =>
                Uint8List.sublistView(b, 0, keep < 0 ? b.length + keep : keep)),
            isNull);
      });
    }

    test('another key ⇒ nothing, and the file is left as it was', () async {
      keys.keys[_alice] = List<int>.generate(32, (i) => i);
      expect(await vault().read(_alice, _q1, _m1), isNull);
      expect(sealedFile(_alice, _q1, _m1).readAsBytesSync(), original);
    });

    test('another account, even with the same master key ⇒ nothing', () async {
      keys.keys[_bob] = keys.keys[_alice]!;
      final bobs = sealedFile(_bob, _q1, _m1)..createSync(recursive: true);
      bobs.writeAsBytesSync(original);
      expect(await vault().read(_bob, _q1, _m1), isNull);
    });

    test('another Quotation or media id (a renamed file) ⇒ nothing', () async {
      for (final (q, m) in [(_q2, _m1), (_q1, _m2)]) {
        final moved = sealedFile(_alice, q, m)..createSync(recursive: true);
        moved.writeAsBytesSync(original);
        expect(await vault().read(_alice, q, m), isNull, reason: '$q $m');
      }
    });

    test('a key store that cannot be read ⇒ nothing read, nothing stored',
        () async {
      keys.broken = true;
      expect(await vault().read(_alice, _q1, _m1), isNull);
      await expectLater(vault().store(_alice, _q2, _m2, _pdf(100)),
          throwsA(isA<QuotationPdfVaultUnavailable>()));
      expect(sealedFile(_alice, _q2, _m2).existsSync(), isFalse);
    });

    test('a lost key: nothing opens; only a new authorized store replaces',
        () async {
      await vault().store(_alice, _q2, _m2, _pdf(200, seed: 2));
      keys.keys.remove(_alice);
      expect(await vault().read(_alice, _q1, _m1), isNull);
      expect(await vault().read(_alice, _q2, _m2), isNull);
      await vault().store(_alice, _q1, _m1, _pdf(5000));
      expect(await vault().read(_alice, _q1, _m1), _pdf(5000));
      expect(await vault().read(_alice, _q2, _m2), isNull,
          reason: 'still unreadable, never guessed');
      expect(sealedFile(_alice, _q2, _m2).existsSync(), isTrue,
          reason: 'not deleted: only replaced by a new authorized copy');
    });

    test('ids that are not lower-case UUIDs are refused', () async {
      await expectLater(
          vault().store(_alice, '../x', _m1, _pdf(10)), throwsArgumentError);
      expect(await vault().read(_alice, _q1.toUpperCase(), _m1), isNull);
    });
  });

  // -----------------------------------------------------------------------
  group('writes are atomic and verified before they are published', () {
    test('a failed write (disk full) leaves the previous copy and no temp',
        () async {
      await vault().store(_alice, _q1, _m1, _pdf(1000, seed: 1));
      // Half the file reaches the disk, then the disk is full.
      QuotationPdfVault.debugWrite = (file, bytes) async {
        await file.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
        throw const FileSystemException('No space left on device');
      };
      await expectLater(vault().store(_alice, _q1, _m1, _pdf(1000, seed: 9)),
          throwsA(isA<FileSystemException>()));
      QuotationPdfVault.debugWrite = null;
      expect(await vault().read(_alice, _q1, _m1), _pdf(1000, seed: 1));
      expect(
          Directory(_sep([docs.path, 'quotation_pdfs', _alice]))
              .listSync()
              .map((e) => e.path)
              .where((p) => p.endsWith('.tmp')),
          isEmpty);
    });

    test('a write that does not read back exactly is never published',
        () async {
      QuotationPdfVault.debugAfterWrite = (file) async {
        final bytes = file.readAsBytesSync();
        bytes[bytes.length - 1] ^= 1;
        file.writeAsBytesSync(bytes);
      };
      await expectLater(vault().store(_alice, _q1, _m1, _pdf(1000)),
          throwsA(isA<QuotationPdfVaultWriteFailed>()));
      expect(sealedFile(_alice, _q1, _m1).existsSync(), isFalse);
      expect(Directory(_sep([docs.path, 'quotation_pdfs', _alice])).listSync(),
          isEmpty,
          reason: 'the temporary file is removed too');
    });

    test('a new version replaces the old only once it is in place', () async {
      await vault().store(_alice, _q1, _m1, _pdf(100, seed: 1));
      await vault().store(_alice, _q1, _m2, _pdf(100, seed: 2));
      expect(await vault().read(_alice, _q1, _m2), _pdf(100, seed: 2));
      expect(sealedFile(_alice, _q1, _m1).existsSync(), isFalse);
    });

    test('keeping other versions leaves them (for migration)', () async {
      await vault().store(_alice, _q1, _m1, _pdf(100, seed: 1));
      await vault()
          .store(_alice, _q1, _m2, _pdf(100, seed: 2), replaceOthers: false);
      expect(await vault().versionsOf(_alice, _q1), {_m1, _m2});
    });

    test('an empty PDF is refused', () async {
      await expectLater(
          vault().store(_alice, _q1, _m1, Uint8List(0)), throwsArgumentError);
    });
  });

  // -----------------------------------------------------------------------
  group('viewing copies', () {
    test('a plaintext copy in this account\'s temporary folder, then gone',
        () async {
      await vault().store(_alice, _q1, _m1, _pdf(3000));
      final view = (await vault().openForViewing(_alice, _q1, _m1))!;
      expect(view.readAsBytesSync(), _pdf(3000));
      expect(view.parent.path, _sep([temp.path, 'bw_quotation_view', _alice]));
      expect(QuotationPdfVault.isViewingCopy(view.path, temp.path), isTrue);
      await vault().release(view);
      expect(view.existsSync(), isFalse);
    });

    test('nothing to view when the copy is not authentic', () async {
      await vault().store(_alice, _q1, _m1, _pdf(3000));
      keys.keys[_alice] = List<int>.generate(32, (i) => i);
      expect(await vault().openForViewing(_alice, _q1, _m1), isNull);
      expect(
          Directory(_sep([temp.path, 'bw_quotation_view', _alice]))
                  .existsSync() &&
              Directory(_sep([temp.path, 'bw_quotation_view', _alice]))
                  .listSync()
                  .isNotEmpty,
          isFalse);
    });

    test('copies left by a crash are swept once they are old', () async {
      await vault().store(_alice, _q1, _m1, _pdf(3000));
      await vault().store(_bob, _q2, _m2, _pdf(3000));
      final aliceOld = (await vault().openForViewing(_alice, _q1, _m1))!;
      final bobOld = (await vault().openForViewing(_bob, _q2, _m2))!;
      clock = clock
          .add(QuotationPdfVault.viewingLifetime + const Duration(minutes: 1));
      aliceOld.setLastModifiedSync(clock.subtract(
          QuotationPdfVault.viewingLifetime + const Duration(minutes: 1)));
      bobOld.setLastModifiedSync(clock.subtract(
          QuotationPdfVault.viewingLifetime + const Duration(minutes: 1)));
      final fresh = (await vault().openForViewing(_alice, _q1, _m1))!;
      expect(aliceOld.existsSync(), isFalse);
      expect(bobOld.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    // Final review (R3): a viewing copy an earlier run left (a crash, or a
    // share that never says it ended) is gone at this run's first sweep,
    // however recent it is; within a run only old copies are swept.
    test('the first sweep of a run removes every copy an earlier run left',
        () async {
      await vault().store(_alice, _q1, _m1, _pdf(3000));
      await vault().store(_bob, _q2, _m2, _pdf(3000));
      final left = [
        (await vault().openForViewing(_alice, _q1, _m1))!,
        (await vault().openForViewing(_bob, _q2, _m2))!,
      ];
      await vault().sweepViewingCopies();
      for (final f in left) {
        expect(f.existsSync(), isTrue, reason: 'this run\'s own, still recent');
      }
      QuotationPdfVault.debugNewProcess(); // the app starts again
      await vault().sweepViewingCopies();
      for (final f in left) {
        expect(f.existsSync(), isFalse, reason: f.path);
      }
    });

    test('release never deletes a file outside the viewing folder', () async {
      final elsewhere = File(_sep([docs.path, 'keep.pdf']))
        ..writeAsBytesSync([1]);
      await vault().release(elsewhere);
      expect(elsewhere.existsSync(), isTrue);
    });
  });

  // -----------------------------------------------------------------------
  group('removal', () {
    test('purge removes one Quotation\'s copies only', () async {
      await vault().store(_alice, _q1, _m1, _pdf(100));
      await vault().store(_alice, _q2, _m2, _pdf(100));
      await vault().purge(_alice, _q1);
      expect(await vault().read(_alice, _q1, _m1), isNull);
      expect(await vault().read(_alice, _q2, _m2), _pdf(100));
    });

    // Final review (R4): the key goes first, so a cleanup cut short leaves
    // only files nobody can open.
    test('forgetting an account deletes its key before its files', () async {
      await vault().store(_alice, _q1, _m1, _pdf(100));
      final folder = Directory(_sep([docs.path, 'quotation_pdfs', _alice]));
      bool? filesStillThere;
      keys.onDelete = (uid) {
        if (uid == _alice) filesStillThere = folder.existsSync();
      };
      await vault().forgetAccount(_alice);
      expect(filesStillThere, isTrue);
      expect(folder.existsSync(), isFalse);
    });

    test('forgetting an account removes its files, key and views only',
        () async {
      await vault().store(_alice, _q1, _m1, _pdf(100));
      await vault().store(_bob, _q2, _m2, _pdf(100));
      final aliceView = (await vault().openForViewing(_alice, _q1, _m1))!;
      final bobView = (await vault().openForViewing(_bob, _q2, _m2))!;
      final failed = await vault().forgetAccount(_alice);
      expect(failed, 0);
      expect(
          Directory(_sep([docs.path, 'quotation_pdfs', _alice])).existsSync(),
          isFalse);
      expect(keys.keys.containsKey(_alice), isFalse);
      expect(aliceView.existsSync(), isFalse);
      expect(bobView.existsSync(), isTrue);
      expect(await vault().read(_bob, _q2, _m2), _pdf(100));
      expect(
          Directory(_sep([docs.path, 'quotation_pdfs', '.work'])).existsSync(),
          isFalse,
          reason: 'the work folder is QuotationPdfFiles\' to clean');
    });
  });

  test('measurements: seal and open (test VM, not a device)', () async {
    final lines = <String>[];
    for (final size in [100000, 1000000, 5000000, 20000000]) {
      final pdf = _pdf(size);
      final store = Stopwatch()..start();
      await vault().store(_alice, _q1, _m1, pdf);
      store.stop();
      final read = Stopwatch()..start();
      final back = await vault().read(_alice, _q1, _m1);
      read.stop();
      expect(back, pdf);
      lines.add('pdf $size B: store (seal + write + verify + publish) '
          '${store.elapsedMilliseconds} ms, read (verify + decrypt) '
          '${read.elapsedMilliseconds} ms');
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
