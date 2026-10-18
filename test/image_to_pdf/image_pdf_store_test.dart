import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart' hide PdfPageSize;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_store.dart';

Uint8List simplePdf(int pages, {String? password}) {
  final document = PdfDocument();
  for (var i = 0; i < pages; i++) {
    document.pages.add().graphics.drawString(
        'page ${i + 1}', PdfStandardFont(PdfFontFamily.helvetica, 20),
        bounds: const Rect.fromLTWH(20, 20, 200, 30));
  }
  if (password != null) {
    document.security.algorithm = PdfEncryptionAlgorithm.aesx256BitRevision6;
    document.security.userPassword = password;
    document.security.ownerPassword = password;
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

List<String> relativeFiles(Directory dir) {
  if (!dir.existsSync()) return <String>[];
  return [
    for (final item in dir.listSync(recursive: true, followLinks: false))
      if (item is File)
        p.relative(item.path, from: dir.path).replaceAll('\\', '/')
  ]..sort();
}

void main() {
  late Directory base;
  late Directory work;
  var counter = 0;
  var clockTick = 0;

  setUp(() {
    base = Directory.systemTemp.createTempSync('i2p_store_');
    work = Directory.systemTemp.createTempSync('i2p_work_');
    counter = 0;
    clockTick = 0;
  });
  tearDown(() {
    for (final d in [base, work]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  ImagePdfStore storeFor(String user,
      {ImagePdfFileCopier? copier, ImagePdfFileVerifier? verify}) {
    return ImagePdfStore(
      accountDir: ImagePdfStore.accountDirectory(base, user),
      userId: user,
      verify: verify ?? (file) async => analyzeImagePdf(file.path),
      copier: copier,
      clock: () => DateTime.utc(2026, 10, 18, 9, 0, clockTick++),
      idGenerator: () => 'doc${counter++}',
    );
  }

  Future<(File, ImagePdfFileInfo)> output(String tag,
      {int pages = 2, String? password}) async {
    final file = File(p.join(work.path, '$tag.pdf'))
      ..writeAsBytesSync(simplePdf(pages, password: password));
    return (file, analyzeImagePdf(file.path, password: password));
  }

  Future<ImagePdfDocument> save(ImagePdfStore store, String name, String tag,
      {int pages = 2, int images = 2, String? password}) async {
    final (file, info) = await output(tag, pages: pages, password: password);
    return store.add(
        source: file,
        name: name,
        expected: ImagePdfFileInfo(
            size: info.size, pageCount: pages, encrypted: info.encrypted),
        pageCount: pages,
        imageCount: images);
  }

  test('a saved document is listed with its real size, pages and pictures',
      () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Contract', 'A', pages: 4, images: 6);
    expect(doc.pageCount, 4);
    expect(doc.imageCount, 6);
    expect(doc.encrypted, isFalse);
    expect(doc.name, 'Contract');
    expect(doc.fileName, 'doc0.pdf');
    final library = await store.load();
    expect(library.documents.map((d) => d.id), [doc.id]);
    expect(store.fileOf(doc).lengthSync(), doc.fileSize);
    expect(library.missingIds, isEmpty);
    expect(relativeFiles(ImagePdfStore.accountDirectory(base, 'user-a')),
        ['files/doc0.pdf', 'index.json']);
  });

  test('titles are unique per account, Arabic is kept, stored names are ids',
      () async {
    final store = storeFor('user-a');
    final first = await save(store, 'عقد البيع', 'A');
    final second = await save(store, 'عقد البيع', 'B');
    expect(first.name, 'عقد البيع');
    expect(second.name, 'عقد البيع (2)');
    for (final doc in [first, second]) {
      expect(ImagePdfNaming.isStoredFileName(doc.fileName), isTrue);
    }
    expect(first.exportFileName, 'عقد البيع.pdf');
    expect(ImagePdfNaming.sanitizeDisplayName('a/b\\c:d*e?'), 'a b c d e');
    expect(ImagePdfNaming.sanitizeDisplayName('\u202Eevil\u202C name'),
        'evil name');
    expect(ImagePdfNaming.sanitizeDisplayName('  ..  '), isNull);
    expect(ImagePdfNaming.defaultName(DateTime(2026, 10, 18, 9, 5)),
        'PDF_Document_20261018_0905');
  });

  test('another account never sees these documents', () async {
    final a = storeFor('user-a');
    await save(a, 'Mine', 'A');
    final b = storeFor('user-b');
    expect((await b.load()).documents, isEmpty);
    await save(b, 'Theirs', 'B');
    expect((await a.load()).documents.map((d) => d.name), ['Mine']);
    expect((await b.load()).documents.map((d) => d.name), ['Theirs']);
    expect(ImagePdfStore.accountDirectory(base, 'user-a').path,
        isNot(ImagePdfStore.accountDirectory(base, 'user-b').path));
  });

  test('an index that names another account is refused and set aside',
      () async {
    final a = storeFor('user-a');
    await save(a, 'Mine', 'A');
    final dirA = ImagePdfStore.accountDirectory(base, 'user-a');
    final dirB = ImagePdfStore.accountDirectory(base, 'user-b');
    await Directory(p.join(dirB.path, 'files')).create(recursive: true);
    File(p.join(dirA.path, 'index.json'))
        .copySync(p.join(dirB.path, 'index.json'));
    File(p.join(dirA.path, 'files', 'doc0.pdf'))
        .copySync(p.join(dirB.path, 'files', 'doc0.pdf'));
    final library = await storeFor('user-b').load();
    expect(library.recoveredFromDamagedIndex, isTrue);
    expect(library.documents.single.name, 'Recovered PDF');
    expect(
        relativeFiles(dirB).any((f) => f.startsWith('index.damaged-')), isTrue);
  });

  test('an account id can never name a parent folder', () {
    final tricky = ImagePdfStore.accountDirectory(base, '../../etc/passwd');
    expect(p.isWithin(base.path, tricky.path), isTrue);
    expect(p.basename(tricky.path), startsWith('u_'));
    expect(() => ImagePdfStore.accountDirectory(base, ''), throwsArgumentError);
    expect(p.basename(p.dirname(tricky.path)), 'image_to_pdf');
  });

  test('a copy that fails half way leaves nothing and changes nothing',
      () async {
    final failing = storeFor('user-a', copier: (source, dest) async {
      await dest.writeAsBytes((await source.readAsBytes()).sublist(0, 50));
      throw const FileSystemException(
          'disk full', '', OSError('No space left on device', 28));
    });
    await save(storeFor('user-a'), 'Existing', 'E');
    final (file, info) = await output('N');
    await expectLater(
        failing.add(
            source: file,
            name: 'New',
            expected: info,
            pageCount: 2,
            imageCount: 2),
        throwsA(isA<ImagePdfException>()
            .having((e) => e.kind, 'kind', ImagePdfFailure.storageFull)));
    expect((await storeFor('user-a').load()).documents.map((d) => d.name),
        ['Existing']);
    final dir = ImagePdfStore.accountDirectory(base, 'user-a');
    expect(relativeFiles(dir).where((f) => f.endsWith('.part')), isEmpty);
    expect(relativeFiles(dir).where((f) => f.startsWith('files/')),
        ['files/doc0.pdf']);
  });

  test('a copy of the wrong size or page count is never listed', () async {
    final truncating = storeFor('user-a', copier: (source, dest) async {
      final bytes = await source.readAsBytes();
      await dest.writeAsBytes(bytes.sublist(0, bytes.length - 10));
    });
    final (file, info) = await output('N', pages: 3);
    await expectLater(
        truncating.add(
            source: file,
            name: 'Cut',
            expected: info,
            pageCount: 3,
            imageCount: 3),
        throwsA(isA<ImagePdfException>()
            .having((e) => e.kind, 'kind', ImagePdfFailure.writeFailed)));
    // The right size but a different PDF: the verifier reads another page count.
    final other = File(p.join(work.path, 'other.pdf'))
      ..writeAsBytesSync(simplePdf(4));
    final swapping = storeFor('user-a', copier: (source, dest) async {
      final bytes = await other.readAsBytes();
      final real = await source.readAsBytes();
      await dest.writeAsBytes(bytes.length == real.length ? bytes : real);
    });
    final (same, sameInfo) = await output('M', pages: 3);
    await expectLater(
        swapping.add(
            source: same,
            name: 'Lie',
            expected: ImagePdfFileInfo(
                size: sameInfo.size, pageCount: 4, encrypted: false),
            pageCount: 4,
            imageCount: 4),
        throwsA(isA<ImagePdfException>()
            .having((e) => e.kind, 'kind', ImagePdfFailure.writeFailed)));
    expect((await storeFor('user-a').load()).documents, isEmpty);
  });

  test('a protected PDF is stored as protected and stays protected', () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Sealed', 'S', pages: 3, password: 'abcdef');
    expect(doc.encrypted, isTrue);
    expect(doc.pageCount, 3);
    final library = await store.load();
    expect(library.documents.single.encrypted, isTrue);
    expect(await store.isIntact(doc), isTrue);
    // An unprotected file swapped in under the same name is not the document.
    store.fileOf(doc).writeAsBytesSync(simplePdf(3));
    expect(await store.isIntact(doc), isFalse);
  });

  test('a protected file found without its list is recovered without a count',
      () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Sealed', 'S', pages: 3, password: 'abcdef');
    final dir = ImagePdfStore.accountDirectory(base, 'user-a');
    File(p.join(dir.path, 'index.json')).deleteSync();
    final library = await storeFor('user-a').load();
    expect(library.recoveredFromDamagedIndex, isTrue);
    final recovered = library.documents.single;
    expect(recovered.id, doc.id);
    expect(recovered.encrypted, isTrue);
    expect(recovered.pageCount, 0);
  });

  test('a crash after the pending entry is finished or undone on the next load',
      () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Done', 'D');
    final dir = ImagePdfStore.accountDirectory(base, 'user-a');
    final indexFile = File(p.join(dir.path, 'index.json'));
    var index =
        jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
    (index['entries'] as List).single['state'] = 'pending';
    indexFile.writeAsStringSync(jsonEncode(index));
    var library = await storeFor('user-a').load();
    expect(library.documents.map((d) => d.id), [doc.id]);
    index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
    expect((index['entries'] as List).single['state'], 'ready');

    store.fileOf(doc).deleteSync();
    (index['entries'] as List).single['state'] = 'pending';
    indexFile.writeAsStringSync(jsonEncode(index));
    File('${store.fileOf(doc).path}.part').writeAsBytesSync([1, 2, 3]);
    library = await storeFor('user-a').load();
    expect(library.documents, isEmpty);
    expect(relativeFiles(dir).where((f) => f.endsWith('.part')), isEmpty);
  });

  test('abandoned drafts are swept, a draft in progress is not', () async {
    final store = storeFor('user-a');
    final dir = ImagePdfStore.accountDirectory(base, 'user-a');
    final stale = File(p.join(dir.path, 'work', 'old.pdf'))
      ..createSync(recursive: true);
    final stalePart = File(p.join(dir.path, 'work', 'old2.pdf.part'))
      ..createSync();
    final live = await store.newWorkFile();
    live.writeAsBytesSync([1]);
    final livePart = File('${live.path}.part')..writeAsBytesSync([2]);
    await store.load();
    expect(stale.existsSync(), isFalse);
    expect(stalePart.existsSync(), isFalse);
    expect(live.existsSync(), isTrue);
    expect(livePart.existsSync(), isTrue);
    await store.releaseWorkFile(live);
    expect(live.existsSync(), isFalse);
    expect(livePart.existsSync(), isFalse);
  });

  test('staged pictures are swept only when asked, never by an ordinary load',
      () async {
    final store = storeFor('user-a');
    final staged = await store.newStagingFile('jpg');
    await staged.parent.create(recursive: true);
    staged.writeAsBytesSync([1, 2, 3]);
    expect(p.basename(staged.path), 'doc0.jpg');
    await save(store, 'Doc', 'D');
    await store.load();
    expect(staged.existsSync(), isTrue);
    await store.sweepStaging();
    expect(staged.existsSync(), isFalse);
    // An odd extension cannot name a path.
    final odd = await store.newStagingFile('../../x');
    expect(p.dirname(odd.path), store.stagingDirectory.path);
    expect(p.extension(odd.path), '.img');
  });

  test('a damaged index is set aside and rebuilt, never deleted', () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'Kept', 'K');
    final dir = ImagePdfStore.accountDirectory(base, 'user-a');
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
    Map<String, Object?> record({String fileName = 'x.pdf', int pages = 1}) => {
          'id': 'x',
          'fileName': fileName,
          'name': 'n',
          'createdAt': '2026-10-18T00:00:00Z',
          'fileSize': 1,
          'pageCount': pages,
          'imageCount': 1,
        };
    expect(
        () => ImagePdfDocument.fromJson(record(fileName: '../../secret.pdf')),
        throwsFormatException);
    expect(() => ImagePdfDocument.fromJson('nope'), throwsFormatException);
    expect(() => ImagePdfDocument.fromJson(record(pages: 0)),
        throwsFormatException);
    expect(ImagePdfDocument.fromJson(record()).name, 'n');
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
        throwsA(isA<ImagePdfException>()
            .having((e) => e.kind, 'kind', ImagePdfFailure.nameInUse)));
    await expectLater(
        store.rename(b.id, '///'),
        throwsA(isA<ImagePdfException>()
            .having((e) => e.kind, 'kind', ImagePdfFailure.invalidName)));
    await expectLater(
        store.rename('missing', 'X'),
        throwsA(isA<ImagePdfException>()
            .having((e) => e.kind, 'kind', ImagePdfFailure.notFound)));
    final names = (await store.load()).documents.map((d) => d.name).toList()
      ..sort();
    expect(names, ['Two', 'عقد جديد']);
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
  });

  test('an interrupted delete is finished on the next load', () async {
    final store = storeFor('user-a');
    final doc = await save(store, 'One', 'A');
    final dir = ImagePdfStore.accountDirectory(base, 'user-a');
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
    final inputs = [for (var i = 0; i < 4; i++) await output('T$i')];
    final saved = await Future.wait([
      for (final (file, info) in inputs)
        store.add(
            source: file,
            name: 'Same',
            expected: info,
            pageCount: 2,
            imageCount: 2),
    ]);
    expect(saved.map((d) => d.name).toSet(), hasLength(4));
    expect((await store.load()).documents, hasLength(4));
  });

  test('two saves never overwrite each other\'s file', () async {
    final store = storeFor('user-a');
    final one = await save(store, 'Same', 'A', pages: 1);
    final two = await save(store, 'Same', 'B', pages: 3);
    expect(one.fileName, isNot(two.fileName));
    expect(analyzeImagePdf(store.fileOf(one).path).pageCount, 1);
    expect(analyzeImagePdf(store.fileOf(two).path).pageCount, 3);
  });
}
