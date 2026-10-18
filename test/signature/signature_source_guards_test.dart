import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/signature/signature_store.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

const String signatureViews = 'lib/src/views/Screens/home/Toolkit/signature';
const String signatureServices = 'lib/src/services/signature';
const String signatureViewModels = 'lib/src/viewmodels/signature';

String read(String path) => File(path).readAsStringSync();

List<File> sourcesIn(String folder) => Directory(folder)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String name(File file) => file.path.replaceAll(r'\', '/');

/// The code of [file] without its comments, so a comment that explains what the
/// tool no longer does is not mistaken for code that does it.
String code(File file) => file.readAsStringSync().split('\n').map((line) {
      final at = line.indexOf('//');
      return at < 0 ? line : line.substring(0, at);
    }).join('\n');

/// Source guards for the Document Signature tool: facts about the code that no
/// behaviour test would notice breaking.
void main() {
  final all = <File>[
    ...sourcesIn(signatureViews),
    ...sourcesIn(signatureServices),
    ...sourcesIn(signatureViewModels),
  ];

  group('no old behaviour comes back', () {
    test(
        'the tool no longer asks for storage permissions or reaches around '
        'the platform route', () {
      for (final file in all) {
        final source = code(file);
        for (final banned in <String>[
          'Permission.photos',
          'requestStoragePermissions',
          'CleanPermissionService',
          'getExternalStorageDirectory',
          '/storage/emulated',
          'MANAGE_EXTERNAL_STORAGE',
          'saveFileToDownloads',
          "'fileBytes'",
          'XFile(',
        ]) {
          expect(source.contains(banned), isFalse,
              reason: '${name(file)} uses $banned');
        }
      }
    });

    test(
        'the only storage permission is the shared exporter route for '
        'Android 9 and older', () {
      // The Scanner export route asks for it only below Android 10; the tool
      // itself never requests a permission.
      for (final file in all) {
        final source = code(file);
        if (name(file).endsWith('signature_wiring.dart')) {
          expect('Permission.storage'.allMatches(source).length, 1);
          final at = source.indexOf('Permission.storage');
          expect(source.lastIndexOf('requestLegacyStoragePermission', at),
              greaterThan(0));
        } else {
          expect(source.contains('Permission.'), isFalse, reason: name(file));
          expect(source.contains('permission_handler'), isFalse,
              reason: name(file));
        }
      }
    });

    test('the page view that could not track the page is gone', () {
      for (final file in all) {
        final source = code(file);
        expect(source.contains('flutter_pdfview'), isFalse, reason: name(file));
        expect(source.contains('PDFView('), isFalse, reason: name(file));
        expect(source.contains('onRender:'), isFalse, reason: name(file));
        expect(
            source.contains('Future.delayed(const Duration(milliseconds: 100)'),
            isFalse,
            reason:
                '${name(file)} waits for a render instead of reading geometry');
      }
    });

    test(
        'signatures are not kept in a device-wide list or in the shared folder',
        () {
      for (final file in all) {
        final source = code(file);
        if (!name(file).endsWith('signature_wiring.dart')) {
          expect(source.contains('signed_documents_list'), isFalse,
              reason: name(file));
        }
        expect(source.contains("'signed_documents'"), isFalse,
            reason: '${name(file)} names the old shared folder');
      }
      expect(SignatureStore.rootFolderName, isNot('signed_documents'));
      // The old list is only counted by the wiring.
      final wiring = read('$signatureServices/signature_wiring.dart');
      expect(wiring,
          contains("legacySignedDocumentIndexKey = 'signed_documents_list'"));
      expect(wiring,
          contains('getStringList(legacySignedDocumentIndexKey)?.length'));
    });

    test('nothing is uploaded or sent to an AI service', () {
      for (final file in all) {
        final source = code(file);
        for (final banned in <String>[
          'package:http/',
          'package:dio/',
          'supabase_flutter',
          'firebase_storage',
          'cloud_functions',
          'FirebaseStorage',
          'r2-profile-upload',
          'google_mlkit',
        ]) {
          expect(source.contains(banned), isFalse,
              reason: '${name(file)} uses $banned');
        }
      }
    });

    test('no certificate based signing, and no claim of one', () {
      for (final file in all) {
        final source = code(file);
        expect(source.contains('PdfCertificate'), isFalse, reason: name(file));
        expect(source.contains('PdfSignature('), isFalse, reason: name(file));
        expect(source.contains('PdfSignatureField('), isFalse,
            reason: name(file));
      }
    });
  });

  group('the one quota boundary', () {
    test('only the usage gate touches the plan limit or Firestore', () {
      for (final file in all) {
        if (name(file).endsWith('signature_usage_gate.dart')) continue;
        final source = code(file);
        expect(source.contains('QuotaHelper'), isFalse, reason: name(file));
        expect(source.contains('FirebaseFirestore'), isFalse,
            reason: name(file));
        expect(source.contains('cloud_firestore'), isFalse, reason: name(file));
        expect(source.contains('lifetimeCreated'), isFalse, reason: name(file));
      }
    });

    test('the gate keeps the tool\'s own section and is fail-open', () {
      final gate = read('$signatureServices/signature_usage_gate.dart');
      expect(gate, contains("static const String section = 'signature'"));
      expect(gate, contains('QuotaHelper.checkAndWarnQuota('));
      expect(gate, contains('catch (_)'));
      expect(gate.toLowerCase(), contains('not authoritative'),
          reason: 'the file must say it is not server enforcement');
    });

    test('a saved document is counted after it is stored, once', () {
      final vm = read('$signatureViewModels/signature_editor_viewmodel.dart');
      final stored = vm.indexOf('await _store.add(');
      final counted = vm.indexOf('_usage.recordSignedDocument(');
      expect(stored, greaterThan(0));
      expect(counted, greaterThan(stored),
          reason: 'it is counted only after the store succeeded');
      expect('_usage.recordSignedDocument('.allMatches(vm).length, 1);
      // The view layer never counts.
      for (final file in sourcesIn(signatureViews)) {
        expect(
            file.readAsStringSync().contains('recordSignedDocument'), isFalse,
            reason: name(file));
      }
    });
  });

  group('the file is never changed in place', () {
    test('the engine only reads the source file', () {
      final engine = read('$signatureServices/signature_pdf_engine.dart');
      expect('File(job.sourcePath)'.allMatches(engine).length, 1);
      final read1 = engine.indexOf('Uint8List _readSource(');
      final end = engine.indexOf('\n}\n', read1);
      final body = engine.substring(read1, end);
      for (final write in ['writeAs', 'delete', 'rename', 'open(']) {
        expect(body.contains(write), isFalse,
            reason: '_readSource uses $write');
      }
      // The signed copy goes to the path the caller owns.
      expect(engine, contains('File(job.outputPath)'));
    });

    test('the incremental save is not switched off', () {
      final engine = read('$signatureServices/signature_pdf_engine.dart');
      expect(engine.contains('incrementalUpdate = false'), isFalse);
      expect(engine.contains('flattenAllFields'), isFalse);
      expect(engine.contains('flattenAllAnnotations'), isFalse);
      expect(engine.contains('createTemplate'), isFalse,
          reason: 'page templates would drop links and forms');
    });

    test('the form is only read on a document that is never saved', () {
      final engine = read('$signatureServices/signature_pdf_engine.dart');
      final write = engine.indexOf('SignatureWriteResult runSignatureWrite(');
      final verify = engine.indexOf('bool verifySignatureOutput(');
      final writeBody = engine.substring(write, verify);
      expect(writeBody.contains('.form'), isFalse,
          reason:
              'reading the form of the document being saved can rewrite it');
      expect(writeBody.contains('.annotations'), isFalse);
      expect(writeBody.contains('bookmarks'), isFalse);
    });

    test('a draft and its saved copy are compared byte for byte', () {
      final store = read('$signatureServices/signature_store.dart');
      expect(store, contains('sameBytes(source, copy)'));
      final vm = read('$signatureViewModels/signature_editor_viewmodel.dart');
      expect(vm, contains('source: draft.file'));
    });
  });

  group('privacy and storage', () {
    test('signed documents are kept out of backups on both platforms', () {
      for (final path in [
        'android/app/src/main/res/xml/backup_rules.xml',
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ]) {
        final xml = read(path);
        final root = 'path="app_flutter/${SignatureStore.rootFolderName}"';
        final count = root.allMatches(xml).length;
        expect(count, path.contains('data_extraction') ? 2 : 1, reason: path);
        // Parses as XML-ish: balanced exclude tags.
        expect(RegExp(r'<exclude ').allMatches(xml).length,
            RegExp(r'/>').allMatches(xml).length,
            reason: path);
      }
      final viewModel =
          read('$signatureViewModels/signature_library_viewmodel.dart');
      expect(viewModel, contains('_backup.exclude(root.path)'));
    });

    test('a signature image is never written to disk by the tool', () {
      for (final file in all) {
        final source = code(file);
        // Stamps travel as bytes in memory; only the PDF writer and the store
        // write files.
        if (name(file).endsWith('signature_pdf_engine.dart') ||
            name(file).endsWith('signature_store.dart') ||
            name(file).endsWith('signature_platform.dart')) {
          continue;
        }
        expect(source.contains('writeAsBytes'), isFalse, reason: name(file));
        expect(source.contains('createTemp'), isFalse, reason: name(file));
      }
    });

    test('the account comes from the one canonical repository', () {
      final wiring = read('$signatureServices/signature_wiring.dart');
      expect(wiring, contains('authRepository'));
      expect(wiring, contains('auth.currentUserId'));
      expect(wiring.contains('FirebaseAuth'), isFalse);
      expect(wiring.contains('Supabase.instance'), isFalse);
    });

    test('share and export go through the shared routes', () {
      final storage = read('$signatureViews/signed_documents_storage.dart');
      expect(storage, contains('ShareLive.sendFiles('));
      final platform = read('$signatureServices/signature_platform.dart');
      expect(platform, contains('exportFile('));
      expect(platform, contains("mimeType: 'application/pdf'"));
      final view = read('$signatureViews/signature_view.dart');
      expect(view, contains('_vm.exportDocument('));
      expect(view.contains('Directory('), isFalse);
    });
  });

  group('messages', () {
    test('every literal message key in the screens exists in both languages',
        () {
      final en = jsonDecode(read('lib/src/common/localization/app_en.arb'))
          as Map<String, dynamic>;
      final ar = jsonDecode(read('lib/src/common/localization/app_ar.arb'))
          as Map<String, dynamic>;
      final key = RegExp(r"translate\(\s*'([A-Za-z0-9_]+)'");
      for (final file in sourcesIn(signatureViews)) {
        for (final match in key.allMatches(file.readAsStringSync())) {
          final k = match.group(1)!;
          expect(en.containsKey(k), isTrue, reason: '${name(file)}: $k (en)');
          expect(ar.containsKey(k), isTrue, reason: '${name(file)}: $k (ar)');
        }
      }
      for (final k in kSignatureFailureKeys.values) {
        expect(en.containsKey(k), isTrue, reason: '$k (en)');
        expect(ar.containsKey(k), isTrue, reason: '$k (ar)');
      }
    });

    test('there is no hard-coded user-facing English left in the screens', () {
      for (final file in sourcesIn(signatureViews)) {
        final source = code(file);
        for (final banned in <String>[
          "'Please draw a signature first'",
          "'Failed to export signature'",
          "'Error exporting signature",
          "'Failed to save PDF",
          "'Downloads\\n",
          '(Accessible via Files app)',
          "'App Downloads'",
          "'External Storage'",
        ]) {
          expect(source.contains(banned), isFalse,
              reason: '${name(file)} has $banned');
        }
      }
    });
  });

  group('the interface keeps its identity', () {
    test(
        'the screens keep the tool\'s red, the Montserrat-based theme and '
        'the original library layout', () {
      final library = read('$signatureViews/signature_view.dart');
      expect(library, contains('SignatureColors.redLight'));
      expect(library, contains('FloatingActionButton.extended('));
      expect(library, contains('SliverGridDelegateWithFixedCrossAxisCount('));
      // Two columns, as before; the tile height is fixed (and follows the text
      // size) because a width-based ratio overflowed on a 360 dp phone.
      expect(library, contains('crossAxisCount: 2'));
      expect(library, contains('mainAxisExtent: 200'));
      expect(library.contains('childAspectRatio'), isFalse);
      expect(library, contains("translate('uploadAndSignDocuments')"));
      expect(library.contains('fontFamily'), isFalse,
          reason: 'fonts come from the theme, not from this screen');
      final editor = read('$signatureViews/document_view.dart');
      expect(editor, contains('SignatureColors.redLight'));
      expect(editor, contains('FloatingActionButtonLocation.centerFloat'));
      expect(editor.contains('fontFamily'), isFalse);
    });

    test('a drag on an item and the zoom around it do not compete', () {
      final canvas = read('$signatureViews/signature_page_canvas.dart');
      expect(canvas, contains('class _EagerScaleRecognizer'));
      expect(canvas, contains('globalToLocal'));
      expect(canvas, contains('InteractiveViewer('));
      expect(canvas.contains('MediaQuery.sizeOf'), isFalse,
          reason:
              'the page is laid out in its own box, not by the screen size');
    });

    test('the page and its items share one frame', () {
      final canvas = read('$signatureViews/signature_page_canvas.dart');
      final viewerAt = canvas.indexOf('InteractiveViewer(');
      final surfaceAt = canvas.indexOf('_buildSurface(vm, page, viewport)');
      final stampAt = canvas.indexOf('_StampOverlay(');
      expect(viewerAt, greaterThan(0));
      expect(surfaceAt, greaterThan(viewerAt));
      expect(stampAt, greaterThan(0));
      // The items are built inside the surface, which is inside the viewer.
      final surfaceMethod = canvas.indexOf('Widget _buildSurface(');
      expect(stampAt, greaterThan(surfaceMethod));
    });
  });

  group('documentation of the limits', () {
    test('the checkpoint says what is not verified and what the quota is', () {
      final doc = read('docs/CURRENT_CHECKPOINT.md');
      final section = doc.indexOf('CHECKPOINT S4');
      expect(section, greaterThan(0));
      final text = doc.substring(section);
      expect(text, contains('SIGNATURE_S4'));
      expect(text, contains('not authoritative'));
      expect(text, contains('NOT RUN'));
      expect(text.toLowerCase(), contains('not a certificate'));
    });
  });
}
