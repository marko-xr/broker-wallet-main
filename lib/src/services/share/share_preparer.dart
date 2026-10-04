import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/share/share_format.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';

/// What kind of file an attachment is.
enum ShareAttachmentKind { image, video, pdf }

/// A file an attachment resolved to.
class FetchedShareFile {
  const FetchedShareFile(this.file, {this.isTemporary = false});

  final File file;

  /// True when the file was made for this share (a download) and so may simply
  /// be moved into place; false when it belongs to a cache and must be copied.
  final bool isTemporary;
}

/// One file to attach to a share: how to get its bytes, and what to call it.
class ShareAttachment {
  const ShareAttachment({
    required this.key,
    required this.kind,
    required this.baseName,
    required this.fetch,
  });

  /// Identifies the attachment in a [ShareFailure].
  final String key;
  final ShareAttachmentKind kind;

  /// The file's name without extension.
  final String baseName;

  /// Resolves the bytes. A download is written into [scratch] (the share's own
  /// folder) and must stop, and clean up, once the token is cancelled. May throw
  /// a [ShareFailure]; any other error counts as a generic failure.
  final Future<FetchedShareFile> Function(
    Directory scratch,
    ShareCancelToken cancel,
  ) fetch;
}

/// The prepared files of one share and the folder that holds them.
class ShareBundle {
  const ShareBundle(this.directory, this.files);

  final Directory directory;
  final List<PreparedShareFile> files;

  /// Removes the folder. Only for a share nobody received: a closed share sheet
  /// or a share that was called off. A share that was received is left for the
  /// age-based sweep, so a receiving app is never cut off from its file.
  Future<void> discard() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // A leftover folder is swept by age; never fail the caller for it.
    }
  }
}

/// Turns attachments into real files with professional names and correct types,
/// inside one private folder per share.
///
///  * Every share gets its own folder under [stagingRoot], named by the moment
///    it was made, so two shares can never overwrite each other's files.
///  * A file keeps the extension its bytes prove it to be: a photo that is a
///    JPEG is `.jpg` whatever it was called before, and a file whose bytes are
///    not an accepted type is refused rather than renamed.
///  * Names are made of letters, digits and hyphens only, so nothing a person
///    typed can reach a path.
///  * Folders older than [staleAfter] are swept before each new share, so
///    leftovers cannot pile up; nothing newer is ever deleted, because a
///    receiving app may still be reading it.
class SharePreparer {
  SharePreparer({
    required Future<Directory> Function() stagingRoot,
    DateTime Function()? now,
    this.staleAfter = const Duration(hours: 6),
  })  : _stagingRoot = stagingRoot,
        _now = now ?? DateTime.now;

  final Future<Directory> Function() _stagingRoot;
  final DateTime Function() _now;
  final Duration staleAfter;

  int _counter = 0;

  /// Prepares [attachments] in order.
  ///
  /// Throws a [ShareFailure] if any cannot be had — a share is never sent
  /// with some of the chosen files missing. A network or session failure stops
  /// at once (every other file would fail the same way); an unavailable file
  /// is recorded and the rest are still tried, so the person is told about all
  /// of them together. Throws [ShareCancelled] when [cancel] was called.
  Future<ShareBundle> prepare(
    List<ShareAttachment> attachments,
    ShareCancelToken cancel, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final root = await _stagingRoot();
    if (!await root.exists()) await root.create(recursive: true);
    await _sweepStale(root);

    // A folder that does not exist yet, so two shares can never share one.
    Directory directory;
    do {
      directory = Directory(
        '${root.path}${Platform.pathSeparator}'
        '${_now().millisecondsSinceEpoch}-${_counter++}',
      );
    } while (await directory.exists());
    await directory.create(recursive: true);

    try {
      final files = <PreparedShareFile>[];
      final usedNames = <String>{};
      final failedKeys = <String>[];
      final kinds = <ShareFailureKind>{};

      for (final attachment in attachments) {
        _throwIfCancelled(cancel);
        try {
          final fetched = await attachment.fetch(directory, cancel);
          _throwIfCancelled(cancel);
          files.add(await _stage(fetched, attachment, directory, usedNames));
          onProgress?.call(files.length, attachments.length);
        } on ShareCancelled {
          rethrow;
        } on ShareFailure catch (failure) {
          if (failure.kind == ShareFailureKind.network ||
              failure.kind == ShareFailureKind.session) {
            throw ShareFailure(failure.kind);
          }
          kinds.add(failure.kind);
          failedKeys.add(attachment.key);
        } catch (_) {
          _throwIfCancelled(cancel);
          kinds.add(ShareFailureKind.generic);
          failedKeys.add(attachment.key);
        }
      }

      if (failedKeys.isNotEmpty) {
        throw ShareFailure(
          kinds.contains(ShareFailureKind.unavailable)
              ? ShareFailureKind.unavailable
              : ShareFailureKind.generic,
          failedKeys: List<String>.unmodifiable(failedKeys),
        );
      }
      return ShareBundle(
          directory, List<PreparedShareFile>.unmodifiable(files));
    } catch (_) {
      await ShareBundle(directory, const <PreparedShareFile>[]).discard();
      rethrow;
    }
  }

  static void _throwIfCancelled(ShareCancelToken cancel) {
    if (cancel.isCancelled) throw const ShareCancelled();
  }

  Future<PreparedShareFile> _stage(
    FetchedShareFile fetched,
    ShareAttachment attachment,
    Directory directory,
    Set<String> usedNames,
  ) async {
    final source = fetched.file;
    if (!await source.exists() || await source.length() < 1) {
      throw const ShareFailure(ShareFailureKind.unavailable);
    }
    final type = await _typeOf(source, attachment.kind);

    final stem = ShareFormat.fileStem(attachment.baseName, maxLength: 80);
    final base = stem.isEmpty ? 'Broker-Wallet' : stem;
    var name = '$base.${type.extension}';
    var suffix = 2;
    while (!usedNames.add(name.toLowerCase())) {
      name = '$base-${suffix++}.${type.extension}';
    }

    final target = File('${directory.path}${Platform.pathSeparator}$name');
    if (fetched.isTemporary) {
      try {
        await source.rename(target.path);
      } on FileSystemException {
        await source.copy(target.path);
        try {
          await source.delete();
        } catch (_) {
          // The share's own folder is removed as a whole.
        }
      }
    } else {
      await source.copy(target.path);
    }
    return PreparedShareFile(
      path: target.path,
      name: name,
      mimeType: type.mimeType,
    );
  }

  /// The extension and MIME type [file]'s own bytes prove it to be, for a file
  /// of the given kind. Throws [ShareFailure.unavailable] for bytes that are not
  /// an accepted type.
  static Future<_FileType> _typeOf(File file, ShareAttachmentKind kind) async {
    final header = await OfferMediaPolicy.readHeader(file);

    if (kind == ShareAttachmentKind.pdf) {
      if (_looksLikePdf(header)) {
        return const _FileType('pdf', 'application/pdf');
      }
      throw const ShareFailure(ShareFailureKind.unavailable);
    }

    final detected = OfferMediaPolicy.resolveContentType(header);
    if (detected != null) {
      final known = _byContentType[detected];
      if (known != null) return known;
    }

    // Bytes no detector recognizes (an old record's file): trust the name only
    // when it is an accepted media extension of the right kind.
    final name = file.path.toLowerCase();
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1);
    final byName = _byExtension[extension];
    if (byName != null &&
        byName.isVideo == (kind == ShareAttachmentKind.video)) {
      return byName;
    }
    throw const ShareFailure(ShareFailureKind.unavailable);
  }

  static bool _looksLikePdf(List<int> header) {
    // `%PDF` at the very start.
    return header.length >= 4 &&
        header[0] == 0x25 &&
        header[1] == 0x50 &&
        header[2] == 0x44 &&
        header[3] == 0x46;
  }

  static const Map<String, _FileType> _byContentType = <String, _FileType>{
    'image/jpeg': _FileType('jpg', 'image/jpeg'),
    'image/png': _FileType('png', 'image/png'),
    'image/webp': _FileType('webp', 'image/webp'),
    'video/mp4': _FileType('mp4', 'video/mp4', isVideo: true),
    'video/quicktime': _FileType('mov', 'video/quicktime', isVideo: true),
    'video/3gpp': _FileType('3gp', 'video/3gpp', isVideo: true),
  };

  static const Map<String, _FileType> _byExtension = <String, _FileType>{
    'jpg': _FileType('jpg', 'image/jpeg'),
    'jpeg': _FileType('jpg', 'image/jpeg'),
    'png': _FileType('png', 'image/png'),
    'webp': _FileType('webp', 'image/webp'),
    'mp4': _FileType('mp4', 'video/mp4', isVideo: true),
    'mov': _FileType('mov', 'video/quicktime', isVideo: true),
    '3gp': _FileType('3gp', 'video/3gpp', isVideo: true),
  };

  /// Removes share folders made more than [staleAfter] ago. The folder's name is
  /// the moment it was made, so no timestamp on disk has to be trusted.
  Future<void> _sweepStale(Directory root) async {
    try {
      final cutoff = _now().millisecondsSinceEpoch - staleAfter.inMilliseconds;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final segments =
            entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty) continue;
        final made = int.tryParse(segments.last.split('-').first);
        if (made == null || made > cutoff) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Retried by the next sweep.
        }
      }
    } catch (_) {
      // Housekeeping only: a failed sweep never blocks a share.
    }
  }
}

class _FileType {
  const _FileType(this.extension, this.mimeType, {this.isVideo = false});

  final String extension;
  final String mimeType;
  final bool isVideo;
}
