// QuotationMediaPublisher: the logo and PDF of a saved Quotation are finished
// after the editor closes, kept on the device until done, and resumed after a
// restart from the Quotation as the server holds it.

import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_media_publisher.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_media_workflow.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = 'alice-account';
const _bob = 'bob-account';
const _q1 = 'q-1';

/// The server: one Quotation's row and media slots, and what was called.
class _FakeServer implements QuotationService {
  int version = 1;
  String? logoId;
  String? pdfId;
  bool exists = true;
  String title = 'Villa 12';
  final calls = <String>[];

  /// Fails the next media step with this, once.
  Object? failNext;
  Completer<void>? pdfGate;

  void _maybeFail(String step) {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
  }

  @override
  Future<T> batchMutations<T>(Future<T> Function() action) => action();

  @override
  Future<QuotationMediaState?> getMediaState(String quotationId) async {
    calls.add('state');
    if (!exists) return null;
    return QuotationMediaState(
        version: version, officeLogoMediaId: logoId, pdfMediaId: pdfId);
  }

  @override
  Future<QuotationModel?> getQuotationById(String quotationId) async {
    calls.add('read');
    if (!exists) return null;
    return QuotationModel(
      id: quotationId,
      userId: _alice,
      propertyTitle: title,
      officeName: 'Office',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<QuotationMediaBinding> uploadOfficeLogo({
    required String quotationId,
    required File file,
    required String? expectedMediaId,
    required String mediaObjectId,
    String? originalFileName,
  }) async {
    calls.add('logo $mediaObjectId expected $expectedMediaId');
    _maybeFail('logo');
    logoId = mediaObjectId;
    version++;
    return QuotationMediaBinding(
        mediaObjectId: mediaObjectId, resultingVersion: version);
  }

  @override
  Future<QuotationMediaRemoval> removeOfficeLogo({
    required String quotationId,
    required String? expectedMediaId,
  }) async {
    calls.add('remove logo expected $expectedMediaId');
    _maybeFail('remove');
    logoId = null;
    version++;
    return QuotationMediaRemoval(resultingVersion: version);
  }

  @override
  Future<SignedQuotationMedia?> signedOfficeLogo(String quotationId) async {
    calls.add('signed logo');
    return SignedQuotationMedia(
      mediaObjectId: logoId!,
      contentType: 'image/png',
      url: 'https://signed.example/logo',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<QuotationMediaBinding> publishPdf({
    required String quotationId,
    required File pdf,
    required String? expectedMediaId,
  }) async {
    calls.add('pdf expected $expectedMediaId');
    final gate = pdfGate;
    if (gate != null) await gate.future;
    _maybeFail('pdf');
    pdfId = 'pdf-${calls.length}';
    version++;
    return QuotationMediaBinding(
        mediaObjectId: pdfId!, resultingVersion: version);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;
  late _FakeServer server;
  late String? signedIn;
  late StreamController<void> hints;
  final rendered = <String>[];

  QuotationMediaPublisher newPublisher() => QuotationMediaPublisher(
        service: () => server,
        generatePdf: (quotation, {Locale? locale}) async {
          rendered.add(
              '${quotation.propertyTitle}|${quotation.officeLogoUrl}|${locale?.languageCode}');
          final file = File('${temp.path}/render-${rendered.length}.pdf');
          await file.writeAsBytes([37, 80, 68, 70]);
          return file.path;
        },
        currentUserId: () => signedIn,
        documents: () async => temp,
        retryHints: hints.stream,
        backoff: const [Duration(hours: 1)],
      );

  Future<File> pickedLogo() async {
    final file = File('${temp.path}/picked.png');
    await file.writeAsBytes([137, 80, 78, 71]);
    return file;
  }

  /// Lets the publisher's background run finish.
  Future<void> settle(QuotationMediaPublisher publisher) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await publisher.whenSettled(_q1);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('quotation_publisher_test');
    server = _FakeServer();
    signedIn = _alice;
    hints = StreamController<void>.broadcast();
    rendered.clear();
  });

  tearDown(() async {
    await hints.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('a new logo is bound first, then the PDF drawn with it is published',
      () async {
    final publisher = newPublisher();
    await publisher.enqueue(
      account: _alice,
      quotationId: _q1,
      locale: const Locale('ar'),
      logo: await pickedLogo(),
      logoMediaId: 'logo-1',
      logoFileName: 'office.png',
    );
    expect(publisher.isPending(_q1), isTrue);
    await settle(publisher);

    expect(server.calls, [
      'state',
      'logo logo-1 expected null',
      'read',
      'state',
      'pdf expected null',
    ]);
    expect(server.logoId, 'logo-1');
    expect(server.pdfId, isNotNull);
    expect(rendered.single, startsWith('Villa 12|file:'),
        reason: 'the PDF draws the logo just uploaded, from the device copy');
    expect(rendered.single, endsWith('|ar'));
    expect(publisher.isPending(_q1), isFalse);
    expect(publisher.publishedVersion(_q1), server.version);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(QuotationMediaPublisher.journalKey), isNull,
        reason: 'nothing is left waiting');
  });

  test('the logo is copied, so the editor may delete its own file', () async {
    final publisher = newPublisher();
    final logo = await pickedLogo();
    server.pdfGate = Completer<void>();
    await publisher.enqueue(
      account: _alice,
      quotationId: _q1,
      logo: logo,
      logoMediaId: 'logo-1',
    );
    await logo.delete();
    server.pdfGate!.complete();
    await settle(publisher);
    expect(server.logoId, 'logo-1');
    expect(rendered.single, contains('file:'));
  });

  test('a network failure keeps the job; it is retried and then finishes',
      () async {
    final publisher = newPublisher();
    server.failNext =
        const QuotationMediaException(QuotationMediaFailure.interrupted);
    await publisher.enqueue(account: _alice, quotationId: _q1);
    await settle(publisher);

    expect(publisher.isPending(_q1), isTrue);
    expect(server.pdfId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(QuotationMediaPublisher.journalKey), contains(_q1));

    hints.add(null); // the network is back
    await settle(publisher);
    expect(server.pdfId, isNotNull);
    expect(publisher.isPending(_q1), isFalse);
  });

  test(
      'after a restart the job resumes and rebuilds the PDF from the '
      'Quotation as the server holds it', () async {
    final first = newPublisher();
    server.failNext =
        const QuotationMediaException(QuotationMediaFailure.unavailable);
    await first.enqueue(
      account: _alice,
      quotationId: _q1,
      logo: await pickedLogo(),
      logoMediaId: 'logo-1',
    );
    await settle(first);
    expect(first.isPending(_q1), isTrue);

    // The app is closed; another save elsewhere changed the title.
    server.title = 'Villa 12 (edited)';
    final second = newPublisher();
    expect(second.isPending(_q1), isFalse, reason: 'not loaded yet');
    await second.resume();
    await settle(second);

    expect(server.logoId, 'logo-1');
    expect(server.pdfId, isNotNull);
    expect(rendered.last, startsWith('Villa 12 (edited)|'));
    expect(second.isPending(_q1), isFalse);
  });

  test('a logo already bound by an earlier attempt is not uploaded again',
      () async {
    server.logoId = 'logo-1'; // confirmed, but the answer was lost
    final publisher = newPublisher();
    await publisher.enqueue(
      account: _alice,
      quotationId: _q1,
      logo: await pickedLogo(),
      logoMediaId: 'logo-1',
    );
    await settle(publisher);
    expect(server.calls.where((c) => c.startsWith('logo')), isEmpty);
    expect(server.pdfId, isNotNull);
  });

  test('a cleared logo is removed before the PDF', () async {
    server.logoId = 'old-logo';
    final publisher = newPublisher();
    await publisher.enqueue(
        account: _alice, quotationId: _q1, removeLogo: true);
    await settle(publisher);
    expect(server.calls, contains('remove logo expected old-logo'));
    expect(server.logoId, isNull);
    expect(rendered.single, startsWith('Villa 12|null|'));
  });

  test('a deleted Quotation ends its job without publishing', () async {
    server.exists = false;
    final publisher = newPublisher();
    await publisher.enqueue(account: _alice, quotationId: _q1);
    await settle(publisher);
    expect(publisher.isPending(_q1), isFalse);
    expect(rendered, isEmpty);
  });

  test('a newer save while one runs is published after it, never dropped',
      () async {
    final publisher = newPublisher();
    server.pdfGate = Completer<void>();
    await publisher.enqueue(account: _alice, quotationId: _q1);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    server.title = 'Villa 12 v2';
    await publisher.enqueue(account: _alice, quotationId: _q1);
    server.pdfGate!.complete();
    server.pdfGate = null;
    await settle(publisher);
    await settle(publisher);

    expect(rendered.length, 2);
    expect(rendered.last, startsWith('Villa 12 v2|'));
    expect(publisher.isPending(_q1), isFalse);
  });

  test("another account's job waits for that account", () async {
    final publisher = newPublisher();
    signedIn = _bob;
    await publisher.enqueue(account: _alice, quotationId: _q1);
    await settle(publisher);
    expect(rendered, isEmpty);

    signedIn = _alice;
    expect(publisher.isPending(_q1), isTrue);
    await publisher.resume();
    await settle(publisher);
    expect(rendered, hasLength(1));
  });

  test('Delete Account drops the account\'s jobs and logo copies', () async {
    final publisher = newPublisher();
    signedIn = null; // nothing runs
    await publisher.enqueue(
      account: _alice,
      quotationId: _q1,
      logo: await pickedLogo(),
      logoMediaId: 'logo-1',
    );
    final copies = Directory(temp.path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('.work'))
        .toList();
    expect(copies, hasLength(1));

    await publisher.forgetAccount(_alice);
    signedIn = _alice;
    expect(publisher.isPending(_q1), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(copies.single.existsSync(), isFalse);
  });
}
