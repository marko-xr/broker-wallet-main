// What may be a land / plot plan: decided from a file's own bytes, with the
// gallery's image contract reused, a 25 MiB document limit, and the same type
// table as the Media Worker and the database. Pure: no widgets, no network.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mib = 1024 * 1024;

List<int> _pad(List<int> head, [int length = 64]) => [
      ...head,
      ...List<int>.filled(length > head.length ? length - head.length : 0, 0),
    ];

/// The start of a ZIP local file header whose first entry is [firstEntry].
List<int> _zip(String firstEntry, {int flags = 0}) {
  final name = utf8.encode(firstEntry);
  final out = List<int>.filled(30 + name.length + 16, 0);
  out.setRange(0, 4, [0x50, 0x4b, 0x03, 0x04]);
  out[6] = flags;
  out[26] = name.length & 0xff;
  out[27] = name.length >> 8;
  out.setRange(30, 30 + name.length, name);
  return out;
}

final List<int> _jpeg = _pad([0xff, 0xd8, 0xff]);
final List<int> _png = _pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
final List<int> _webp =
    _pad([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
final List<int> _pdf = utf8.encode('%PDF-1.7\n1 0 obj\n%%EOF');
final List<int> _doc = _pad([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
final List<int> _docx = _zip('[Content_Types].xml');

Future<File> _file(
  String name,
  List<int> bytes, {
  int? length,
}) async {
  final dir = await Directory.systemTemp.createTemp('plan_policy_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  if (length != null && length > bytes.length) {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.truncate(length);
    } finally {
      await handle.close();
    }
  }
  return file;
}

void main() {
  group('detectContentType', () {
    test('recognizes every accepted plan type from its leading bytes', () {
      expect(
          PlanAttachmentPolicy.detectContentType(_jpeg), PlanContentTypes.jpeg);
      expect(
          PlanAttachmentPolicy.detectContentType(_png), PlanContentTypes.png);
      expect(
          PlanAttachmentPolicy.detectContentType(_webp), PlanContentTypes.webp);
      expect(
          PlanAttachmentPolicy.detectContentType(_pdf), PlanContentTypes.pdf);
      expect(
          PlanAttachmentPolicy.detectContentType(_doc), PlanContentTypes.doc);
      expect(
          PlanAttachmentPolicy.detectContentType(_docx), PlanContentTypes.docx);
    });

    test('a PDF is %PDF- followed by a 1.x or 2.x version', () {
      expect(PlanAttachmentPolicy.detectContentType(utf8.encode('%PDF-2.0\n')),
          PlanContentTypes.pdf);
      expect(PlanAttachmentPolicy.detectContentType(utf8.encode('%PDF-1.4\n')),
          PlanContentTypes.pdf);
      expect(PlanAttachmentPolicy.detectContentType(utf8.encode('%PDF-3.0\n')),
          isNull);
      expect(PlanAttachmentPolicy.detectContentType(utf8.encode('%PDF-1.x\n')),
          isNull);
      expect(
          PlanAttachmentPolicy.detectContentType(utf8.encode('%PDF')), isNull);
      expect(PlanAttachmentPolicy.detectContentType(utf8.encode(' %PDF-1.4\n')),
          isNull);
    });

    test(
        'an Office Open XML package is a ZIP whose first entry is an Office part',
        () {
      for (final entry in const [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'docProps/core.xml',
      ]) {
        expect(PlanAttachmentPolicy.detectContentType(_zip(entry)),
            PlanContentTypes.docx,
            reason: entry);
      }
    });

    test('other ZIP containers, archives and encrypted packages are refused',
        () {
      for (final entry in const [
        'AndroidManifest.xml',
        'META-INF/MANIFEST.MF',
        'notes.txt',
        'xl/workbook.xml',
        'ppt/presentation.xml',
      ]) {
        expect(PlanAttachmentPolicy.detectContentType(_zip(entry)), isNull,
            reason: entry);
      }
      expect(
          PlanAttachmentPolicy.detectContentType(
              _zip('[Content_Types].xml', flags: 1)),
          isNull,
          reason: 'an encrypted first entry');
      expect(PlanAttachmentPolicy.detectContentType(_zip('')), isNull);
      // A RAR archive, a 7-Zip archive and an empty ZIP.
      expect(
          PlanAttachmentPolicy.detectContentType(
              _pad([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00])),
          isNull);
      expect(
          PlanAttachmentPolicy.detectContentType(
              _pad([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c])),
          isNull);
      expect(
          PlanAttachmentPolicy.detectContentType(
              _pad([0x50, 0x4b, 0x05, 0x06])),
          isNull);
    });

    test('executables, scripts, SVG, GIF, HEIC and video are not plans', () {
      final refused = <String, List<int>>{
        'a Windows executable': _pad([0x4d, 0x5a]),
        'an ELF binary': _pad([0x7f, 0x45, 0x4c, 0x46]),
        'a shell script': utf8.encode('#!/bin/sh\nrm -rf /\n'),
        'an SVG': utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
        'an HTML page': utf8.encode('<!doctype html><html></html>'),
        'a GIF': utf8.encode('GIF89a......'),
        'a CAD drawing': utf8.encode('AC1027.....'),
        'a HEIC photo': _pad(
            [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]),
        'an MP4 video': _pad(
            [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d]),
        'nothing': <int>[],
        'one byte': <int>[0xff],
      };
      refused.forEach((label, bytes) {
        expect(PlanAttachmentPolicy.detectContentType(bytes), isNull,
            reason: label);
      });
    });
  });

  group('check', () {
    test('accepts every plan type with its kind and size', () async {
      final cases = <String, (List<int>, String, PlanAttachmentKind)>{
        'plan.jpg': (_jpeg, PlanContentTypes.jpeg, PlanAttachmentKind.image),
        'plan.png': (_png, PlanContentTypes.png, PlanAttachmentKind.image),
        'plan.webp': (_webp, PlanContentTypes.webp, PlanAttachmentKind.image),
        'plan.pdf': (_pdf, PlanContentTypes.pdf, PlanAttachmentKind.pdf),
        'plan.doc': (_doc, PlanContentTypes.doc, PlanAttachmentKind.word),
        'plan.docx': (_docx, PlanContentTypes.docx, PlanAttachmentKind.word),
      };
      for (final entry in cases.entries) {
        final (bytes, contentType, kind) = entry.value;
        final check =
            await PlanAttachmentPolicy.check(await _file(entry.key, bytes));
        expect(check.isAccepted, isTrue, reason: entry.key);
        expect(check.contentType, contentType, reason: entry.key);
        expect(check.kind, kind, reason: entry.key);
        expect(check.length, bytes.length, reason: entry.key);
      }
    });

    test('the bytes decide, not the name: images accept any name', () async {
      for (final name in const [
        'photo.jfif',
        'scan',
        'IMG_0001.JPG',
        'a.bin'
      ]) {
        final check =
            await PlanAttachmentPolicy.check(await _file(name, _jpeg));
        expect(check.isAccepted, isTrue, reason: name);
        expect(check.contentType, PlanContentTypes.jpeg, reason: name);
      }
    });

    test('a document whose name says it is something else is refused',
        () async {
      // A spreadsheet or archive that shares a Word container's bytes.
      for (final name in const [
        'budget.xlsx',
        'deck.pptx',
        'plans.zip',
        'app.apk',
        'plan.docx.exe',
      ]) {
        final check =
            await PlanAttachmentPolicy.check(await _file(name, _docx));
        expect(check.rejection, PlanAttachmentRejection.unsupportedType,
            reason: name);
      }
      // A PDF or a Word file under a name of another document family.
      expect(
          (await PlanAttachmentPolicy.check(await _file('plan.docx', _pdf)))
              .rejection,
          PlanAttachmentRejection.unsupportedType);
      expect(
          (await PlanAttachmentPolicy.check(await _file('plan.pdf', _docx)))
              .rejection,
          PlanAttachmentRejection.unsupportedType);
      expect(
          (await PlanAttachmentPolicy.check(await _file('plan.exe', _pdf)))
              .rejection,
          PlanAttachmentRejection.unsupportedType);
      // A legacy .doc saved under a .docx name (it happens) and the reverse are fine.
      expect(
          (await PlanAttachmentPolicy.check(await _file('plan.docx', _doc)))
              .isAccepted,
          isTrue);
      expect(
          (await PlanAttachmentPolicy.check(await _file('plan.doc', _docx)))
              .isAccepted,
          isTrue);
      // A document with no extension at all is decided by its bytes.
      expect(
          (await PlanAttachmentPolicy.check(await _file('plan', _pdf)))
              .isAccepted,
          isTrue);
    });

    test('refuses what is not a plan, whatever its name says', () async {
      for (final (name, bytes) in <(String, List<int>)>[
        ('plan.pdf', _pad([0x4d, 0x5a])),
        ('plan.jpg', utf8.encode('<svg/>')),
        ('plan.png', utf8.encode('GIF89a......')),
        (
          'plan.mp4',
          _pad([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d])
        ),
        ('plan.dwg', utf8.encode('AC1027.....')),
      ]) {
        final check =
            await PlanAttachmentPolicy.check(await _file(name, bytes));
        expect(check.rejection, PlanAttachmentRejection.unsupportedType,
            reason: name);
      }
    });

    test('enforces the size limits exactly: images 10 MiB, documents 25 MiB',
        () async {
      expect(
          (await PlanAttachmentPolicy.check(
                  await _file('a.jpg', _jpeg, length: 10 * _mib)))
              .isAccepted,
          isTrue);
      expect(
          (await PlanAttachmentPolicy.check(
                  await _file('b.jpg', _jpeg, length: 10 * _mib + 1)))
              .rejection,
          PlanAttachmentRejection.imageTooLarge);
      expect(
          (await PlanAttachmentPolicy.check(
                  await _file('c.pdf', _pdf, length: 25 * _mib)))
              .isAccepted,
          isTrue);
      expect(
          (await PlanAttachmentPolicy.check(
                  await _file('d.pdf', _pdf, length: 25 * _mib + 1)))
              .rejection,
          PlanAttachmentRejection.documentTooLarge);
      expect(
          (await PlanAttachmentPolicy.check(
                  await _file('e.docx', _docx, length: 25 * _mib)))
              .isAccepted,
          isTrue);
      expect(
          (await PlanAttachmentPolicy.check(
                  await _file('f.doc', _doc, length: 25 * _mib + 1)))
              .rejection,
          PlanAttachmentRejection.documentTooLarge);
    });

    test('an empty or missing file is unreadable', () async {
      expect(
          (await PlanAttachmentPolicy.check(await _file('empty.pdf', <int>[])))
              .rejection,
          PlanAttachmentRejection.unreadable);
      final dir = await Directory.systemTemp.createTemp('plan_policy_missing_');
      addTearDown(() => dir.delete(recursive: true));
      final missing = File('${dir.path}${Platform.pathSeparator}gone.pdf');
      expect((await PlanAttachmentPolicy.check(missing)).rejection,
          PlanAttachmentRejection.unreadable);
    });
  });

  group('the one image contract', () {
    test('the plan reuses the gallery\'s image limit and header length', () {
      expect(
          PlanAttachmentPolicy.maxImageBytes, OfferMediaPolicy.maxImageBytes);
      expect(PlanAttachmentPolicy.headerBytes, OfferMediaPolicy.headerBytes);
      expect(PlanAttachmentPolicy.maxDocumentBytes, 25 * _mib);
      expect(PlanAttachmentPolicy.maxBytesFor(PlanAttachmentKind.image),
          10 * _mib);
      for (final kind in [PlanAttachmentKind.pdf, PlanAttachmentKind.word]) {
        expect(PlanAttachmentPolicy.maxBytesFor(kind), 25 * _mib);
      }
    });

    test('every image type the plan accepts is one the gallery accepts', () {
      for (final type in PlanContentTypes.images) {
        expect(OfferMediaPolicy.contentTypes.containsKey(type), isTrue,
            reason: type);
      }
      // ...and a plan never accepts a video the gallery does.
      expect(PlanContentTypes.all.contains('video/mp4'), isFalse);
      expect(PlanContentTypes.all.contains('image/heic'), isFalse);
    });
  });

  group('names and kinds', () {
    test('extensionOf reads the last extension, lower-cased', () {
      expect(PlanAttachmentPolicy.extensionOf('/a/b/Plan.PDF'), 'pdf');
      expect(
          PlanAttachmentPolicy.extensionOf(r'C:\a\b\plan.final.DOCX'), 'docx');
      expect(PlanAttachmentPolicy.extensionOf('/a/b/plan'), '');
      expect(PlanAttachmentPolicy.extensionOf('/a/b/.hidden'), '');
      expect(PlanAttachmentPolicy.extensionOf('/a/b/plan.'), '');
    });

    test('each content type has one kind and one stored extension', () {
      expect(PlanAttachmentKind.fromContentType(PlanContentTypes.jpeg),
          PlanAttachmentKind.image);
      expect(PlanAttachmentKind.fromContentType(PlanContentTypes.pdf),
          PlanAttachmentKind.pdf);
      expect(PlanAttachmentKind.fromContentType(PlanContentTypes.doc),
          PlanAttachmentKind.word);
      expect(PlanAttachmentKind.fromContentType(PlanContentTypes.docx),
          PlanAttachmentKind.word);
      expect(PlanAttachmentKind.fromContentType('image/gif'), isNull);
      expect(PlanAttachmentKind.fromContentType(null), isNull);
      expect(PlanContentTypes.extensionOf(PlanContentTypes.docx), 'docx');
      expect(PlanContentTypes.extensionOf(PlanContentTypes.jpeg), 'jpg');
      expect(PlanContentTypes.extensionOf('application/zip'), isNull);
      for (final type in PlanContentTypes.all) {
        expect(PlanAttachmentKind.fromContentType(type), isNotNull,
            reason: type);
        expect(PlanContentTypes.extensionOf(type), isNotNull, reason: type);
      }
      expect(PlanAttachmentKind.image.isDocument, isFalse);
      expect(PlanAttachmentKind.pdf.isDocument, isTrue);
      expect(PlanAttachmentKind.word.isDocument, isTrue);
    });
  });

  group('one contract with the Worker and the database', () {
    // Read by relative path (the tests run from the repository root): a change
    // on one side that is not made on the other fails here.
    test('the Worker accepts exactly the types and limits the app does', () {
      final worker = File('cloudflare/workers/r2-profile-upload/worker.js')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(
          worker.contains('const MAX_PLAN_DOCUMENT_BYTES = 25 * 1024 * 1024;'),
          isTrue);
      expect(
          worker.contains(
              "const DOCX_CONTENT_TYPE = '${PlanContentTypes.docx}';"),
          isTrue);
      final table = RegExp(
              r'const PLAN_MEDIA_TYPES = Object\.freeze\(\{([\s\S]*?)\n\}\);')
          .firstMatch(worker)!
          .group(1)!;
      final types = <String>{
        for (final m in RegExp(r"^\s*'([a-z]+/[a-z0-9.+-]+)':", multiLine: true)
            .allMatches(table))
          m.group(1)!,
        if (table.contains('[DOCX_CONTENT_TYPE]')) PlanContentTypes.docx,
      };
      expect(types, PlanContentTypes.all);
    });

    test('the database accepts exactly the same types and limits', () {
      final sql = File(
              'supabase/migrations/20261012233000_offer_owner_plan_attachments.sql')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final rules = RegExp(
              r"\('([a-z]+/[a-z0-9.+-]+)'::text,\s*'([a-z]+)'::text,\s*'([a-z]+)'::text,\s*(\d+)::bigint\)")
          .allMatches(sql)
          .toList();
      final byType = {
        for (final m in rules)
          m.group(1)!: (m.group(2)!, int.parse(m.group(4)!)),
      };
      expect(byType.keys.toSet(), PlanContentTypes.all);
      for (final entry in byType.entries) {
        final (extension, cap) = entry.value;
        expect(PlanContentTypes.extensionOf(entry.key), extension,
            reason: entry.key);
        final kind = PlanAttachmentKind.fromContentType(entry.key)!;
        expect(cap, PlanAttachmentPolicy.maxBytesFor(kind), reason: entry.key);
      }
    });

    test(
        'the Worker proves a DOC or DOCX is Word\'s own before it attaches one; '
        'the app\'s own check is only a first look', () {
      final worker = File('cloudflare/workers/r2-profile-upload/worker.js')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final confirm = worker.substring(
        worker.indexOf('async function handlePlanConfirm('),
        worker.indexOf('async function handlePlanGet('),
      );
      final container = confirm.indexOf('detectPlanMimeFromBytes(');
      final proof = confirm.indexOf('proveWordDocument(env.MEDIA_BUCKET');
      final attach = confirm.indexOf('plan.confirmRpc');
      expect(container, greaterThan(-1));
      expect(proof, greaterThan(container),
          reason: 'after the container is recognized');
      expect(attach, greaterThan(proof), reason: 'before anything is attached');

      // What it proves: a WordprocessingML main part, or Word's own stream.
      expect(
          worker.contains(
              "const WORD_MAIN_CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';"),
          isTrue);
      expect(worker.contains("names.get('WORDDOCUMENT')?.type === 2"), isTrue);
      // The type compared is the one the package gives the main part: its own
      // Override, else the Default for its extension (as the packaging format
      // defines it, and as .NET's packaging library writes a Word document).
      expect(
          worker.contains(
              'partContentType(contentTypes, main) === WORD_MAIN_CONTENT_TYPE'),
          isTrue);
      // Only for those two types: an image or a PDF is read as it always was.
      expect(
          worker.contains(
              "if (!isDocx && contentType !== 'application/msword') return true;"),
          isTrue);
    });
  });
}
