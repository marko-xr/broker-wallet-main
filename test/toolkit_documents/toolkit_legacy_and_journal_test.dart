// Which existing local documents may be queued for the cloud, and the durable
// journal the upload coordinator keeps.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_store.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_store.dart';
import 'package:broker_wallet/src/services/scanner/scanner_document_store.dart';
import 'package:broker_wallet/src/services/signature/signature_store.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_sync_journal.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_legacy_migration.dart';

import 'toolkit_fakes.dart';

ToolkitLegacyCandidate candidate(
  String id, {
  ToolkitDocumentType type = ToolkitDocumentType.scanner,
  String? folder,
  String? owner = accountA,
  String contentType = 'application/pdf',
  int size = 1000,
  bool missing = false,
}) =>
    ToolkitLegacyCandidate(
      type: type,
      localId: id,
      accountFolderName:
          folder ?? ToolkitLegacyMigration.accountFolderName(accountA),
      indexOwnerId: owner,
      contentType: contentType,
      sizeBytes: size,
      title: 'T',
      fileMissing: missing,
    );

void main() {
  group('legacy migration eligibility', () {
    ToolkitLegacyPlan plan(List<ToolkitLegacyCandidate> items,
            {Set<String> inCloud = const {}, String user = accountA}) =>
        ToolkitLegacyMigration.plan(
            currentUserId: user, candidates: items, idsAlreadyInCloud: inCloud);

    test('the signed-in account\'s own PDFs are eligible', () {
      final result = plan([
        candidate(doc1),
        candidate(doc2, type: ToolkitDocumentType.signature)
      ]);
      expect(result.eligible.map((c) => c.localId), [doc1, doc2]);
      expect(result.skipped, isEmpty);
    });

    test('another account\'s folder or index is never uploaded', () {
      final result = plan([
        candidate(doc1,
            folder: ToolkitLegacyMigration.accountFolderName(accountB),
            owner: accountB),
        candidate(doc2,
            owner: accountB), // right folder, index names someone else
        candidate(doc3,
            folder: ToolkitLegacyMigration.accountFolderName(
                accountB)), // wrong folder
      ]);
      expect(result.eligible, isEmpty);
      expect(result.skipped.values,
          everyElement(ToolkitLegacyDecision.otherAccount));
    });

    test('legacy ownerless files are never assigned to whoever signs in', () {
      final result =
          plan([candidate(doc1, owner: null), candidate(doc2, owner: '')]);
      expect(result.eligible, isEmpty);
      expect(result.count(ToolkitLegacyDecision.ownerless), 2);
      // And a different account signing in sees nothing either.
      expect(plan([candidate(doc1, owner: null)], user: accountB).eligible,
          isEmpty);
    });

    test('documents the cloud will not take are reported, not hidden', () {
      final result = plan([
        candidate(doc1, contentType: 'image/gif'),
        candidate(doc2, size: 200 * 1024 * 1024),
        candidate(doc3, size: 0),
        candidate('id-not-a-uuid'),
        candidate(doc4, missing: true),
      ]);
      expect(result.eligible, isEmpty);
      expect(result.skipped['scanner/$doc1'],
          ToolkitLegacyDecision.unsupportedType);
      expect(result.skipped['scanner/$doc2'], ToolkitLegacyDecision.tooLarge);
      expect(result.skipped['scanner/$doc3'], ToolkitLegacyDecision.tooLarge);
      expect(result.skipped['scanner/id-not-a-uuid'],
          ToolkitLegacyDecision.invalidId);
      expect(
          result.skipped['scanner/$doc4'], ToolkitLegacyDecision.fileMissing);
    });

    test(
        'a retried migration skips what the cloud already has and any duplicate id',
        () {
      final result = plan([candidate(doc1), candidate(doc2), candidate(doc2)],
          inCloud: {doc1});
      expect(result.eligible.map((c) => c.localId), [doc2]);
      expect(result.count(ToolkitLegacyDecision.alreadyInCloud), 2);
    });

    test('the account folder name follows exactly the four stores\' rule', () {
      final base = Directory.systemTemp;
      for (final user in [accountA, 'plain_user-1', 'a b@c.d', 'مستخدم']) {
        final expected =
            p.basename(ScannerDocumentStore.accountDirectory(base, user).path);
        expect(ToolkitLegacyMigration.accountFolderName(user), expected,
            reason: user);
        for (final other in [
          CombinePdfStore.accountDirectory(base, user),
          ImagePdfStore.accountDirectory(base, user),
          SignatureStore.accountDirectory(base, user),
        ]) {
          expect(p.basename(other.path), expected, reason: user);
        }
      }
      expect(() => ToolkitLegacyMigration.accountFolderName(''),
          throwsArgumentError);
    });
  });

  group('file journal', () {
    late Directory dir;
    setUp(() async =>
        dir = await Directory.systemTemp.createTemp('toolkit_journal_'));
    tearDown(() => dir.delete(recursive: true));

    FileToolkitSyncJournal journalFor(String account) =>
        FileToolkitSyncJournal(directory: dir, accountId: account);

    test('entries round trip with every field', () async {
      final journal = journalFor(accountA);
      final entry = entryFor(doc1, pdfBytes(), sha: sha(pdfBytes())).copyWith(
        state: ToolkitDocumentSyncState.syncFailedRetryable,
        attempts: 3,
        nextAttemptAt: DateTime.utc(2026, 10, 19, 10),
        lastFailure: ToolkitFailure.rateLimited,
        cloudConfirmedAt: DateTime.utc(2026, 10, 19, 9),
        confirmedTitle: 'Lease',
        cloudVersion: 4,
      );
      await journal.save(entry);
      final loaded = (await journalFor(accountA).load()).single;
      expect(loaded.toJson(), entry.toJson());
      expect(loaded.state, ToolkitDocumentSyncState.syncFailedRetryable);
      expect(loaded.contentType, ToolkitContentType.pdf);
      expect(loaded.staleAcknowledged, isFalse);

      // The format and the user's stale acknowledgement are real file fields.
      final image = entryFor(doc2, jpegBytes(),
              contentType: ToolkitContentType.jpeg, sha: sha(jpegBytes()))
          .copyWith(staleAcknowledged: true);
      await journal.save(image);
      final again = (await journalFor(accountA).load())
          .firstWhere((e) => e.documentId == doc2);
      expect(again.contentType, ToolkitContentType.jpeg);
      expect(again.staleAcknowledged, isTrue);
      expect(again.localRef, endsWith('.jpg'));
      // An entry from before the format existed (or with a forged one) is dropped.
      final raw = image.toJson()..remove('contentType');
      expect(ToolkitSyncEntry.tryFromJson(raw), isNull);
      expect(
          ToolkitSyncEntry.tryFromJson(
              image.toJson()..['contentType'] = 'image/gif'),
          isNull);
      final scannerOnly =
          entryFor(doc3, pdfBytes(), type: ToolkitDocumentType.signature)
              .toJson()
            ..['contentType'] = 'image/png';
      expect(ToolkitSyncEntry.tryFromJson(scannerOnly), isNull,
          reason: 'a signature cannot be a PNG');
      expect(loaded.lastFailure, ToolkitFailure.rateLimited);
      expect(loaded.isCloudConfirmed, isTrue);
    });

    test(
        'save replaces by id, remove forgets, and the file never holds bytes or URLs',
        () async {
      final journal = journalFor(accountA);
      await journal.save(entryFor(doc1, pdfBytes(), title: 'One'));
      await journal.save(entryFor(doc1, pdfBytes(), title: 'Replaced'));
      await journal.save(entryFor(doc2, pdfBytes()));
      expect((await journal.load()).map((e) => e.title).toSet(),
          {'Replaced', 'Lease'});
      await journal.remove(doc1);
      expect((await journal.load()).map((e) => e.documentId), [doc2]);
      final text = dir.listSync().whereType<File>().single.readAsStringSync();
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('%PDF')));
      expect(text, isNot(contains('presigned')));
    });

    test('each account has its own file', () async {
      await journalFor(accountA).save(entryFor(doc1, pdfBytes()));
      await journalFor(accountB)
          .save(entryFor(doc2, pdfBytes(), account: accountB));
      expect(
          (await journalFor(accountA).load()).map((e) => e.documentId), [doc1]);
      expect(
          (await journalFor(accountB).load()).map((e) => e.documentId), [doc2]);
      expect(dir.listSync().whereType<File>(), hasLength(2));
    });

    test('a journal naming another account is refused and kept aside',
        () async {
      await journalFor(accountB)
          .save(entryFor(doc2, pdfBytes(), account: accountB));
      final bFile = dir.listSync().whereType<File>().single;
      // A file of B copied over A's name must not be believed.
      File('${dir.path}/toolkit_sync_$accountA.json')
          .writeAsStringSync(bFile.readAsStringSync());
      expect(await journalFor(accountA).load(), isEmpty);
      expect(
          dir
              .listSync()
              .whereType<File>()
              .any((f) => f.path.contains('.damaged.')),
          isTrue);
    });

    test('a damaged journal is moved aside, never deleted', () async {
      final file = File('${dir.path}/toolkit_sync_$accountA.json')
        ..writeAsStringSync('{not json');
      expect(await journalFor(accountA).load(), isEmpty);
      expect(file.existsSync(), isFalse);
      final aside = dir.listSync().whereType<File>().single;
      expect(aside.readAsStringSync(), '{not json');
      // And it keeps working afterwards.
      await journalFor(accountA).save(entryFor(doc1, pdfBytes()));
      expect(await journalFor(accountA).load(), hasLength(1));
    });

    test('a malformed entry is dropped and the rest survive', () async {
      final good = entryFor(doc1, pdfBytes()).toJson();
      final bad = Map<String, Object?>.of(good)..['documentId'] = 'nope';
      final badTitle = Map<String, Object?>.of(good)..['title'] = ' padded ';
      File('${dir.path}/toolkit_sync_$accountA.json')
          .writeAsStringSync(jsonEncode({
        'version': 1,
        'accountId': accountA,
        'entries': [good, bad, badTitle, 'text', null],
      }));
      expect(
          (await journalFor(accountA).load()).map((e) => e.documentId), [doc1]);
    });

    test('an interrupted write leaves the previous complete journal', () async {
      final journal = journalFor(accountA);
      await journal.save(entryFor(doc1, pdfBytes()));
      // A crash after writing the temporary file and before the rename.
      File('${dir.path}/toolkit_sync_$accountA.json.tmp')
          .writeAsStringSync('{"half":');
      expect(
          (await journalFor(accountA).load()).map((e) => e.documentId), [doc1]);
      await journal.save(entryFor(doc2, pdfBytes()));
      expect(await journal.load(), hasLength(2));
    });

    test('many concurrent saves lose nothing', () async {
      final journal = journalFor(accountA);
      final ids = [
        for (var i = 0; i < 25; i++)
          'd0d${i.toString().padLeft(5, '0')}-0000-4000-8000-000000000000'
      ];
      await Future.wait(
          [for (final id in ids) journal.save(entryFor(id, pdfBytes()))]);
      expect(
          (await journal.load()).map((e) => e.documentId).toSet(), ids.toSet());
    });

    test('an account id that is not plain cannot name another folder',
        () async {
      final odd =
          FileToolkitSyncJournal(directory: dir, accountId: '../../etc/passwd');
      await odd.save(entryFor(doc1, pdfBytes(), account: '../../etc/passwd'));
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(p.dirname(files.single.path), dir.path);
    });
  });
}
