// Where the Toolkit cloud finds a tool's files: inside the tool's own account
// folder, the way every tool's store lays it out (`<account folder>/files/<id>.<ext>`).
// It only computes paths and looks; it never creates, moves or deletes anything.
//
// A document that is downloaded from the account is first written to
// `<account folder>/restore/<id>.<ext>` (outside `files/`, so the store's own
// sweep of half-written files never touches a download that is running); the
// tool's store then adopts it.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';

class ToolkitAccountFiles implements ToolkitLocalFiles {
  const ToolkitAccountFiles(this.accountDir);

  /// The tool's folder for the signed-in account (`<base>/<tool>/<account>`).
  final Directory accountDir;

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final RegExp _safeExtension = RegExp(r'^[a-z0-9]{1,5}$');

  static bool _plain(String id, String extension) =>
      _safeId.hasMatch(id) && _safeExtension.hasMatch(extension);

  /// The stored file of document [id], or null for an id or extension that cannot
  /// be a stored file's name.
  File? storedFile(String id, String extension) => _plain(id, extension)
      ? File(p.join(accountDir.path, 'files', '$id.$extension'))
      : null;

  /// Where document [id] is downloaded to before the tool stores it.
  File? restoreFile(String id, String extension) => _plain(id, extension)
      ? File(p.join(accountDir.path, 'restore', '$id.$extension'))
      : null;

  /// Where the account's journal for this tool is kept.
  Directory get journalDirectory => Directory(p.join(accountDir.path, 'cloud'));

  @override
  Future<File?> resolve(ToolkitSyncEntry entry) async {
    final file = storedFile(entry.localRef, entry.contentType.extension);
    if (file == null || !await file.exists()) return null;
    return file;
  }
}
