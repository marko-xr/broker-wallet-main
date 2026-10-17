import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scanner_document_store.dart';

import 'scanner_fixtures.dart';

Future<ScannerFailure?> failureOf(Future<Object?> Function() action) async {
  try {
    await action();
  } on ScannerException catch (e) {
    return e.kind;
  }
  return null;
}

void main() {
  late Directory base;
  late Directory sources;
  var idCounter = 0;
  var clockTick = 0;

  ScannerDocumentStore storeFor(
    String userId, {
    ScannerFileCopier? copier,
  }) {
    return ScannerDocumentStore(
      accountDir: ScannerDocumentStore.accountDirectory(base, userId),
      userId: userId,
      inspector: testInspector(),
      copier: copier,
      clock: () => DateTime.utc(2026, 10, 17, 12, 0, clockTick++),
      idGenerator: () => 'id${idCounter++}',
    );
  }

  Future<ScannerNewDocument> pdfItem(String name, int pages,
      {ScanMode mode = ScanMode.document}) async {
    final file = await writeFile(sources,
        '${name.hashCode}_${idCounter}_$pages.pdf', await pdfBytes(pages));
    return ScannerNewDocument(
      source: file,
      inspected: await testInspector().inspect(file),
      name: name,
      scanType: mode,
    );
  }

  Future<ScannerNewDocument> imageItem(String name, int seed,
      {String? batchId, int index = 0}) async {
    final file = await writeFile(
        sources, 'img_${idCounter}_$seed.jpg', jpegBytes(seed: seed));
    return ScannerNewDocument(
      source: file,
      inspected: await testInspector().inspect(file),
      name: name,
      scanType: ScanMode.document,
      batchId: batchId,
      batchIndex: index,
    );
  }

  setUp(() {
    base = makeTempDir('store');
    sources = makeTempDir('sources');
    idCounter = 0;
    clockTick = 0;
  });
  tearDown(() {
    base.deleteSync(recursive: true);
    sources.deleteSync(recursive: true);
  });

  group('saving', () {
    test('a PDF is stored with its real page count, under an internal name',
        () async {
      final store = storeFor('user-a');
      final saved =
          await store.add(<ScannerNewDocument>[await pdfItem('Lease', 3)]);
      expect(saved, hasLength(1));
      final doc = saved.single;
      expect(doc.pageCount, 3);
      expect(doc.format, ExportFormat.pdf);
      expect(doc.mimeType, 'application/pdf');
      expect(doc.fileName, 'id0.pdf');
      final file = store.fileOf(doc);
      expect(file.existsSync(), isTrue);
      expect(await file.length(), doc.fileSize);
      final library = await store.load();
      expect(library.documents.single.name, 'Lease');
      expect(library.missingIds, isEmpty);
    });

    test('images are one document per page, in the order they were scanned',
        () async {
      final store = storeFor('user-a');
      final saved = await store.add(<ScannerNewDocument>[
        await imageItem('Plan_page_1', 0, batchId: 'b1', index: 0),
        await imageItem('Plan_page_2', 1, batchId: 'b1', index: 1),
        await imageItem('Plan_page_3', 2, batchId: 'b1', index: 2),
      ]);
      expect(saved.map((d) => d.name),
          <String>['Plan_page_1', 'Plan_page_2', 'Plan_page_3']);
      expect(saved.every((d) => d.mimeType == 'image/jpeg'), isTrue);
      expect(saved.every((d) => d.extension == 'jpg'), isTrue);
      final listed = (await store.load()).documents.map((d) => d.name);
      expect(listed, <String>['Plan_page_1', 'Plan_page_2', 'Plan_page_3']);
    });

    test('the same title twice never collides: Lease, Lease (2)', () async {
      final store = storeFor('user-a');
      await store.add(<ScannerNewDocument>[await pdfItem('Lease', 1)]);
      final again =
          await store.add(<ScannerNewDocument>[await pdfItem('lease', 1)]);
      expect(again.single.name, 'lease (2)');
      final names = (await store.load()).documents.map((d) => d.name).toSet();
      expect(names, <String>{'Lease', 'lease (2)'});
    });

    test('an Arabic title is kept; the stored file name stays plain ASCII',
        () async {
      final store = storeFor('user-a');
      final saved = await store
          .add(<ScannerNewDocument>[await pdfItem('عقد إيجار شقة', 1)]);
      expect(saved.single.name, 'عقد إيجار شقة');
      expect(saved.single.exportFileName, 'عقد إيجار شقة.pdf');
      expect(
          RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(saved.single.fileName), isTrue);
    });

    test(
        'a full disk saves nothing and changes no existing document, and a '
        'retry then works', () async {
      var failing = true;
      final store = storeFor('user-a', copier: (source, destination) async {
        if (failing) {
          await destination.writeAsBytes(<int>[1, 2]);
          throw const FileSystemException(
              'No space', '', OSError('ENOSPC', 28));
        }
        await source.copy(destination.path);
      });
      failing = false;
      await store.add(<ScannerNewDocument>[await pdfItem('Existing', 2)]);
      final before = relativeFiles(base);

      failing = true;
      final item = await pdfItem('New', 1);
      expect(await failureOf(() => store.add(<ScannerNewDocument>[item])),
          ScannerFailure.storageFull);
      expect(relativeFiles(base), before, reason: 'no part or final file left');
      var library = await store.load();
      expect(library.documents.map((d) => d.name), <String>['Existing']);

      failing = false;
      final saved = await store.add(<ScannerNewDocument>[item]);
      expect(saved.single.name, 'New');
      library = await store.load();
      expect(library.documents.map((d) => d.name).toSet(),
          <String>{'Existing', 'New'});
    });

    test('a copy that stops half way is caught by verification and not listed',
        () async {
      final store = storeFor('user-a', copier: (source, destination) async {
        final bytes = await source.readAsBytes();
        await destination.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
      });
      final item = await pdfItem('Half', 3);
      expect(await failureOf(() => store.add(<ScannerNewDocument>[item])),
          ScannerFailure.writeFailed);
      expect((await store.load()).documents, isEmpty);
      expect(relativeFiles(base).where((f) => f.contains('files')), isEmpty);
    });

    test('a zero-byte copy never counts as saved', () async {
      final store = storeFor('user-a', copier: (source, destination) async {
        await destination.writeAsBytes(<int>[]);
      });
      final item = await jpegItem();
      expect(await failureOf(() => store.add(<ScannerNewDocument>[item])),
          ScannerFailure.writeFailed);
      expect((await store.load()).documents, isEmpty);
    });

    test('a multi-page image save is all or nothing', () async {
      var calls = 0;
      final store = storeFor('user-a', copier: (source, destination) async {
        calls++;
        if (calls == 2) {
          throw const FileSystemException('disk error');
        }
        await source.copy(destination.path);
      });
      final items = <ScannerNewDocument>[
        await imageItem('S_page_1', 0, batchId: 'b', index: 0),
        await imageItem('S_page_2', 1, batchId: 'b', index: 1),
        await imageItem('S_page_3', 2, batchId: 'b', index: 2),
      ];
      expect(
          await failureOf(() => store.add(items)), ScannerFailure.writeFailed);
      expect((await store.load()).documents, isEmpty);
      expect(relativeFiles(base).where((f) => f.endsWith('.jpg')), isEmpty);
    });

    test('two saves started together both succeed, one after the other',
        () async {
      final store = storeFor('user-a');
      final a = await pdfItem('First', 1);
      final b = await pdfItem('Second', 2);
      final results = await Future.wait(<Future<List<ScannerDocument>>>[
        store.add(<ScannerNewDocument>[a]),
        store.add(<ScannerNewDocument>[b]),
      ]);
      expect(results.expand((r) => r).map((d) => d.name).toSet(),
          <String>{'First', 'Second'});
      expect((await store.load()).documents, hasLength(2));
    });
  });

  group('persistence and account isolation', () {
    test(
        'a cold restart (a new store over the same folder) lists the same '
        'documents', () async {
      final first = storeFor('user-a');
      await first.add(<ScannerNewDocument>[await pdfItem('Kept', 4)]);
      final second = storeFor('user-a');
      final library = await second.load();
      expect(library.documents.single.name, 'Kept');
      expect(library.documents.single.pageCount, 4);
      expect(second.fileOf(library.documents.single).existsSync(), isTrue);
    });

    test('Account B never sees Account A\'s documents, and A still does',
        () async {
      final a = storeFor('user-a');
      await a.add(<ScannerNewDocument>[await pdfItem('A secret', 1)]);
      final b = storeFor('user-b');
      expect((await b.load()).documents, isEmpty);
      await b.add(<ScannerNewDocument>[await pdfItem('B only', 1)]);
      expect(
          (await a.load()).documents.map((d) => d.name), <String>['A secret']);
      expect((await b.load()).documents.map((d) => d.name), <String>['B only']);
      expect(a.accountDir.path == b.accountDir.path, isFalse);
    });

    test('an index copied from another account is refused and set aside',
        () async {
      final a = storeFor('user-a');
      await a.add(<ScannerNewDocument>[await pdfItem('A secret', 1)]);
      final b = storeFor('user-b');
      await b.accountDir.create(recursive: true);
      await File(p.join(a.accountDir.path, 'index.json'))
          .copy(p.join(b.accountDir.path, 'index.json'));
      final library = await b.load();
      expect(library.documents, isEmpty);
      expect(library.recoveredFromDamagedIndex, isTrue);
      expect(
          b.accountDir
              .listSync()
              .any((e) => p.basename(e.path).startsWith('index.damaged-')),
          isTrue,
          reason: 'the foreign index is kept aside, not deleted');
    });

    test('an account id can never name a folder outside the scanner folder',
        () {
      final dir = ScannerDocumentStore.accountDirectory(base, '../../etc');
      expect(p.isWithin(p.join(base.path, 'scanner'), dir.path), isTrue);
      expect(p.basename(dir.path).startsWith('u_'), isTrue);
      expect(() => ScannerDocumentStore.accountDirectory(base, ''),
          throwsArgumentError);
      expect(ScannerDocumentStore.accountDirectory(base, 'a1b2-c3').path,
          p.join(base.path, 'scanner', 'a1b2-c3'));
    });

    test('a legacy global index and its files are never read or touched',
        () async {
      // The first Scanner kept every account's documents in one device-wide
      // list and put the files straight into the documents folder.
      final legacyFile =
          await writeFile(base, 'old_scan.pdf', await pdfBytes(2));
      final store = storeFor('user-a');
      await store.add(<ScannerNewDocument>[await pdfItem('Mine', 1)]);
      final library = await store.load();
      expect(library.documents.map((d) => d.name), <String>['Mine']);
      expect(legacyFile.existsSync(), isTrue);
    });
  });

  group('renaming', () {
    test('changes only the title; the stored file is untouched', () async {
      final store = storeFor('user-a');
      final saved =
          await store.add(<ScannerNewDocument>[await pdfItem('Draft', 2)]);
      final before = await store.fileOf(saved.single).readAsBytes();
      final renamed = await store.rename(saved.single.id, '  Title Deed  ');
      expect(renamed.name, 'Title Deed');
      expect((await store.load()).documents.single.name, 'Title Deed');
      expect(store.fileOf(saved.single).path, endsWith(saved.single.fileName));
      expect(await store.fileOf(saved.single).readAsBytes(), before);
    });

    test('a name another document uses is refused, case aside', () async {
      final store = storeFor('user-a');
      final first =
          await store.add(<ScannerNewDocument>[await pdfItem('One', 1)]);
      await store.add(<ScannerNewDocument>[await pdfItem('Two', 1)]);
      expect(await failureOf(() => store.rename(first.single.id, 'two')),
          ScannerFailure.nameInUse);
      expect((await store.load()).documents.map((d) => d.name).toSet(),
          <String>{'One', 'Two'});
      // Keeping its own name (even in other case) is fine.
      expect((await store.rename(first.single.id, 'ONE')).name, 'ONE');
    });

    test('an empty or separator-only name is invalid; a path becomes a name',
        () async {
      final store = storeFor('user-a');
      final saved =
          await store.add(<ScannerNewDocument>[await pdfItem('Name', 1)]);
      for (final bad in <String>['', '   ', '///', '..', '. . .']) {
        expect(await failureOf(() => store.rename(saved.single.id, bad)),
            ScannerFailure.invalidName,
            reason: bad);
      }
      final renamed = await store.rename(saved.single.id, '../../evil/x');
      expect(renamed.name.contains('/'), isFalse);
      expect(renamed.name.contains('..'), isFalse);
      expect(store.fileOf(saved.single).path.contains('evil'), isFalse);
    });

    test('an unknown id is not found', () async {
      final store = storeFor('user-a');
      expect(await failureOf(() => store.rename('nope', 'X')),
          ScannerFailure.notFound);
    });
  });

  group('deleting', () {
    test('removes the selected document and its file, nothing else', () async {
      final store = storeFor('user-a');
      final saved = await store.add(<ScannerNewDocument>[
        await pdfItem('A', 1),
        await pdfItem('B', 1),
        await pdfItem('C', 1),
      ]);
      final outcome = await store.delete(<String>[saved[1].id]);
      expect(outcome.deleted, <String>[saved[1].id]);
      expect(store.fileOf(saved[1]).existsSync(), isFalse);
      expect(store.fileOf(saved[0]).existsSync(), isTrue);
      expect(store.fileOf(saved[2]).existsSync(), isTrue);
      expect((await store.load()).documents.map((d) => d.name).toSet(),
          <String>{'A', 'C'});
    });

    test('bulk delete removes exactly the chosen set and reports unknown ids',
        () async {
      final store = storeFor('user-a');
      final saved = await store.add(<ScannerNewDocument>[
        await pdfItem('A', 1),
        await pdfItem('B', 1),
        await pdfItem('C', 1),
        await pdfItem('D', 1),
      ]);
      final outcome =
          await store.delete(<String>[saved[0].id, saved[3].id, 'ghost']);
      expect(outcome.deleted.toSet(), <String>{saved[0].id, saved[3].id});
      expect(outcome.notFound, <String>['ghost']);
      expect(outcome.failed, isEmpty);
      expect((await store.load()).documents.map((d) => d.name).toSet(),
          <String>{'B', 'C'});
    });

    test('never deletes a file outside the account folder', () async {
      final outsideFile =
          await writeFile(base, 'precious.pdf', await pdfBytes(1));
      final store = storeFor('user-a');
      final saved =
          await store.add(<ScannerNewDocument>[await pdfItem('A', 1)]);
      await store.delete(<String>[saved.single.id]);
      expect(outsideFile.existsSync(), isTrue);
    });
  });

  group('missing, damaged and interrupted', () {
    test(
        'a document whose file vanished stays listed as missing and can still '
        'be removed', () async {
      final store = storeFor('user-a');
      final saved = await store.add(<ScannerNewDocument>[
        await pdfItem('Gone', 1),
        await pdfItem('Here', 1),
      ]);
      store.fileOf(saved[0]).deleteSync();
      final library = await store.load();
      expect(library.documents, hasLength(2));
      expect(library.missingIds, <String>{saved[0].id});
      expect(await store.isIntact(saved[0]), isFalse);
      expect(await store.isIntact(saved[1]), isTrue);
      final outcome = await store.delete(<String>[saved[0].id]);
      expect(outcome.deleted, <String>[saved[0].id]);
      expect(
          (await store.load()).documents.map((d) => d.name), <String>['Here']);
    });

    test('a file changed after saving is no longer intact', () async {
      final store = storeFor('user-a');
      final saved =
          await store.add(<ScannerNewDocument>[await pdfItem('X', 2)]);
      await store.fileOf(saved.single).writeAsBytes(<int>[1, 2, 3]);
      expect(await store.isIntact(saved.single), isFalse);
    });

    test('a damaged index is kept aside and rebuilt from the valid files',
        () async {
      final store = storeFor('user-a');
      final saved = await store.add(<ScannerNewDocument>[
        await pdfItem('One', 2),
        await imageItem('Two', 1),
      ]);
      await File(p.join(store.accountDir.path, 'index.json'))
          .writeAsString('{ this is not json');
      final fresh = storeFor('user-a');
      final library = await fresh.load();
      expect(library.recoveredFromDamagedIndex, isTrue);
      expect(library.documents, hasLength(2));
      expect(library.documents.map((d) => d.pageCount).toSet(), <int>{2, 1});
      for (final doc in saved) {
        expect(fresh.fileOf(doc).existsSync(), isTrue,
            reason: 'recovery never deletes a document');
      }
      expect(
          store.accountDir
              .listSync()
              .any((e) => p.basename(e.path).startsWith('index.damaged-')),
          isTrue);
      // The rebuilt index is saved: loading again needs no recovery.
      expect(
          (await storeFor('user-a').load()).recoveredFromDamagedIndex, isFalse);
    });

    test('an index naming a file outside its folder is refused as damaged',
        () async {
      final store = storeFor('user-a');
      await store.accountDir.create(recursive: true);
      final evil = <String, Object?>{
        'version': 1,
        'userId': 'user-a',
        'entries': <Object?>[
          <String, Object?>{
            'state': 'ready',
            'document': <String, Object?>{
              'id': 'x',
              'fileName': '../../outside.pdf',
              'name': 'Evil',
              'scanType': 'document',
              'format': 'pdf',
              'mimeType': 'application/pdf',
              'createdAt': '2026-10-17T12:00:00.000Z',
              'fileSize': 10,
              'pageCount': 1,
              'batchIndex': 0,
            },
          },
        ],
      };
      await File(p.join(store.accountDir.path, 'index.json'))
          .writeAsString(jsonEncode(evil));
      final library = await store.load();
      expect(library.documents, isEmpty);
      expect(library.recoveredFromDamagedIndex, isTrue);
    });

    test(
        'an interrupted save: a whole file is kept, a missing one dropped, '
        'half-written parts removed', () async {
      final store = storeFor('user-a');
      final good =
          await store.add(<ScannerNewDocument>[await pdfItem('Good', 1)]);
      // Hand-craft the state a crash would leave behind.
      final doc = ScannerDocument(
        id: 'crash1',
        fileName: 'crash1.pdf',
        name: 'Finished before crash',
        scanType: ScanMode.document,
        format: ExportFormat.pdf,
        mimeType: 'application/pdf',
        createdAt: DateTime.utc(2026, 10, 17, 13),
        fileSize: 0,
        pageCount: 2,
      );
      final bytes = await pdfBytes(2);
      final whole = doc.toJson()..['fileSize'] = bytes.length;
      final lost = Map<String, dynamic>.from(whole)
        ..['id'] = 'crash2'
        ..['fileName'] = 'crash2.pdf'
        ..['name'] = 'Never written';
      await writeFile(Directory(p.join(store.accountDir.path, 'files')),
          'crash1.pdf', bytes);
      await writeFile(Directory(p.join(store.accountDir.path, 'files')),
          'crash3.pdf.part', <int>[1, 2, 3]);
      final index = jsonDecode(
          await File(p.join(store.accountDir.path, 'index.json'))
              .readAsString()) as Map<String, dynamic>;
      (index['entries'] as List)
        ..add(<String, Object?>{'state': 'pending', 'document': whole})
        ..add(<String, Object?>{'state': 'pending', 'document': lost});
      await File(p.join(store.accountDir.path, 'index.json'))
          .writeAsString(jsonEncode(index));

      final library = await storeFor('user-a').load();
      expect(library.documents.map((d) => d.name).toSet(),
          <String>{'Good', 'Finished before crash'});
      expect(library.missingIds, isEmpty);
      expect(relativeFiles(store.accountDir).any((f) => f.endsWith('.part')),
          isFalse);
      expect(good.single.name, 'Good');
    });

    test('an interrupted delete is finished and the document stays gone',
        () async {
      final store = storeFor('user-a');
      final saved = await store.add(<ScannerNewDocument>[
        await pdfItem('Doomed', 1),
        await pdfItem('Safe', 1),
      ]);
      final indexFile = File(p.join(store.accountDir.path, 'index.json'));
      final index =
          jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
      for (final entry in index['entries'] as List) {
        if ((entry as Map)['document']['id'] == saved[0].id) {
          entry['state'] = 'deleting';
        }
      }
      await indexFile.writeAsString(jsonEncode(index));
      final library = await storeFor('user-a').load();
      expect(library.documents.map((d) => d.name), <String>['Safe']);
      expect(store.fileOf(saved[0]).existsSync(), isFalse);
      expect(store.fileOf(saved[1]).existsSync(), isTrue);
    });
  });

  group('names', () {
    test(
        'sanitizing keeps Unicode and drops separators, controls and bidi '
        'overrides', () {
      expect(ScannerNaming.sanitizeDisplayName('عقد/إيجار'), 'عقد إيجار');
      expect(ScannerNaming.sanitizeDisplayName('a\\b:c*d?e"f<g>h|i'),
          'a b c d e f g h i');
      expect(ScannerNaming.sanitizeDisplayName('x\u0000y\u202Ez'), 'x y z');
      expect(ScannerNaming.sanitizeDisplayName('  ..hidden.  '), 'hidden');
      expect(ScannerNaming.sanitizeDisplayName('a   b\t\nc'), 'a b c');
      expect(ScannerNaming.sanitizeDisplayName('   '), isNull);
      expect(ScannerNaming.sanitizeDisplayName('...'), isNull);
    });

    test('long names are cut by characters, never in the middle of one', () {
      final emoji = List.filled(100, '😀').join();
      final cut = ScannerNaming.sanitizeDisplayName(emoji)!;
      expect(cut.runes.length, ScannerNaming.maxNameRunes);
      expect(cut.runes.every((r) => r == 0x1F600), isTrue);
    });

    test('unique names add (2), (3) and compare without case', () {
      expect(ScannerNaming.uniqueName('A', <String>[]), 'A');
      expect(ScannerNaming.uniqueName('A', <String>['a']), 'A (2)');
      expect(ScannerNaming.uniqueName('A', <String>['a', 'A (2)']), 'A (3)');
    });

    test('only internal file names are accepted from an index', () {
      expect(ScannerNaming.isStoredFileName('3f2a-9b.pdf'), isTrue);
      expect(ScannerNaming.isStoredFileName('x.jpg'), isTrue);
      expect(ScannerNaming.isStoredFileName('x.png'), isTrue);
      expect(ScannerNaming.isStoredFileName('../x.pdf'), isFalse);
      expect(ScannerNaming.isStoredFileName('a/b.pdf'), isFalse);
      expect(ScannerNaming.isStoredFileName(r'a\b.pdf'), isFalse);
      expect(ScannerNaming.isStoredFileName('x.exe'), isFalse);
      expect(ScannerNaming.isStoredFileName('x.pdf.part'), isFalse);
      expect(ScannerNaming.isStoredFileName('عقد.pdf'), isFalse);
    });

    test('the default title names the mode and the minute', () {
      expect(
          ScannerNaming.defaultName(
              ScanMode.businessCard, DateTime(2026, 3, 7, 9, 5)),
          'businessCard_scan_20260307_0905');
    });
  });
}

Future<ScannerNewDocument> jpegItem() async {
  final dir = makeTempDir('jpeg_item');
  final file = await writeFile(dir, 'one.jpg', jpegBytes());
  return ScannerNewDocument(
    source: file,
    inspected: await testInspector().inspect(file),
    name: 'Photo',
    scanType: ScanMode.document,
  );
}
