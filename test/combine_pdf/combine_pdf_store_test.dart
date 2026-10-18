import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:broker_wallet/src/services/combine_pdf/combine_executor.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_store.dart';

import 'combine_fixtures.dart';

void main() {
  late Directory base;
  late Directory work;
  var counter = 0;
  var clockTick = 0;

  setUp(() {
    base = makeTempDir('store');
    work = makeTempDir('work');
    counter = 0;
    clockTick = 0;
  });
  tearDown(() {
    for (final d in [base, work]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  CombinePdfStore storeFor(String user,
      {CombineFileCopier? copier, CombineFileVerifier? verify}) {
    return CombinePdfStore(
      accountDir: CombinePdfStore.accountDirectory(base, user),
      userId: user,
      verify: verify ??
          (file) => const InlineCombineExecutor()
              .analyze(file.path, maxBytes: 1 << 28),
      copier: copier,
      clock: () => DateTime.utc(2026, 10, 18, 9, 0, clockTick++),
      idGenerator: () => 'doc${counter++}',
    );
  }

  Future<(File, CombineAnalysis)> output(String tag, {int pages = 2}) async {
    final file = await writeFile(work, '$tag.pdf', buildPdf(tag, count: pages));
    return (file, await const InlineCombineExecutor().analyze(file.path));
  }

  Future<CombinedPdf> save(CombinePdfStore store, String name, String tag,
      {int pages = 2}) async {
    final (file, analysis) = await output(tag, pages: pages);
    return store.add(source: file, name: name, expected: analysis);
  }

  test('a saved document is listed with its real size and page count',
      () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Contract', 'A', pages: 4);
    expect(doc.pageCount, 4);
    expect(doc.name, 'Contract');
    expect(doc.fileName, 'doc0.pdf');
    final library = await store.load();
    expect(library.documents.map((d) => d.id), [doc.id]);
    expect(store.fileOf(doc).lengthSync(), doc.fileSize);
    expect(library.missingIds, isEmpty);
    // The folder holds the document and the index, nothing else.
    expect(relativeFiles(CombinePdfStore.accountDirectory(base, 'user-a')),
        ['files/doc0.pdf', 'index.json']);
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
      expect(CombineNaming.isStoredFileName(doc.fileName), isTrue);
    }
    expect(first.exportFileName, 'عقد البيع.pdf');
  });

  test('titles lose path separators and bidi controls but keep their letters',
      () {
    expect(CombineNaming.sanitizeDisplayName('a/b\\c:d*e?'), 'a b c d e');
    expect(CombineNaming.sanitizeDisplayName('\u202Eevil\u202C name'), 'evil name');
    expect(CombineNaming.sanitizeDisplayName('  ..  '), isNull);
    expect(CombineNaming.sanitizeDisplayName('   '), isNull);
    expect(CombineNaming.sanitizeDisplayName('x' * 200)!.runes.length, 80);
    expect(CombineNaming.defaultName(DateTime(2026, 10, 18, 9, 5)),
        'combined_20261018_0905');
  });

  test('another account never sees these documents', () async {
    final a = storeFor('user-a');
    await save(a, 'Mine', 'A');
    final b = storeFor('user-b');
    expect((await b.load()).documents, isEmpty);
    await save(b, 'Theirs', 'B');
    expect((await a.load()).documents.map((d) => d.name), ['Mine']);
    expect((await b.load()).documents.map((d) => d.name), ['Theirs']);
    expect(CombinePdfStore.accountDirectory(base, 'user-a').path,
        isNot(CombinePdfStore.accountDirectory(base, 'user-b').path));
  });

  test('an index that names another account is refused and set aside',
      () async {
    final a = storeFor('user-a');
    await save(a, 'Mine', 'A');
    final dirA = CombinePdfStore.accountDirectory(base, 'user-a');
    final dirB = CombinePdfStore.accountDirectory(base, 'user-b');
    // Copy account A's folder under account B, as a mangled restore could.
    await Directory(p.join(dirB.path, 'files')).create(recursive: true);
    File(p.join(dirA.path, 'index.json'))
        .copySync(p.join(dirB.path, 'index.json'));
    File(p.join(dirA.path, 'files', 'doc0.pdf'))
        .copySync(p.join(dirB.path, 'files', 'doc0.pdf'));
    final library = await storeFor('user-b').load();
    // Not trusted as A's list; rebuilt from the valid file with a generic title.
    expect(library.recoveredFromDamagedIndex, isTrue);
    expect(library.documents.single.name, 'Recovered PDF');
    expect(
        relativeFiles(dirB).any((f) => f.startsWith('index.damaged-')), isTrue);
  });

  test('an account id can never name a parent folder', () {
    final tricky = CombinePdfStore.accountDirectory(base, '../../etc/passwd');
    expect(p.isWithin(base.path, tricky.path), isTrue);
    expect(p.basename(tricky.path), startsWith('u_'));
    expect(
        () => CombinePdfStore.accountDirectory(base, ''), throwsArgumentError);
  });

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
        store.add(source: file, name: 'New', expected: analysis),
        throwsA(isA<CombinePdfException>()
            .having((e) => e.kind, 'kind', CombinePdfFailure.storageFull)));
    final library = await storeFor('user-a').load();
    expect(library.documents.map((d) => d.name), ['Existing']);
    final dir = CombinePdfStore.accountDirectory(base, 'user-a');
    expect(relativeFiles(dir).where((f) => f.endsWith('.part')), isEmpty);
    expect(relativeFiles(dir).where((f) => f.startsWith('files/')),
        ['files/doc0.pdf']);
  });

  test('a copy of the wrong size or page count is never listed', () async {
    final truncating = storeFor('user-a', copier: (source, dest) async {
      final bytes = await source.readAsBytes();
      await dest.writeAsBytes(bytes.sublist(0, bytes.length - 10));
    });
    final (file, analysis) = await output('N', pages: 3);
    await expectLater(
        truncating.add(source: file, name: 'Cut', expected: analysis),
        throwsA(isA<CombinePdfException>()
            .having((e) => e.kind, 'kind', CombinePdfFailure.writeFailed)));
    // Same size but different content: the verifier reads another page count.
    final other = await writeFile(work, 'other.pdf', buildPdf('N', count: 4));
    final swapping = storeFor('user-a', copier: (source, dest) async {
      final bytes = await other.readAsBytes();
      final real = await source.readAsBytes();
      await dest.writeAsBytes(bytes.length == real.length ? bytes : real);
    });
    final (same, sameAnalysis) = await output('M', pages: 3);
    final lying = CombineAnalysis(
        size: sameAnalysis.size, pageCount: 4, features: sameAnalysis.features);
    await expectLater(
        swapping.add(source: same, name: 'Lie', expected: lying),
        throwsA(isA<CombinePdfException>()
            .having((e) => e.kind, 'kind', CombinePdfFailure.writeFailed)));
    expect((await storeFor('user-a').load()).documents, isEmpty);
  });

  test('a crash after the pending entry is finished or undone on the next load',
      () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Done', 'D');
    final dir = CombinePdfStore.accountDirectory(base, 'user-a');
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

  test('abandoned work files are swept, a combine in progress is not',
      () async {
    final store = storeFor('user-a');
    final dir = CombinePdfStore.accountDirectory(base, 'user-a');
    final stale = File(p.join(dir.path, 'work', 'old.pdf'))
      ..createSync(recursive: true);
    final live = await store.newWorkFile();
    live.writeAsBytesSync([1]);
    await store.load();
    expect(stale.existsSync(), isFalse);
    expect(live.existsSync(), isTrue);
    await store.releaseWorkFile(live);
    expect(live.existsSync(), isFalse);
  });

  test('a damaged index is set aside and rebuilt, never deleted', () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Kept', 'K');
    final dir = CombinePdfStore.accountDirectory(base, 'user-a');
    File(p.join(dir.path, 'index.json')).writeAsStringSync('{ not json');
    final library = await storeFor('user-a').load();
    expect(library.recoveredFromDamagedIndex, isTrue);
    expect(library.documents.single.id, doc.id);
    final aside =
        relativeFiles(dir).where((f) => f.startsWith('index.damaged-'));
    expect(aside, hasLength(1));
    expect(
        File(p.join(dir.path, aside.single)).readAsStringSync(), '{ not json');
  });

  test('a record naming a file outside the folder is refused', () {
    expect(
        () => CombinedPdf.fromJson({
              'id': 'x',
              'fileName': '../../secret.pdf',
              'name': 'n',
              'createdAt': '2026-10-18T00:00:00Z',
              'fileSize': 1,
              'pageCount': 1,
            }),
        throwsFormatException);
    expect(() => CombinedPdf.fromJson('nope'), throwsFormatException);
    expect(
        () => CombinedPdf.fromJson({
              'id': 'x',
              'fileName': 'x.pdf',
              'name': 'n',
              'createdAt': '2026-10-18T00:00:00Z',
              'fileSize': 1,
              'pageCount': 0,
            }),
        throwsFormatException);
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

  test('renaming works on the id, refuses clashes and keeps the stored file',
      () async {
    final store = storeFor('user-a');
    final a = await save(store, 'One', 'A');
    final b = await save(store, 'Two', 'B');
    final renamed = await store.rename(a.id, '  عقد جديد  ');
    expect(renamed.name, 'عقد جديد');
    expect(renamed.fileName, a.fileName);
    await expectLater(
        store.rename(b.id, 'عقد جديد'),
        throwsA(isA<CombinePdfException>()
            .having((e) => e.kind, 'kind', CombinePdfFailure.nameInUse)));
    await expectLater(store.rename(b.id, 'ONE'), completes);
    await expectLater(
        store.rename(b.id, '///'),
        throwsA(isA<CombinePdfException>()
            .having((e) => e.kind, 'kind', CombinePdfFailure.invalidName)));
    await expectLater(
        store.rename('missing', 'X'),
        throwsA(isA<CombinePdfException>()
            .having((e) => e.kind, 'kind', CombinePdfFailure.notFound)));
    final names = (await store.load()).documents.map((d) => d.name).toList()
      ..sort();
    expect(names, ['ONE', 'عقد جديد']);
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
  });

  test('an interrupted delete is finished on the next load', () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'One', 'A');
    final dir = CombinePdfStore.accountDirectory(base, 'user-a');
    final indexFile = File(p.join(dir.path, 'index.json'));
    final index =
        jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
    (index['entries'] as List).single['state'] = 'deleting';
    indexFile.writeAsStringSync(jsonEncode(index));
    expect((await storeFor('user-a').load()).documents, isEmpty);
    expect(store.fileOf(doc).existsSync(), isFalse);
  });

  test('operations run one at a time, so no two saves share a title', () async {
    final store = storeFor('user-a');
    final inputs = [
      for (var i = 0; i < 4; i++) await output('T$i'),
    ];
    final saved = await Future.wait([
      for (final (file, analysis) in inputs)
        store.add(source: file, name: 'Same', expected: analysis),
    ]);
    final names = saved.map((d) => d.name).toSet();
    expect(names, hasLength(4));
    expect((await store.load()).documents, hasLength(4));
  });
}
