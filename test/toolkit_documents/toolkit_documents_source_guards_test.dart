// Source guards for checkpoint C1: the cloud document foundation is inactive and
// its backend sources keep their security shape. These read files only; they do
// not prove production behavior (the SQL is exercised by
// supabase/tests/toolkit_documents_test.sql and the Worker by
// cloudflare/workers/r2-profile-upload/test/toolkit_documents.test.mjs).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

List<File> dartFilesUnder(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  const migration =
      'supabase/migrations/20261019100000_toolkit_cloud_documents.sql';
  const worker = 'cloudflare/workers/r2-profile-upload/worker.js';
  const module = 'cloudflare/workers/r2-profile-upload/toolkit_documents.js';

  group('inactive in the app', () {
    // The four tools are wired to the cloud, each through its wiring and its
    // list view model (Combine PDFs also through its screen, which shows the
    // state of a document), and the one status line widget. Every other file
    // stays free of the foundation.
    const wired = <String>{
      'lib/src/services/combine_pdf/combine_wiring.dart',
      'lib/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart',
      'lib/src/views/Screens/home/Toolkit/combine_pdfs_view.dart',
      'lib/src/services/scanner/scanner_wiring.dart',
      'lib/src/viewmodels/scanner/scanner_viewmodel.dart',
      'lib/src/services/image_to_pdf/image_pdf_wiring.dart',
      'lib/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart',
      'lib/src/services/signature/signature_wiring.dart',
      'lib/src/viewmodels/signature/signature_library_viewmodel.dart',
      'lib/src/views/Widgets/toolkit_cloud_status_line.dart',
    };

    test(
        'only the four tools\' wiring and view models (and the status line) '
        'import it', () {
      final importers = <String>{};
      for (final file in dartFilesUnder('lib')) {
        final path = file.path.replaceAll('\\', '/');
        if (path.contains('/services/toolkit_documents/')) continue;
        if (read(file.path).contains('toolkit_documents/')) {
          importers.add(path);
        }
      }
      expect(importers, wired);
    });

    test('the cloud is on by default; the staging gate is debug-only', () {
      final models = read(
          'lib/src/services/toolkit_documents/toolkit_document_models.dart');
      expect(models, contains("'TOOLKIT_CLOUD_DOCUMENTS'"));
      expect(models, contains('defaultValue: true'));
      expect(models, contains('static bool get isActive => enabled;'));
      expect(models, isNot(contains('kDebugMode')));
      final config = read('lib/src/config/r2_config.dart');
      expect(config, contains('debugBuild: kDebugMode'));
      expect(config, isNot(contains('kReleaseMode')));
      final wiring =
          read('lib/src/services/toolkit_documents/toolkit_cloud_wiring.dart');
      expect(wiring, contains('ToolkitCloudDocumentsFeature.isActive'));
      expect(wiring, contains('R2Config.isToolkitConfigured'));
    });

    test('only the Toolkit service uses the Toolkit address and gate key', () {
      for (final file in dartFilesUnder('lib')) {
        final path = file.path.replaceAll('\\', '/');
        if (path.endsWith('lib/src/config/r2_config.dart')) continue;
        if (path.contains('/services/toolkit_documents/')) continue;
        final text = read(file.path);
        final usesToolkitConfig = text.contains('toolkitWorkerUrl') ||
            text.contains('toolkitStagingKey') ||
            text.contains('isToolkitConfigured');
        expect(usesToolkitConfig, isFalse, reason: path);
      }
    });

    test('the four tools still use their own local stores', () {
      for (final store in [
        'lib/src/services/scanner/scanner_document_store.dart',
        'lib/src/services/combine_pdf/combine_pdf_store.dart',
        'lib/src/services/image_to_pdf/image_pdf_store.dart',
        'lib/src/services/signature/signature_store.dart',
      ]) {
        final text = read(store);
        expect(text, isNot(contains('toolkit')), reason: store);
        expect(text, isNot(contains('r2_')), reason: store);
      }
    });

    test('the foundation never deletes a local document', () {
      final sources = dartFilesUnder('lib/src/services/toolkit_documents');
      final deletions = <String>[];
      for (final file in sources) {
        // `_library.delete(` is the account copy's delete (a request to the
        // server that never touches a file); it is not a file deletion.
        final text =
            read(file.path).replaceAll('_library.delete(', '_library_');
        // Only temporary and journal files are ever deleted or replaced.
        for (final match
            in RegExp(r'\.delete\(|deleteSync\(').allMatches(text)) {
          final line = text.substring(0, match.start).split('\n').length;
          deletions.add('${file.path.split(RegExp(r'[\\/]')).last}:$line');
        }
      }
      for (final site in deletions) {
        final name = site.split(':').first;
        expect(
          {
            'toolkit_document_download_service.dart',
            'toolkit_document_sync_journal.dart',
            'r2_toolkit_document_service.dart',
          },
          contains(name),
          reason: 'only the download part file, the journal and a failed '
              'download target may be deleted; found $site',
        );
      }
    });

    test('no code path stores or logs a URL or an object key', () {
      for (final file in dartFilesUnder('lib/src/services/toolkit_documents')) {
        final text = read(file.path);
        expect(text, isNot(contains('debugPrint')), reason: file.path);
        expect(text, isNot(contains('print(')), reason: file.path);
        expect(text, isNot(contains('objectKey')), reason: file.path);
        expect(text, isNot(contains('object_key')), reason: file.path);
      }
    });
  });

  group('Worker', () {
    test(
        'the routes are off unless TOOLKIT_DOCUMENTS_ENABLED is exactly "true"',
        () {
      expect(
          read(module), contains("env?.TOOLKIT_DOCUMENTS_ENABLED === 'true'"));
      for (final config in ['wrangler.toml']) {
        final text = read('cloudflare/workers/r2-profile-upload/$config');
        expect('TOOLKIT_DOCUMENTS_ENABLED = "false"'.allMatches(text).length, 2,
            reason: 'production and staging both ship off');
        expect(
            'TOOLKIT_DOCUMENT_SWEEP_MODE = "off"'.allMatches(text).length, 2);
        expect(text, isNot(contains('TOOLKIT_DOCUMENTS_ENABLED = "true"')));
      }
    });

    test('every route verifies the session first and takes the account from it',
        () {
      final text = read(module);
      expect(text, contains('await deps.verifyUser(request, env)'));
      expect(text, isNot(contains('body.userId')));
      expect(text, isNot(contains('body.ownerId')));
      expect(text, isNot(contains('body.objectKey')));
      expect(text, isNot(contains('searchParams.get(\'userId\')')));
      // Verified before any handler runs.
      expect(text.indexOf('deps.verifyUser'),
          lessThan(text.indexOf("case 'authorize'")));
    });

    test('the object key is derived on the server and never returned', () {
      final text = read(module);
      expect(text, contains('profiles/\${userId}/\${TOOLKIT_KEY_SEGMENT}/'));
      // The key reaches the signer and the bucket only: no response body built
      // by noStore(...) or refuse(...) mentions a key.
      final bodies =
          RegExp(r'noStore\(deps, env, \{[\s\S]*?\}\);').allMatches(text);
      expect(bodies.length, greaterThanOrEqualTo(8));
      for (final body in bodies) {
        expect(body.group(0), isNot(contains('object_key')));
        expect(body.group(0), isNot(contains('objectKey')));
        expect(body.group(0), isNot(contains('profiles/')));
      }
    });

    test('the router and the scheduled hook are wired once each', () {
      final text = read(worker);
      expect(
          "handleToolkitDocumentRequest(request, env, toolkitDocumentDeps())"
              .allMatches(text)
              .length,
          1);
      expect('runToolkitDocumentCleanup(env)'.allMatches(text).length, 1);
    });
  });

  group('migration', () {
    final sql = read(migration);

    test('only the service role can change anything', () {
      expect(
          sql,
          contains(
              'alter table public.toolkit_documents enable row level security'));
      expect(
          sql,
          contains(
              'revoke all on public.toolkit_documents from public, anon, authenticated, service_role'));
      expect(
          RegExp(r'grant\s+(insert|update|delete|all)[^;]*toolkit_documents[^;]*authenticated',
                  caseSensitive: false)
              .hasMatch(sql),
          isFalse);
      expect(
          RegExp(r'grant[^;]*to[^;]*\banon\b', caseSensitive: false)
              .hasMatch(sql),
          isFalse);
      // Every function is revoked from the client roles and granted to service_role.
      final created = RegExp(r'create function public\.(\w+)')
          .allMatches(sql)
          .map((m) => m.group(1)!)
          .toSet();
      for (final name in created) {
        expect(RegExp('revoke all on function public\\.$name\\(').hasMatch(sql),
            isTrue,
            reason: '$name revoke');
      }
      expect(created.length, greaterThanOrEqualTo(14));
    });

    test('privileged functions fix the search path', () {
      for (final match
          in RegExp(r'create function public\.(\w+)[\s\S]*?\$function\$;')
              .allMatches(sql)) {
        expect(match.group(0), contains("set search_path = ''"),
            reason: match.group(1));
      }
    });

    test('the object key is pinned and no URL, secret or bytes are stored', () {
      expect(
          sql,
          contains(
              "object_key = 'profiles/' || owner_id::text || '/toolkit-documents/' || id::text || '.' ||"));
      expect(sql, isNot(contains('bytea')));
      expect(
          RegExp(r'\b(url|signed|presigned|password|token)\b\s+text',
                  caseSensitive: false)
              .hasMatch(sql),
          isFalse);
      expect(
          sql,
          contains(
              'create policy app_session_gate on public.toolkit_documents'));
      expect(
          sql,
          contains(
              "using (owner_id = (select auth.uid()) and status = 'ready')"));
    });

    test('clients cannot read the bucket or the key', () {
      final grant = RegExp(
              r'grant select \(([\s\S]*?)\) on public\.toolkit_documents to authenticated')
          .firstMatch(sql)!
          .group(1)!;
      for (final hidden in [
        'bucket',
        'object_key',
        'observed_etag',
        'upload_attempts',
        'last_authorized_at'
      ]) {
        expect(grant, isNot(contains(hidden)), reason: hidden);
      }
    });

    test(
        'nothing in this checkpoint touches the existing media or deletion code',
        () {
      expect(sql, isNot(contains('alter table public.media_objects')));
      expect(sql, isNot(contains('account_deletion_jobs')));
      expect(read('cloudflare/workers/r2-profile-upload/account_deletion.js'),
          isNot(contains('toolkit')));
    });
  });

  group('C1.1 guards', () {
    const content = 'cloudflare/workers/r2-profile-upload/toolkit_content.js';

    test('the format table is one pure module; keys never use a client name',
        () {
      final pure = read(content);
      expect(RegExp(r'^import ', multiLine: true).hasMatch(pure), isFalse);
      final text = read(module);
      for (final forbidden in [
        'body.fileName',
        'body.filename',
        'body.extension',
        'body.objectKey',
        'body.bucket',
      ]) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(
          text, contains('toolkitObjectKey(userId, documentId, contentType)'));
      expect(text,
          contains('contentTypeAllowedForTool(documentType, contentType)'));
    });

    test('the table pins format, tool, digest and key together', () {
      final sql = read(migration);
      expect(
          sql,
          contains(
              "check (content_type in ('application/pdf', 'image/jpeg', 'image/png'))"));
      expect(
          sql,
          contains(
              "check (content_type = 'application/pdf' or document_type = 'scanner')"));
      expect(sql, contains('content_sha256 text not null'));
      expect(sql, contains("when 'image/jpeg' then 'jpg'"));
      expect(sql, contains("when 'image/png' then 'png'"));
      expect(sql, contains('sha256_verified boolean not null default false'));
      expect(
          sql,
          contains(
              'The verification flag is set only when a document becomes ready'));
    });

    test('the tombstone floor is internal and the purge advances it', () {
      final sql = read(migration);
      expect(
          sql, contains('create table public.toolkit_document_account_state'));
      expect(
          sql,
          contains(
              'alter table public.toolkit_document_account_state enable row level security'));
      expect(
          RegExp(r'revoke all on public\.toolkit_document_account_state\s+from public, anon, authenticated, service_role')
              .hasMatch(sql),
          isTrue);
      expect(
          RegExp(r'^grant\b[^;]*toolkit_document_account_state',
                  caseSensitive: false, multiLine: true)
              .hasMatch(sql),
          isFalse);
      expect(sql, contains("'stale_document'"));
      expect(
          sql, contains('insert into public.toolkit_document_account_state'));
    });

    test('the foundation knows no format beyond the three', () {
      final models = read(
          'lib/src/services/toolkit_documents/toolkit_document_models.dart');
      expect(
          RegExp(r"'(application|image|text|video|audio)/[a-z+.-]+'")
              .allMatches(models)
              .map((m) => m.group(0))
              .toSet(),
          {"'application/pdf'", "'image/jpeg'", "'image/png'"});
    });
  });
}
