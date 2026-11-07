// This device's encrypted copies of Quotation PDFs, one file each, per
// account (Q-2c-1b, Option E; tracker §7AY).
//
// File `<documents>/quotation_pdfs/<account>/<quotation id>_<media id>.bwqp`:
//
//   "BWQP" (4) | version 0x01 (1) | tag (32) | IV (16) | ciphertext
//
// - Keys: a 32-byte master key per account (`Hive.generateSecureKey`, the
//   generator the list caches use) in secure storage under
//   `quotation_pdfs_key_v1_<uid>`. The encryption key and the MAC key are
//   HMAC-SHA256 of the master key over two fixed labels (the one-block PRF
//   derivation of D-3, with labels of their own), so neither is the master
//   key and they never equal each other.
// - Encryption: AES-256-CBC with PKCS7 padding and a fresh IV from
//   `Random.secure()` for every file (`HiveAesCipher`, the cipher the list
//   boxes use, called with offset 0 as its implementation requires).
// - Authentication (encrypt-then-MAC): HMAC-SHA256 under the MAC key over
//   the length-prefixed label, version, header bytes, account, Quotation id,
//   media id and IV + ciphertext. It is checked, comparing every byte, before
//   anything is decrypted: a malformed, truncated, altered, renamed, wrong-
//   key or wrong-account file is never decrypted and reads as no copy.
// - Writes go to a temporary file in the same folder, are read back,
//   authenticated, decrypted and compared with the PDF, and only then
//   renamed into place (atomic within the folder). A failure leaves what
//   was there.
// - A copy that cannot be opened (a lost key, damage) is not deleted: only a
//   new copy from an authorized source replaces it. Nothing is ever guessed
//   or taken from an unauthenticated file.
// - Viewing and sharing need a plain file: it is written to
//   `<temporary>/bw_quotation_view/<account>/`, outside every backup, and
//   removed when the viewer closes; otherwise (a share, which never says it
//   ended, or a crash) swept once it is older than [viewingLifetime], and
//   every copy an earlier run left goes at this run's first sweep (opening
//   the Quotations screen or a PDF).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_files.dart';
import 'package:broker_wallet/src/services/encrypted_account_list_cache.dart'
    show AccountCacheKeyStore, SecureAccountCacheKeyStore;
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Quotation PDF master keys in secure storage, under
/// `quotation_pdfs_key_v1_<uid>`.
class SecureQuotationPdfKeyStore extends SecureAccountCacheKeyStore {
  const SecureQuotationPdfKeyStore() : super(prefix: _prefix);

  static const String _prefix = 'quotation_pdfs_key_v1_';

  static String storageKeyFor(String uid) => '$_prefix$uid';
}

/// The account's key could not be read or kept: nothing was stored.
class QuotationPdfVaultUnavailable implements Exception {
  const QuotationPdfVaultUnavailable();

  @override
  String toString() => 'QuotationPdfVaultUnavailable';
}

/// A sealed copy did not read back exactly: nothing was published.
class QuotationPdfVaultWriteFailed implements Exception {
  const QuotationPdfVaultWriteFailed();

  @override
  String toString() => 'QuotationPdfVaultWriteFailed';
}

class QuotationPdfVault {
  QuotationPdfVault({
    Future<Directory> Function()? documents,
    Future<Directory> Function()? temporary,
    AccountCacheKeyStore keys = const SecureQuotationPdfKeyStore(),
    ScannerBackupGuard? backup,
    DateTime Function()? now,
  })  : _documents = documents ?? getApplicationDocumentsDirectory,
        _temporary = temporary ?? getTemporaryDirectory,
        _keys = keys,
        _backup = backup ?? PlatformScannerBackupGuard(),
        _now = now ?? DateTime.now;

  final Future<Directory> Function() _documents;
  final Future<Directory> Function() _temporary;
  final AccountCacheKeyStore _keys;
  final ScannerBackupGuard _backup;
  final DateTime Function() _now;

  static const String fileExtension = '.bwqp';
  static const String viewFolderName = 'bw_quotation_view';

  /// How long a viewing copy may stay before the next view sweeps it.
  static const Duration viewingLifetime = Duration(hours: 1);

  static final List<int> _magic = ascii.encode('BWQP');
  static const int _version = 1;
  static const int _tagLength = 32;
  static const int _ivLength = 16;
  static const int _headerLength = 4 + 1 + _tagLength;

  static final List<int> _encLabel =
      utf8.encode('broker_wallet/quotation_pdfs/v1/enc');
  static final List<int> _macLabel =
      utf8.encode('broker_wallet/quotation_pdfs/v1/mac');
  static const String _tagLabel = 'bw-quotation-pdf';

  static final RegExp _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final Random _names = Random.secure();

  /// Replaces the file write (tests: a full disk).
  @visibleForTesting
  static Future<void> Function(File file, List<int> bytes)? debugWrite;

  /// Runs after the temporary file is written, before it is verified
  /// (tests: bad storage).
  @visibleForTesting
  static Future<void> Function(File file)? debugAfterWrite;

  /// The derived keys of [master] (tests only).
  @visibleForTesting
  static ({List<int> enc, List<int> mac}) debugDerive(List<int> master) {
    final keys = _Keys.of(master);
    return (enc: keys.enc, mac: keys.mac);
  }

  // One write at a time per account, so two first writes never make two keys.
  static final Map<String, Future<void>> _queues = {};

  static Future<R> _oneAtATime<R>(String uid, Future<R> Function() action) {
    final previous = _queues[uid] ?? Future<void>.value();
    final run = previous.then((_) => action());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _queues[uid] = done;
    unawaited(done.whenComplete(() {
      if (identical(_queues[uid], done)) _queues.remove(uid);
    }));
    return run;
  }

  static bool _ids(String quotationId, String mediaId) =>
      _uuid.hasMatch(quotationId) && _uuid.hasMatch(mediaId);

  Future<Directory> _accountDir(String uid) async =>
      QuotationPdfFiles.accountDirectory(await _documents(), uid);

  Future<File> _file(String uid, String quotationId, String mediaId) async =>
      File(p.join((await _accountDir(uid)).path,
          '${quotationId}_$mediaId$fileExtension'));

  /// The account's keys, or null when it has none (and [create] is false).
  /// Throws [QuotationPdfVaultUnavailable] when the key store fails or holds
  /// something that is not a key: then nothing is read or stored.
  Future<_Keys?> _keysFor(String uid, {required bool create}) async {
    List<int>? master;
    try {
      master = await _keys.read(uid);
    } catch (_) {
      throw const QuotationPdfVaultUnavailable();
    }
    if (master != null) {
      if (master.length != 32) throw const QuotationPdfVaultUnavailable();
      return _Keys.of(master);
    }
    if (!create) return null;
    final fresh = Hive.generateSecureKey();
    try {
      await _keys.write(uid, fresh);
    } catch (_) {
      throw const QuotationPdfVaultUnavailable();
    }
    return _Keys.of(fresh);
  }

  // -----------------------------------------------------------------------
  // Format
  // -----------------------------------------------------------------------

  static List<int> _tag(_Keys keys, String uid, String quotationId,
      String mediaId, Uint8List sealedBody) {
    final out = BytesBuilder(copy: false);
    void part(List<int> bytes) {
      out
        ..add((ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List())
        ..add(bytes);
    }

    part(utf8.encode(_tagLabel));
    part(utf8.encode('$_version'));
    part([..._magic, _version]);
    part(utf8.encode(uid));
    part(utf8.encode(quotationId));
    part(utf8.encode(mediaId));
    part(sealedBody);
    return Hmac(sha256, keys.mac).convert(out.takeBytes()).bytes;
  }

  static Uint8List _seal(_Keys keys, String uid, String quotationId,
      String mediaId, Uint8List pdf) {
    final cipher = HiveAesCipher(keys.enc);
    final out = Uint8List(cipher.maxEncryptedSize(pdf));
    // HiveAesCipher writes the IV first and requires offset 0.
    final length = cipher.encrypt(pdf, 0, pdf.length, out, 0);
    final body = Uint8List.sublistView(out, 0, length);
    final tag = _tag(keys, uid, quotationId, mediaId, body);
    return (BytesBuilder(copy: false)
          ..add(_magic)
          ..addByte(_version)
          ..add(tag)
          ..add(body))
        .takeBytes();
  }

  /// The PDF in [sealed] once its tag has matched, or null.
  static Uint8List? _open(_Keys keys, String uid, String quotationId,
      String mediaId, Uint8List sealed) {
    if (sealed.length < _headerLength + _ivLength + 16) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (sealed[i] != _magic[i]) return null;
    }
    if (sealed[4] != _version) return null;
    final body = Uint8List.sublistView(sealed, _headerLength);
    if ((body.length - _ivLength) % 16 != 0) return null;
    final given = Uint8List.sublistView(sealed, 5, _headerLength);
    if (!_sameTag(given, _tag(keys, uid, quotationId, mediaId, body))) {
      return null;
    }
    try {
      final out = Uint8List(body.length);
      final length = HiveAesCipher(keys.enc)
          .decrypt(Uint8List.fromList(body), 0, body.length, out, 0);
      return Uint8List.sublistView(out, 0, length);
    } catch (_) {
      return null;
    }
  }

  /// Compares every byte whatever the first difference.
  static bool _sameTag(List<int> given, List<int> expected) {
    if (given.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= given[i] ^ expected[i];
    }
    return difference == 0;
  }

  // -----------------------------------------------------------------------
  // Reading and writing
  // -----------------------------------------------------------------------

  /// [uid]'s PDF of [quotationId] with [mediaId], authenticated; null when
  /// there is none, or it is not authentic, or the key cannot be read.
  Future<Uint8List?> read(
      String uid, String quotationId, String mediaId) async {
    if (uid.isEmpty || !_ids(quotationId, mediaId)) return null;
    final file = await _file(uid, quotationId, mediaId);
    if (!await file.exists()) return null;
    final _Keys? keys;
    try {
      keys = await _keysFor(uid, create: false);
    } on QuotationPdfVaultUnavailable {
      return null;
    }
    if (keys == null) return null;
    try {
      return _open(keys, uid, quotationId, mediaId, await file.readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  /// The media ids of [quotationId] held for [uid] (authentic or not).
  Future<Set<String>> versionsOf(String uid, String quotationId) async {
    final dir = await _accountDir(uid);
    if (!await dir.exists()) return {};
    final prefix = '${quotationId}_';
    final versions = <String>{};
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(prefix) && name.endsWith(fileExtension)) {
        versions.add(
            name.substring(prefix.length, name.length - fileExtension.length));
      }
    }
    return versions;
  }

  /// Seals [pdf] as [uid]'s copy of [quotationId] with [mediaId] and
  /// publishes it once it reads back exactly. With [replaceOthers], other
  /// copies of the same Quotation are removed after the new one is in place
  /// (only an authorized current PDF may do that).
  Future<void> store(
    String uid,
    String quotationId,
    String mediaId,
    Uint8List pdf, {
    bool replaceOthers = true,
  }) async {
    if (uid.isEmpty || !_ids(quotationId, mediaId)) {
      throw ArgumentError('not a Quotation PDF id');
    }
    if (pdf.isEmpty) throw ArgumentError.value(pdf.length, 'pdf', 'empty');
    await _oneAtATime(uid, () async {
      final keys = (await _keysFor(uid, create: true))!;
      final documents = await _documents();
      final dir = QuotationPdfFiles.accountDirectory(documents, uid);
      await dir.create(recursive: true);
      await _backup
          .exclude(p.join(documents.path, QuotationPdfFiles.rootFolderName));
      final target =
          File(p.join(dir.path, '${quotationId}_$mediaId$fileExtension'));
      final sealed = _seal(keys, uid, quotationId, mediaId, pdf);
      final suffix = List.generate(8, (_) => _names.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final temporary = File('${target.path}.$suffix.tmp');
      try {
        final write = debugWrite;
        if (write != null) {
          await write(temporary, sealed);
        } else {
          await temporary.writeAsBytes(sealed, flush: true);
        }
        await debugAfterWrite?.call(temporary);
        final back = _open(
            keys, uid, quotationId, mediaId, await temporary.readAsBytes());
        if (back == null || !listEquals(back, pdf)) {
          throw const QuotationPdfVaultWriteFailed();
        }
        await temporary.rename(target.path);
      } finally {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {}
      }
      if (replaceOthers) {
        for (final other in await versionsOf(uid, quotationId)) {
          if (other == mediaId) continue;
          try {
            await File(p.join(dir.path, '${quotationId}_$other$fileExtension'))
                .delete();
          } catch (_) {}
        }
      }
    });
  }

  /// Removes every copy of [quotationId] held for [uid]. Best effort.
  Future<void> purge(String uid, String quotationId) async {
    if (uid.isEmpty) return;
    final dir = await _accountDir(uid);
    for (final media in await versionsOf(uid, quotationId)) {
      try {
        await File(p.join(dir.path, '${quotationId}_$media$fileExtension'))
            .delete();
      } catch (_) {}
    }
  }

  // -----------------------------------------------------------------------
  // Viewing copies
  // -----------------------------------------------------------------------

  static String _viewRoot(String temporary) =>
      p.join(temporary, viewFolderName);

  /// Whether [path] is a viewing copy under [temporary].
  static bool isViewingCopy(String path, String temporary) =>
      p.isWithin(_viewRoot(temporary), path);

  /// A plain copy of [uid]'s authentic PDF to open or share, in its own
  /// temporary folder; null when there is no authentic copy.
  Future<File?> openForViewing(
      String uid, String quotationId, String mediaId) async {
    final pdf = await read(uid, quotationId, mediaId);
    if (pdf == null) return null;
    final temporary = (await _temporary()).path;
    await _sweep(temporary);
    final dir = Directory(
        p.join(_viewRoot(temporary), QuotationPdfFiles.folderNameFor(uid)));
    await dir.create(recursive: true);
    final suffix = List.generate(8, (_) => _names.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final file = File(p.join(dir.path, '${quotationId}_$suffix.pdf'));
    try {
      await file.writeAsBytes(pdf, flush: true);
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }
    return file;
  }

  /// Removes [file] when it is a viewing copy; anything else is left.
  Future<void> release(File file) async {
    final temporary = (await _temporary()).path;
    if (!isViewingCopy(file.path, temporary)) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Whether this run has swept yet. Every viewing copy that exists before
  /// the first sweep was made by an earlier run (each copy is made only
  /// after a sweep), so none is shown now.
  static bool _sweptThisRun = false;

  /// Starts a new run (tests only).
  @visibleForTesting
  static void debugNewProcess() => _sweptThisRun = false;

  /// Removes viewing copies no viewer needs: at this run's first sweep every
  /// one an earlier run left (a crash, or a share that never said it ended),
  /// and after that those older than [viewingLifetime]. Best effort.
  Future<void> sweepViewingCopies() async => _sweep((await _temporary()).path);

  Future<void> _sweep(String temporary) async {
    final everything = !_sweptThisRun;
    _sweptThisRun = true;
    final root = Directory(_viewRoot(temporary));
    if (!await root.exists()) return;
    final cutoff = _now().subtract(viewingLifetime);
    try {
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        try {
          if (everything || (await entity.lastModified()).isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // Delete Account
  // -----------------------------------------------------------------------

  /// Removes [uid]'s key, its encrypted copies and its viewing copies;
  /// nothing of any other account. The key goes first, so a cleanup cut
  /// short leaves only files nobody can open (final review R4). Best effort:
  /// returns how many steps could not be completed.
  Future<int> forgetAccount(String uid) async {
    if (uid.isEmpty) return 0;
    var failed = 0;
    Future<void> step(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        failed++;
      }
    }

    await _oneAtATime(uid, () async {
      await step(() => _keys.delete(uid));
      await step(() async {
        final dir = await _accountDir(uid);
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      await step(() async {
        final dir = Directory(p.join(_viewRoot((await _temporary()).path),
            QuotationPdfFiles.folderNameFor(uid)));
        if (await dir.exists()) await dir.delete(recursive: true);
      });
    });
    return failed;
  }
}

class _Keys {
  _Keys._(this.enc, this.mac);

  factory _Keys.of(List<int> master) => _Keys._(
        Hmac(sha256, master).convert(QuotationPdfVault._encLabel).bytes,
        Hmac(sha256, master).convert(QuotationPdfVault._macLabel).bytes,
      );

  final List<int> enc;
  final List<int> mac;
}
