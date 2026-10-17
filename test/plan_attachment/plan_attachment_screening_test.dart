// Screening a picked file before anything is sent: what it really is (from its
// bytes), whether it fits, the draft's one-time identity, and the HEIC → JPEG
// conversion that keeps a plan image independent of platform HEIF support.
// Pure: no widgets, no network.

import 'dart:io';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_policy.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_screening.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_bytes.dart';

const int _mib = 1024 * 1024;

final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  late PlanTempDir area;

  setUp(() => area = PlanTempDir());
  tearDown(() => area.dispose());

  /// Grows [file] to [length] bytes without writing them all.
  Future<void> growTo(File file, int length) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.truncate(length);
    } finally {
      await handle.close();
    }
  }

  group('an accepted file', () {
    test('becomes a draft that knows its kind, type, size and name', () async {
      final cases = <String, List<Object>>{
        'plan.pdf': <Object>[
          planPdfBytes(900),
          PlanContentTypes.pdf,
          PlanAttachmentKind.pdf,
        ],
        'plan.doc': <Object>[
          planDocBytes(900),
          PlanContentTypes.doc,
          PlanAttachmentKind.word,
        ],
        'plan.docx': <Object>[
          planDocxBytes(900),
          PlanContentTypes.docx,
          PlanAttachmentKind.word,
        ],
        'plan.jpg': <Object>[
          planJpegBytes(900),
          PlanContentTypes.jpeg,
          PlanAttachmentKind.image,
        ],
        'plan.png': <Object>[
          planPngBytes(900),
          PlanContentTypes.png,
          PlanAttachmentKind.image,
        ],
      };
      for (final entry in cases.entries) {
        final file = area.write(entry.key, entry.value[0] as List<int>);
        final result = await screenPlanFile(
          file,
          displayName: entry.key,
          newMediaObjectId: () => 'id-${entry.key}',
        );
        expect(result.isAccepted, isTrue, reason: entry.key);
        final draft = result.draft!;
        expect(draft.contentType, entry.value[1], reason: entry.key);
        expect(draft.kind, entry.value[2], reason: entry.key);
        expect(draft.byteLength, (entry.value[0] as List<int>).length);
        expect(draft.displayName, entry.key);
        expect(draft.mediaObjectId, 'id-${entry.key}');
        expect(draft.path, file.path,
            reason: 'the picked file itself is uploaded, never a copy');
        expect(draft.ownedTempPath, isNull,
            reason: 'nothing was made by the app, so nothing is deleted later');
        expect(result.rejection, isNull);
      }
    });

    test('keeps the user\'s file name, trimmed, and none when it is blank',
        () async {
      final file = area.write('picked.pdf', planPdfBytes());
      expect(
          (await screenPlanFile(file, displayName: '  Plot 14 plan.pdf  '))
              .draft!
              .displayName,
          'Plot 14 plan.pdf');
      expect(
          (await screenPlanFile(file, displayName: '   ')).draft!.displayName,
          isNull);
      expect((await screenPlanFile(file, displayName: '')).draft!.displayName,
          isNull);
      expect((await screenPlanFile(file)).draft!.displayName, isNull);
    });

    test('is given a fresh upload identity, once, when accepted', () async {
      final file = area.write('picked.pdf', planPdfBytes());
      final first = (await screenPlanFile(file)).draft!;
      final second = (await screenPlanFile(file)).draft!;
      expect(_uuidV4.hasMatch(first.mediaObjectId), isTrue);
      expect(_uuidV4.hasMatch(second.mediaObjectId), isTrue);
      expect(first.mediaObjectId, isNot(second.mediaObjectId),
          reason: 'each pick is its own upload');
    });

    test('is judged by its bytes: an image keeps any name', () async {
      final file = area.write('scan-without-extension', planJpegBytes());
      final result = await screenPlanFile(file);
      expect(result.draft!.contentType, PlanContentTypes.jpeg);
    });

    test('a document is judged by its bytes and its name together', () async {
      // A Word container named as something else (a spreadsheet, an archive).
      final renamed = area.write('budget.xlsx', planDocxBytes());
      final result = await screenPlanFile(renamed);
      expect(result.isAccepted, isFalse);
      expect(result.rejection, PlanAttachmentRejection.unsupportedType);
    });
  });

  group('a refused file', () {
    test('is explained with one fixed reason', () async {
      final exe =
          area.write('plan.pdf', <int>[0x4d, 0x5a, ...List.filled(64, 0)]);
      final unsupported = await screenPlanFile(exe);
      expect(unsupported.rejection, PlanAttachmentRejection.unsupportedType);
      expect(unsupported.draft, isNull);

      final empty = area.write('empty.pdf', <int>[]);
      expect((await screenPlanFile(empty)).rejection,
          PlanAttachmentRejection.unreadable);

      final missing = File('${area.path}${Platform.pathSeparator}gone.pdf');
      expect((await screenPlanFile(missing)).rejection,
          PlanAttachmentRejection.unreadable);
    });

    test('a file the user picked is never deleted by a refusal', () async {
      final text =
          area.write('notes.txt', <int>[...'just some text'.codeUnits]);
      final result = await screenPlanFile(text);
      expect(result.isAccepted, isFalse);
      expect(text.existsSync(), isTrue);
    });

    test('too large: images over 10 MiB, documents over 25 MiB', () async {
      final image = area.write('big.jpg', planJpegBytes());
      await growTo(image, PlanAttachmentPolicy.maxImageBytes + 1);
      expect((await screenPlanFile(image)).rejection,
          PlanAttachmentRejection.imageTooLarge);

      final document = area.write('big.pdf', planPdfBytes());
      await growTo(document, 25 * _mib + 1);
      expect((await screenPlanFile(document)).rejection,
          PlanAttachmentRejection.documentTooLarge);
    });

    test('exactly at the limit is accepted', () async {
      final image = area.write('edge.jpg', planJpegBytes());
      await growTo(image, PlanAttachmentPolicy.maxImageBytes);
      expect((await screenPlanFile(image)).isAccepted, isTrue);

      final document = area.write('edge.docx', planDocxBytes());
      await growTo(document, 25 * _mib);
      expect((await screenPlanFile(document)).isAccepted, isTrue);
    });
  });

  group('a HEIC / HEIF photo', () {
    test('is converted to JPEG on the device before it is ever uploaded',
        () async {
      final heic = area.write('IMG_0001.heic', planHeicBytes(2000));
      final jpeg = area.write('converted.jpg', planJpegBytes(1500));
      final converted = <String>[];
      final result = await screenPlanFile(
        heic,
        displayName: 'IMG_0001.heic',
        convertHeif: (source) async {
          converted.add(source.path);
          return jpeg;
        },
      );

      expect(converted, [heic.path]);
      final draft = result.draft!;
      expect(draft.path, jpeg.path, reason: 'the JPEG is what gets uploaded');
      expect(draft.contentType, PlanContentTypes.jpeg);
      expect(draft.kind, PlanAttachmentKind.image);
      expect(draft.byteLength, 1500);
      expect(draft.ownedTempPath, jpeg.path,
          reason: 'the converted file is the app\'s own, to clean up');
      expect(heic.existsSync(), isTrue,
          reason: 'the original is never touched');
    });

    test('is refused when it cannot be converted', () async {
      final heic = area.write('IMG_0002.heic', planHeicBytes());
      expect((await screenPlanFile(heic)).rejection,
          PlanAttachmentRejection.unsupportedType,
          reason: 'no converter at all');
      expect(
        (await screenPlanFile(heic, convertHeif: (source) async => null))
            .rejection,
        PlanAttachmentRejection.unsupportedType,
        reason: 'the converter could not decode it',
      );
      expect(heic.existsSync(), isTrue);
    });

    test('a conversion that is not a plan image is discarded, not kept',
        () async {
      final heic = area.write('IMG_0003.heic', planHeicBytes());
      final junk = area.write('junk.jpg', <int>[...'not an image'.codeUnits]);
      final result = await screenPlanFile(
        heic,
        convertHeif: (source) async => junk,
      );
      expect(result.rejection, PlanAttachmentRejection.unsupportedType);
      expect(junk.existsSync(), isFalse,
          reason: 'a file the app made and refused is removed');
      expect(heic.existsSync(), isTrue);
    });

    test('a conversion that is too large is discarded, not kept', () async {
      final heic = area.write('IMG_0004.heic', planHeicBytes());
      final huge = area.write('huge.jpg', planJpegBytes());
      await growTo(huge, PlanAttachmentPolicy.maxImageBytes + 1);
      final result = await screenPlanFile(
        heic,
        convertHeif: (source) async => huge,
      );
      expect(result.rejection, PlanAttachmentRejection.imageTooLarge);
      expect(huge.existsSync(), isFalse);
    });

    test('a video named like a photo is not mistaken for HEIC', () async {
      // An ISO base-media file whose brand is a video brand must not go through
      // the photo converter, whatever its name.
      final mp4 = area.write('clip.heic', <int>[
        0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, //
        0x69, 0x73, 0x6f, 0x6d, 0, 0, 2, 0, //
        0x69, 0x73, 0x6f, 0x6d, 0x6d, 0x70, 0x34, 0x31,
        ...List<int>.filled(200, 3),
      ]);
      var converterCalled = false;
      final result = await screenPlanFile(
        mp4,
        convertHeif: (source) async {
          converterCalled = true;
          return null;
        },
      );
      expect(converterCalled, isFalse);
      expect(result.rejection, PlanAttachmentRejection.unsupportedType);
    });
  });

  group('deleteQuietly', () {
    test('removes a file, ignores a missing one, never throws', () async {
      final file = area.write('temp.bin', <int>[1, 2, 3]);
      await deleteQuietly(file.path);
      expect(file.existsSync(), isFalse);
      await deleteQuietly(file.path);
      await deleteQuietly('${area.path}${Platform.pathSeparator}nowhere');
    });
  });
}
