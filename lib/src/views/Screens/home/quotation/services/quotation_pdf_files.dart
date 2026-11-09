// Where Quotation PDFs live on this device (Q-2c-1, tracker §7AY).
//
// `<documents>/quotation_pdfs` is excluded from Android cloud backup and
// device transfer (backup_rules.xml, data_extraction_rules.xml) and, on
// iPhone, marked when it is created. A new PDF is generated in its account's
// work folder, `quotation_pdfs/.work/<account>/`, never in the documents
// folder itself, which is backed up.
//
// The bound copies that QuotationPdfCache keeps are still in the documents
// folder, unencrypted: encrypting them in a per-account store, and moving
// the existing ones there, waits for its own approval (§7AY).

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/services/quotations_local_cache.dart';
import 'package:broker_wallet/src/services/scanner/scanner_backup_guard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class QuotationPdfFiles {
  QuotationPdfFiles({
    Future<Directory> Function()? documents,
    QuotationsLocalCache savedLists = const QuotationsLocalCache(),
    ScannerBackupGuard? backup,
  })  : _documents = documents ?? getApplicationDocumentsDirectory,
        _savedLists = savedLists,
        _backup = backup ?? PlatformScannerBackupGuard();

  final Future<Directory> Function() _documents;
  final QuotationsLocalCache _savedLists;
  final ScannerBackupGuard _backup;

  /// The folder, directly under the documents folder, that backup rules name.
  static const String rootFolderName = 'quotation_pdfs';

  /// Inside [rootFolderName]: where PDFs are generated, per account.
  static const String workFolderName = '.work';

  /// A copy kept by QuotationPdfCache: `quotation_<id>_<media id>.pdf`.
  static final RegExp _boundName = RegExp(
      r'^quotation_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$');

  /// A generated PDF an earlier version left in the documents folder:
  /// `quotation_<id>.pdf`.
  static final RegExp _generatedName = RegExp(
      r'^quotation_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.pdf$');

  /// `<documents>/quotation_pdfs/.work/<account>`. The account id is the
  /// folder name when it is plain (a UUID is); anything else is hex encoded,
  /// so no id can name a parent folder.
  static Directory workDirectory(Directory documents, String userId) =>
      Directory(p.join(documents.path, rootFolderName, workFolderName,
          folderNameFor(userId)));

  /// `<documents>/quotation_pdfs/<account>`: the account's encrypted copies
  /// (QuotationPdfVault). No account folder name can be [workFolderName].
  static Directory accountDirectory(Directory documents, String userId) =>
      Directory(p.join(documents.path, rootFolderName, folderNameFor(userId)));

  /// The folder name of [userId]: the id itself when it is plain (a UUID
  /// is), otherwise hex encoded, so no id can name a parent folder.
  static String folderNameFor(String userId) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final plain = RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(userId);
    return plain
        ? userId
        : 'u_${utf8.encode(userId).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Where a new PDF of [quotation] is generated, in its account's work
  /// folder (created, and on iPhone excluded from backup, when needed).
  Future<File> workFileFor(QuotationModel quotation) async {
    final documents = await _documents();
    final directory = workDirectory(documents, quotation.userId);
    await directory.create(recursive: true);
    await _backup.exclude(p.join(documents.path, rootFolderName));
    final id = quotation.id ?? DateTime.now().millisecondsSinceEpoch;
    return File(p.join(directory.path, 'quotation_$id.pdf'));
  }

  /// Removes what this device holds of the deleted account [uid]'s Quotation
  /// PDFs: its work folder, and each PDF in the documents folder that names
  /// a Quotation of its verified saved list (written only from that
  /// account's server lists; a Quotation id belongs to one account). Run it
  /// before that list is forgotten. Nothing else is touched: no other
  /// account's file, no file whose owner is not proven (an unreadable or
  /// missing list proves nothing), no other name. Best effort: returns how
  /// many files could not be removed.
  Future<int> forgetAccount(String uid) async {
    if (uid.isEmpty) return 0;
    var failed = 0;
    final documents = await _documents();
    final work = workDirectory(documents, uid);
    try {
      if (await work.exists()) await work.delete(recursive: true);
    } catch (_) {
      failed++;
    }
    final saved = await _savedLists.readSaved(uid);
    final ids = {
      for (final q in saved?.items ?? const <QuotationModel>[])
        if (q.id != null) q.id!
    };
    if (ids.isEmpty) return failed;
    try {
      await for (final entity in documents.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final id =
            (_boundName.firstMatch(name) ?? _generatedName.firstMatch(name))
                ?.group(1);
        if (id == null || !ids.contains(id)) continue;
        try {
          await entity.delete();
        } catch (_) {
          failed++;
        }
      }
    } catch (_) {
      failed++;
    }
    return failed;
  }
}
