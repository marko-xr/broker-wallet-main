import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';

/// Reads a stored or freshly written PDF back and says what it holds.
typedef ImagePdfFileVerifier = Future<ImagePdfFileInfo> Function(File file);

/// Copies [source] to [destination]. A seam so a test can make a copy fail or
/// stop half way; the default is a plain file copy.
typedef ImagePdfFileCopier = Future<void> Function(
    File source, File destination);

/// What the store holds for one account right now.
class ImagePdfLibrary {
  const ImagePdfLibrary({
    required this.documents,
    this.missingIds = const <String>{},
    this.recoveredFromDamagedIndex = false,
  });

  /// Newest first.
  final List<ImagePdfDocument> documents;

  /// Documents whose stored file is no longer on the phone. They stay listed so
  /// the user can see and remove them; nothing is recreated.
  final Set<String> missingIds;

  /// The index could not be read, was kept aside, and was rebuilt from the
  /// stored files themselves.
  final bool recoveredFromDamagedIndex;
}

/// The outcome of removing several documents.
class ImagePdfDeleteOutcome {
  const ImagePdfDeleteOutcome({
    required this.deleted,
    required this.failed,
    required this.notFound,
  });

  final List<String> deleted;
  final List<String> failed;
  final List<String> notFound;
}

enum _EntryState { pending, ready, deleting }

class _Entry {
  _Entry(this.document, this.state);

  ImagePdfDocument document;
  _EntryState state;
}

class _IndexState {
  _IndexState(this.entries, this.rebuilt);

  final List<_Entry> entries;
  final bool rebuilt;
}

/// The Images to PDF tool's private document store for ONE signed-in account.
///
/// It follows the Scanner's and Combine's stores: `<base>/image_to_pdf/<account>/`
/// holds `files/<id>.pdf` (named by an internal id, never by what the user
/// typed), `index.json` (titles, dates, counts, written to a temporary file and
/// renamed), `work/` (where a conversion writes its draft before it is stored)
/// and `staging/` (the private copies of the pictures the user selected).
/// Another account never reads this folder, and the index records its owner and
/// is refused when it names someone else.
///
/// Saving is journaled: the index first lists the new document as `pending`; the
/// file is copied to `<id>.pdf.part`, read back and checked (size, protection
/// and page count), and only then renamed; the index is then rewritten with the
/// document `ready`. A failure removes what this save created and leaves every
/// existing document untouched, and a crash is finished or undone by the next
/// [load]. Deleting is journaled the same way. A damaged index is set aside
/// (never deleted) and rebuilt from the valid files. Operations run one at a
/// time.
class ImagePdfStore {
  ImagePdfStore({
    required this.accountDir,
    required this.userId,
    required ImagePdfFileVerifier verify,
    ImagePdfFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _verify = verify,
        _copier = copier ?? _plainCopy,
        _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? (() => const Uuid().v4());

  final Directory accountDir;
  final String userId;
  final ImagePdfFileVerifier _verify;
  final ImagePdfFileCopier _copier;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<void> _tail = Future<void>.value();
  final Set<String> _activeWork = <String>{};

  static Future<void> _plainCopy(File source, File destination) async {
    await source.copy(destination.path);
  }

  /// The folder, directly under the app's documents folder, that holds every
  /// account's PDFs. Backup rules name it.
  static const String rootFolderName = 'image_to_pdf';

  /// `<base>/image_to_pdf/<account>`: the folder of [userId]. The account id is
  /// the folder name when it is plain (a UUID is); anything else is hex encoded,
  /// so no id can name a parent folder.
  static Directory accountDirectory(Directory base, String userId) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final plain = RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(userId);
    final name = plain
        ? userId
        : 'u_${utf8.encode(userId).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    return Directory(p.join(base.path, rootFolderName, name));
  }

  Directory get _filesDir => Directory(p.join(accountDir.path, 'files'));
  Directory get _workDir => Directory(p.join(accountDir.path, 'work'));
  Directory get stagingDirectory =>
      Directory(p.join(accountDir.path, 'staging'));
  File get _indexFile => File(p.join(accountDir.path, 'index.json'));

  /// The stored file of [document].
  File fileOf(ImagePdfDocument document) =>
      File(p.join(_filesDir.path, document.fileName));

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// A fresh path inside this account's `work/` folder for a conversion to
  /// write to. The file is the caller's to release; a crash leaves it for the
  /// next [load] to sweep.
  Future<File> newWorkFile() async {
    await _workDir.create(recursive: true);
    final file = File(p.join(_workDir.path, '${_newId()}.pdf'));
    _activeWork.add(file.path);
    return file;
  }

  /// Removes a work file (and any half-written sibling) and stops protecting it
  /// from the sweep.
  Future<void> releaseWorkFile(File file) async {
    _activeWork.remove(file.path);
    await _quietDelete(file);
    await _quietDelete(File('${file.path}.part'));
  }

  /// A fresh path inside `staging/` for a private copy of a selected picture.
  Future<File> newStagingFile(String extension) async {
    await stagingDirectory.create(recursive: true);
    final safe =
        RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension) ? extension : 'img';
    return File(p.join(stagingDirectory.path, '${_newId()}.$safe'));
  }

  /// Deletes every staged copy. Selections do not survive the app, so this is
  /// called when the tool opens for the account, before anything is staged.
  Future<void> sweepStaging() async {
    try {
      if (await stagingDirectory.exists()) {
        await for (final item in stagingDirectory.list(followLinks: false)) {
          if (item is File) await _quietDelete(item);
        }
      }
    } on FileSystemException {
      // Only clutter; tried again next time.
    }
  }

  // ---------------------------------------------------------------- reading

  /// Reads the account's documents, finishing or undoing any interrupted save
  /// or delete first.
  Future<ImagePdfLibrary> load() => _serial(_loadLocked);

  Future<ImagePdfLibrary> _loadLocked() async {
    final state = await _readIndex();
    await _removeAbandonedParts();
    var changed = state.rebuilt;
    final kept = <_Entry>[];
    for (final entry in state.entries) {
      switch (entry.state) {
        case _EntryState.ready:
          kept.add(entry);
        case _EntryState.pending:
          changed = true;
          if (await _isWhole(entry.document)) {
            entry.state = _EntryState.ready;
            kept.add(entry);
          } else {
            await _quietDelete(fileOf(entry.document));
          }
        case _EntryState.deleting:
          changed = true;
          try {
            await _deleteIfPresent(fileOf(entry.document));
          } catch (_) {
            // Still there: leave it listed rather than lose track of it.
            entry.state = _EntryState.ready;
            kept.add(entry);
          }
      }
    }
    if (changed) {
      try {
        await _writeIndex(kept);
      } on ImagePdfException {
        // The in-memory view is still right; the next load repeats this.
      }
    }
    final missing = <String>{};
    for (final entry in kept) {
      if (!await fileOf(entry.document).exists()) {
        missing.add(entry.document.id);
      }
    }
    return ImagePdfLibrary(
      documents: _sorted(kept.map((e) => e.document)),
      missingIds: missing,
      recoveredFromDamagedIndex: state.rebuilt,
    );
  }

  bool _matches(ImagePdfFileInfo inspected, ImagePdfDocument document) {
    if (inspected.size != document.fileSize) return false;
    if (inspected.encrypted != document.encrypted) return false;
    return document.encrypted || inspected.pageCount == document.pageCount;
  }

  Future<bool> _isWhole(ImagePdfDocument document) async {
    try {
      final file = fileOf(document);
      if (!await file.exists()) return false;
      return _matches(await _verify(file), document);
    } on ImagePdfException {
      return false;
    }
  }

  List<ImagePdfDocument> _sorted(Iterable<ImagePdfDocument> documents) {
    final list = documents.toList();
    list.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return list;
  }

  // ------------------------------------------------------------------ index

  Future<_IndexState> _readIndex() async {
    final index = _indexFile;
    if (!await index.exists()) {
      final rebuilt = await _rebuildFromFiles();
      return _IndexState(rebuilt, rebuilt.isNotEmpty);
    }
    try {
      final decoded = jsonDecode(await index.readAsString());
      if (decoded is! Map || decoded['userId'] != userId) {
        throw const FormatException('index belongs to another account');
      }
      final raw = decoded['entries'];
      if (raw is! List) throw const FormatException('no entries');
      final entries = <_Entry>[];
      for (final item in raw) {
        if (item is! Map) throw const FormatException('bad entry');
        final state = _EntryState.values.where((s) => s.name == item['state']);
        if (state.isEmpty) throw const FormatException('bad state');
        entries.add(
            _Entry(ImagePdfDocument.fromJson(item['document']), state.first));
      }
      return _IndexState(entries, false);
    } on FormatException {
      return _quarantineAndRebuild();
    } on FileSystemException {
      return _quarantineAndRebuild();
    }
  }

  Future<_IndexState> _quarantineAndRebuild() async {
    try {
      final stamp = _clock().millisecondsSinceEpoch;
      await _indexFile
          .rename(p.join(accountDir.path, 'index.damaged-$stamp.json'));
    } on FileSystemException {
      // Left in place; the rebuilt index overwrites it only if the write works,
      // and the damaged text is never the only copy of any document's bytes.
    }
    return _IndexState(await _rebuildFromFiles(), true);
  }

  /// Entries for the valid files in `files/`, for an account whose index is
  /// missing or damaged. Their titles are generic: the titles are what the lost
  /// index held.
  Future<List<_Entry>> _rebuildFromFiles() async {
    final folder = _filesDir;
    if (!await folder.exists()) return <_Entry>[];
    final entries = <_Entry>[];
    final taken = <String>[];
    await for (final item in folder.list(followLinks: false)) {
      if (item is! File) continue;
      final fileName = p.basename(item.path);
      if (!ImagePdfNaming.isStoredFileName(fileName)) continue;
      try {
        final inspected = await _verify(item);
        final stat = await item.stat();
        final name = ImagePdfNaming.uniqueName('Recovered PDF', taken);
        taken.add(name);
        entries.add(_Entry(
          ImagePdfDocument(
            id: p.basenameWithoutExtension(fileName),
            fileName: fileName,
            name: name,
            createdAt: stat.modified,
            fileSize: inspected.size,
            pageCount: inspected.pageCount,
            imageCount: 0,
            encrypted: inspected.encrypted,
          ),
          _EntryState.ready,
        ));
      } on ImagePdfException {
        continue;
      }
    }
    return entries;
  }

  Future<void> _writeIndex(List<_Entry> entries) async {
    final temp = File('${_indexFile.path}.tmp');
    try {
      await accountDir.create(recursive: true);
      final text = jsonEncode(<String, Object?>{
        'version': 1,
        'userId': userId,
        'entries': <Object?>[
          for (final e in entries)
            <String, Object?>{
              'state': e.state.name,
              'document': e.document.toJson(),
            },
        ],
      });
      await temp.writeAsString(text, flush: true);
      await temp.rename(_indexFile.path);
    } on FileSystemException catch (error) {
      await _quietDelete(temp);
      throw _mapFileError(error);
    }
  }

  /// Finishes or undoes anything an earlier run left half done, then returns
  /// the settled entries every mutation starts from.
  Future<List<_Entry>> _prepare() async {
    await _loadLocked();
    return (await _readIndex()).entries;
  }

  Future<void> _removeAbandonedParts() async {
    try {
      if (await _filesDir.exists()) {
        await for (final item in _filesDir.list(followLinks: false)) {
          if (item is File && item.path.endsWith('.part')) {
            await _quietDelete(item);
          }
        }
      }
      if (await _workDir.exists()) {
        await for (final item in _workDir.list(followLinks: false)) {
          if (item is! File) continue;
          final base = item.path.endsWith('.part')
              ? item.path.substring(0, item.path.length - 5)
              : item.path;
          if (!_activeWork.contains(base)) await _quietDelete(item);
        }
      }
      await _quietDelete(File('${_indexFile.path}.tmp'));
    } on FileSystemException {
      // Abandoned parts are only clutter; they are tried again next time.
    }
  }

  // ----------------------------------------------------------------- adding

  /// Stores [source] (a finished PDF whose pages and size were just read as
  /// [expected]) under the title [name], made unique among the account's
  /// documents. Either the document is saved, verified and listed, or nothing is
  /// and the existing documents are untouched. Throws an [ImagePdfException]
  /// (`storageFull` or `writeFailed`).
  Future<ImagePdfDocument> add({
    required File source,
    required String name,
    required ImagePdfFileInfo expected,
    required int pageCount,
    required int imageCount,
  }) {
    return _serial(() async {
      final entries = await _prepare();
      final taken = <String>[for (final e in entries) e.document.name];
      final id = _newId();
      final created = ImagePdfDocument(
        id: id,
        fileName: '$id.pdf',
        name: ImagePdfNaming.uniqueName(name, taken),
        createdAt: _clock(),
        fileSize: expected.size,
        pageCount: pageCount,
        imageCount: imageCount,
        encrypted: expected.encrypted,
      );
      await _writeIndex(<_Entry>[
        ...entries,
        _Entry(created, _EntryState.pending),
      ]);
      final target = fileOf(created);
      final part = File('${target.path}.part');
      try {
        await _filesDir.create(recursive: true);
        await _copier(source, part);
        await _verifyCopy(part, created);
        await part.rename(target.path);
        await _writeIndex(<_Entry>[
          ...entries,
          _Entry(created, _EntryState.ready),
        ]);
      } catch (error) {
        await _quietDelete(part);
        await _quietDelete(target);
        try {
          await _writeIndex(entries);
        } on ImagePdfException {
          // The next load drops the pending entry, whose file is gone.
        }
        if (error is ImagePdfException) rethrow;
        if (error is FileSystemException) throw _mapFileError(error);
        throw const ImagePdfException(ImagePdfFailure.writeFailed,
            detail: 'add');
      }
      return created;
    });
  }

  Future<void> _verifyCopy(File copy, ImagePdfDocument expected) async {
    final int size;
    try {
      size = await copy.length();
    } on FileSystemException {
      throw const ImagePdfException(ImagePdfFailure.writeFailed,
          detail: 'verify');
    }
    if (size != expected.fileSize) {
      throw const ImagePdfException(ImagePdfFailure.writeFailed,
          detail: 'size');
    }
    try {
      final actual = await _verify(copy);
      if (!_matches(actual, expected)) {
        throw const ImagePdfException(ImagePdfFailure.writeFailed,
            detail: 'content');
      }
    } on ImagePdfException catch (error) {
      if (error.kind == ImagePdfFailure.writeFailed) rethrow;
      throw const ImagePdfException(ImagePdfFailure.writeFailed,
          detail: 'content');
    }
  }

  // --------------------------------------------------------------- renaming

  /// Gives a document a new title. The stored file keeps its internal name;
  /// only the index changes. Throws `invalidName`, `nameInUse`, `notFound` or
  /// `writeFailed`.
  Future<ImagePdfDocument> rename(String id, String newName) {
    return _serial(() async {
      final name = ImagePdfNaming.sanitizeDisplayName(newName);
      if (name == null) {
        throw const ImagePdfException(ImagePdfFailure.invalidName);
      }
      final entries = await _prepare();
      final index = entries.indexWhere(
          (e) => e.document.id == id && e.state == _EntryState.ready);
      if (index < 0) {
        throw const ImagePdfException(ImagePdfFailure.notFound);
      }
      final clash = entries.any((e) =>
          e.document.id != id &&
          e.state != _EntryState.deleting &&
          e.document.name.toLowerCase() == name.toLowerCase());
      if (clash) {
        throw const ImagePdfException(ImagePdfFailure.nameInUse);
      }
      final updated = entries[index].document.copyWith(name: name);
      final next = <_Entry>[
        for (var i = 0; i < entries.length; i++)
          i == index ? _Entry(updated, _EntryState.ready) : entries[i],
      ];
      await _writeIndex(next);
      return updated;
    });
  }

  // --------------------------------------------------------------- deleting

  /// Removes the listed documents and their stored files, and nothing else.
  Future<ImagePdfDeleteOutcome> delete(Iterable<String> ids) {
    return _serial(() async {
      final wanted = ids.toSet();
      final entries = await _prepare();
      final targets = entries
          .where((e) =>
              wanted.contains(e.document.id) && e.state == _EntryState.ready)
          .toList();
      final found = targets.map((e) => e.document.id).toSet();
      final notFound = <String>[
        for (final id in wanted)
          if (!found.contains(id)) id,
      ];
      if (targets.isEmpty) {
        return ImagePdfDeleteOutcome(
            deleted: const <String>[],
            failed: const <String>[],
            notFound: notFound);
      }
      for (final target in targets) {
        target.state = _EntryState.deleting;
      }
      try {
        await _writeIndex(entries);
      } catch (_) {
        for (final target in targets) {
          target.state = _EntryState.ready;
        }
        rethrow;
      }
      final deleted = <String>[];
      final failed = <String>[];
      for (final target in targets) {
        try {
          await _deleteIfPresent(fileOf(target.document));
          deleted.add(target.document.id);
        } catch (_) {
          failed.add(target.document.id);
          target.state = _EntryState.ready;
        }
      }
      final remaining = <_Entry>[
        for (final e in entries)
          if (!deleted.contains(e.document.id)) e,
      ];
      try {
        await _writeIndex(remaining);
      } on ImagePdfException {
        // The files are gone; the next load finishes removing the entries.
      }
      return ImagePdfDeleteOutcome(
          deleted: deleted, failed: failed, notFound: notFound);
    });
  }

  // ------------------------------------------------------------------ check

  /// Whether [document]'s stored file is still the complete file that was
  /// saved: present, the same size, and a readable PDF with the same pages (a
  /// protected file: still protected).
  Future<bool> isIntact(ImagePdfDocument document) async {
    try {
      return _matches(await _verify(fileOf(document)), document);
    } on ImagePdfException {
      return false;
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> _quietDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  ImagePdfException _mapFileError(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112) {
      return const ImagePdfException(ImagePdfFailure.storageFull);
    }
    return const ImagePdfException(ImagePdfFailure.writeFailed, detail: 'io');
  }
}
