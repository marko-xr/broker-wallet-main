// Behavioural tests for the Quotation form's save / reopen / edit / media flow.
//
// The view-model runs against a small in-memory server that models the hosted
// semantics: `save_quotation`'s optimistic version, a version bump on every
// media slot change, per-slot `expectedMediaId` staleness, and idempotent
// confirm. Nothing here is mocked at the view-model boundary, so these cover the
// real ordering and failure behaviour the user depends on.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/quotation/add_quotation_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/add_quotation_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/logo_background_removal_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/logo_optimization_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_pdf_cache.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_supabase_mapper.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

const _logoA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _pdfA = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
final _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, 1];
final _pdfBytes = '%PDF-1.4\n%%EOF\n'.codeUnits;

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);
  final String? uid;

  @override
  String? get currentUserId => uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MediaCall {
  _MediaCall(this.op, {this.role, this.expected, this.mediaId});
  final String op;
  final QuotationMediaRole? role;
  final String? expected;
  final String? mediaId;
}

/// The hosted backend as the app sees it: aggregate RPC + media Worker.
class _FakeServer implements QuotationRemote, QuotationMediaTransport {
  int? version;
  QuotationModel? stored;
  String? logoId;
  String? pdfId;

  final List<QuotationSavePayload> payloads = [];
  final List<QuotationModel> savedModels = [];
  final List<String> savedIds = [];
  final List<int?> savedExpectedVersions = [];
  final List<_MediaCall> media = [];
  String? uploadedLogoPath;

  /// A one-shot failure for the next aggregate save.
  Object? saveError;

  /// Roles whose signed PUT fails, until cleared.
  final Set<QuotationMediaRole> failUpload = {};

  /// Holds the next save open until completed (to test re-entrancy).
  Completer<void>? saveGate;
  Completer<void>? logoUploadGate;
  Completer<void>? logoUploadStarted;
  int mediaStateReads = 0;
  int signedReads = 0;
  DateTime? signedExpiry;
  bool omitMediaVersion = false;

  QuotationMediaRole? _authorizedRole;

  String? slot(QuotationMediaRole role) =>
      role == QuotationMediaRole.officeLogo ? logoId : pdfId;

  void _setSlot(QuotationMediaRole role, String? id) {
    if (role == QuotationMediaRole.officeLogo) {
      logoId = id;
    } else {
      pdfId = id;
    }
  }

  // ---- QuotationRemote ----------------------------------------------------

  @override
  Future<QuotationSaveResult> save(QuotationModel quotation,
      {required String quotationId, int? expectedVersion}) async {
    // The real adapter builds the payload first and may refuse it.
    final payload = QuotationSupabaseMapper.toSavePayload(quotation,
        quotationId: quotationId, expectedVersion: expectedVersion);
    payloads.add(payload);
    savedModels.add(quotation);
    savedIds.add(quotationId);
    savedExpectedVersions.add(expectedVersion);
    if (saveGate != null) await saveGate!.future;
    if (saveError != null) {
      final error = saveError!;
      saveError = null;
      throw error;
    }
    if (expectedVersion == null) {
      if (version != null) {
        return QuotationSaveResult(
            quotationId: quotationId, version: version!, outcome: 'replayed');
      }
      version = 1;
    } else {
      if (version == null) {
        throw const QuotationException(QuotationFailure.notFound);
      }
      if (version != expectedVersion) {
        throw const QuotationException(QuotationFailure.versionConflict);
      }
      version = version! + 1;
    }
    stored = quotation.copyWith(id: quotationId);
    return QuotationSaveResult(
      quotationId: quotationId,
      version: version!,
      outcome: expectedVersion == null ? 'created' : 'updated',
    );
  }

  @override
  Future<QuotationModel?> getQuotation(String quotationId) async {
    if (version == null || stored == null) return null;
    return stored!.copyWith(
      id: quotationId,
      version: version,
      officeLogoMediaId: logoId,
      pdfMediaId: pdfId,
    );
  }

  @override
  Future<QuotationMediaState?> getMediaState(String quotationId) async {
    mediaStateReads++;
    return version == null
          ? null
          : QuotationMediaState(
              version: version!, officeLogoMediaId: logoId, pdfMediaId: pdfId);
  }

  @override
  Future<String?> getMediaFileName(String mediaId) async => 'office-logo.png';

  @override
  Future<List<QuotationModel>> listQuotations() async => const [];

  @override
  Stream<List<QuotationModel>> watchQuotations() => const Stream.empty();

  @override
  Future<void> softDelete(String quotationId) async {}

  // ---- QuotationMediaTransport -------------------------------------------

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
    media.add(_MediaCall('authorize',
        role: role, expected: expectedMediaId, mediaId: mediaObjectId));
    if (expectedMediaId != slot(role)) {
      throw const QuotationMediaException(
          QuotationMediaFailure.staleReplacement,
          statusCode: 409);
    }
    _authorizedRole = role;
    return QuotationMediaAuthorization.pending(
        mediaObjectId: mediaObjectId, presignedUrl: 'https://signed.example/put');
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  }) async {
    media.add(_MediaCall('upload', role: _authorizedRole));
    if (_authorizedRole == QuotationMediaRole.officeLogo) {
      uploadedLogoPath = file.path;
    }
    if (_authorizedRole == QuotationMediaRole.officeLogo &&
        logoUploadGate != null) {
      if (logoUploadStarted != null && !logoUploadStarted!.isCompleted) {
        logoUploadStarted!.complete();
      }
      await logoUploadGate!.future;
    }
    if (failUpload.contains(_authorizedRole)) {
      throw const QuotationMediaException(QuotationMediaFailure.interrupted);
    }
  }

  @override
  Future<QuotationMediaConfirmation> confirm({
    required String quotationId,
    required QuotationMediaRole role,
    required String mediaObjectId,
    required String? expectedMediaId,
  }) async {
    media.add(_MediaCall('confirm',
        role: role, expected: expectedMediaId, mediaId: mediaObjectId));
    if (slot(role) == mediaObjectId) {
      return const QuotationMediaConfirmation(alreadyConfirmed: true);
    }
    if (expectedMediaId != slot(role)) {
      throw const QuotationMediaException(
          QuotationMediaFailure.staleReplacement,
          statusCode: 409);
    }
    final previous = slot(role);
    _setSlot(role, mediaObjectId);
    version = version! + 1;
    return QuotationMediaConfirmation(
        previousMediaId: previous,
        resultingVersion: omitMediaVersion ? null : version);
  }

  @override
  Future<QuotationMediaRemoval> remove({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
  }) async {
    media.add(_MediaCall('remove', role: role, expected: expectedMediaId));
    if (slot(role) != null && slot(role) != expectedMediaId) {
      throw const QuotationMediaException(
          QuotationMediaFailure.staleReplacement,
          statusCode: 409);
    }
    final previous = slot(role);
    if (previous == null) {
      return QuotationMediaRemoval(resultingVersion: version, alreadyRemoved: true);
    }
    _setSlot(role, null);
    version = version! + 1;
    return QuotationMediaRemoval(previousMediaId: previous, resultingVersion: version);
  }

  @override
  Future<QuotationSignedMedia> fetchSigned(String quotationId) async {
    signedReads++;
    return QuotationSignedMedia(
        officeLogo: logoId == null
            ? null
            : SignedQuotationMedia(
                mediaObjectId: logoId!,
                contentType: 'image/png',
                url: 'https://signed.example/logo',
                expiresAt: signedExpiry ??
                    DateTime.now().add(const Duration(minutes: 15)),
              ),
      );
  }

  Iterable<_MediaCall> of(QuotationMediaRole role, String op) =>
      media.where((c) => c.role == role && c.op == op);
}

class _FakeLogoBackgroundRemoval extends LogoBackgroundRemovalService {
  _FakeLogoBackgroundRemoval(this.output);

  final File output;
  int calls = 0;

  @override
  Future<File> removeBackground(File source) async {
    calls++;
    return output;
  }
}

/// Stands in for the isolate-based optimizer: returns [output] (null means the
/// picked logo is already small enough), or fails, once [gate] opens.
class _FakeLogoOptimizer extends LogoOptimizationService {
  _FakeLogoOptimizer({this.output, this.error, this.gate, this.build});

  final File? output;
  final Object? error;
  final Completer<void>? gate;

  /// Makes a different copy for each source.
  final Future<File?> Function(File source)? build;
  final List<String> sources = [];

  @override
  Future<File?> optimize(File source) async {
    sources.add(source.path);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return build != null ? build!(source) : output;
  }
}

class _Env {
  _Env._(this.dir, this.server, this.vm, this.generated, this.toasts);

  final Directory dir;
  final _FakeServer server;
  final AddQuotationViewModel vm;

  /// The model each PDF was drawn from (to see where its logo came from).
  final List<QuotationModel> generated;
  final List<String> toasts;
}

Future<_Env> _env({
  String? uid = 'user-1',
  String? editId,
  bool pdfFails = false,
  Future<File?> Function()? logoPicker,
  LogoBackgroundRemovalService? backgroundRemoval,
  LogoOptimizationService? logoOptimizer,
  QuotationCreationGate? creationGate,
  Completer<void>? pdfStarted,
  Completer<void>? pdfGate,
  Duration longSaveThreshold = AddQuotationViewModel.defaultLongSaveThreshold,
  _FakeServer? server,
}) async {
  final dir = await Directory.systemTemp.createTemp('quotation_vm_test_');
  final backend = server ?? _FakeServer();
  final generated = <QuotationModel>[];
  final toasts = <String>[];

  final service = QuotationService(
    remote: backend,
    mediaTransport: backend,
    pdfCache: QuotationPdfCache(directory: () async => dir),
  );
  final vm = AddQuotationViewModel(
    quotationService: service,
    authRepository: _FakeAuth(uid),
    editQuotationId: editId,
    logoPicker: logoPicker,
    logoBackgroundRemovalService: backgroundRemoval,
    // The real optimizer needs an isolate and real image bytes.
    logoOptimizationService: logoOptimizer ?? _FakeLogoOptimizer(),
    creationGate: creationGate,
    longSaveThreshold: longSaveThreshold,
    toast: (message, _) => toasts.add(message),
    pdfGenerator: (quotation, {locale}) async {
      generated.add(quotation);
      if (pdfStarted != null && !pdfStarted.isCompleted) pdfStarted.complete();
      if (pdfGate != null) await pdfGate.future;
      if (pdfFails) throw StateError('renderer failed');
      final file = File('${dir.path}${Platform.pathSeparator}'
          'quotation_${quotation.id}.pdf');
      await file.writeAsBytes(_pdfBytes);
      return file.path;
    },
  );
  // A save that fails returns at once, while the PDF it was rendering beside
  // the save may still be writing its file; the view-model then deletes that
  // file itself. The directory is removed only after that and the other
  // temporary-file removals have finished, never while a handle is open.
  addTearDown(() async {
    // A renderer parked on [pdfGate] has not touched the disk yet, and under a
    // widget test's fake clock it could not finish anyway.
    final parked = pdfGate != null && !pdfGate.isCompleted;
    if (!parked) await vm.backgroundWorkSettled();
    vm.dispose();
    if (!parked) await vm.backgroundWorkSettled();
    await dir.delete(recursive: true);
  });
  return _Env._(dir, backend, vm, generated, toasts);
}

Future<File> _logoFile(Directory dir, [String name = 'logo.png']) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(_png);
  return file;
}

void _fill(AddQuotationViewModel vm) {
  vm
    ..setPropertyTitle('Apartment 306')
    ..setOfficeName('Realtig')
    ..setTotalAmount('120000');
}

/// A Quotation that already exists on the server, at [version].
_FakeServer _existing({
  int version = 3,
  String? logo,
  String? pdf,
  String title = 'Marina Tower 12',
}) {
  return _FakeServer()
    ..version = version
    ..logoId = logo
    ..pdfId = pdf
    ..stored = QuotationModel(
      id: 'q-existing',
      userId: 'user-1',
      propertyTitle: title,
      propertyType: 'Apartment',
      parking: true,
      officeName: 'Realtig',
      date: '2026-10-01',
      startDate: '2026-10-01',
      endDate: '2027-09-30',
      currencyCode: 'AED',
      totalAmount: 120000,
      numberOfInstallments: 2,
      paymentType: 'cheque',
      insuranceAmount: 2000.5,
      insuranceReturnable: true,
      customNote: 'note',
      welcomeMessageMode: WelcomeMessageMode.custom,
      customWelcomeMessage: 'Hello there',
      downpayments: [
        DownpaymentItem(
            method: PaymentMethod.cheque,
            number: 1,
            date: DateTime(2026, 10, 1),
            amount: 60000),
        DownpaymentItem(
            method: PaymentMethod.cheque,
            number: 2,
            date: DateTime(2027, 4, 1),
            amount: 60000),
      ],
      governmentFees: GovernmentFees(
          percentOfTotalRent: 2, municipality: 100, total: 2500),
      administrativeFees: AdministrativeFees(fees: [
        AdministrativeFeeItem(title: 'Commission', amount: 5000),
      ]),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Localizations load assets asynchronously. Serve the real ARB files before
    // pumping widget tests so their home widgets are built deterministically.
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        if (message == null) return null;
        final key = utf8.decode(message.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    try {
      await AppLocalizations.preloadAllLanguages();
    } finally {
      // Keep the normal test asset bundle for the editor's images and icons.
      binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets', null);
    }
    expect(AppLocalizations.translateFor('en', 'quotationSaving'),
        'Saving quotation...');
    expect(AppLocalizations.translateFor('ar', 'quotationSaving'),
        'جارٍ حفظ عرض السعر...');
    // One save is one operation: the stage texts are not user-facing.
    for (final code in ['en', 'ar']) {
      expect(AppLocalizations.translateFor(code, 'quotationUploadingLogo'),
          isNull);
      expect(AppLocalizations.translateFor(code, 'quotationPreparing'), isNull);
    }
  });

  group('create', () {
    test('saves the aggregate first, then binds the PDF, as one create', () async {
      final env = await _env();
      _fill(env.vm);

      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.saved);
      expect(outcome.messageKey, isNull,
          reason: 'a create keeps the existing success message');

      final server = env.server;
      expect(server.payloads, hasLength(1));
      expect(server.savedExpectedVersions.single, isNull,
          reason: 'a create has no expected version');
      expect(Uuid.isValidUUID(fromString: server.savedIds.single), isTrue);

      expect(
        server.media.map((c) => c.op).toList(),
        ['authorize', 'upload', 'confirm'],
        reason: 'the PDF is authorized, uploaded privately, then confirmed',
      );
      expect(server.media.first.role, QuotationMediaRole.quotationPdf);
      expect(server.media.first.expected, isNull);
      expect(server.pdfId, isNotNull);
      expect(env.vm.boundPdfMediaId, server.pdfId);
      expect(env.generated, hasLength(1));
      expect(server.mediaStateReads, 0,
          reason: 'the PDF confirmation already supplied the new version');
    });

    test('never sends a media id, owner or version in the saved aggregate',
        () async {
      final env = await _env();
      _fill(env.vm);
      await env.vm.performSave();

      final model = env.server.savedModels.single;
      expect(model.officeLogoMediaId, isNull);
      expect(model.pdfMediaId, isNull);
      expect(model.version, isNull);
      final raw = env.server.payloads.single.toRpcParams().toString();
      expect(raw.contains('media'), isFalse);
      expect(raw.contains('owner'), isFalse);
      expect(raw.contains('user-1'), isFalse);
    });

    test('adopts the server version after the media bumped it, so an edit is an update',
        () async {
      final env = await _env();
      _fill(env.vm);
      await env.vm.performSave();

      // save -> v1, PDF confirm -> v2.
      expect(env.server.version, 2);
      expect(env.vm.version, 2);

      env.vm.setOfficeName('Realtig Properties');
      final second = await env.vm.performSave();

      expect(second.kind, QuotationSaveKind.saved);
      expect(second.wasUpdate, isTrue);
      expect(second.messageKey, 'quotationUpdatedSuccessfully');
      expect(env.server.savedExpectedVersions, [null, 2]);
      expect(env.server.savedIds.toSet(), hasLength(1),
          reason: 'the same Quotation, not a second one');
      // The regenerated PDF replaced the first against its confirmed id.
      final pdfAuthorizes = env.server.of(QuotationMediaRole.quotationPdf, 'authorize');
      expect(pdfAuthorizes.last.expected, isNotNull);
      expect(env.server.version, 4);
      expect(env.vm.version, 4);
    });

    test('a blank title is refused before anything is sent', () async {
      final env = await _env();
      env.vm
        ..setOfficeName('Realtig')
        ..setTotalAmount('1');

      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.invalid);
      expect(outcome.messageKey, 'quotationTitleRequired');
      expect(env.server.savedIds, isEmpty);
      expect(env.server.payloads, isEmpty);
      expect(env.server.media, isEmpty);
    });

    test('an administrative fee with an amount but no title is refused', () async {
      final env = await _env();
      _fill(env.vm);
      env.vm.addAdministrativeFeeRow();
      env.vm.updateAdministrativeFeeAmount(0, '50');

      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.invalid);
      expect(outcome.messageKey, 'quotationAdminFeeTitleRequired');
      expect(env.server.media, isEmpty);
    });

    test('maps the whole form to the contract: children, dates and enums', () async {
      final env = await _env();
      _fill(env.vm);
      env.vm
        ..setPaymentType('bankTransfer')
        ..setNumberOfInstallments('2')
        ..setStartDate('2026-10-01')
        ..setEndDate('2027-09-30')
        ..setGovPercentOfTotalRent('2')
        ..setGovMunicipality('100');
      env.vm.addAdministrativeFeeRow();
      env.vm.updateAdministrativeFeeTitle(0, 'Commission');
      env.vm.updateAdministrativeFeeAmount(0, '5000');

      await env.vm.performSave();

      final payload = env.server.payloads.single;
      expect(payload.header['payment_type'], 'bank_transfer');
      expect(payload.header['number_of_installments'], 2);
      expect(payload.downpayments, hasLength(2),
          reason: 'the smart schedule is saved as the form shows it');
      expect(payload.downpayments.map((d) => d['sequence_number']), [1, 2]);
      expect(payload.downpayments.first['method'], 'bank_transfer');
      expect(payload.downpayments.first['due_at'], '2026-10-01T00:00:00.000Z');
      expect(payload.governmentFees!['percent_of_total_rent'], 2);
      expect(payload.governmentFees!['municipality'], 100);
      expect(payload.administrativeFees,
          [
            {'ordinal': 0, 'title': 'Commission', 'amount': 5000}
          ]);
    });

    test('a retry after a failed save replays the same id as a create', () async {
      final env = await _env();
      _fill(env.vm);
      env.server.saveError =
          const QuotationException(QuotationFailure.network);

      final first = await env.vm.performSave();
      expect(first.kind, QuotationSaveKind.failed);
      expect(first.failure, QuotationFailure.network);
      expect(first.messageKey, 'quotationNetworkError');
      expect(env.server.media, isEmpty, reason: 'no media without a saved Quotation');
      expect(env.vm.version, isNull);

      final second = await env.vm.performSave();
      expect(second.kind, QuotationSaveKind.saved);
      expect(env.server.savedIds, hasLength(2));
      expect(env.server.savedIds.toSet(), hasLength(1),
          reason: 'one stable id, so a lost answer can never make two Quotations');
      expect(env.server.savedExpectedVersions, [null, null]);
    });

    test('a signed-out user saves nothing', () async {
      final env = await _env(uid: null);
      _fill(env.vm);

      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.failed);
      expect(outcome.failure, QuotationFailure.notSignedIn);
      expect(outcome.messageKey, 'quotationSessionExpired');
      expect(env.server.savedIds, isEmpty);
    });

    test('a second tap while saving does nothing', () async {
      final env = await _env();
      _fill(env.vm);
      env.server.saveGate = Completer<void>();

      final first = env.vm.performSave();
      await Future<void>.delayed(Duration.zero);
      expect(env.vm.isLoading, isTrue);

      final second = await env.vm.performSave();
      expect(second.kind, QuotationSaveKind.busy);

      env.server.saveGate!.complete();
      expect((await first).kind, QuotationSaveKind.saved);
      expect(env.server.savedIds, hasLength(1));
      expect(env.vm.isLoading, isFalse);
    });

    testWidgets('two UI Save taps share one quota preflight and lock immediately',
        (tester) async {
      final quotaGate = Completer<bool>();
      var quotaCalls = 0;
      final env = await tester.runAsync(() => _env(
            creationGate: (_) {
              quotaCalls++;
              return quotaGate.future;
            },
          ));
      final vm = env!.vm;
      BuildContext? formContext;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          formContext = context;
          return const SizedBox.shrink();
        }),
      ));

      final first = vm.save(formContext!);
      expect(vm.isLoading, isTrue,
          reason: 'the button must lock before the quota request completes');
      expect(vm.saveProgress, QuotationSaveProgress.saving);
      final second = vm.save(formContext!);
      expect(quotaCalls, 1);

      quotaGate.complete(false);
      await tester.pump();
      await Future.wait([first, second]);
      expect(vm.isLoading, isFalse);
      expect(vm.saveProgress, QuotationSaveProgress.idle);
      expect(env.server.savedIds, isEmpty);
    });

    test('a fast save only ever shows the button progress', () async {
      final env = await _env(longSaveThreshold: const Duration(milliseconds: 600));
      _fill(env.vm);
      final seen = <QuotationSaveProgress>[];
      env.vm.addListener(() => seen.add(env.vm.saveProgress));

      final saving = env.vm.performSave();
      expect(env.vm.isLoading, isTrue);
      expect(env.vm.saveProgress, QuotationSaveProgress.saving);
      expect((await saving).kind, QuotationSaveKind.saved);

      expect(env.vm.isLoading, isFalse);
      expect(env.vm.saveProgress, QuotationSaveProgress.idle);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(seen, isNot(contains(QuotationSaveProgress.longSaving)),
          reason: 'the timer of a finished save must not fire later');
      expect(env.vm.saveProgress, QuotationSaveProgress.idle);
    });

    test('a long save moves progress to the one centered indicator and clears on success',
        () async {
      final env = await _env(longSaveThreshold: const Duration(milliseconds: 60));
      _fill(env.vm);
      env.server.saveGate = Completer<void>();

      final saving = env.vm.performSave();
      expect(env.vm.saveProgress, QuotationSaveProgress.saving);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(env.vm.isLoading, isTrue);
      expect(env.vm.saveProgress, QuotationSaveProgress.longSaving);

      env.server.saveGate!.complete();
      expect((await saving).kind, QuotationSaveKind.saved);
      expect(env.vm.isLoading, isFalse);
      expect(env.vm.saveProgress, QuotationSaveProgress.idle,
          reason: 'no minimum display time: it clears as the save ends');
    });

    test('a failed save clears its loading state', () async {
      final env = await _env(longSaveThreshold: const Duration(milliseconds: 60));
      _fill(env.vm);
      env.server.saveGate = Completer<void>();
      env.server.saveError =
          const QuotationException(QuotationFailure.versionConflict);
      final saving = env.vm.performSave();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(env.vm.saveProgress, QuotationSaveProgress.longSaving);

      env.server.saveGate!.complete();
      final outcome = await saving;
      expect(outcome.kind, QuotationSaveKind.failed);
      expect(outcome.messageKey, 'quotationVersionConflict');
      expect(env.vm.isLoading, isFalse);
      expect(env.vm.saveProgress, QuotationSaveProgress.idle);
    });

    test('missing media version triggers one authoritative refresh', () async {
      final server = _FakeServer()..omitMediaVersion = true;
      final env = await _env(server: server);
      _fill(env.vm);

      expect((await env.vm.performSave()).kind, QuotationSaveKind.saved);
      expect(server.mediaStateReads, 1);
      expect(env.vm.version, server.version);
    });

    group('editor loading UI', () {
      Future<void> pumpEditor(
        WidgetTester tester,
        AddQuotationViewModel vm, {
        Locale locale = const Locale('en'),
      }) async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
            child: child ?? const SizedBox.shrink(),
          ),
          home: AddQuotationView(viewModel: vm),
        ));
        await tester.pumpAndSettle();
      }

      final buttonSpinner = find.descendant(
        of: find.byType(SaveCancelButtons),
        matching: find.byType(CircularProgressIndicator),
      );
      final saveButton = find.descendant(
        of: find.byType(SaveCancelButtons),
        matching: find.byType(ElevatedButton),
      );

      for (final entry in {
        const Locale('en'): 'Saving quotation...',
        const Locale('ar'): 'جارٍ حفظ عرض السعر...',
      }.entries) {
        testWidgets(
            'a short save shows the button spinner only; a long one replaces it with one centered indicator (${entry.key.languageCode})',
            (tester) async {
          // The renderer is held back so no file is opened while the widget
          // test's fake clock cannot finish its I/O.
          final env =
              (await tester.runAsync(() => _env(pdfGate: Completer<void>())))!;
          _fill(env.vm);
          env.server.saveGate = Completer<void>();
          await pumpEditor(tester, env.vm, locale: entry.key);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(SaveCancelButtons), findsOneWidget);

          QuotationSaveOutcome? outcome;
          unawaited(env.vm.performSave().then((o) => outcome = o));
          expect(env.vm.isLoading, isTrue);
          await tester.pump();

          // The first moments: the button locks and spins, nothing else.
          expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull);
          expect(buttonSpinner, findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text(entry.value), findsNothing);

          // Just under the threshold: still only the button spinner.
          await tester.pump(AddQuotationViewModel.defaultLongSaveThreshold -
              const Duration(milliseconds: 100));
          expect(env.vm.saveProgress, QuotationSaveProgress.saving);
          expect(buttonSpinner, findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text(entry.value), findsNothing);

          // At the threshold: one centered indicator, and the button's goes.
          await tester.pump(const Duration(milliseconds: 100));
          expect(env.vm.saveProgress, QuotationSaveProgress.longSaving);
          expect(find.text(entry.value), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsOneWidget,
              reason: 'never two spinners at once');
          expect(buttonSpinner, findsNothing);
          expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull,
              reason: 'Save stays disabled');
          expect(tester.takeException(), isNull);

          // The save ends in an error: every loading UI is gone at once.
          env.server.saveError =
              const QuotationException(QuotationFailure.versionConflict);
          env.server.saveGate!.complete();
          await tester.pump();
          await tester.pump();
          expect(outcome?.kind, QuotationSaveKind.failed);
          expect(env.vm.isLoading, isFalse);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text(entry.value), findsNothing);
          expect(tester.widget<ElevatedButton>(saveButton).onPressed,
              isNotNull);
          expect(tester.takeException(), isNull);
        });
      }
    });

    test('a blank title starts no PDF work at all', () async {
      final env = await _env();
      env.vm.setOfficeName('Realtig');

      expect((await env.vm.performSave()).kind, QuotationSaveKind.invalid);

      expect(env.generated, isEmpty);
      expect(env.server.payloads, isEmpty);
    });

    test('the PDF is prepared while the database save is still running',
        () async {
      final pdfStarted = Completer<void>();
      final env = await _env(pdfStarted: pdfStarted);
      _fill(env.vm);
      env.server.saveGate = Completer<void>();

      final saving = env.vm.performSave();
      await pdfStarted.future;
      expect(env.server.savedIds, hasLength(1), reason: 'the save has started');
      expect(env.server.version, isNull, reason: 'but it has not answered');
      expect(env.generated, hasLength(1));
      expect(env.server.media, isEmpty,
          reason: 'nothing is published before the save succeeds');

      env.server.saveGate!.complete();
      expect((await saving).kind, QuotationSaveKind.saved);
      expect(env.generated, hasLength(1), reason: 'one PDF per save');
      expect(env.server.of(QuotationMediaRole.quotationPdf, 'confirm'),
          hasLength(1));
      expect(env.server.pdfId, isNotNull);
    });

    test('a failed save discards its PDF; the retry waits for that and publishes its own',
        () async {
      final pdfGate = Completer<void>();
      final env = await _env(pdfGate: pdfGate);
      _fill(env.vm);
      env.server.saveError =
          const QuotationException(QuotationFailure.network);

      final first = await env.vm.performSave();
      expect(first.kind, QuotationSaveKind.failed,
          reason: 'the failure is reported without waiting for the renderer');
      expect(env.vm.isLoading, isFalse);
      expect(env.server.media, isEmpty, reason: 'nothing is published');

      // The form changes before the retry; the old render must not be reused.
      env.vm.setPropertyTitle('Apartment 307');
      final second = env.vm.performSave();
      await pumpEventQueue();
      expect(env.server.savedIds, hasLength(1),
          reason: 'the retry waits for the discarded renderer first');

      pdfGate.complete();
      expect((await second).kind, QuotationSaveKind.saved);
      expect(env.generated.map((m) => m.propertyTitle),
          ['Apartment 306', 'Apartment 307'],
          reason: 'the retry rendered its own PDF from its own data');
      expect(env.server.of(QuotationMediaRole.quotationPdf, 'authorize'),
          hasLength(1),
          reason: 'only the retry published a PDF');
      expect(env.server.of(QuotationMediaRole.quotationPdf, 'confirm'),
          hasLength(1));
      final pdfFiles = env.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .toList();
      expect(pdfFiles, hasLength(1),
          reason: 'only the published PDF remains; the discarded one is gone');
      expect(pdfFiles.single.path, contains(env.server.pdfId!));
    });

    test('a failed save leaves no generated PDF behind once its renderer finishes',
        () async {
      final env = await _env();
      _fill(env.vm);
      env.server.saveError =
          const QuotationException(QuotationFailure.versionConflict);

      expect((await env.vm.performSave()).kind, QuotationSaveKind.failed);
      await env.vm.backgroundWorkSettled();

      expect(env.generated, hasLength(1),
          reason: 'the PDF was prepared beside the save');
      final pdfFiles = env.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'));
      expect(pdfFiles, isEmpty);
      expect(env.server.media, isEmpty, reason: 'nothing was published');
    });

    test('a save still waiting for a discarded renderer does not start once the form is gone',
        () async {
      final pdfGate = Completer<void>();
      final env = await _env(pdfGate: pdfGate);
      _fill(env.vm);
      env.server.saveError =
          const QuotationException(QuotationFailure.network);
      expect((await env.vm.performSave()).kind, QuotationSaveKind.failed);

      final retry = env.vm.performSave();
      await pumpEventQueue();
      env.vm.dispose();
      pdfGate.complete();

      expect((await retry).kind, QuotationSaveKind.busy);
      expect(env.server.savedIds, hasLength(1), reason: 'no second save was sent');
      await env.vm.backgroundWorkSettled();
      final pdfFiles = env.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'));
      expect(pdfFiles, isEmpty);
    });

    test('one save sends one refresh signal, however many steps it took',
        () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_signal_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir);
      var signals = 0;
      final sub = CoreEntityMutationNotifier.changes.listen((_) => signals++);
      addTearDown(sub.cancel);

      // Aggregate, logo and PDF: three mutations.
      final withLogo = await _env(logoPicker: () async => picked);
      _fill(withLogo.vm);
      await withLogo.vm.pickLogo();
      expect((await withLogo.vm.performSave()).kind, QuotationSaveKind.saved);
      expect(withLogo.server.media.where((c) => c.op == 'confirm'),
          hasLength(2));
      expect(signals, 1);

      // A save that fails changes nothing and signals nothing.
      final failing = await _env();
      _fill(failing.vm);
      failing.server.saveError =
          const QuotationException(QuotationFailure.network);
      await failing.vm.performSave();
      expect(signals, 1);

      // The aggregate was saved even though the PDF was not.
      final pdfFails = await _env(pdfFails: true);
      _fill(pdfFails.vm);
      await pdfFails.vm.performSave();
      expect(signals, 2);
    });
  });

  group('reopen and edit', () {
    test('loads the whole aggregate into the form and keeps its version', () async {
      final server = _existing(version: 3, logo: _logoA, pdf: _pdfA);
      final env = await _env(editId: 'q-existing', server: server);

      await env.vm.loadForEdit();

      final vm = env.vm;
      expect(vm.isLoadingExisting, isFalse);
      expect(vm.loadFailed, isFalse);
      expect(vm.isEditMode, isTrue);
      expect(vm.version, 3);
      expect(vm.quotationId, 'q-existing');
      expect(vm.propertyTitle, 'Marina Tower 12');
      expect(vm.propertyType, 'Apartment');
      expect(vm.parking, isTrue);
      expect(vm.date, '2026-10-01');
      expect(vm.startDate, '2026-10-01');
      expect(vm.endDate, '2027-09-30');
      expect(vm.officeName, 'Realtig');
      expect(vm.totalAmount, '120000');
      expect(vm.numberOfInstallments, '2');
      expect(vm.paymentType, 'cheque');
      expect(vm.insuranceAmount, '2000.5');
      expect(vm.insuranceReturnable, isTrue);
      expect(vm.customNote, 'note');
      expect(vm.welcomeMessageMode, WelcomeMessageMode.custom);
      expect(vm.customWelcomeMessage, 'Hello there');
      expect(vm.downpayments.map((d) => d.date), ['2026-10-01', '2027-04-01']);
      expect(vm.downpayments.map((d) => d.amount), ['60000.00', '60000.00']);
      expect(vm.downpayments.map((d) => d.method), ['cheque', 'cheque']);
      expect(vm.govPercentOfTotalRent, '2');
      expect(vm.govMunicipality, '100');
      expect(vm.govTotal, '2500.00');
      expect(vm.administrativeFees.single.title, 'Commission');
      expect(vm.administrativeFees.single.amount, '5000');
      expect(vm.admTotal, '5000.00');
      expect(vm.boundLogoMediaId, _logoA);
      expect(vm.boundPdfMediaId, _pdfA);
      expect(vm.officeLogoFileName, 'office-logo.png');
      expect(vm.hasLogoSelected, isTrue);
    });

    test('a Quotation that does not exist (or was deleted) fails to load cleanly',
        () async {
      final env = await _env(editId: 'gone'); // the server holds nothing
      await env.vm.loadForEdit();
      expect(env.vm.loadFailed, isTrue);
      expect(env.vm.isLoadingExisting, isFalse);
    });

    test('saving an edit is an update against exactly the loaded version', () async {
      final server = _existing(version: 3, pdf: _pdfA);
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();

      env.vm.setOfficeName('Renamed office');
      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.saved);
      expect(outcome.messageKey, 'quotationUpdatedSuccessfully');
      expect(server.savedIds.single, 'q-existing');
      expect(server.savedExpectedVersions.single, 3);
      expect(server.savedModels.single.officeName, 'Renamed office');
      // The PDF was regenerated and replaced the bound one, by its id.
      expect(server.of(QuotationMediaRole.quotationPdf, 'authorize').single.expected,
          _pdfA);
      expect(env.vm.version, server.version);
    });

    test('a loaded schedule and totals are not recalculated over when a field changes',
        () async {
      final server = _existing();
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();

      env.vm.setNumberOfInstallments('5'); // would regenerate a fresh schedule

      expect(env.vm.downpayments, hasLength(2),
          reason: 'the saved schedule counts as entered');
      expect(env.vm.endDate, '2027-09-30');
    });

    test('a newer version on the server is a conflict: nothing is overwritten', () async {
      final server = _existing(version: 3);
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();

      server.version = 4; // another device saved in the meantime
      env.vm.setOfficeName('My stale edit');
      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.failed);
      expect(outcome.failure, QuotationFailure.versionConflict);
      expect(outcome.messageKey, 'quotationVersionConflict');
      expect(server.media, isEmpty, reason: 'no PDF or logo work after a conflict');
      expect(server.version, 4, reason: 'the newer server version is untouched');
      expect(env.vm.version, 3, reason: 'the form still names what it was based on');
    });

    test('a deleted Quotation cannot be saved over', () async {
      final server = _existing(version: 3);
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();

      server.saveError = const QuotationException(QuotationFailure.deleted);
      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.failed);
      expect(outcome.messageKey, 'quotationNoLongerAvailable');
    });
  });

  group('office logo', () {
    test('a picked logo is bound after the Quotation is saved, replacing nothing', () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_pick_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir);
      final env = await _env(logoPicker: () async => picked);

      final vm = env.vm;
      _fill(vm);
      expect(await vm.pickLogo(), QuotationLogoPick.selected);
      expect(vm.selectedLogoFile?.path, picked.path);
      expect(vm.officeLogoFileName, 'logo.png');
      expect(vm.hasLogoSelected, isTrue);
      expect(env.server.media, isEmpty, reason: 'nothing is sent on select');

      final outcome = await vm.performSave();

      expect(outcome.kind, QuotationSaveKind.saved);
      final logoOps = env.server.media
          .where((c) => c.role == QuotationMediaRole.officeLogo)
          .map((c) => c.op)
          .toList();
      expect(logoOps, ['authorize', 'upload', 'confirm']);
      expect(env.server.logoId, isNotNull);
      expect(vm.boundLogoMediaId, env.server.logoId);
      expect(vm.selectedLogoFile, isNull);
      // The aggregate was saved before any media: the Quotation exists to bind to.
      expect(env.server.savedIds, hasLength(1));
      // The PDF drew the logo from the local file just picked.
      expect(env.generated.single.officeLogoUrl, startsWith('file:'));
    });

    test('a picked file that is not an accepted logo is turned away', () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_pdf_');
      addTearDown(() => dir.delete(recursive: true));
      final pdf = File('${dir.path}${Platform.pathSeparator}doc.pdf');
      await pdf.writeAsBytes(_pdfBytes);

      final env = await _env(logoPicker: () async => pdf);
      expect(await env.vm.pickLogo(), QuotationLogoPick.rejected);
      expect(env.vm.selectedLogoFile, isNull);
      expect(env.vm.hasLogoSelected, isFalse);
      expect(env.vm.officeLogoFileName, isEmpty);
    });

    test('dismissing the picker changes nothing', () async {
      final env = await _env(logoPicker: () async => null);
      expect(await env.vm.pickLogo(), QuotationLogoPick.dismissed);
      expect(env.vm.hasLogoSelected, isFalse);
    });

    test('a failed replacement upload keeps the bound logo, keeps the Quotation saved, and can be retried',
        () async {
      final server = _existing(version: 3, logo: _logoA, pdf: _pdfA);
      final dir = await Directory.systemTemp.createTemp('quotation_vm_logo_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir, 'new-logo.png');

      final env = await _env(
          editId: 'q-existing', server: server, logoPicker: () async => picked);
      await env.vm.loadForEdit();
      expect(await env.vm.pickLogo(), QuotationLogoPick.selected);

      server.failUpload.add(QuotationMediaRole.officeLogo);
      final failed = await env.vm.performSave();

      expect(failed.kind, QuotationSaveKind.mediaIncomplete);
      expect(failed.logoFailure, QuotationMediaFailure.interrupted);
      expect(env.vm.isLoading, isFalse);
      expect(env.vm.saveProgress, QuotationSaveProgress.idle);
      expect(failed.pdfFailure, isNull, reason: 'the PDF is independent of the logo');
      expect(failed.messageKey, 'quotationSavedMediaFailure');
      expect(server.savedIds, ['q-existing'], reason: 'the aggregate was saved');
      expect(server.logoId, _logoA,
          reason: 'the previously bound logo survives a failed replacement');
      expect(env.vm.boundLogoMediaId, _logoA);
      expect(env.vm.selectedLogoFile, isNotNull, reason: 'kept, so a retry can resend it');
      expect(server.of(QuotationMediaRole.officeLogo, 'confirm'), isEmpty);
      expect(server.of(QuotationMediaRole.officeLogo, 'remove'), isEmpty);

      // The retry is an update, and re-sends the same upload identity.
      server.failUpload.clear();
      final retried = await env.vm.performSave();

      expect(retried.kind, QuotationSaveKind.saved);
      expect(server.savedExpectedVersions.length, 2);
      expect(server.savedExpectedVersions.last, isNotNull);
      final authorizes =
          server.of(QuotationMediaRole.officeLogo, 'authorize').toList();
      expect(authorizes, hasLength(2));
      expect(authorizes[0].mediaId, authorizes[1].mediaId,
          reason: 'the same logo keeps one upload identity across retries');
      expect(server.logoId, authorizes.last.mediaId);
      expect(env.vm.boundLogoMediaId, server.logoId);
      expect(env.vm.selectedLogoFile, isNull);
    });

    test('clearing a bound logo removes it on save, against its confirmed id', () async {
      final server = _existing(version: 3, logo: _logoA, pdf: _pdfA);
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();

      env.vm.clearLogo();
      expect(env.vm.hasLogoSelected, isFalse);
      expect(env.vm.officeLogoFileName, isEmpty);
      expect(server.media, isEmpty, reason: 'nothing is removed until save');

      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.saved);
      final removes = server.of(QuotationMediaRole.officeLogo, 'remove').toList();
      expect(removes, hasLength(1));
      expect(removes.single.expected, _logoA);
      expect(server.logoId, isNull);
      expect(env.vm.boundLogoMediaId, isNull);
      expect(env.generated.single.officeLogoUrl, isNull,
          reason: 'the regenerated PDF no longer draws the removed logo');
    });

    test('clearing a logo that was never uploaded sends nothing', () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_clear_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir);
      final env = await _env(logoPicker: () async => picked);
      _fill(env.vm);
      await env.vm.pickLogo();

      env.vm.clearLogo();
      await env.vm.performSave();

      expect(env.server.media.where((c) => c.role == QuotationMediaRole.officeLogo),
          isEmpty);
    });

    test('an existing logo is drawn into the regenerated PDF through a signed link',
        () async {
      final server = _existing(version: 3, logo: _logoA, pdf: _pdfA);
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();

      await env.vm.performSave();

      expect(env.generated.single.officeLogoUrl, 'https://signed.example/logo');
      expect(server.of(QuotationMediaRole.officeLogo, 'authorize'), isEmpty,
          reason: 'an unchanged logo is not re-uploaded');
      expect(server.logoId, _logoA);
      expect(env.generated, hasLength(1));
      expect(server.signedReads, 1,
          reason: 'Save reuses the still-valid preview link for the same logo');
      expect(server.mediaStateReads, 0,
          reason: 'confirmed media version already came from the Worker');
    });

    test('an expired preview link is refreshed before PDF rendering', () async {
      final server = _existing(version: 3, logo: _logoA, pdf: _pdfA)
        ..signedExpiry = DateTime.now().subtract(const Duration(seconds: 1));
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();
      expect(server.signedReads, 1);

      expect((await env.vm.performSave()).kind, QuotationSaveKind.saved);
      expect(server.signedReads, 2);
    });

    testWidgets('prepared background removal is reused through toggle and Save',
        (tester) async {
      final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('quotation_vm_background_')))!;
      addTearDown(() => dir.delete(recursive: true));
      final original = (await tester.runAsync(() => _logoFile(dir)))!;
      final processed = (await tester.runAsync(
          () => _logoFile(dir, 'logo-transparent.png')))!;
      final optimized = (await tester.runAsync(
          () => _logoFile(dir, 'logo-small.png')))!;
      final removal = _FakeLogoBackgroundRemoval(processed);
      final optimizer = _FakeLogoOptimizer(output: optimized);
      final env = (await tester.runAsync(() => _env(
            logoPicker: () async => original,
            backgroundRemoval: removal,
            logoOptimizer: optimizer,
          )))!;
      const contextKey = ValueKey('quotation-logo-form-context');
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: const SizedBox(key: contextKey),
      ));
      await tester.pumpAndSettle();
      final formContext = tester.element(find.byKey(contextKey));

      await tester.runAsync(() async {
        final vm = env.vm;
        _fill(vm);
        expect(await vm.pickLogo(), QuotationLogoPick.selected);
        await vm.setRemoveLogoBackground(formContext, true);
        expect(removal.calls, 1);
        expect(vm.officeLogoPreviewFile?.path, processed.path);
        await vm.setRemoveLogoBackground(formContext, false);
        expect(vm.officeLogoPreviewFile?.path, original.path);
        await vm.setRemoveLogoBackground(formContext, true);
        expect(removal.calls, 1);
        expect(vm.officeLogoPreviewFile?.path, processed.path);

        expect((await vm.performSave()).kind, QuotationSaveKind.saved);
        expect(removal.calls, 1,
            reason: 'Save must use the already previewed PNG');
        expect(env.server.of(QuotationMediaRole.officeLogo, 'upload'),
            hasLength(1));
        expect(env.server.uploadedLogoPath, processed.path,
            reason: 'Save must upload the prepared result');
        expect(env.generated, hasLength(1));
        expect(env.generated.single.officeLogoUrl,
            Uri.file(processed.path).toString(),
            reason: 'the transparent PNG wins over the resized original');
        expect(optimizer.sources, [original.path],
            reason: 'the original was shrunk once, when it was picked');
      });
    });

    test('PDF preparation overlaps logo transfer but publication waits for logo',
        () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_overlap_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir);
      final server = _FakeServer()
        ..logoUploadGate = Completer<void>()
        ..logoUploadStarted = Completer<void>();
      final pdfStarted = Completer<void>();
      final env = await _env(
        logoPicker: () async => picked,
        server: server,
        pdfStarted: pdfStarted,
      );
      _fill(env.vm);
      await env.vm.pickLogo();

      final saving = env.vm.performSave();
      await Future.wait([pdfStarted.future, server.logoUploadStarted!.future]);
      expect(server.of(QuotationMediaRole.officeLogo, 'confirm'), isEmpty);
      expect(server.of(QuotationMediaRole.quotationPdf, 'authorize'), isEmpty,
          reason: 'PDF upload waits for logo synchronization');

      server.logoUploadGate!.complete();
      expect((await saving).kind, QuotationSaveKind.saved);
      expect(env.generated, hasLength(1));
      expect(server.media.indexWhere((call) =>
              call.role == QuotationMediaRole.quotationPdf &&
              call.op == 'authorize'),
          greaterThan(server.media.indexWhere((call) =>
              call.role == QuotationMediaRole.officeLogo &&
              call.op == 'confirm')));
    });

    test('the logo is shrunk when picked; Save uploads and draws that copy, not the original',
        () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_opt_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir, 'camera.png');
      final small = await _logoFile(dir, 'camera-small.png');
      final optimizer = _FakeLogoOptimizer(output: small);
      final env = await _env(
          logoPicker: () async => picked, logoOptimizer: optimizer);
      _fill(env.vm);

      expect(await env.vm.pickLogo(), QuotationLogoPick.selected);
      expect(optimizer.sources, [picked.path],
          reason: 'the copy is made at pick time');
      expect(env.server.media, isEmpty);

      expect((await env.vm.performSave()).kind, QuotationSaveKind.saved);

      expect(optimizer.sources, hasLength(1), reason: 'Save does no image work');
      expect(env.server.uploadedLogoPath, small.path);
      expect(env.generated.single.officeLogoUrl, Uri.file(small.path).toString());
      expect(env.vm.officeLogoPreviewFile?.path, small.path);
      expect(await picked.readAsBytes(), _png,
          reason: 'the picked image itself is never modified');
    });

    test('Save waits for a logo copy that is still being made instead of starting another',
        () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_wait_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir, 'camera.png');
      final small = await _logoFile(dir, 'camera-small.png');
      final gate = Completer<void>();
      final optimizer = _FakeLogoOptimizer(output: small, gate: gate);
      final env = await _env(
          logoPicker: () async => picked, logoOptimizer: optimizer);
      _fill(env.vm);
      await env.vm.pickLogo();

      final saving = env.vm.performSave();
      await pumpEventQueue();
      expect(env.server.savedIds, hasLength(1),
          reason: 'the database save does not wait for the logo copy');
      expect(env.server.of(QuotationMediaRole.officeLogo, 'authorize'), isEmpty);

      gate.complete();
      expect((await saving).kind, QuotationSaveKind.saved);
      expect(optimizer.sources, hasLength(1));
      expect(env.server.uploadedLogoPath, small.path);
    });

    for (final entry in {
      'is already small': _FakeLogoOptimizer(),
      'cannot be optimized': _FakeLogoOptimizer(error: StateError('decode')),
    }.entries) {
      test('a logo that ${entry.key} is sent as it was picked', () async {
        final dir = await Directory.systemTemp.createTemp('quotation_vm_asis_');
        addTearDown(() => dir.delete(recursive: true));
        final picked = await _logoFile(dir, 'logo.png');
        final env = await _env(
            logoPicker: () async => picked, logoOptimizer: entry.value);
        _fill(env.vm);
        expect(await env.vm.pickLogo(), QuotationLogoPick.selected);

        expect((await env.vm.performSave()).kind, QuotationSaveKind.saved);
        expect(env.server.uploadedLogoPath, picked.path);
        expect(env.generated.single.officeLogoUrl,
            Uri.file(picked.path).toString());
      });
    }

    test('Save never starts background removal when the option was not chosen',
        () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_nobg_');
      addTearDown(() => dir.delete(recursive: true));
      final picked = await _logoFile(dir, 'logo.png');
      final processed = await _logoFile(dir, 'logo-transparent.png');
      final removal = _FakeLogoBackgroundRemoval(processed);
      final env = await _env(
          logoPicker: () async => picked, backgroundRemoval: removal);
      _fill(env.vm);
      await env.vm.pickLogo();

      expect((await env.vm.performSave()).kind, QuotationSaveKind.saved);

      expect(removal.calls, 0);
      expect(env.server.uploadedLogoPath, picked.path);
    });

    test('a replaced or cleared logo removes its temporary copy', () async {
      final dir = await Directory.systemTemp.createTemp('quotation_vm_temp_');
      addTearDown(() => dir.delete(recursive: true));
      final first = await _logoFile(dir, 'first.png');
      final second = await _logoFile(dir, 'second.png');
      final queue = [first, second];
      final optimizer = _FakeLogoOptimizer(
        build: (source) => _logoFile(
            dir, '${source.uri.pathSegments.last}-small.png'),
      );
      final env = await _env(
          logoPicker: () async => queue.removeAt(0), logoOptimizer: optimizer);
      final firstCopy = File('${dir.path}${Platform.pathSeparator}first.png-small.png');
      final secondCopy = File('${dir.path}${Platform.pathSeparator}second.png-small.png');

      await env.vm.pickLogo();
      await env.vm.backgroundWorkSettled();
      expect(firstCopy.existsSync(), isTrue);

      await env.vm.pickLogo();
      await env.vm.backgroundWorkSettled();
      expect(firstCopy.existsSync(), isFalse, reason: 'replaced');
      expect(secondCopy.existsSync(), isTrue);
      expect(first.existsSync() && second.existsSync(), isTrue,
          reason: 'the picked images are never deleted');

      env.vm.clearLogo();
      await env.vm.backgroundWorkSettled();
      expect(secondCopy.existsSync(), isFalse, reason: 'cleared');
      expect(second.existsSync(), isTrue);
    });
  });

  group('PDF', () {
    test('a failed PDF leaves the saved Quotation intact and the next save is an update',
        () async {
      final env = await _env(pdfFails: true);
      _fill(env.vm);

      final first = await env.vm.performSave();

      expect(first.kind, QuotationSaveKind.mediaIncomplete);
      expect(first.pdfFailure, QuotationMediaFailure.unknown);
      expect(env.vm.isLoading, isFalse);
      expect(env.vm.saveProgress, QuotationSaveProgress.idle);
      expect(first.messageKey, 'quotationSavedMediaFailure');
      expect(env.server.version, 1);
      expect(env.server.pdfId, isNull);
      expect(env.server.media, isEmpty);
      expect(env.vm.version, 1);

      final second = await env.vm.performSave();
      expect(second.kind, QuotationSaveKind.mediaIncomplete);
      expect(env.server.savedExpectedVersions, [null, 1],
          reason: 'the Quotation exists now: a retry is an update, never a second create');
      expect(env.server.savedIds.toSet(), hasLength(1));
    });

    test('a failed PDF upload never removes the previously bound PDF', () async {
      final server = _existing(version: 3, pdf: _pdfA);
      final env = await _env(editId: 'q-existing', server: server);
      await env.vm.loadForEdit();
      server.failUpload.add(QuotationMediaRole.quotationPdf);

      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.mediaIncomplete);
      expect(outcome.pdfFailure, QuotationMediaFailure.interrupted);
      expect(env.vm.isLoading, isFalse);
      expect(env.vm.saveProgress, QuotationSaveProgress.idle);
      expect(server.pdfId, _pdfA, reason: 'the previous PDF is still the bound one');
      expect(server.of(QuotationMediaRole.quotationPdf, 'remove'), isEmpty);
      expect(env.vm.boundPdfMediaId, _pdfA);
      // The generated file is private data and is not left behind.
      final leftovers = env.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'));
      expect(leftovers, isEmpty);
    });
  });

  group('messages', () {
    test('every way the Quotation can fail to save tells the user in their language',
        () async {
      const expected = {
        QuotationFailure.versionConflict: 'quotationVersionConflict',
        QuotationFailure.notFound: 'quotationNoLongerAvailable',
        QuotationFailure.deleted: 'quotationNoLongerAvailable',
        QuotationFailure.invalidPayload: 'quotationInvalidData',
        QuotationFailure.notSignedIn: 'quotationSessionExpired',
        QuotationFailure.permissionDenied: 'quotationSessionExpired',
        QuotationFailure.network: 'quotationNetworkError',
        QuotationFailure.idConflict: 'quotationSaveFailed',
        QuotationFailure.unknown: 'quotationSaveFailed',
      };
      for (final entry in expected.entries) {
        final env = await _env();
        _fill(env.vm);
        env.server.saveError = QuotationException(entry.key);

        final outcome = await env.vm.performSave();

        expect(outcome.kind, QuotationSaveKind.failed, reason: entry.key.name);
        expect(outcome.failure, entry.key);
        expect(outcome.messageKey, entry.value, reason: entry.key.name);
      }
    });

    test('an unexpected error saving is the generic failure, never raw text', () async {
      final env = await _env();
      _fill(env.vm);
      env.server.saveError = StateError('SQLSTATE 23505 duplicate key ...');

      final outcome = await env.vm.performSave();

      expect(outcome.kind, QuotationSaveKind.failed);
      expect(outcome.failure, QuotationFailure.unknown);
      expect(outcome.messageKey, 'quotationSaveFailed');
      expect(env.toasts, isEmpty);
    });
  });
}
