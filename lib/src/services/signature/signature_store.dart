import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/services/signature/signature_models.dart';

/// Reads a stored or freshly written signed PDF back and says what it holds.
typedef SignatureFileVerifier = Future<SignatureAnalysis> Function(File file);

/// Copies [source] to [destination]. A seam so a test can make a copy fail or
/// stop half way; the default is a plain file copy.
typedef SignatureFileCopier = Future<void> Function(
    File source, File destination);

/// What the store holds for one account right now.
class SignatureLibrary {
  const SignatureLibrary({
    required this.documents,
    this.missingIds = const <String>{},
    this.recoveredFromDamagedIndex = false,
  });

  /// Newest first.
  final List<SignedDocument> documents;

  /// Documents whose stored file is no longer on the phone. They stay listed so
  /// the user can see and remove them; nothing is recreated.
  final Set<String> missingIds;

  /// The index could not be read, was kept aside, and was rebuilt from the
  /// stored files themselves.
  final bool recoveredFromDamagedIndex;
}

/// The outcome of removing several documents.
class SignatureDeleteOutcome {
  const SignatureDeleteOutcome({
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

  SignedDocument document;
  _EntryState state;
}

class _IndexState {
  _IndexState(this.entries, this.rebuilt);

  final List<_Entry> entries;
  final bool rebuilt;
}

/// The Signature tool's private document store for ONE signed-in account.
///
/// It follows the Scanner's and Combine's store: `<base>/signature_pdfs/<account>/`
/// holds `files/<id>.pdf` (named by an internal id, never by what the user
/// typed), `index.json` (titles, dates, counts, written to a temporary file and
/// renamed) and `work/` (where a signed draft is written before it is stored).
/// Another account never reads this folder, and the index records its owner and
/// is refused when it names someone else.
///
/// The folder is new: documents an earlier version kept in `signed_documents/`
/// and in the device-wide `signed_documents_list` preference carry no owner, so
/// this store neither reads, moves nor deletes them.
///
/// Saving is journaled: the index first lists the new document as `pending`; the
/// file is copied to `<id>.pdf.part`, compared byte for byte with the draft and
/// read back as a PDF, and only then renamed; the index is then rewritten with
/// the document `ready`. A failure removes what this save created and leaves
/// every existing document untouched, and a crash is finished or undone by the
/// next [load]. Deleting is journaled the same way. A damaged index is set aside
/// (never deleted) and rebuilt from the valid files. Operations run one at a
/// time.
class SignatureStore {
  SignatureStore({
    required this.accountDir,
    required this.userId,
    required SignatureFileVerifier verify,
    SignatureFileCopier? copier,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _verify = verify,
        _copier = copier ?? _plainCopy,
        _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? (() => const Uuid().v4());

  final Directory accountDir;
  final String userId;
  final SignatureFileVerifier _verify;
  final SignatureFileCopier _copier;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<void> _tail = Future<void>.value();
  final Set<String> _activeWork = <String>{};

  static Future<void> _plainCopy(File source, File destination) async {
    await source.copy(destination.path);
  }

  /// The folder, directly under the app's documents folder, that holds every
  /// account's signed documents. Backup rules name it.
  static const String rootFolderName = 'signature_pdfs';

  /// `<base>/signature_pdfs/<account>`: the folder of [userId]. The account id is
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
  File get _indexFile => File(p.join(accountDir.path, 'index.json'));

  /// The stored file of [document].
  File fileOf(SignedDocument document) =>
      File(p.join(_filesDir.path, document.fileName));

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// A fresh path inside this account's `work/` folder for a signed draft to be
  /// written to. The file is the caller's to delete; a crash leaves it for the
  /// next [load] to sweep.
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

  /// Reads the account's documents, finishing or undoing any interrupted save or
  /// delete first.
  Future<SignatureLibrary> load() => _serial(_loadLocked);

  Future<SignatureLibrary> _loadLocked() async {
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
      } on SignatureException {
        // The in-memory view is still right; the next load repeats this.
      }
    }
    final missing = <String>{};
    for (final entry in kept) {
      if (!await fileOf(entry.document).exists()) {
        missing.add(entry.document.id);
      }
    }
    return SignatureLibrary(
      documents: _sorted(kept.map((e) => e.document)),
      missingIds: missing,
      recoveredFromDamagedIndex: state.rebuilt,
    );
  }

  Future<bool> _isWhole(SignedDocument document) async {
    try {
      final file = fileOf(document);
      if (!await file.exists()) return false;
      final inspected = await _verify(file);
      return inspected.size == document.fileSize &&
          inspected.pageCount == document.pageCount;
    } on SignatureException {
      return false;
    }
  }

  List<SignedDocument> _sorted(Iterable<SignedDocument> documents) {
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
            _Entry(SignedDocument.fromJson(item['document']), state.first));
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
  /// missing or damaged. Their titles are generic and their counts unknown (zero):
  /// the titles and counts are what the lost index held.
  Future<List<_Entry>> _rebuildFromFiles() async {
    final folder = _filesDir;
    if (!await folder.exists()) return <_Entry>[];
    final entries = <_Entry>[];
    final taken = <String>[];
    await for (final item in folder.list(followLinks: false)) {
      if (item is! File) continue;
      final fileName = p.basename(item.path);
      if (!SignatureNaming.isStoredFileName(fileName)) continue;
      try {
        final inspected = await _verify(item);
        final stat = await item.stat();
        final name = SignatureNaming.uniqueName('Recovered PDF', taken);
        taken.add(name);
        entries.add(_Entry(
          SignedDocument(
            id: p.basenameWithoutExtension(fileName),
            fileName: fileName,
            name: name,
            createdAt: stat.modified,
            fileSize: inspected.size,
            pageCount: inspected.pageCount,
            signatureCount: 0,
            itemCount: 0,
          ),
          _EntryState.ready,
        ));
      } on SignatureException {
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

  /// Finishes or undoes anything an earlier run left half done, then returns the
  /// settled entries every mutation starts from.
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

  /// Stores [source] (a finished signed PDF whose size and pages were just
  /// read) under the title [name], made unique among the account's documents.
  /// Either the document is saved, verified and listed, or nothing is and the
  /// existing documents are untouched. The stored file is proved to be the same
  /// bytes as [source]. Throws a [SignatureException] (`storageFull` or
  /// `writeFailed`).
  Future<SignedDocument> add({
    required File source,
    required String name,
    required int size,
    required int pageCount,
    required int signatureCount,
    required int itemCount,
  }) {
    return _serial(() async {
      final entries = await _prepare();
      final taken = <String>[for (final e in entries) e.document.name];
      final id = _newId();
      final created = SignedDocument(
        id: id,
        fileName: '$id.pdf',
        name: SignatureNaming.uniqueName(name, taken),
        createdAt: _clock(),
        fileSize: size,
        pageCount: pageCount,
        signatureCount: signatureCount,
        itemCount: itemCount,
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
        await _verifyCopy(source, part, size, pageCount);
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
        } on SignatureException {
          // The next load drops the pending entry, whose file is gone.
        }
        if (error is SignatureException) rethrow;
        if (error is FileSystemException) throw _mapFileError(error);
        throw const SignatureException(SignatureFailure.writeFailed,
            detail: 'add');
      }
      return created;
    });
  }

  /// Stores [source], a signed PDF downloaded from the account's cloud, under the
  /// SAME id it has there, so the phone and the account name it alike. Either it
  /// is listed with a verified file, or nothing is. Idempotent: an id already
  /// listed with its file is returned as it is, and one listed whose file is gone
  /// gets its file back. [expectedSize] is what the cloud says the file has; the
  /// file must also read as a PDF. How many signatures and other items it holds is
  /// not kept in the account, so the counts are unknown (0). [source] is removed
  /// once stored (and when it can never be stored); it is kept when the phone is
  /// out of space, so a retry need not download it again.
  Future<SignedDocument> restoreFromCloud({
    required String id,
    required File source,
    required String name,
    required DateTime createdAt,
    required int expectedSize,
  }) {
    return _serial(() async {
      final fileName = '$id.pdf';
      if (!SignatureNaming.isStoredFileName(fileName)) {
        await _quietDelete(source);
        throw const SignatureException(SignatureFailure.writeFailed,
            detail: 'id');
      }
      final SignatureAnalysis inspected;
      try {
        inspected = await _verify(source);
      } on SignatureException {
        await _quietDelete(source);
        throw const SignatureException(SignatureFailure.writeFailed,
            detail: 'content');
      }
      if (inspected.size != expectedSize) {
        await _quietDelete(source);
        throw const SignatureException(SignatureFailure.writeFailed,
            detail: 'size');
      }
      final entries = await _prepare();
      final index = entries.indexWhere(
          (e) => e.document.id == id && e.state == _EntryState.ready);
      final title =
          SignatureNaming.sanitizeDisplayName(name) ?? 'Restored PDF';
      final created = index >= 0
          ? entries[index].document
          : SignedDocument(
              id: id,
              fileName: fileName,
              name: SignatureNaming.uniqueName(title, <String>[
                for (final e in entries)
                  if (e.document.id != id) e.document.name,
              ]),
              createdAt: createdAt,
              fileSize: inspected.size,
              pageCount: inspected.pageCount,
              signatureCount: 0,
              itemCount: 0,
            );
      final target = fileOf(created);
      if (index >= 0 && await target.exists()) {
        await _quietDelete(source);
        return created;
      }
      if (index < 0) {
        await _writeIndex(<_Entry>[
          ...entries,
          _Entry(created, _EntryState.pending),
        ]);
      }
      final part = File('${target.path}.part');
      try {
        await _filesDir.create(recursive: true);
        await _copier(source, part);
        await _verifyCopy(source, part, inspected.size, inspected.pageCount);
        await part.rename(target.path);
        if (index < 0) {
          await _writeIndex(<_Entry>[
            ...entries,
            _Entry(created, _EntryState.ready),
          ]);
        }
      } catch (error) {
        await _quietDelete(part);
        await _quietDelete(target);
        if (index < 0) {
          try {
            await _writeIndex(entries);
          } on SignatureException {
            // The next load drops the pending entry, whose file is gone.
          }
        }
        if (error is SignatureException) rethrow;
        if (error is FileSystemException) throw _mapFileError(error);
        throw const SignatureException(SignatureFailure.writeFailed,
            detail: 'restore');
      }
      await _quietDelete(source);
      return created;
    });
  }

  Future<void> _verifyCopy(
      File source, File copy, int size, int pageCount) async {
    final int copySize;
    try {
      copySize = await copy.length();
    } on FileSystemException {
      throw const SignatureException(SignatureFailure.writeFailed,
          detail: 'verify');
    }
    if (copySize != size) {
      throw const SignatureException(SignatureFailure.writeFailed,
          detail: 'size');
    }
    try {
      if (!await sameBytes(source, copy)) {
        throw const SignatureException(SignatureFailure.writeFailed,
            detail: 'bytes');
      }
    } on FileSystemException {
      throw const SignatureException(SignatureFailure.writeFailed,
          detail: 'bytes');
    }
    try {
      final actual = await _verify(copy);
      if (actual.pageCount != pageCount) {
        throw const SignatureException(SignatureFailure.writeFailed,
            detail: 'content');
      }
    } on SignatureException catch (error) {
      if (error.kind == SignatureFailure.writeFailed) rethrow;
      throw const SignatureException(SignatureFailure.writeFailed,
          detail: 'content');
    }
  }

  /// Whether [a] and [b] hold exactly the same bytes. Read in chunks, so a large
  /// PDF is never held twice in memory.
  static Future<bool> sameBytes(File a, File b) async {
    final length = await a.length();
    if (length != await b.length()) return false;
    final first = await a.open();
    final second = await b.open();
    try {
      const chunk = 64 * 1024;
      var done = 0;
      while (done < length) {
        final want = math.min(chunk, length - done);
        final x = await first.read(want);
        final y = await second.read(want);
        if (x.length != y.length || x.isEmpty) return false;
        for (var i = 0; i < x.length; i++) {
          if (x[i] != y[i]) return false;
        }
        done += x.length;
      }
      return true;
    } finally {
      await first.close();
      await second.close();
    }
  }

  // --------------------------------------------------------------- renaming

  /// Gives a document a new title. The stored file keeps its internal name; only
  /// the index changes. Throws `invalidName`, `nameInUse`, `notFound` or
  /// `writeFailed`.
  Future<SignedDocument> rename(String id, String newName) {
    return _serial(() async {
      final name = SignatureNaming.sanitizeDisplayName(newName);
      if (name == null) {
        throw const SignatureException(SignatureFailure.invalidName);
      }
      final entries = await _prepare();
      final index = entries.indexWhere(
          (e) => e.document.id == id && e.state == _EntryState.ready);
      if (index < 0) {
        throw const SignatureException(SignatureFailure.notFound);
      }
      final clash = entries.any((e) =>
          e.document.id != id &&
          e.state != _EntryState.deleting &&
          e.document.name.toLowerCase() == name.toLowerCase());
      if (clash) {
        throw const SignatureException(SignatureFailure.nameInUse);
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
  Future<SignatureDeleteOutcome> delete(Iterable<String> ids) {
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
        return SignatureDeleteOutcome(
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
      } on SignatureException {
        // The files are gone; the next load finishes removing the entries.
      }
      return SignatureDeleteOutcome(
          deleted: deleted, failed: failed, notFound: notFound);
    });
  }

  // ------------------------------------------------------------------ check

  /// Whether [document]'s stored file is still the complete file that was saved:
  /// present, the same size, and a readable PDF with the same pages.
  Future<bool> isIntact(SignedDocument document) async {
    try {
      final inspected = await _verify(fileOf(document));
      return inspected.size == document.fileSize &&
          inspected.pageCount == document.pageCount;
    } on SignatureException {
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

  SignatureException _mapFileError(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112) {
      return const SignatureException(SignatureFailure.storageFull);
    }
    return const SignatureException(SignatureFailure.writeFailed, detail: 'io');
  }
}
