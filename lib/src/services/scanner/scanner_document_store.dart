import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/scanner/scan_file_inspector.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';

/// Copies [source] to [destination]. A seam so a test can make a copy fail or
/// stop half way; the default is a plain file copy.
typedef ScannerFileCopier = Future<void> Function(
    File source, File destination);

/// One verified scan file about to be stored.
class ScannerNewDocument {
  const ScannerNewDocument({
    required this.source,
    required this.inspected,
    required this.name,
    required this.scanType,
    this.batchId,
    this.batchIndex = 0,
  });

  /// A local file whose [inspected] facts were just read from it.
  final File source;
  final InspectedScanFile inspected;

  /// The title; made unique among the account's documents when stored.
  final String name;
  final ScanMode scanType;
  final String? batchId;
  final int batchIndex;
}

/// What the store holds for one account right now.
class ScannerLibrary {
  const ScannerLibrary({
    required this.documents,
    this.missingIds = const <String>{},
    this.recoveredFromDamagedIndex = false,
  });

  /// Newest first; the pages of one image scan stay in their order.
  final List<ScannerDocument> documents;

  /// Documents whose stored file is no longer on the phone. They stay listed so
  /// the user can see and remove them; nothing is recreated.
  final Set<String> missingIds;

  /// The index could not be read, was kept aside, and was rebuilt from the
  /// stored files themselves.
  final bool recoveredFromDamagedIndex;
}

/// The outcome of removing several documents.
class ScannerDeleteOutcome {
  const ScannerDeleteOutcome({
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

  ScannerDocument document;
  _EntryState state;
}

/// The Scanner's private document store for ONE signed-in account.
///
/// Each account has its own folder, `<base>/scanner/<account>/`, holding
/// `files/<id>.<ext>` (the documents, named by an internal id and never by what
/// the user typed) and `index.json` (titles, dates, counts). Another account
/// never reads this folder, and the index records its owner and is refused when
/// it names someone else.
///
/// Saving is journaled so no step can leave a half-made document that looks
/// complete. The index first lists the new documents as `pending`; each file
/// is copied to `<id>.<ext>.part`, checked (size and a full inspection), and
/// only then renamed to its final name; the index is then rewritten with the
/// documents `ready`, by writing a temporary file and renaming it over the old
/// index. A failure at any point removes what this save created and leaves
/// every existing document untouched. If the app dies mid-way, the next
/// [load] finishes or undoes the save: a `pending` document whose file is whole
/// is kept, otherwise it is dropped. Deleting is journaled the same way
/// (`deleting`), so a deleted document cannot reappear.
///
/// A damaged index is moved aside (never deleted) and rebuilt from the valid
/// files in `files/`. All operations run one at a time.
class ScannerDocumentStore {
  ScannerDocumentStore({
    required this.accountDir,
    required this.userId,
    required ScanFileInspector inspector,
    ScannerFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _inspector = inspector,
        _copier = copier ?? _plainCopy,
        _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? (() => const Uuid().v4());

  final Directory accountDir;
  final String userId;
  final ScanFileInspector _inspector;
  final ScannerFileCopier _copier;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<void> _tail = Future<void>.value();

  static Future<void> _plainCopy(File source, File destination) async {
    await source.copy(destination.path);
  }

  /// `<base>/scanner/<account>`: the folder of [userId]. The account id is used
  /// as the folder name when it is plain (a UUID is); anything else is hex
  /// encoded, so no id can name a parent folder.
  static Directory accountDirectory(Directory base, String userId) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final plain = RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(userId);
    final name = plain
        ? userId
        : 'u_${utf8.encode(userId).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    return Directory(p.join(base.path, 'scanner', name));
  }

  Directory get _filesDir => Directory(p.join(accountDir.path, 'files'));
  File get _indexFile => File(p.join(accountDir.path, 'index.json'));

  /// The stored file of [document].
  File fileOf(ScannerDocument document) =>
      File(p.join(_filesDir.path, document.fileName));

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  // ---------------------------------------------------------------- reading

  /// Reads the account's documents, finishing or undoing any interrupted save
  /// or delete first.
  Future<ScannerLibrary> load() => _serial(_loadLocked);

  Future<ScannerLibrary> _loadLocked() async {
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
      } on ScannerException {
        // The in-memory view is still right; the next load repeats this.
      }
    }
    final missing = <String>{};
    for (final entry in kept) {
      if (!await fileOf(entry.document).exists()) {
        missing.add(entry.document.id);
      }
    }
    return ScannerLibrary(
      documents: _sorted(kept.map((e) => e.document)),
      missingIds: missing,
      recoveredFromDamagedIndex: state.rebuilt,
    );
  }

  Future<bool> _isWhole(ScannerDocument document) async {
    try {
      final file = fileOf(document);
      if (!await file.exists()) return false;
      final inspected = await _inspector.inspect(file);
      return inspected.size == document.fileSize &&
          inspected.kind.extension == document.extension;
    } on ScannerException {
      return false;
    }
  }

  List<ScannerDocument> _sorted(Iterable<ScannerDocument> documents) {
    final list = documents.toList();
    list.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      if (byDate != 0) return byDate;
      final byPage = a.batchIndex.compareTo(b.batchIndex);
      if (byPage != 0) return byPage;
      return a.id.compareTo(b.id);
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
            _Entry(ScannerDocument.fromJson(item['document']), state.first));
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
  /// missing or damaged. Their titles are generic: the titles are what the
  /// lost index held.
  Future<List<_Entry>> _rebuildFromFiles() async {
    final folder = _filesDir;
    if (!await folder.exists()) return <_Entry>[];
    final entries = <_Entry>[];
    final taken = <String>[];
    await for (final item in folder.list(followLinks: false)) {
      if (item is! File) continue;
      final fileName = p.basename(item.path);
      if (!ScannerNaming.isStoredFileName(fileName)) continue;
      try {
        final inspected = await _inspector.inspect(item);
        final stat = await item.stat();
        final name = ScannerNaming.uniqueName('Recovered scan', taken);
        taken.add(name);
        entries.add(_Entry(
          ScannerDocument(
            id: p.basenameWithoutExtension(fileName),
            fileName: fileName,
            name: name,
            scanType: ScanMode.document,
            format: inspected.kind.format,
            mimeType: inspected.kind.mimeType,
            createdAt: stat.modified,
            fileSize: inspected.size,
            pageCount: inspected.pageCount,
          ),
          _EntryState.ready,
        ));
      } on ScannerException {
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
    final folder = _filesDir;
    try {
      if (!await folder.exists()) return;
      await for (final item in folder.list(followLinks: false)) {
        if (item is File && item.path.endsWith('.part')) {
          await _quietDelete(item);
        }
      }
      await _quietDelete(File('${_indexFile.path}.tmp'));
    } on FileSystemException {
      // Abandoned parts are only clutter; they are tried again next time.
    }
  }

  // ----------------------------------------------------------------- adding

  /// Stores [items] as one unit: either every document is saved, verified and
  /// listed, or none is and the existing documents are untouched. Throws a
  /// [ScannerException] (`storageFull` or `writeFailed`).
  Future<List<ScannerDocument>> add(List<ScannerNewDocument> items) {
    return _serial(() async {
      if (items.isEmpty) return <ScannerDocument>[];
      final entries = await _prepare();
      final taken = <String>[for (final e in entries) e.document.name];
      final now = _clock();
      final created = <ScannerDocument>[];
      for (final item in items) {
        final id = _newId();
        final name = ScannerNaming.uniqueName(item.name, taken);
        taken.add(name);
        created.add(ScannerDocument(
          id: id,
          fileName: '$id.${item.inspected.kind.extension}',
          name: name,
          scanType: item.scanType,
          format: item.inspected.kind.format,
          mimeType: item.inspected.kind.mimeType,
          createdAt: now,
          fileSize: item.inspected.size,
          pageCount: item.inspected.pageCount,
          batchId: item.batchId,
          batchIndex: item.batchIndex,
        ));
      }
      final withPending = <_Entry>[
        ...entries,
        for (final doc in created) _Entry(doc, _EntryState.pending),
      ];
      await _writeIndex(withPending);

      final finals = <File>[];
      try {
        await _filesDir.create(recursive: true);
        for (var i = 0; i < created.length; i++) {
          final target = fileOf(created[i]);
          final part = File('${target.path}.part');
          finals.add(target);
          await _copier(items[i].source, part);
          await _verifyCopy(part, items[i].inspected);
          await part.rename(target.path);
        }
        await _writeIndex(<_Entry>[
          ...entries,
          for (final doc in created) _Entry(doc, _EntryState.ready),
        ]);
      } catch (error) {
        for (final file in finals) {
          await _quietDelete(File('${file.path}.part'));
          await _quietDelete(file);
        }
        try {
          await _writeIndex(entries);
        } on ScannerException {
          // The next load drops the pending entries, whose files are gone.
        }
        if (error is ScannerException) rethrow;
        if (error is FileSystemException) throw _mapFileError(error);
        throw const ScannerException(ScannerFailure.writeFailed, 'add');
      }
      return _sorted(created);
    });
  }

  Future<void> _verifyCopy(File copy, InspectedScanFile expected) async {
    final int size;
    try {
      size = await copy.length();
    } on FileSystemException {
      throw const ScannerException(ScannerFailure.writeFailed, 'verify');
    }
    if (size != expected.size) {
      throw const ScannerException(ScannerFailure.writeFailed, 'size');
    }
    try {
      final actual = await _inspector.inspect(copy);
      if (actual.kind != expected.kind ||
          actual.pageCount != expected.pageCount) {
        throw const ScannerException(ScannerFailure.writeFailed, 'content');
      }
    } on ScannerException {
      throw const ScannerException(ScannerFailure.writeFailed, 'content');
    }
  }

  // --------------------------------------------------------------- renaming

  /// Gives a document a new title. The stored file keeps its internal name; only
  /// the index changes. Throws `invalidName`, `nameInUse`, `notFound` or
  /// `writeFailed`.
  Future<ScannerDocument> rename(String id, String newName) {
    return _serial(() async {
      final name = ScannerNaming.sanitizeDisplayName(newName);
      if (name == null) {
        throw const ScannerException(ScannerFailure.invalidName);
      }
      final entries = await _prepare();
      final index = entries.indexWhere(
          (e) => e.document.id == id && e.state == _EntryState.ready);
      if (index < 0) throw const ScannerException(ScannerFailure.notFound);
      final clash = entries.any((e) =>
          e.document.id != id &&
          e.state != _EntryState.deleting &&
          e.document.name.toLowerCase() == name.toLowerCase());
      if (clash) throw const ScannerException(ScannerFailure.nameInUse);
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
  Future<ScannerDeleteOutcome> delete(Iterable<String> ids) {
    return _serial(() async {
      final wanted = ids.toSet();
      final entries = await _prepare();
      final targets = entries
          .where((e) =>
              wanted.contains(e.document.id) && e.state == _EntryState.ready)
          .toList();
      final found = targets.map((e) => e.document.id).toSet();
      final notFound = <String>[
        for (final id in ids)
          if (!found.contains(id)) id,
      ];
      if (targets.isEmpty) {
        return ScannerDeleteOutcome(
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
      } on ScannerException {
        // The files are gone; the next load finishes removing the entries.
      }
      return ScannerDeleteOutcome(
          deleted: deleted, failed: failed, notFound: notFound);
    });
  }

  // ------------------------------------------------------------------ check

  /// Whether [document]'s stored file is still the complete file that was
  /// saved: present, the same size, and a readable PDF or image.
  Future<bool> isIntact(ScannerDocument document) async {
    try {
      final inspected = await _inspector.inspect(fileOf(document));
      return inspected.size == document.fileSize &&
          inspected.kind.extension == document.extension;
    } on ScannerException {
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

  ScannerException _mapFileError(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112) {
      return const ScannerException(ScannerFailure.storageFull);
    }
    return const ScannerException(ScannerFailure.writeFailed, 'io');
  }
}

class _IndexState {
  _IndexState(this.entries, this.rebuilt);

  final List<_Entry> entries;
  final bool rebuilt;
}
