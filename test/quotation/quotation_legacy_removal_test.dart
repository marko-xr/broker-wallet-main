// Source guards for the Quotation migration.
//
// These read the Quotation feature's own source and fail if the active path
// drifts back to the legacy backend or crosses a security boundary:
//  - no Firestore / Firebase Storage / Hive anywhere in the Quotation feature;
//  - the only client write is `save_quotation` (plus the soft-delete column);
//    child tables and the server-controlled media columns are never written;
//  - no server credential or storage secret is present in Flutter source.
// They also check that every message the feature can show exists in both
// languages. They are static checks: they prove the code's shape, not hosted
// behaviour.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final Directory _quotationDir =
    Directory('lib/src/views/Screens/home/quotation');

List<File> _sources() => _quotationDir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _strip(String source) => source
    // Line and block comments are documentation, not behaviour.
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  test('the Quotation feature directory is present and non-trivial', () {
    expect(_quotationDir.existsSync(), isTrue);
    final names = _sources().map((f) => f.uri.pathSegments.last).toSet();
    expect(names, containsAll(<String>{
      'quotation_service.dart',
      'supabase_quotation_service.dart',
      'r2_quotation_media_service.dart',
      'quotation_media_workflow.dart',
      'quotation_supabase_mapper.dart',
      'add_quotation_viewmodel.dart',
      'list_quotations_viewmodel.dart',
      'pdf_generation_service.dart',
    }));
  });

  group('legacy backend is gone from the active Quotation path', () {
    const forbidden = <String>[
      'cloud_firestore',
      'firebase_storage',
      'firebase_core',
      'FirebaseFirestore',
      'FirebaseStorage',
      'FirebaseAuth',
      'hive_flutter',
      'Hive.',
      'DocumentSnapshot',
      'Timestamp.',
      'uploadPdfToStorage',
      'saveQuotationWithMediaFast',
      'fast_media_upload_service',
      'FastMediaUploadService',
      'QuotaHelper',
    ];

    for (final token in forbidden) {
      test('no reference to $token', () {
        for (final file in _sources()) {
          final code = _strip(file.readAsStringSync());
          expect(code.contains(token), isFalse,
              reason: '${file.path} still references $token');
        }
      });
    }

    test('the PDF is identified by media id, never by a stored URL', () {
      for (final file in _sources()) {
        final code = _strip(file.readAsStringSync());
        expect(RegExp(r'\bpdfUrl\b').hasMatch(code), isFalse,
            reason: '${file.path} still uses a stored pdfUrl');
        expect(code.contains('local://'), isFalse,
            reason: '${file.path} still uses the legacy local:// scheme');
      }
    });
  });

  group('security boundaries', () {
    test('the only table write is the soft-delete column; everything else is RPC or read',
        () {
      var updates = 0;
      for (final file in _sources()) {
        final code = _strip(file.readAsStringSync());
        // Every table access is `.from('<table>').<verb>(`.
        for (final match
            in RegExp(r"\.from\('([a-z_]+)'\)\s*\.(\w+)\(").allMatches(code)) {
          final table = match.group(1);
          final verb = match.group(2);
          expect(const {'select', 'update'}.contains(verb), isTrue,
              reason: '${file.path}: $table is accessed with $verb');
          if (verb == 'update') {
            updates++;
            expect(table, 'quotations');
            expect(file.path.endsWith('supabase_quotation_service.dart'), isTrue);
            expect(
              RegExp(r"\.from\('quotations'\)\s*\.update\(\s*\{\s*'deleted_at'\s*:")
                  .hasMatch(code),
              isTrue,
              reason: 'the one update must set only deleted_at',
            );
          }
        }
      }
      expect(updates, 1, reason: 'exactly one soft-delete write');
    });

    test('children and the server-controlled media columns are never written', () {
      for (final file in _sources()) {
        final code = _strip(file.readAsStringSync());
        for (final table in const [
          'quotation_downpayments',
          'quotation_government_fees',
          'quotation_administrative_fees',
          'quotation_media',
          'media_objects',
        ]) {
          expect(
            RegExp("\\.from\\('$table'\\)\\s*\\.(insert|update|upsert|delete)")
                .hasMatch(code),
            isFalse,
            reason: '${file.path} writes $table',
          );
        }
        // A header key for a media column would be a client write of it.
        expect(
          RegExp(r"'(office_logo_media_id|pdf_media_id)'\s*:").hasMatch(code),
          isFalse,
          reason: '${file.path} builds a map keyed by a media column',
        );
      }
    });

    test('the aggregate is saved only through save_quotation', () {
      final service = File(
              'lib/src/views/Screens/home/quotation/services/supabase_quotation_service.dart')
          .readAsStringSync();
      expect(service.contains("'save_quotation'"), isTrue);
      final rpcCalls = RegExp(r"\.rpc\(\s*'([a-z_]+)'").allMatches(service);
      expect(rpcCalls.map((m) => m.group(1)).toSet(), {'save_quotation'},
          reason: 'the confirm/remove media RPCs are service-role only and '
              'must never be called from the client');
    });

    test('no server credential, storage secret or signing code is in Flutter source',
        () {
      const secrets = [
        'service_role',
        'SERVICE_ROLE',
        'SUPABASE_SECRET',
        'sb_secret',
        'R2_ACCESS_KEY',
        'R2_SECRET',
        'aws4',
        'AwsClient',
        'X-Amz-Signature',
        'STAGING_TEST_KEY',
        'Staging-Key',
      ];
      for (final file in _sources()) {
        final code = file.readAsStringSync();
        for (final secret in secrets) {
          expect(code.contains(secret), isFalse,
              reason: '${file.path} contains $secret');
        }
      }
    });

    test('a signed URL is never written to state, a file name or a log', () {
      for (final file in _sources()) {
        final code = _strip(file.readAsStringSync());
        // Diagnostics may name only fixed categories.
        for (final match in RegExp(r'debugPrint\(([^;]*)\)').allMatches(code)) {
          final text = match.group(1)!;
          expect(RegExp(r'url|Url|URL|path|key|token|presigned', caseSensitive: false)
                  .hasMatch(text),
              isFalse,
              reason: '${file.path} logs ${match.group(0)}');
        }
      }
    });

    test('the Worker address comes from R2Config, never a literal', () {
      final media = File(
              'lib/src/views/Screens/home/quotation/services/r2_quotation_media_service.dart')
          .readAsStringSync();
      expect(media.contains('R2Config.workerUrl'), isTrue);
      expect(media.contains('brokerwallet.ae'), isFalse);
      expect(media.contains('workers.dev'), isFalse);
    });
  });

  group('localization', () {
    const keys = <String>[
      'quotationTitleRequired',
      'quotationAdminFeeTitleRequired',
      'quotationInvalidData',
      'quotationVersionConflict',
      'quotationNoLongerAvailable',
      'quotationSessionExpired',
      'quotationNetworkError',
      'quotationSaveFailed',
      'quotationUpdatedSuccessfully',
      'quotationSavedMediaFailure',
      'quotationLoadFailed',
      'quotationLogoUnsupported',
      'quotationPdfUnavailable',
      'quotationDeleteFailed',
      'quotationListLoadFailed',
    ];

    Map<String, dynamic> arb(String language) => jsonDecode(File(
            'lib/src/common/localization/app_$language.arb')
        .readAsStringSync()) as Map<String, dynamic>;

    test('every Quotation message exists, non-empty, in English and Arabic', () {
      final en = arb('en');
      final ar = arb('ar');
      for (final key in keys) {
        expect((en[key] as String?)?.trim(), isNotEmpty, reason: 'en $key');
        expect((ar[key] as String?)?.trim(), isNotEmpty, reason: 'ar $key');
        expect(en[key], isNot(key));
        expect(ar[key], isNot(en[key]), reason: '$key is translated');
      }
    });

    test('the Arabic messages are Arabic text', () {
      final ar = arb('ar');
      final arabic = RegExp(r'[؀-ۿ]');
      for (final key in keys) {
        expect(arabic.hasMatch(ar[key] as String), isTrue, reason: 'ar $key');
      }
    });

    test('every message the Quotation screens can show is defined, and none is orphaned',
        () {
      final used = <String>{};
      for (final file in _sources()) {
        final name = file.uri.pathSegments.last;
        if (!const {
          'add_quotation_viewmodel.dart',
          'list_quotations_viewmodel.dart',
          'add_quotation_view.dart',
          'list_quotation_view.dart',
        }.contains(name)) {
          continue;
        }
        // A message key is a `quotationXxx` literal in the screens and their
        // view-models (the plain `quotation` title key has no suffix).
        used.addAll(RegExp(r"'(quotation[A-Z][A-Za-z]+)'")
            .allMatches(file.readAsStringSync())
            .map((m) => m.group(1)!));
      }
      expect(used, isNotEmpty);
      expect(used, containsAll(keys),
          reason: 'a defined message that no screen can show is dead text');
      final en = arb('en');
      final ar = arb('ar');
      for (final key in used) {
        expect(en.containsKey(key), isTrue, reason: 'en is missing $key');
        expect(ar.containsKey(key), isTrue, reason: 'ar is missing $key');
      }
    });
  });
}
