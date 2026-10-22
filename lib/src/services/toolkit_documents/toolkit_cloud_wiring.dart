// Builds the real [ToolkitCloudLibrary] for a tool: the Worker client bound to
// the signed-in account, the durable journal in the tool's own account folder,
// and a hasher that runs off the UI isolate.
//
// ONE library is shared per account and tool: the tool's list screen and anything
// opened from it use the same journal, and closing a screen never stops the work
// in flight. When another account signs in, the libraries of the previous one
// are shut down.
//
// Returns null, so the tool simply stays local, when the cloud copy is switched
// off at build time (`--dart-define=TOOLKIT_CLOUD_DOCUMENTS=false`, the kill
// switch) or Toolkit has no usable Worker address ([R2Config.isToolkitConfigured]).
// The journal lives inside the tool's account folder, which Android and iPhone
// backup already exclude.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:broker_wallet/src/services/toolkit_documents/r2_toolkit_document_service.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_library.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_sha256.dart';

abstract final class ToolkitCloudWiring {
  static final Map<String, DefaultToolkitCloudLibrary> _shared =
      <String, DefaultToolkitCloudLibrary>{};

  /// The cloud library of [type] for [accountId], or null when the tool stays
  /// local. [directory] is where the journal is kept.
  static ToolkitCloudLibrary? create({
    required String accountId,
    required ToolkitDocumentType type,
    required Directory directory,
    required ToolkitLocalFiles files,
    required String? Function() currentAccountId,
  }) {
    if (!ToolkitCloudDocumentsFeature.isActive ||
        !R2Config.isToolkitConfigured) {
      return null;
    }
    final mine = '$accountId|';
    for (final key in _shared.keys.toList()) {
      if (!key.startsWith(mine)) {
        final other = _shared.remove(key);
        if (other != null) unawaited(other.shutdown());
      }
    }
    return _shared.putIfAbsent(
      '$mine${type.wireName}',
      () => DefaultToolkitCloudLibrary(
        accountId: accountId,
        transport: R2ToolkitDocumentService(accountId: accountId),
        journal: FileToolkitSyncJournal(
          directory: directory,
          accountId: accountId,
        ),
        files: files,
        currentAccountId: currentAccountId,
        hasher: hashOffUiThread,
        shared: true,
      ),
    );
  }

  /// SHA-256 of [file] on a short-lived isolate, so a large document never
  /// stalls the screen.
  static Future<String> hashOffUiThread(File file) {
    final path = file.path;
    return Isolate.run(() => ToolkitSha256.hexOfFile(File(path)));
  }
}
