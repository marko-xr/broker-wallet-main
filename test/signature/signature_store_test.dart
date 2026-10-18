import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';
import 'package:broker_wallet/src/services/signature/signature_store.dart';

import 'signature_fixtures.dart';

Matcher failsWith(SignatureFailure kind) =>
    throwsA(isA<SignatureException>().having((e) => e.kind, 'kind', kind));

void main() {
  late Directory base;
  late Directory work;
  var counter = 0;
  var clockTick = 0;

  setUp(() {
    base = makeTempDir('sig_store');
    work = makeTempDir('sig_work');
    counter = 0;
    clockTick = 0;
  });
  tearDown(() {
    for (final d in [base, work]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  SignatureStore storeFor(String user,
      {SignatureFileCopier? copier, SignatureFileVerifier? verify}) {
    return SignatureStore(
      accountDir: SignatureStore.accountDirectory(base, user),
      userId: user,
      verify: verify ??
          (file) async => analyzeSignaturePdf(file.path, maxBytes: 1 << 28),
      copier: copier,
      clock: () => DateTime.utc(2026, 10, 18, 9, 0, clockTick++),
      idGenerator: () => 'doc${counter++}',
    );
  }

  Future<(File, SignatureAnalysis)> output(String tag, {int pages = 2}) async {
    final file = await writeFile(work, '$tag.pdf', buildPdf(tag, count: pages));
    return (file, analysisOf(file));
  }

  Future<SignedDocument> save(SignatureStore store, String name, String tag,
      {int pages = 2, int signatures = 1, int items = 2}) async {
    final (file, analysis) = await output(tag, pages: pages);
    return store.add(
      source: file,
      name: name,
      size: analysis.size,
      pageCount: analysis.pageCount,
      signatureCount: signatures,
      itemCount: items,
    );
  }

  Directory accountDir(String user) =>
      SignatureStore.accountDirectory(base, user);

  test('a saved document is listed with its real size, pages and counts',
      () async {
    final store = storeFor('user-a');
    final doc =
        await save(store, 'Contract', 'A', pages: 4, signatures: 2, items: 5);
    expect(doc.pageCount, 4);
    expect(doc.signatureCount, 2);
    expect(doc.itemCount, 5);
    expect(doc.name, 'Contract');
    expect(doc.fileName, 'doc0.pdf');
    final library = await storeFor('user-a').load();
    expect(library.documents.map((d) => d.id), [doc.id]);
    expect(library.documents.single.signatureCount, 2);
    expect(library.documents.single.itemCount, 5);
    expect(store.fileOf(doc).lengthSync(), doc.fileSize);
    expect(library.missingIds, isEmpty);
    // The folder holds the document and the index, nothing else.
    expect(
        relativeFiles(accountDir('user-a')), ['files/doc0.pdf', 'index.json']);
  });

  test('the stored file is exactly the file that was handed over', () async {
    final store = storeFor('user-a');
    final (file, analysis) = await output('Same');
    final doc = await store.add(
      source: file,
      name: 'Same',
      size: analysis.size,
      pageCount: analysis.pageCount,
      signatureCount: 1,
      itemCount: 1,
    );
    expect(store.fileOf(doc).readAsBytesSync(), file.readAsBytesSync());
    expect(await SignatureStore.sameBytes(store.fileOf(doc), file), isTrue);
  });

  test('titles are unique per account, Arabic is kept, collisions get a number',
      () async {
    final store = storeFor('user-a');
    final first = await save(store, 'عقد البيع', 'A');
    final second = await save(store, 'عقد البيع', 'B');
    final third = await save(store, 'عقد البيع', 'C');
    expect(first.name, 'عقد البيع');
    expect(second.name, 'عقد البيع (2)');
    expect(third.name, 'عقد البيع (3)');
    expect({first.fileName, second.fileName, third.fileName}, hasLength(3));
    // The stored file name is an internal id, never the typed title.
    for (final doc in [first, second, third]) {
      expect(SignatureNaming.isStoredFileName(doc.fileName), isTrue);
    }
    expect(first.exportFileName, 'عقد البيع.pdf');
  });

  group('accounts', () {
    test('another account never sees these documents', () async {
      final a = storeFor('user-a');
      await save(a, 'Mine', 'A');
      final b = storeFor('user-b');
      expect((await b.load()).documents, isEmpty);
      await save(b, 'Theirs', 'B');
      expect((await a.load()).documents.map((d) => d.name), ['Mine']);
      expect((await b.load()).documents.map((d) => d.name), ['Theirs']);
      expect(accountDir('user-a').path, isNot(accountDir('user-b').path));
    });

    test('an index that names another account is refused and set aside',
        () async {
      final a = storeFor('user-a');
      await save(a, 'Mine', 'A');
      final dirA = accountDir('user-a');
      final dirB = accountDir('user-b');
      // Account A's folder copied under account B, as a mangled restore could.
      await Directory(p.join(dirB.path, 'files')).create(recursive: true);
      File(p.join(dirA.path, 'index.json'))
          .copySync(p.join(dirB.path, 'index.json'));
      File(p.join(dirA.path, 'files', 'doc0.pdf'))
          .copySync(p.join(dirB.path, 'files', 'doc0.pdf'));
      final library = await storeFor('user-b').load();
      // Not trusted as A's list; rebuilt from the valid file with a generic title
      // and unknown (zero) counts.
      expect(library.recoveredFromDamagedIndex, isTrue);
      expect(library.documents.single.name, 'Recovered PDF');
      expect(library.documents.single.signatureCount, 0);
      expect(library.documents.single.itemCount, 0);
      expect(relativeFiles(dirB).any((f) => f.startsWith('index.damaged-')),
          isTrue);
    });

    test('an account id can never name a parent folder', () {
      final tricky = SignatureStore.accountDirectory(base, '../../etc/passwd');
      expect(p.isWithin(base.path, tricky.path), isTrue);
      expect(p.basename(tricky.path), startsWith('u_'));
      expect(
          () => SignatureStore.accountDirectory(base, ''), throwsArgumentError);
      expect(
          p.isWithin(p.join(base.path, SignatureStore.rootFolderName),
              accountDir('user-a').path),
          isTrue);
    });

    test('documents an earlier version kept are neither read nor touched',
        () async {
      // The old tool kept every account's PDFs in one folder and one list.
      final legacy = Directory(p.join(base.path, 'signed_documents'))
        ..createSync(recursive: true);
      final oldPdf = await writeFile(
          legacy, 'signed_doc_1760000000000.pdf', buildPdf('OLD', count: 1));
      final oldBytes = oldPdf.readAsBytesSync();
      final note = await writeFile(legacy, 'note.txt', 'keep me'.codeUnits);

      final store = storeFor('user-a');
      expect((await store.load()).documents, isEmpty);
      final doc = await save(store, 'New', 'N');
      await store.rename(doc.id, 'Renamed');
      await save(store, 'Other', 'O');
      await store.delete([doc.id]);
      await storeFor('user-b').load();

      expect(SignatureStore.rootFolderName, isNot('signed_documents'));
      expect(oldPdf.existsSync(), isTrue);
      expect(oldPdf.readAsBytesSync(), oldBytes);
      expect(note.readAsStringSync(), 'keep me');
      expect(
          relativeFiles(legacy), ['note.txt', 'signed_doc_1760000000000.pdf']);
      // And they are not listed for anyone.
      expect((await store.load()).documents.map((d) => d.name), ['Other']);
      expect((await storeFor('user-b').load()).documents, isEmpty);
    });
  });

  group('saving', () {
    test('a copy that fails half way leaves nothing and changes nothing',
        () async {
      final store = storeFor('user-a', copier: (source, dest) async {
        await dest.writeAsBytes(
            await source.readAsBytes().then((b) => b.sublist(0, 50)));
        throw const FileSystemException(
            'disk full', '', OSError('No space left on device', 28));
      });
      await save(storeFor('user-a'), 'Existing', 'E');
      final (file, analysis) = await output('N');
      await expectLater(
          store.add(
              source: file,
              name: 'New',
              size: analysis.size,
              pageCount: analysis.pageCount,
              signatureCount: 1,
              itemCount: 1),
          failsWith(SignatureFailure.storageFull));
      final library = await storeFor('user-a').load();
      expect(library.documents.map((d) => d.name), ['Existing']);
      final dir = accountDir('user-a');
      expect(relativeFiles(dir).where((f) => f.endsWith('.part')), isEmpty);
      expect(relativeFiles(dir).where((f) => f.startsWith('files/')),
          ['files/doc0.pdf']);
    });

    test('a zero-byte, short, altered or wrong copy is never a success',
        () async {
      final (file, analysis) = await output('N', pages: 3);
      Future<void> expectRefused(SignatureFileCopier copier,
          {int? pageCount}) async {
        final store = storeFor('user-a', copier: copier);
        await expectLater(
            store.add(
                source: file,
                name: 'Bad',
                size: analysis.size,
                pageCount: pageCount ?? analysis.pageCount,
                signatureCount: 1,
                itemCount: 1),
            failsWith(SignatureFailure.writeFailed));
        expect((await storeFor('user-a').load()).documents, isEmpty);
        expect(
            relativeFiles(accountDir('user-a'))
                .where((f) => f.startsWith('files/')),
            isEmpty);
      }

      // Nothing was written.
      await expectRefused((source, dest) async => dest.writeAsBytes(<int>[]));
      // Cut short.
      await expectRefused((source, dest) async {
        final bytes = await source.readAsBytes();
        await dest.writeAsBytes(bytes.sublist(0, bytes.length - 10));
      });
      // The right size, one byte different.
      await expectRefused((source, dest) async {
        final bytes = await source.readAsBytes();
        bytes[bytes.length ~/ 2] ^= 0xFF;
        await dest.writeAsBytes(bytes);
      });
      // A faithful copy of a file that is not what the record says.
      await expectRefused((source, dest) async => source.copy(dest.path),
          pageCount: analysis.pageCount + 1);
    });

    test('operations run one at a time, so no two saves share a title',
        () async {
      final store = storeFor('user-a');
      final inputs = [
        for (var i = 0; i < 4; i++) await output('T$i'),
      ];
      final saved = await Future.wait([
        for (final (file, analysis) in inputs)
          store.add(
              source: file,
              name: 'Same',
              size: analysis.size,
              pageCount: analysis.pageCount,
              signatureCount: 1,
              itemCount: 1),
      ]);
      expect(saved.map((d) => d.name).toSet(), hasLength(4));
      expect((await store.load()).documents, hasLength(4));
    });
  });

  group('recovery', () {
    test(
        'a crash after the pending entry is finished or undone on the next load',
        () async {
      final store = storeFor('user-a');
      final doc = await save(store, 'Done', 'D');
      final dir = accountDir('user-a');
      final indexFile = File(p.join(dir.path, 'index.json'));

      // Crash after the file was renamed but before the index said "ready".
      var index =
          jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
      (index['entries'] as List).single['state'] = 'pending';
      indexFile.writeAsStringSync(jsonEncode(index));
      var library = await storeFor('user-a').load();
      expect(library.documents.map((d) => d.id), [doc.id]);
      index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
      expect((index['entries'] as List).single['state'], 'ready');

      // Crash after the pending entry but before the file existed.
      store.fileOf(doc).deleteSync();
      (index['entries'] as List).single['state'] = 'pending';
      indexFile.writeAsStringSync(jsonEncode(index));
      File('${store.fileOf(doc).path}.part').writeAsBytesSync([1, 2, 3]);
      library = await storeFor('user-a').load();
      expect(library.documents, isEmpty);
      expect(relativeFiles(dir).where((f) => f.endsWith('.part')), isEmpty);
    });

    test('a pending entry whose file is cut short is dropped, not listed',
        () async {
      final store = storeFor('user-a');
      final doc = await save(store, 'Cut', 'C');
      final dir = accountDir('user-a');
      final indexFile = File(p.join(dir.path, 'index.json'));
      final index =
          jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
      (index['entries'] as List).single['state'] = 'pending';
      indexFile.writeAsStringSync(jsonEncode(index));
      final bytes = store.fileOf(doc).readAsBytesSync();
      store.fileOf(doc).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      expect((await storeFor('user-a').load()).documents, isEmpty);
      expect(store.fileOf(doc).existsSync(), isFalse);
    });

    test('abandoned work files are swept, a draft in progress is not',
        () async {
      final store = storeFor('user-a');
      final dir = accountDir('user-a');
      final stale = File(p.join(dir.path, 'work', 'old.pdf'))
        ..createSync(recursive: true);
      final live = await store.newWorkFile();
      live.writeAsBytesSync([1]);
      await store.load();
      expect(stale.existsSync(), isFalse);
      expect(live.existsSync(), isTrue);
      await store.releaseWorkFile(live);
      expect(live.existsSync(), isFalse);
      expect(p.isWithin(p.join(dir.path, 'work'), live.path), isTrue);
    });

    test('a damaged index is set aside and rebuilt, never deleted', () async {
      final store = storeFor('user-a');
      final doc = await save(store, 'Kept', 'K');
      final dir = accountDir('user-a');
      File(p.join(dir.path, 'index.json')).writeAsStringSync('{ not json');
      final library = await storeFor('user-a').load();
      expect(library.recoveredFromDamagedIndex, isTrue);
      expect(library.documents.single.id, doc.id);
      final aside =
          relativeFiles(dir).where((f) => f.startsWith('index.damaged-'));
      expect(aside, hasLength(1));
      expect(File(p.join(dir.path, aside.single)).readAsStringSync(),
          '{ not json');
    });

    test('a record naming a file outside the folder is refused', () {
      Map<String, Object?> record(Object? fileName, {int pages = 1}) =>
          <String, Object?>{
            'id': 'x',
            'fileName': fileName,
            'name': 'n',
            'createdAt': '2026-10-18T00:00:00Z',
            'fileSize': 1,
            'pageCount': pages,
            'signatureCount': 0,
            'itemCount': 0,
          };
      expect(() => SignedDocument.fromJson(record('../../secret.pdf')),
          throwsFormatException);
      expect(() => SignedDocument.fromJson('nope'), throwsFormatException);
      expect(() => SignedDocument.fromJson(record('x.pdf', pages: 0)),
          throwsFormatException);
      expect(SignedDocument.fromJson(record('x.pdf')).fileName, 'x.pdf');
    });

    test(
        'a document whose file vanished stays listed as missing and can be removed',
        () async {
      final store = storeFor('user-a');
      final doc = await save(store, 'Gone', 'G');
      store.fileOf(doc).deleteSync();
      final library = await store.load();
      expect(library.documents.map((d) => d.id), [doc.id]);
      expect(library.missingIds, {doc.id});
      expect(await store.isIntact(doc), isFalse);
      final outcome = await store.delete([doc.id]);
      expect(outcome.deleted, [doc.id]);
      expect((await store.load()).documents, isEmpty);
    });

    test('an interrupted delete is finished on the next load', () async {
      final store = storeFor('user-a');
      final doc = await save(store, 'One', 'A');
      final dir = accountDir('user-a');
      final indexFile = File(p.join(dir.path, 'index.json'));
      final index =
          jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
      (index['entries'] as List).single['state'] = 'deleting';
      indexFile.writeAsStringSync(jsonEncode(index));
      expect((await storeFor('user-a').load()).documents, isEmpty);
      expect(store.fileOf(doc).existsSync(), isFalse);
    });

    test('a stored file that was altered is no longer intact', () async {
      final store = storeFor('user-a');
      final doc = await save(store, 'Altered', 'A');
      expect(await store.isIntact(doc), isTrue);
      final file = store.fileOf(doc);
      file.writeAsBytesSync(<int>[...file.readAsBytesSync(), 0, 0]);
      expect(await store.isIntact(doc), isFalse);
    });
  });

  group('renaming and deleting', () {
    test('renaming works on the id, refuses clashes and keeps the stored file',
        () async {
      final store = storeFor('user-a');
      final a = await save(store, 'One', 'A');
      final b = await save(store, 'Two', 'B');
      final renamed = await store.rename(a.id, '  عقد جديد  ');
      expect(renamed.name, 'عقد جديد');
      expect(renamed.fileName, a.fileName);
      await expectLater(store.rename(b.id, 'عقد جديد'),
          failsWith(SignatureFailure.nameInUse));
      await expectLater(store.rename(b.id, 'ONE'), completes);
      await expectLater(
          store.rename(b.id, '///'), failsWith(SignatureFailure.invalidName));
      await expectLater(
          store.rename('missing', 'X'), failsWith(SignatureFailure.notFound));
      final names = (await store.load()).documents.map((d) => d.name).toList()
        ..sort();
      expect(names, ['ONE', 'عقد جديد']);
    });

    test('a rename never touches the stored bytes', () async {
      final store = storeFor('user-a');
      final doc = await save(store, 'One', 'A');
      final before = store.fileOf(doc).readAsBytesSync();
      await store.rename(doc.id, 'Another');
      expect(store.fileOf(doc).readAsBytesSync(), before);
    });

    test('deleting removes exactly the listed documents and reports the rest',
        () async {
      final store = storeFor('user-a');
      final a = await save(store, 'One', 'A');
      final b = await save(store, 'Two', 'B');
      final c = await save(store, 'Three', 'C');
      final outcome = await store.delete([a.id, c.id, 'nope']);
      expect(outcome.deleted, unorderedEquals([a.id, c.id]));
      expect(outcome.notFound, ['nope']);
      expect(outcome.failed, isEmpty);
      expect((await store.load()).documents.map((d) => d.id), [b.id]);
      expect(store.fileOf(a).existsSync(), isFalse);
      expect(store.fileOf(b).existsSync(), isTrue);
      // A second account's identical id is untouched.
      final other = storeFor('user-b');
      counter = 0;
      final x = await save(other, 'Same id', 'X');
      expect(x.id, isNot(b.id));
      expect((await store.load()).documents.map((d) => d.id), [b.id]);
    });

    test('a bulk delete of everything leaves an empty, healthy account',
        () async {
      final store = storeFor('user-a');
      final ids = [
        for (final tag in ['A', 'B', 'C', 'D'])
          (await save(store, 'Doc $tag', tag)).id,
      ];
      final outcome = await store.delete(ids);
      expect(outcome.deleted, unorderedEquals(ids));
      expect((await store.load()).documents, isEmpty);
      expect(
          relativeFiles(accountDir('user-a'))
              .where((f) => f.startsWith('files/')),
          isEmpty);
      // The account can save again.
      expect((await save(store, 'After', 'Z')).name, 'After');
    });
  });
}
