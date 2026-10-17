// A local, app-controlled copy of a plan, for viewing, opening and sharing.
//
// The private bucket is the source of truth. A plan is fetched through a fresh
// short-lived signed link, written into the app's own temporary folder under a
// name made of the record's kind, its id and the plan's stable media id, and
// checked against its real bytes before it is used. The link itself is never
// shown, shared, logged or opened by another app: other apps, and the share
// sheet, only ever receive this local file.
//
// Because the name carries the media id, a plan replaced on another device (a
// new id) can never be mistaken for the copy held here. The copy lives in the
// system's temporary folder, which is neither backed up nor kept by the app
// beyond what the system allows.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_policy.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';

class PlanAttachmentCache {
  PlanAttachmentCache({Future<Directory> Function()? directory})
      : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory(
        '${temporary.path}${Platform.pathSeparator}plan_attachments');
  }

  static String _prefix(PlanParent parent, String parentId) =>
      '${parent.name}_${parentId}_';

  /// Where this exact plan's copy lives (it may not exist yet).
  Future<File> fileFor(
    PlanParent parent,
    String parentId,
    PlanAttachmentRef ref,
  ) async {
    final directory = await _directory();
    if (!await directory.exists()) await directory.create(recursive: true);
    final extension = PlanContentTypes.extensionOf(ref.contentType) ?? 'bin';
    return File('${directory.path}${Platform.pathSeparator}'
        '${_prefix(parent, parentId)}${ref.mediaObjectId}.$extension');
  }

  /// The held copy of exactly this plan, or null.
  Future<File?> existing(
    PlanParent parent,
    String parentId,
    PlanAttachmentRef ref,
  ) async {
    final file = await fileFor(parent, parentId, ref);
    return await file.exists() ? file : null;
  }

  /// Removes every held copy of the record's plans except [keepMediaId]'s.
  /// Best effort.
  Future<void> removeOthers(
    PlanParent parent,
    String parentId, {
    String? keepMediaId,
  }) async {
    try {
      final directory = await _directory();
      if (!await directory.exists()) return;
      final prefix = _prefix(parent, parentId);
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        if (keepMediaId != null && name.startsWith('$prefix$keepMediaId.')) {
          continue;
        }
        await entity.delete();
      }
    } catch (_) {
      // A leftover cache file is harmless; never fail the caller for it.
    }
  }
}

/// Makes a verified local file of a plan, downloading it when this phone does
/// not hold it yet.
class PlanAttachmentFiles {
  PlanAttachmentFiles({
    required PlanAttachmentTransport transport,
    PlanAttachmentCache? cache,
    DateTime Function()? now,
  })  : _transport = transport,
        _cache = cache ?? PlanAttachmentCache(),
        _now = now ?? DateTime.now;

  final PlanAttachmentTransport _transport;
  final PlanAttachmentCache _cache;
  final DateTime Function() _now;

  /// The plan [ref] of the record [parentId] as a local file whose real bytes
  /// are the plan's own type.
  ///
  /// Throws a [PlanAttachmentException]: `staleReplacement` when the record's
  /// plan is no longer [ref] (it changed elsewhere), `typeMismatch` when the
  /// downloaded bytes are not what was stored, or a transport failure.
  Future<File> ensureLocal({
    required PlanParent parent,
    required String parentId,
    required PlanAttachmentRef ref,
  }) async {
    final held = await _cache.existing(parent, parentId, ref);
    if (held != null) {
      if (await _isThePlan(held, ref)) return held;
      try {
        await held.delete();
      } catch (_) {}
    }

    var source = ref;
    if (!ref.hasFreshUrl(_now())) {
      final current =
          await _transport.fetchCurrent(parent: parent, parentId: parentId);
      if (current == null || current.mediaObjectId != ref.mediaObjectId) {
        throw const PlanAttachmentException(
            PlanAttachmentFailure.staleReplacement);
      }
      source = current;
    }
    final url = source.signedUrl;
    if (url == null || url.isEmpty) {
      throw const PlanAttachmentException(
          PlanAttachmentFailure.invalidResponse);
    }

    final target = await _cache.fileFor(parent, parentId, ref);
    // A download is first written beside its target under a name that keeps the
    // real extension (the bytes are checked as a plan file), then moved in.
    final partial = File('${target.parent.path}${Platform.pathSeparator}'
        'download_${target.uri.pathSegments.last}');
    await _transport.download(
      url: url,
      target: partial,
      maxBytes: PlanAttachmentPolicy.maxBytesFor(ref.kind),
    );
    if (!await _isThePlan(partial, ref)) {
      try {
        await partial.delete();
      } catch (_) {}
      throw const PlanAttachmentException(PlanAttachmentFailure.typeMismatch);
    }
    if (await target.exists()) await target.delete();
    final adopted = await partial.rename(target.path);
    await _cache.removeOthers(parent, parentId, keepMediaId: ref.mediaObjectId);
    return adopted;
  }

  Future<bool> _isThePlan(File file, PlanAttachmentRef ref) async {
    final check = await PlanAttachmentPolicy.check(file);
    return check.isAccepted && check.contentType == ref.contentType;
  }
}
