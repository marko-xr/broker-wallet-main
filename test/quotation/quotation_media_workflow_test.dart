// Tests for the Quotation media upload / removal sequences.
//
// The properties that matter:
//  - a logo or PDF is only ever replaced by the server's confirm, so a failed
//    or interrupted replacement can never remove the previously bound media;
//  - a stale operation is refused rather than overwriting a newer one;
//  - a retry after a lost confirm answer resolves to the already-bound media.

import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_media_workflow.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

const _q = '3f2c9d0a-5b7e-4c1a-9a55-0d6f8e1b2a44';
const _bound = '11111111-1111-4111-8111-111111111111';
const _fresh = '22222222-2222-4222-8222-222222222222';

final _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, 1, 2];
final _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0, 9];
final _webp = <int>[0x52, 0x49, 0x46, 0x46, 1, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 3];
final _pdf = '%PDF-1.4\n%%EOF\n'.codeUnits;

Future<File> _file(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('quotation_workflow_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}f.bin');
  await file.writeAsBytes(bytes);
  return file;
}

/// A file of [length] bytes that starts with [header].
Future<File> _bigFile(List<int> header, int length) async {
  final file = await _file(header);
  final raf = await file.open(mode: FileMode.append);
  await raf.truncate(length);
  await raf.close();
  return file;
}

class _Call {
  _Call(this.name, [this.args = const {}]);
  final String name;
  final Map<String, Object?> args;
}

/// A scripted [QuotationMediaTransport]. Each operation records its call and
/// either answers or throws what the test set up.
class _FakeTransport implements QuotationMediaTransport {
  final List<_Call> calls = [];

  /// Throwables / answers consumed per operation, in order.
  final List<Object> authorizeScript = [];
  final List<Object> confirmScript = [];
  Object? uploadError;

  List<String> get names => calls.map((c) => c.name).toList();

  @override
  Future<QuotationMediaAuthorization> authorize({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    calls.add(_Call('authorize', {
      'quotationId': quotationId,
      'role': role,
      'expectedMediaId': expectedMediaId,
      'mediaObjectId': mediaObjectId,
      'contentType': contentType,
      'contentLength': contentLength,
      'originalFileName': originalFileName,
    }));
    if (authorizeScript.isNotEmpty) {
      final next = authorizeScript.removeAt(0);
      if (next is QuotationMediaAuthorization) return next;
      throw next;
    }
    return QuotationMediaAuthorization.pending(
        mediaObjectId: mediaObjectId, presignedUrl: 'https://signed.example/put');
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  }) async {
    calls.add(_Call('upload', {'contentType': contentType}));
    if (uploadError != null) throw uploadError!;
  }

  @override
  Future<QuotationMediaConfirmation> confirm({
    required String quotationId,
    required QuotationMediaRole role,
    required String mediaObjectId,
    required String? expectedMediaId,
  }) async {
    calls.add(_Call('confirm', {
      'role': role,
      'mediaObjectId': mediaObjectId,
      'expectedMediaId': expectedMediaId,
    }));
    if (confirmScript.isNotEmpty) {
      final next = confirmScript.removeAt(0);
      if (next is QuotationMediaConfirmation) return next;
      throw next;
    }
    return const QuotationMediaConfirmation(
        previousMediaId: _bound, resultingVersion: 5);
  }

  @override
  Future<QuotationMediaRemoval> remove({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
  }) async {
    calls.add(_Call('remove', {'role': role, 'expectedMediaId': expectedMediaId}));
    return const QuotationMediaRemoval(previousMediaId: _bound, resultingVersion: 6);
  }

  @override
  Future<QuotationSignedMedia> fetchSigned(String quotationId) async =>
      const QuotationSignedMedia();
}

QuotationMediaException _stale() => const QuotationMediaException(
    QuotationMediaFailure.staleReplacement,
    statusCode: 409,
    workerCode: 'stale_replacement');

void main() {
  group('logo pre-check', () {
    test('accepts JPEG, PNG and WebP by their real bytes, whatever the name',
        () async {
      for (final entry in {
        'image/jpeg': _jpeg,
        'image/png': _png,
        'image/webp': _webp,
      }.entries) {
        final check = await QuotationMediaWorkflow.checkLogo(await _file(entry.value));
        expect(check.contentType, entry.key);
        expect(check.length, entry.value.length);
      }
    });

    test('refuses anything else before a byte is sent', () async {
      for (final bytes in [
        _pdf, // a PDF is not a logo
        'GIF89a....'.codeUnits, // GIF is not accepted
        [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63], // HEIC
        <int>[], // empty
      ]) {
        await expectLater(
          QuotationMediaWorkflow.checkLogo(await _file(bytes)),
          throwsA(isA<QuotationMediaException>().having((e) => e.failure,
              'failure', QuotationMediaFailure.unsupportedType)),
        );
      }
    });

    test('refuses a logo over 10 MiB', () async {
      final big = await _bigFile(_jpeg, QuotationMediaWorkflow.maxLogoBytes + 1);
      await expectLater(
        QuotationMediaWorkflow.checkLogo(big),
        throwsA(isA<QuotationMediaException>()
            .having((e) => e.failure, 'failure', QuotationMediaFailure.tooLarge)),
      );
      final exact = await _bigFile(_jpeg, QuotationMediaWorkflow.maxLogoBytes);
      expect((await QuotationMediaWorkflow.checkLogo(exact)).length,
          QuotationMediaWorkflow.maxLogoBytes);
    });
  });

  group('logo upload', () {
    test('runs authorize, the signed PUT, then the trusted confirm, in that order',
        () async {
      final transport = _FakeTransport();
      final workflow = QuotationMediaWorkflow(transport);
      final file = await _file(_png);

      final binding = await workflow.uploadLogo(
        quotationId: _q,
        file: file,
        expectedMediaId: _bound,
        mediaObjectId: _fresh,
        originalFileName: 'logo.png',
      );

      expect(transport.names, ['authorize', 'upload', 'confirm']);
      final authorize = transport.calls[0].args;
      expect(authorize['role'], QuotationMediaRole.officeLogo);
      expect(authorize['expectedMediaId'], _bound);
      expect(authorize['mediaObjectId'], _fresh);
      expect(authorize['contentType'], 'image/png');
      expect(authorize['contentLength'], _png.length);
      expect(authorize['originalFileName'], 'logo.png');
      expect(transport.calls[1].args['contentType'], 'image/png');
      expect(transport.calls[2].args['expectedMediaId'], _bound);
      expect(transport.calls[2].args['mediaObjectId'], _fresh);

      expect(binding.mediaObjectId, _fresh);
      expect(binding.previousMediaId, _bound);
      expect(binding.resultingVersion, 5);
    });

    test('a file the server would refuse never reaches the Worker', () async {
      final transport = _FakeTransport();
      final workflow = QuotationMediaWorkflow(transport);

      await expectLater(
        workflow.uploadLogo(
            quotationId: _q,
            file: await _file(_pdf),
            expectedMediaId: null,
            mediaObjectId: _fresh),
        throwsA(isA<QuotationMediaException>()),
      );
      expect(transport.calls, isEmpty);
    });

    test('a failed PUT never confirms: the previously bound logo is untouched',
        () async {
      final transport = _FakeTransport()
        ..uploadError =
            const QuotationMediaException(QuotationMediaFailure.interrupted);
      final workflow = QuotationMediaWorkflow(transport);

      await expectLater(
        workflow.uploadLogo(
            quotationId: _q,
            file: await _file(_jpeg),
            expectedMediaId: _bound,
            mediaObjectId: _fresh),
        throwsA(isA<QuotationMediaException>().having((e) => e.failure,
            'failure', QuotationMediaFailure.interrupted)),
      );

      expect(transport.names, ['authorize', 'upload'],
          reason: 'no confirm, and above all no remove of the bound logo');
      expect(transport.names.contains('remove'), isFalse);
    });

    test('a refused confirm leaves the bound logo to the server and reports it',
        () async {
      final transport = _FakeTransport()
        ..confirmScript.add(const QuotationMediaException(
            QuotationMediaFailure.typeMismatch,
            statusCode: 422));
      final workflow = QuotationMediaWorkflow(transport);

      await expectLater(
        workflow.uploadLogo(
            quotationId: _q,
            file: await _file(_jpeg),
            expectedMediaId: _bound,
            mediaObjectId: _fresh),
        throwsA(isA<QuotationMediaException>().having(
            (e) => e.failure, 'failure', QuotationMediaFailure.typeMismatch)),
      );
      expect(transport.names, ['authorize', 'upload', 'confirm']);
    });

    test('an id that is already bound uploads nothing', () async {
      final transport = _FakeTransport()
        ..authorizeScript
            .add(const QuotationMediaAuthorization.ready(mediaObjectId: _fresh));
      final workflow = QuotationMediaWorkflow(transport);

      final binding = await workflow.uploadLogo(
          quotationId: _q,
          file: await _file(_jpeg),
          expectedMediaId: _fresh,
          mediaObjectId: _fresh);

      expect(transport.names, ['authorize']);
      expect(binding.mediaObjectId, _fresh);
    });
  });

  group('stale operations', () {
    test('a retry after a lost confirm answer resolves to the bound media',
        () async {
      final transport = _FakeTransport()
        ..authorizeScript.add(_stale())
        ..confirmScript.add(const QuotationMediaConfirmation(alreadyConfirmed: true));
      final workflow = QuotationMediaWorkflow(transport);

      final binding = await workflow.uploadLogo(
          quotationId: _q,
          file: await _file(_jpeg),
          expectedMediaId: _bound,
          mediaObjectId: _fresh);

      expect(binding.mediaObjectId, _fresh);
      expect(transport.names, ['authorize', 'confirm'],
          reason: 'resolved by the idempotent confirm; nothing is uploaded again');
    });

    test('a genuinely newer slot is refused, not overwritten', () async {
      final transport = _FakeTransport()
        ..authorizeScript.add(_stale())
        ..confirmScript.add(const QuotationMediaException(
            QuotationMediaFailure.unknown,
            statusCode: 404,
            workerCode: 'media_not_found'));
      final workflow = QuotationMediaWorkflow(transport);

      await expectLater(
        workflow.uploadLogo(
            quotationId: _q,
            file: await _file(_jpeg),
            expectedMediaId: _bound,
            mediaObjectId: _fresh),
        throwsA(isA<QuotationMediaException>().having((e) => e.failure,
            'failure', QuotationMediaFailure.staleReplacement)),
      );
      expect(transport.names, ['authorize', 'confirm'],
          reason: 'no PUT and no overwrite');
    });

    test('a stale answer that confirm does not recognise as bound is still stale',
        () async {
      final transport = _FakeTransport()
        ..authorizeScript.add(_stale())
        ..confirmScript.add(const QuotationMediaConfirmation());
      final workflow = QuotationMediaWorkflow(transport);
      await expectLater(
        workflow.uploadLogo(
            quotationId: _q,
            file: await _file(_jpeg),
            expectedMediaId: _bound,
            mediaObjectId: _fresh),
        throwsA(isA<QuotationMediaException>().having((e) => e.failure,
            'failure', QuotationMediaFailure.staleReplacement)),
      );
    });
  });

  group('PDF upload', () {
    test('uploads application/pdf under the quotation_pdf role with a new id each time',
        () async {
      final transport = _FakeTransport();
      final workflow = QuotationMediaWorkflow(transport);
      final file = await _file(_pdf);

      await workflow.uploadPdf(
          quotationId: _q,
          file: file,
          expectedMediaId: _bound,
          currentExpected: () async => _bound);
      await workflow.uploadPdf(
          quotationId: _q,
          file: file,
          expectedMediaId: _bound,
          currentExpected: () async => _bound);

      final authorizes = transport.calls.where((c) => c.name == 'authorize').toList();
      expect(authorizes, hasLength(2));
      for (final call in authorizes) {
        expect(call.args['role'], QuotationMediaRole.quotationPdf);
        expect(call.args['contentType'], 'application/pdf');
        expect(call.args['expectedMediaId'], _bound);
        expect(call.args['contentLength'], _pdf.length);
        expect(Uuid.isValidUUID(fromString: call.args['mediaObjectId']! as String),
            isTrue);
      }
      expect(authorizes[0].args['mediaObjectId'],
          isNot(authorizes[1].args['mediaObjectId']),
          reason: 'a regenerated PDF is a new media object');
    });

    test('a first PDF is bound against an empty slot', () async {
      final transport = _FakeTransport();
      final workflow = QuotationMediaWorkflow(transport);
      await workflow.uploadPdf(
          quotationId: _q,
          file: await _file(_pdf),
          expectedMediaId: null,
          currentExpected: () async => null);
      expect(transport.calls.first.args['expectedMediaId'], isNull);
    });

    test('a slot that moved meanwhile is re-read and the upload retried once',
        () async {
      final transport = _FakeTransport()..authorizeScript.add(_stale());
      final workflow = QuotationMediaWorkflow(transport);
      var reads = 0;

      final binding = await workflow.uploadPdf(
        quotationId: _q,
        file: await _file(_pdf),
        expectedMediaId: _bound,
        currentExpected: () async {
          reads++;
          return _fresh; // the server's slot now holds another PDF
        },
      );

      expect(reads, 1);
      final authorizes = transport.calls.where((c) => c.name == 'authorize').toList();
      expect(authorizes, hasLength(2));
      expect(authorizes[0].args['expectedMediaId'], _bound);
      expect(authorizes[1].args['expectedMediaId'], _fresh);
      expect(binding.mediaObjectId, authorizes[1].args['mediaObjectId']);
    });

    test('a stale answer with an unchanged slot is not retried in a loop',
        () async {
      final transport = _FakeTransport()..authorizeScript.add(_stale());
      final workflow = QuotationMediaWorkflow(transport);

      await expectLater(
        workflow.uploadPdf(
          quotationId: _q,
          file: await _file(_pdf),
          expectedMediaId: _bound,
          currentExpected: () async => _bound,
        ),
        throwsA(isA<QuotationMediaException>().having((e) => e.failure,
            'failure', QuotationMediaFailure.staleReplacement)),
      );
      expect(transport.calls.where((c) => c.name == 'authorize'), hasLength(1));
    });

    test('a PDF over 20 MiB never reaches the Worker', () async {
      final transport = _FakeTransport();
      final workflow = QuotationMediaWorkflow(transport);
      final big = await _bigFile(_pdf, QuotationMediaWorkflow.maxPdfBytes + 1);

      await expectLater(
        workflow.uploadPdf(
            quotationId: _q,
            file: big,
            expectedMediaId: null,
            currentExpected: () async => null),
        throwsA(isA<QuotationMediaException>()
            .having((e) => e.failure, 'failure', QuotationMediaFailure.tooLarge)),
      );
      expect(transport.calls, isEmpty);
    });

    test('a failed PDF PUT never confirms and never removes the bound PDF',
        () async {
      final transport = _FakeTransport()
        ..uploadError =
            const QuotationMediaException(QuotationMediaFailure.uploadRejected);
      final workflow = QuotationMediaWorkflow(transport);

      await expectLater(
        workflow.uploadPdf(
            quotationId: _q,
            file: await _file(_pdf),
            expectedMediaId: _bound,
            currentExpected: () async => _bound),
        throwsA(isA<QuotationMediaException>()),
      );
      expect(transport.names, ['authorize', 'upload']);
    });
  });

  group('logo removal', () {
    test('removes against the expected media id only', () async {
      final transport = _FakeTransport();
      final workflow = QuotationMediaWorkflow(transport);

      final removal =
          await workflow.removeLogo(quotationId: _q, expectedMediaId: _bound);

      expect(transport.names, ['remove']);
      expect(transport.calls.single.args['role'], QuotationMediaRole.officeLogo);
      expect(transport.calls.single.args['expectedMediaId'], _bound);
      expect(removal.resultingVersion, 6);
    });
  });
}
