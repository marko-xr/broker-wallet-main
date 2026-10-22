// The durable record of Toolkit documents that still need the cloud: what to
// upload, what was confirmed, what the user deleted and has not been confirmed
// by the server. It survives the app being force-stopped, so work in flight
// resumes at the next start instead of being forgotten.
//
// The journal holds NO document bytes and never deletes one. It names a local
// file only by an opaque `localRef` that the tool's own store can resolve. A
// confirmed entry is kept as a ledger: "this id reached the cloud" is what stops
// a document that was deleted elsewhere from being uploaded again.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';

@immutable
class ToolkitSyncEntry {
  const ToolkitSyncEntry({
    required this.documentId,
    required this.accountId,
    required this.type,
    required this.contentType,
    required this.title,
    required this.sizeBytes,
    required this.localRef,
    required this.sourceCreatedAt,
    this.pageCount,
    this.contentSha256,
    this.staleAcknowledged = false,
    this.state = ToolkitDocumentSyncState.savedLocallyPendingSync,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastFailure,
    this.deleteRequested = false,
    this.cloudConfirmedAt,
    this.confirmedTitle,
    this.cloudVersion,
  });

  final String documentId;

  /// The account that owns the document. An entry is only ever acted on while
  /// this account is signed in.
  final String accountId;
  final ToolkitDocumentType type;

  /// The binary format (PDF, or a Scanner JPEG / PNG scan), separate from the tool.
  final ToolkitContentType contentType;

  /// The title the user wants now.
  final String title;
  final int sizeBytes;

  /// Names the local file for the tool's store; opaque here.
  final String localRef;
  final DateTime sourceCreatedAt;
  final int? pageCount;

  /// The file's SHA-256, filled in before the first upload.
  final String? contentSha256;

  /// The user explicitly agreed to back up this document although it predates the
  /// account's deletion history (see [ToolkitFailure.staleDocument]).
  final bool staleAcknowledged;
  final ToolkitDocumentSyncState state;

  /// Failed attempts since the last success (or manual retry).
  final int attempts;

  /// Not before this time; null means "when asked" (a new entry, a paused
  /// session, or a document whose automatic retries ran out).
  final DateTime? nextAttemptAt;
  final ToolkitFailure? lastFailure;

  /// The user deleted the document; the server has not confirmed it yet.
  final bool deleteRequested;

  /// When the server confirmed the stored bytes. Non-null means "this id reached
  /// the cloud", for good.
  final DateTime? cloudConfirmedAt;

  /// The title the server holds, to tell when a rename still has to be sent.
  final String? confirmedTitle;
  final int? cloudVersion;

  bool get isCloudConfirmed => cloudConfirmedAt != null;
  bool get titlePending => isCloudConfirmed && confirmedTitle != title;

  ToolkitSyncEntry copyWith({
    String? title,
    String? contentSha256,
    bool? staleAcknowledged,
    ToolkitDocumentSyncState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttempt = false,
    ToolkitFailure? lastFailure,
    bool clearFailure = false,
    bool? deleteRequested,
    DateTime? cloudConfirmedAt,
    String? confirmedTitle,
    int? cloudVersion,
  }) =>
      ToolkitSyncEntry(
        documentId: documentId,
        accountId: accountId,
        type: type,
        contentType: contentType,
        title: title ?? this.title,
        sizeBytes: sizeBytes,
        localRef: localRef,
        sourceCreatedAt: sourceCreatedAt,
        pageCount: pageCount,
        contentSha256: contentSha256 ?? this.contentSha256,
        staleAcknowledged: staleAcknowledged ?? this.staleAcknowledged,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        nextAttemptAt:
            clearNextAttempt ? null : (nextAttemptAt ?? this.nextAttemptAt),
        lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
        deleteRequested: deleteRequested ?? this.deleteRequested,
        cloudConfirmedAt: cloudConfirmedAt ?? this.cloudConfirmedAt,
        confirmedTitle: confirmedTitle ?? this.confirmedTitle,
        cloudVersion: cloudVersion ?? this.cloudVersion,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'documentId': documentId,
        'accountId': accountId,
        'type': type.wireName,
        'contentType': contentType.mime,
        'title': title,
        'sizeBytes': sizeBytes,
        'localRef': localRef,
        'sourceCreatedAt': sourceCreatedAt.toUtc().toIso8601String(),
        'pageCount': pageCount,
        'contentSha256': contentSha256,
        'staleAcknowledged': staleAcknowledged,
        'state': state.name,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
        'lastFailure': lastFailure?.name,
        'deleteRequested': deleteRequested,
        'cloudConfirmedAt': cloudConfirmedAt?.toUtc().toIso8601String(),
        'confirmedTitle': confirmedTitle,
        'cloudVersion': cloudVersion,
      };

  /// Null for anything that is not a complete, well-formed entry: a damaged
  /// record is dropped rather than guessed at.
  static ToolkitSyncEntry? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['documentId'];
    final account = json['accountId'];
    final type = ToolkitDocumentType.fromWire(json['type']);
    final contentType = ToolkitContentType.fromMime(json['contentType']);
    final title = json['title'];
    final size = json['sizeBytes'];
    final ref = json['localRef'];
    final created = DateTime.tryParse('${json['sourceCreatedAt']}');
    final state = ToolkitDocumentSyncState.values
        .where((s) => s.name == json['state'])
        .firstOrNull;
    final attempts = json['attempts'];
    if (id is! String ||
        !ToolkitDocumentIds.isCanonical(id) ||
        account is! String ||
        account.isEmpty ||
        type == null ||
        contentType == null ||
        !contentType.allowedFor(type) ||
        title is! String ||
        ToolkitDocumentTitles.problemWith(title) != null ||
        size is! int ||
        size < 1 ||
        ref is! String ||
        ref.isEmpty ||
        created == null ||
        state == null ||
        attempts is! int ||
        attempts < 0) {
      return null;
    }
    DateTime? time(String key) {
      final raw = json[key];
      return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    }

    final pages = json['pageCount'];
    final sha = json['contentSha256'];
    final failure = ToolkitFailure.values
        .where((f) => f.name == json['lastFailure'])
        .firstOrNull;
    final version = json['cloudVersion'];
    return ToolkitSyncEntry(
      documentId: id,
      accountId: account,
      type: type,
      contentType: contentType,
      title: title,
      sizeBytes: size,
      localRef: ref,
      sourceCreatedAt: created.toUtc(),
      pageCount: pages is int && pages >= 1 ? pages : null,
      contentSha256:
          sha is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
      staleAcknowledged: json['staleAcknowledged'] == true,
      state: state,
      attempts: attempts,
      nextAttemptAt: time('nextAttemptAt'),
      lastFailure: failure,
      deleteRequested: json['deleteRequested'] == true,
      cloudConfirmedAt: time('cloudConfirmedAt'),
      confirmedTitle: json['confirmedTitle'] is String
          ? json['confirmedTitle'] as String
          : null,
      cloudVersion: version is int && version >= 1 ? version : null,
    );
  }
}

/// The durable store behind the coordinator. One journal per account.
abstract interface class ToolkitSyncJournal {
  Future<List<ToolkitSyncEntry>> load();

  /// Inserts or replaces the entry with the same document id.
  Future<void> save(ToolkitSyncEntry entry);

  Future<void> remove(String documentId);
}

/// A journal in memory, for tests and for builds with no storage. Optional hooks
/// let a test make a write fail.
class InMemoryToolkitSyncJournal implements ToolkitSyncJournal {
  InMemoryToolkitSyncJournal([Iterable<ToolkitSyncEntry> initial = const []]) {
    for (final entry in initial) {
      _entries[entry.documentId] = entry;
    }
  }

  final Map<String, ToolkitSyncEntry> _entries = <String, ToolkitSyncEntry>{};

  /// Set by a test to make the next write throw.
  Object? failNextSave;

  @override
  Future<List<ToolkitSyncEntry>> load() async => _entries.values.toList();

  @override
  Future<void> save(ToolkitSyncEntry entry) async {
    final failure = failNextSave;
    if (failure != null) {
      failNextSave = null;
      throw failure;
    }
    _entries[entry.documentId] = entry;
  }

  @override
  Future<void> remove(String documentId) async {
    _entries.remove(documentId);
  }
}

/// A journal in one JSON file per account, written through a temporary file and
/// renamed over the old one, so a crash leaves the previous complete journal.
/// A file that cannot be read is moved aside (never deleted) and the journal
/// starts empty: the documents themselves are untouched, only the queue is lost,
/// and the migration re-queues anything that never reached the cloud.
class FileToolkitSyncJournal implements ToolkitSyncJournal {
  FileToolkitSyncJournal({required this.directory, required this.accountId});

  final Directory directory;
  final String accountId;

  Future<void> _tail = Future<void>.value();

  /// `toolkit_sync_<account>.json`. The account id is used when it is plain (a
  /// UUID is); anything else is hex encoded, so no id can name another folder.
  File get _file {
    final plain = RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(accountId);
    final name = plain
        ? accountId
        : 'u_${utf8.encode(accountId).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    return File(p.join(directory.path, 'toolkit_sync_$name.json'));
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<List<ToolkitSyncEntry>> load() => _serial(_read);

  Future<List<ToolkitSyncEntry>> _read() async {
    final file = _file;
    if (!await file.exists()) return <ToolkitSyncEntry>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map ||
          decoded['accountId'] != accountId ||
          decoded['entries'] is! List) {
        throw const FormatException('journal does not match this account');
      }
      return <ToolkitSyncEntry>[
        for (final raw in decoded['entries'] as List)
          if (ToolkitSyncEntry.tryFromJson(raw) case final entry?)
            if (entry.accountId == accountId) entry,
      ];
    } catch (_) {
      await _moveAside(file);
      return <ToolkitSyncEntry>[];
    }
  }

  Future<void> _moveAside(File file) async {
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      await file.rename('${file.path}.damaged.$stamp');
    } catch (_) {}
  }

  @override
  Future<void> save(ToolkitSyncEntry entry) => _serial(() async {
        final entries = await _read();
        final next = <ToolkitSyncEntry>[
          for (final e in entries)
            if (e.documentId != entry.documentId) e,
          entry,
        ];
        await _write(next);
      });

  @override
  Future<void> remove(String documentId) => _serial(() async {
        final entries = await _read();
        await _write(<ToolkitSyncEntry>[
          for (final e in entries)
            if (e.documentId != documentId) e,
        ]);
      });

  Future<void> _write(List<ToolkitSyncEntry> entries) async {
    await directory.create(recursive: true);
    final file = _file;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'accountId': accountId,
        'entries': entries.map((e) => e.toJson()).toList(),
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
