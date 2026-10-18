import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';

/// Reads a stored or freshly written combined PDF back and says what it holds.
typedef CombineFileVerifier = Future<CombineAnalysis> Function(File file);

/// Copies [source] to [destination]. A seam so a test can make a copy fail or
/// stop half way; the default is a plain file copy.
typedef CombineFileCopier = Future<void> Function(
    File source, File destination);

/// What the store holds for one account right now.
class CombineLibrary {
  const CombineLibrary({
    required this.documents,
    this.missingIds = const <String>{},
    this.recoveredFromDamagedIndex = false,
  });

  /// Newest first.
  final List<CombinedPdf> documents;

  /// Documents whose stored file is no longer on the phone. They stay listed so
  /// the user can see and remove them; nothing is recreated.
  final Set<String> missingIds;

  /// The index could not be read, was kept aside, and was rebuilt from the
  /// stored files themselves.
  final bool recoveredFromDamagedIndex;
}

/// The outcome of removing several documents.
class CombineDeleteOutcome {
  const CombineDeleteOutcome({
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

  CombinedPdf document;
  _EntryState state;
}

class _IndexState {
  _IndexState(this.entries, this.rebuilt);

  final List<_Entry> entries;
  final bool rebuilt;
}

/// The Combine tool's private document store for ONE signed-in account.
///
/// It follows the Scanner's store: `<base>/combine_pdfs/<account>/` holds
/// `files/<id>.pdf` (named by an internal id, never by what the user typed),
/// `index.json` (titles, dates, counts, written to a temporary file and renamed)
/// and `work/` (where a combine writes before it is stored). Another account
/// never reads this folder, and the index records its owner and is refused when
/// it names someone else.
///
/// Saving is journaled: the index first lists the new document as `pending`;
/// the file is copied to `<id>.pdf.part`, read back and checked (size and page
/// count), and only then renamed; the index is then rewritten with the document
/// `ready`. A failure removes what this save created and leaves every existing
/// document untouched, and a crash is finished or undone by the next [load].
/// Deleting is journaled the same way. A damaged index is set aside (never
/// deleted) and rebuilt from the valid files. Operations run one at a time.
class CombinePdfStore {
  CombinePdfStore({
    required this.accountDir,
    required this.userId,
    required CombineFileVerifier verify,
    CombineFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _verify = verify,
        _copier = copier ?? _plainCopy,
        _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? (() => const Uuid().v4());

  final Directory accountDir;
  final String userId;
  final CombineFileVerifier _verify;
  final CombineFileCopier _copier;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<void> _tail = Future<void>.value();
  final Set<String> _activeWork = <String>{};

  static Future<void> _plainCopy(File source, File destination) async {
    await source.copy(destination.path);
  }

  /// `<base>/combine_pdfs/<account>`: the folder of [userId]. The account id is
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

  /// The folder, directly under the app's documents folder, that holds every
  /// account's combined PDFs. Backup rules name it.
  static const String rootFolderName = 'combine_pdfs';

  Directory get _filesDir => Directory(p.join(accountDir.path, 'files'));
  Directory get _workDir => Directory(p.join(accountDir.path, 'work'));
  File get _indexFile => File(p.join(accountDir.path, 'index.json'));

  /// The stored file of [document].
  File fileOf(CombinedPdf document) =>
      File(p.join(_filesDir.path, document.fileName));

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// A fresh path inside this account's `work/` folder for a combine to write
  /// to. The file is the caller's to delete; a crash leaves it for the next
  /// [load] to sweep.
  Future<File> newWorkFile() async {
    await _workDir.create(recursive: true);
    final file = File(p.join(_workDir.path, '${_newId()}.pdf'));
    _activeWork.add(file.path);
    return file;
  }

  /// Removes a work file and stops protecting it from the sweep.
  Future<void> releaseWorkFile(File file) async {
    _activeWork.remove(file.path);
    await _quietDelete(file);
  }

  // ---------------------------------------------------------------- reading

  /// Reads the account's documents, finishing or undoing any interrupted save
  /// or delete first.
  Future<CombineLibrary> load() => _serial(_loadLocked);

  Future<CombineLibrary> _loadLocked() async {
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
      } on CombinePdfException {
        // The in-memory view is still right; the next load repeats this.
      }
    }
    final missing = <String>{};
    for (final entry in kept) {
      if (!await fileOf(entry.document).exists()) {
        missing.add(entry.document.id);
      }
    }
    return CombineLibrary(
      documents: _sorted(kept.map((e) => e.document)),
      missingIds: missing,
      recoveredFromDamagedIndex: state.rebuilt,
    );
  }

  Future<bool> _isWhole(CombinedPdf document) async {
    try {
      final file = fileOf(document);
      if (!await file.exists()) return false;
      final inspected = await _verify(file);
      return inspected.size == document.fileSize &&
          inspected.pageCount == document.pageCount;
    } on CombinePdfException {
      return false;
    }
  }

  List<CombinedPdf> _sorted(Iterable<CombinedPdf> documents) {
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
        entries
            .add(_Entry(CombinedPdf.fromJson(item['document']), state.first));
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
      if (!CombineNaming.isStoredFileName(fileName)) continue;
      try {
        final inspected = await _verify(item);
        final stat = await item.stat();
        final name = CombineNaming.uniqueName('Recovered PDF', taken);
        taken.add(name);
        entries.add(_Entry(
          CombinedPdf(
            id: p.basenameWithoutExtension(fileName),
            fileName: fileName,
            name: name,
            createdAt: stat.modified,
            fileSize: inspected.size,
            pageCount: inspected.pageCount,
          ),
          _EntryState.ready,
        ));
      } on CombinePdfException {
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
          if (item is File && !_activeWork.contains(item.path)) {
            await _quietDelete(item);
          }
        }
      }
      await _quietDelete(File('${_indexFile.path}.tmp'));
    } on FileSystemException {
      // Abandoned parts are only clutter; they are tried again next time.
    }
  }

  // ----------------------------------------------------------------- adding

  /// Stores [source] (a finished combined PDF whose pages and size were just
  /// read as [expected]) under the title [name], made unique among the
  /// account's documents. Either the document is saved, verified and listed, or
  /// nothing is and the existing documents are untouched. Throws a
  /// [CombinePdfException] (`storageFull` or `writeFailed`).
  Future<CombinedPdf> add({
    required File source,
    required String name,
    required CombineAnalysis expected,
  }) {
    return _serial(() async {
      final entries = await _prepare();
      final taken = <String>[for (final e in entries) e.document.name];
      final id = _newId();
      final created = CombinedPdf(
        id: id,
        fileName: '$id.pdf',
        name: CombineNaming.uniqueName(name, taken),
        createdAt: _clock(),
        fileSize: expected.size,
        pageCount: expected.pageCount,
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
        await _verifyCopy(part, expected);
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
        } on CombinePdfException {
          // The next load drops the pending entry, whose file is gone.
        }
        if (error is CombinePdfException) rethrow;
        if (error is FileSystemException) throw _mapFileError(error);
        throw const CombinePdfException(CombinePdfFailure.writeFailed,
            detail: 'add');
      }
      return created;
    });
  }

  Future<void> _verifyCopy(File copy, CombineAnalysis expected) async {
    final int size;
    try {
      size = await copy.length();
    } on FileSystemException {
      throw const CombinePdfException(CombinePdfFailure.writeFailed,
          detail: 'verify');
    }
    if (size != expected.size) {
      throw const CombinePdfException(CombinePdfFailure.writeFailed,
          detail: 'size');
    }
    try {
      final actual = await _verify(copy);
      if (actual.pageCount != expected.pageCount) {
        throw const CombinePdfException(CombinePdfFailure.writeFailed,
            detail: 'content');
      }
    } on CombinePdfException catch (error) {
      if (error.kind == CombinePdfFailure.writeFailed) rethrow;
      throw const CombinePdfException(CombinePdfFailure.writeFailed,
          detail: 'content');
    }
  }

  // --------------------------------------------------------------- renaming

  /// Gives a document a new title. The stored file keeps its internal name;
  /// only the index changes. Throws `invalidName`, `nameInUse`, `notFound` or
  /// `writeFailed`.
  Future<CombinedPdf> rename(String id, String newName) {
    return _serial(() async {
      final name = CombineNaming.sanitizeDisplayName(newName);
      if (name == null) {
        throw const CombinePdfException(CombinePdfFailure.invalidName);
      }
      final entries = await _prepare();
      final index = entries.indexWhere(
          (e) => e.document.id == id && e.state == _EntryState.ready);
      if (index < 0) {
        throw const CombinePdfException(CombinePdfFailure.notFound);
      }
      final clash = entries.any((e) =>
          e.document.id != id &&
          e.state != _EntryState.deleting &&
          e.document.name.toLowerCase() == name.toLowerCase());
      if (clash) {
        throw const CombinePdfException(CombinePdfFailure.nameInUse);
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
  Future<CombineDeleteOutcome> delete(Iterable<String> ids) {
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
        return CombineDeleteOutcome(
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
      } on CombinePdfException {
        // The files are gone; the next load finishes removing the entries.
      }
      return CombineDeleteOutcome(
          deleted: deleted, failed: failed, notFound: notFound);
    });
  }

  // ------------------------------------------------------------------ check

  /// Whether [document]'s stored file is still the complete file that was
  /// saved: present, the same size, and a readable PDF with the same pages.
  Future<bool> isIntact(CombinedPdf document) async {
    try {
      final inspected = await _verify(fileOf(document));
      return inspected.size == document.fileSize &&
          inspected.pageCount == document.pageCount;
    } on CombinePdfException {
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

  CombinePdfException _mapFileError(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112) {
      return const CombinePdfException(CombinePdfFailure.storageFull);
    }
    return const CombinePdfException(CombinePdfFailure.writeFailed,
        detail: 'io');
  }
}
