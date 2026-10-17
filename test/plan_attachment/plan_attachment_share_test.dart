// Sharing a plan: the plan's verified local file goes through the app's one
// share preparer. A document's real type is proven from its bytes; it takes a
// professional name and never its cache name, a link or an id; and nothing that
// is not an accepted plan type can be shared as one. Pure: no widgets.

import 'dart:io';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_bytes.dart';

const _cacheName =
    'offer_aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa_11111111-1111-4111-8111-111111111111';

Future<Object?> _caught(Future<void> Function() body) async {
  try {
    await body();
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  late PlanTempDir area;

  setUp(() => area = PlanTempDir());
  tearDown(() => area.dispose());

  SharePreparer preparer() => SharePreparer(
        stagingRoot: () async =>
            Directory('${area.path}${Platform.pathSeparator}staging'),
      );

  ShareAttachment attachment(
    File file, {
    ShareAttachmentKind kind = ShareAttachmentKind.document,
    String baseName = 'Plot-14-plan',
    String key = 'plan',
  }) =>
      ShareAttachment(
        key: key,
        kind: kind,
        baseName: baseName,
        fetch: (scratch, cancel) async => FetchedShareFile(file),
      );

  Future<ShareBundle> prepare(ShareAttachment item) =>
      preparer().prepare(<ShareAttachment>[item], ShareCancelToken());

  Future<ShareFailure> failureOf(ShareAttachment item) async {
    final error = await _caught(() => prepare(item));
    expect(error, isA<ShareFailure>());
    return error! as ShareFailure;
  }

  group('a document plan', () {
    test('is shared as the file it is, named by what its bytes prove',
        () async {
      final cases = <String, List<Object>>{
        'pdf': <Object>[planPdfBytes(900), PlanContentTypes.pdf],
        'doc': <Object>[planDocBytes(900), PlanContentTypes.doc],
        'docx': <Object>[planDocxBytes(900), PlanContentTypes.docx],
      };
      for (final entry in cases.entries) {
        final cached =
            area.write('$_cacheName.${entry.key}', entry.value[0] as List<int>);
        final bundle = await prepare(attachment(cached));
        final file = bundle.files.single;
        expect(file.name, 'Plot-14-plan.${entry.key}');
        expect(file.mimeType, entry.value[1]);
        expect(File(file.path).readAsBytesSync(), entry.value[0]);
        expect(cached.existsSync(), isTrue,
            reason: 'the plan\'s cached copy is copied, never moved');
        await bundle.discard();
      }
    });

    test('keeps no trace of its cache name, record id or media id', () async {
      final cached = area.write('$_cacheName.docx', planDocxBytes());
      final bundle = await prepare(attachment(cached));
      final file = bundle.files.single;
      expect(file.name, isNot(contains('offer_')));
      expect(file.path, isNot(contains('aaaaaaaa')));
      expect(file.path, isNot(contains('11111111')));
    });

    test('the extension follows the bytes, not the old name', () async {
      final wrongName = area.write('$_cacheName.pdf', planDocxBytes());
      final bundle = await prepare(attachment(wrongName));
      expect(bundle.files.single.name, 'Plot-14-plan.docx');
      expect(bundle.files.single.mimeType, PlanContentTypes.docx);
      await bundle.discard();

      final noName = area.write('plan.bin', planDocBytes());
      final second = await prepare(attachment(noName));
      expect(second.files.single.name, 'Plot-14-plan.doc');
      await second.discard();
    });

    test('a PDF plan also goes through the app\'s existing PDF kind', () async {
      final cached = area.write('$_cacheName.pdf', planPdfBytes());
      final bundle =
          await prepare(attachment(cached, kind: ShareAttachmentKind.pdf));
      expect(bundle.files.single.name, 'Plot-14-plan.pdf');
      expect(bundle.files.single.mimeType, PlanContentTypes.pdf);
    });

    test('a name cannot reach outside the share\'s folder', () async {
      final cached = area.write('$_cacheName.pdf', planPdfBytes());
      for (final hostile in <String>[
        '../../evil/plan',
        r'..\..\evil',
        '/etc/passwd',
        '',
        '   ',
      ]) {
        final bundle = await prepare(attachment(cached, baseName: hostile));
        final file = File(bundle.files.single.path);
        expect(file.parent.path, bundle.directory.path, reason: hostile);
        expect(bundle.files.single.name, endsWith('.pdf'));
        expect(bundle.files.single.name.contains('/'), isFalse);
        expect(bundle.files.single.name.contains(r'\'), isFalse);
        expect(bundle.files.single.name.contains('..'), isFalse);
        await bundle.discard();
      }
    });
  });

  group('what is not an accepted document is never shared as one', () {
    final refused = <String, List<int>>{
      'a JPEG photo': planJpegBytes(),
      'a PNG photo': planPngBytes(),
      'a program': <int>[0x4d, 0x5a, ...List<int>.filled(200, 0)],
      'plain text': <int>[...'just some text'.codeUnits],
      'an SVG': <int>[...'<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits],
      'a web page': <int>[...'<!doctype html><html></html>'.codeUnits],
      'an archive that is not an Office package': planZipBytes('notes.txt'),
      'an encrypted Office package':
          planZipBytes('[Content_Types].xml', flags: 1),
      'a PDF with an unknown version': <int>[...'%PDF-3.0\n'.codeUnits, 7, 7],
    };

    for (final entry in refused.entries) {
      test(entry.key, () async {
        final file = area.write('$_cacheName.docx', entry.value);
        final failure = await failureOf(attachment(file));
        expect(failure.kind, ShareFailureKind.unavailable);
        expect(failure.failedKeys, ['plan']);
        final staging =
            Directory('${area.path}${Platform.pathSeparator}staging');
        expect(staging.listSync(), isEmpty,
            reason: 'nothing is left behind by a refused share');
      });
    }

    test('an empty or missing file is unavailable', () async {
      final empty = area.write('empty.docx', <int>[]);
      expect((await failureOf(attachment(empty))).kind,
          ShareFailureKind.unavailable);
      final missing = File('${area.path}${Platform.pathSeparator}gone.docx');
      expect((await failureOf(attachment(missing))).kind,
          ShareFailureKind.unavailable);
    });
  });

  group('an image plan', () {
    test('is shared as a photo, named by its real format', () async {
      final cases = <String, List<Object>>{
        'jpg': <Object>[planJpegBytes(), 'image/jpeg'],
        'png': <Object>[planPngBytes(), 'image/png'],
      };
      for (final entry in cases.entries) {
        final cached =
            area.write('$_cacheName.bin', entry.value[0] as List<int>);
        final bundle =
            await prepare(attachment(cached, kind: ShareAttachmentKind.image));
        expect(bundle.files.single.name, 'Plot-14-plan.${entry.key}');
        expect(bundle.files.single.mimeType, entry.value[1]);
        await bundle.discard();
      }
    });

    test('a document is not shared as a photo', () async {
      // A plan's cached copy carries the extension of its verified type, so a
      // document never has a photo name; the bytes then decide.
      for (final entry in <String, List<int>>{
        'pdf': planPdfBytes(),
        'doc': planDocBytes(),
        'docx': planDocxBytes(),
      }.entries) {
        final cached = area.write('$_cacheName.${entry.key}', entry.value);
        final failure = await failureOf(
            attachment(cached, kind: ShareAttachmentKind.image));
        expect(failure.kind, ShareFailureKind.unavailable, reason: entry.key);
      }
    });
  });
}
