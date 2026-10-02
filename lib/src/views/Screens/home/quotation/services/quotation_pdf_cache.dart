// On-device copy of a Quotation's PDF, named by the PDF's stable media id.
//
// The private bucket is the source of truth. A local copy is only a cache of
// one exact media object: because the file name carries the media id, a PDF
// regenerated on another device (a new id) can never be mistaken for the copy
// held here, so no staleness check against a signed URL is needed. Copies are
// private user data and are removed when a Quotation is deleted.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class QuotationPdfCache {
  QuotationPdfCache({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  static String _prefix(String quotationId) => 'quotation_${quotationId}_';

  static String _name(String quotationId, String mediaId) =>
      '${_prefix(quotationId)}$mediaId.pdf';

  /// The cached file for exactly this media id, or null when not held.
  Future<File?> existing(String quotationId, String mediaId) async {
    final file = await _file(quotationId, mediaId);
    return await file.exists() ? file : null;
  }

  /// Moves [generated] into the cache as this media id's copy, replacing any
  /// older copy of the same Quotation.
  Future<File> adopt(
    File generated,
    String quotationId,
    String mediaId,
  ) async {
    final target = await _file(quotationId, mediaId);
    if (await target.exists()) await target.delete();
    File adopted;
    try {
      adopted = await generated.rename(target.path);
    } on FileSystemException {
      // A rename can fail across volumes; copy then remove the source.
      adopted = await generated.copy(target.path);
      await generated.delete();
    }
    await _removeOthers(quotationId, keepMediaId: mediaId);
    return adopted;
  }

  /// Stores downloaded [bytes] as this media id's copy, replacing any older
  /// copy of the same Quotation.
  Future<File> write(
    String quotationId,
    String mediaId,
    List<int> bytes,
  ) async {
    final target = await _file(quotationId, mediaId);
    await target.writeAsBytes(bytes, flush: true);
    await _removeOthers(quotationId, keepMediaId: mediaId);
    return target;
  }

  /// Removes every cached copy of [quotationId]. Best effort.
  Future<void> purge(String quotationId) async {
    await _removeOthers(quotationId);
  }

  Future<File> _file(String quotationId, String mediaId) async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}'
        '${_name(quotationId, mediaId)}');
  }

  Future<void> _removeOthers(String quotationId, {String? keepMediaId}) async {
    try {
      final dir = await _directory();
      final prefix = _prefix(quotationId);
      final keep = keepMediaId == null ? null : _name(quotationId, keepMediaId);
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith(prefix) && name.endsWith('.pdf') && name != keep) {
          await entity.delete();
        }
      }
    } catch (_) {
      // A leftover cache file is harmless; never fail the caller for it.
    }
  }
}
