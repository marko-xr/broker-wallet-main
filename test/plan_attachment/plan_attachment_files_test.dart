// The local, app-controlled copy of a plan: fetched through a fresh short-lived
// link, checked against its real bytes, kept under a name that carries the
// plan's stable media id, and never mistaken for a plan that was replaced.
// Pure: a fake transport and a temporary folder; no widgets, no network.

import 'dart:io';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_files.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_plan_transport.dart';
import 'plan_bytes.dart';

const _recordId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _mediaId = '11111111-1111-4111-8111-111111111111';
const _otherMediaId = '22222222-2222-4222-8222-222222222222';

final DateTime _now = DateTime.utc(2026, 10, 13, 12);

PlanAttachmentRef _ref({
  String id = _mediaId,
  PlanAttachmentKind kind = PlanAttachmentKind.pdf,
  String contentType = PlanContentTypes.pdf,
  String? url = 'https://read.example.test/get?sig=in-hand',
  DateTime? expiresAt,
}) =>
    PlanAttachmentRef(
      mediaObjectId: id,
      kind: kind,
      contentType: contentType,
      displayName: 'Plot 14 plan.pdf',
      byteLength: 256,
      signedUrl: url,
      signedUrlExpiresAt: url == null
          ? null
          : (expiresAt ?? _now.add(const Duration(minutes: 10))),
    );

/// A transport whose read answer carries no link at all.
class _NoLinkTransport extends FakePlanTransport {
  @override
  Future<PlanAttachmentRef?> fetchCurrent({
    required PlanParent parent,
    required String parentId,
  }) async {
    calls.add('fetch');
    return current?.withoutUrl();
  }
}

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
  late Directory cacheDir;
  late FakePlanTransport transport;
  late PlanAttachmentFiles files;

  PlanAttachmentFiles filesFor(FakePlanTransport t) => PlanAttachmentFiles(
        transport: t,
        cache: PlanAttachmentCache(directory: () async => cacheDir),
        now: () => _now,
      );

  List<String> held() => cacheDir.existsSync()
      ? (cacheDir
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toList()
        ..sort())
      : <String>[];

  setUp(() {
    area = PlanTempDir();
    cacheDir =
        Directory('${area.path}${Platform.pathSeparator}plan_attachments');
    transport = FakePlanTransport()..downloadBytes = planPdfBytes(900);
    files = filesFor(transport);
  });
  tearDown(() => area.dispose());

  group('downloading a plan', () {
    test('fetches it through the link in hand and keeps a verified copy',
        () async {
      final file = await files.ensureLocal(
        parent: PlanParent.offer,
        parentId: _recordId,
        ref: _ref(),
      );

      expect(transport.calls, ['download'],
          reason: 'a link still good needs no new read');
      expect(transport.downloadedUrls,
          ['https://read.example.test/get?sig=in-hand']);
      expect(file.readAsBytesSync(), planPdfBytes(900));
      expect(file.uri.pathSegments.last, 'offer_${_recordId}_$_mediaId.pdf',
          reason: 'named by record kind, record id and the plan\'s media id');
      expect(held(), ['offer_${_recordId}_$_mediaId.pdf'],
          reason: 'no partial download is left beside it');
    });

    test('a second look uses the copy held on this phone, with no network',
        () async {
      await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: _ref());
      transport.calls.clear();

      final again = await files.ensureLocal(
        parent: PlanParent.offer,
        parentId: _recordId,
        ref: _ref(url: null),
      );
      expect(again.existsSync(), isTrue);
      expect(transport.calls, isEmpty);
    });

    test('a link that has expired is replaced by a fresh read first', () async {
      transport.current = _ref().withoutUrl();
      final stale = _ref(expiresAt: _now.subtract(const Duration(minutes: 1)));

      await files.ensureLocal(
          parent: PlanParent.owner, parentId: _recordId, ref: stale);

      expect(transport.calls, ['fetch', 'download']);
      expect(transport.downloadedUrls.single,
          contains('read.example.test/get?sig=secret-get'),
          reason: 'the new link is used, not the expired one');
      expect(transport.downloadedUrls.single, isNot(contains('in-hand')));
    });

    test('a link about to expire counts as expired', () async {
      transport.current = _ref().withoutUrl();
      final nearly = _ref(expiresAt: _now.add(const Duration(seconds: 10)));
      await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: nearly);
      expect(transport.calls, ['fetch', 'download']);
    });

    test('never asks for more bytes than the kind allows', () async {
      await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: _ref());
      expect(transport.downloadLimits.single,
          PlanAttachmentPolicy.maxDocumentBytes);

      transport.downloadBytes = planJpegBytes(900);
      await files.ensureLocal(
        parent: PlanParent.offer,
        parentId: _recordId,
        ref: _ref(
          id: _otherMediaId,
          kind: PlanAttachmentKind.image,
          contentType: PlanContentTypes.jpeg,
        ),
      );
      expect(transport.downloadLimits.last, PlanAttachmentPolicy.maxImageBytes);
    });

    test('a Word document keeps its own extension', () async {
      transport.downloadBytes = planDocxBytes(900);
      final docx = await files.ensureLocal(
        parent: PlanParent.offer,
        parentId: _recordId,
        ref: _ref(
          kind: PlanAttachmentKind.word,
          contentType: PlanContentTypes.docx,
        ),
      );
      expect(docx.path, endsWith('.docx'));

      transport.downloadBytes = planDocBytes(900);
      final doc = await files.ensureLocal(
        parent: PlanParent.offer,
        parentId: _recordId,
        ref: _ref(
          id: _otherMediaId,
          kind: PlanAttachmentKind.word,
          contentType: PlanContentTypes.doc,
        ),
      );
      expect(doc.path, endsWith('.doc'));
    });
  });

  group('a plan that is not what was stored', () {
    test('bytes of another type are refused and leave nothing behind',
        () async {
      transport.downloadBytes = planPngBytes(900);
      final error = await _caught(() => files.ensureLocal(
            parent: PlanParent.offer,
            parentId: _recordId,
            ref: _ref(),
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.typeMismatch);
      expect(held(), isEmpty);
    });

    test('a Word file of the other generation is not the stored plan',
        () async {
      transport.downloadBytes = planDocBytes(900);
      final error = await _caught(() => files.ensureLocal(
            parent: PlanParent.offer,
            parentId: _recordId,
            ref: _ref(
              kind: PlanAttachmentKind.word,
              contentType: PlanContentTypes.docx,
            ),
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.typeMismatch);
      expect(held(), isEmpty);
    });

    test('an empty or unrecognizable download is refused', () async {
      for (final bytes in <List<int>>[
        <int>[],
        <int>[...'<html>'.codeUnits]
      ]) {
        transport.downloadBytes = bytes;
        final error = await _caught(() => files.ensureLocal(
              parent: PlanParent.offer,
              parentId: _recordId,
              ref: _ref(),
            ));
        expect((error! as PlanAttachmentException).failure,
            PlanAttachmentFailure.typeMismatch);
        expect(held(), isEmpty);
      }
    });

    test('a held copy that no longer matches is discarded and fetched again',
        () async {
      final first = await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: _ref());
      // The copy is damaged on disk.
      first.writeAsBytesSync(<int>[...'garbage'.codeUnits]);
      transport.calls.clear();

      final repaired = await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: _ref());

      expect(transport.calls, ['download']);
      expect(repaired.readAsBytesSync(), planPdfBytes(900));
      expect(held(), ['offer_${_recordId}_$_mediaId.pdf']);
    });

    test('a download that fails leaves no copy', () async {
      transport.downloadError =
          const PlanAttachmentException(PlanAttachmentFailure.interrupted);
      final error = await _caught(() => files.ensureLocal(
            parent: PlanParent.offer,
            parentId: _recordId,
            ref: _ref(),
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.interrupted);
      expect(held(), isEmpty);
    });
  });

  group('a plan that changed elsewhere', () {
    test('is reported as stale when the record now holds another plan',
        () async {
      transport.current = _ref(id: _otherMediaId).withoutUrl();
      final error = await _caught(() => files.ensureLocal(
            parent: PlanParent.offer,
            parentId: _recordId,
            ref: _ref(expiresAt: _now.subtract(const Duration(minutes: 1))),
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.staleReplacement);
      expect(transport.calls, ['fetch'], reason: 'nothing is downloaded');
      expect(held(), isEmpty);
    });

    test('is reported as stale when the plan was removed', () async {
      transport.current = null;
      final error = await _caught(() => files.ensureLocal(
            parent: PlanParent.offer,
            parentId: _recordId,
            ref: _ref(url: null),
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.staleReplacement);
      expect(transport.calls, ['fetch']);
    });

    test('an answer without any link is not usable', () async {
      final bare = _NoLinkTransport()..current = _ref().withoutUrl();
      final error = await _caught(() => filesFor(bare).ensureLocal(
            parent: PlanParent.offer,
            parentId: _recordId,
            ref: _ref(url: null),
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.invalidResponse);
      expect(bare.calls, ['fetch'], reason: 'nothing is downloaded');
    });

    test('a replaced plan\'s copy is removed once the new one is held',
        () async {
      await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: _ref());
      expect(held(), hasLength(1));

      transport.downloadBytes = planDocxBytes(900);
      await files.ensureLocal(
        parent: PlanParent.offer,
        parentId: _recordId,
        ref: _ref(
          id: _otherMediaId,
          kind: PlanAttachmentKind.word,
          contentType: PlanContentTypes.docx,
        ),
      );
      expect(held(), ['offer_${_recordId}_$_otherMediaId.docx'],
          reason: 'the old plan\'s copy is gone');
    });
  });

  group('copies of different records', () {
    test('an Offer\'s plan and an Owner\'s plan never share a file', () async {
      await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: _ref());
      await files.ensureLocal(
          parent: PlanParent.owner, parentId: _recordId, ref: _ref());
      expect(held(), [
        'offer_${_recordId}_$_mediaId.pdf',
        'owner_${_recordId}_$_mediaId.pdf',
      ]);
    });

    test('replacing one record\'s plan leaves other records\' copies alone',
        () async {
      const otherRecord = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      await files.ensureLocal(
          parent: PlanParent.offer, parentId: otherRecord, ref: _ref());
      await files.ensureLocal(
          parent: PlanParent.offer, parentId: _recordId, ref: _ref());

      transport.downloadBytes = planPngBytes(900);
      await files.ensureLocal(
        parent: PlanParent.offer,
        parentId: _recordId,
        ref: _ref(
          id: _otherMediaId,
          kind: PlanAttachmentKind.image,
          contentType: PlanContentTypes.png,
        ),
      );
      expect(
        held(),
        unorderedEquals(<String>[
          'offer_${otherRecord}_$_mediaId.pdf',
          'offer_${_recordId}_$_otherMediaId.png',
        ]),
        reason: 'only this record\'s old copy was removed',
      );
    });
  });

  group('PlanAttachmentCache', () {
    PlanAttachmentCache cache() =>
        PlanAttachmentCache(directory: () async => cacheDir);

    test('names a copy by record kind, record id, media id and type', () async {
      final file = await cache().fileFor(
        PlanParent.owner,
        _recordId,
        _ref(
          kind: PlanAttachmentKind.image,
          contentType: PlanContentTypes.webp,
        ),
      );
      expect(file.uri.pathSegments.last, 'owner_${_recordId}_$_mediaId.webp');
      expect(cacheDir.existsSync(), isTrue, reason: 'the folder is created');
      expect(file.existsSync(), isFalse, reason: 'a name only, not a file');
    });

    test('knows the copy it holds and only that one', () async {
      final c = cache();
      expect(await c.existing(PlanParent.offer, _recordId, _ref()), isNull);
      final file = await c.fileFor(PlanParent.offer, _recordId, _ref());
      file.writeAsBytesSync(planPdfBytes());
      expect(await c.existing(PlanParent.offer, _recordId, _ref()), isNotNull);
      expect(
          await c.existing(
              PlanParent.offer, _recordId, _ref(id: _otherMediaId)),
          isNull,
          reason: 'a different media id is a different plan');
    });

    test('removeOthers keeps only the named copy of the named record',
        () async {
      final c = cache();
      final keep = await c.fileFor(PlanParent.offer, _recordId, _ref());
      final drop =
          await c.fileFor(PlanParent.offer, _recordId, _ref(id: _otherMediaId));
      final foreign = await c.fileFor(PlanParent.owner, _recordId, _ref());
      for (final file in [keep, drop, foreign]) {
        file.writeAsBytesSync(planPdfBytes());
      }

      await c.removeOthers(PlanParent.offer, _recordId, keepMediaId: _mediaId);
      expect(keep.existsSync(), isTrue);
      expect(drop.existsSync(), isFalse);
      expect(foreign.existsSync(), isTrue, reason: 'another record kind');

      await c.removeOthers(PlanParent.offer, _recordId);
      expect(keep.existsSync(), isFalse, reason: 'no keeper named: all go');
      expect(foreign.existsSync(), isTrue);
    });

    test('removeOthers on a folder that does not exist is a quiet no-op',
        () async {
      await cache().removeOthers(PlanParent.offer, _recordId);
      expect(cacheDir.existsSync(), isFalse);
    });
  });
}
