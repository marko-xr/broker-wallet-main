import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

Map<String, dynamic> arb(String lang) =>
    jsonDecode(read('lib/src/common/localization/app_$lang.arb'))
        as Map<String, dynamic>;

const String servicesFolder = 'lib/src/services/combine_pdf';
const String viewModelPath =
    'lib/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart';
const String toolkitFolder = 'lib/src/views/Screens/home/Toolkit';
const String viewPath = '$toolkitFolder/combine_pdfs_view.dart';
const String pagesPath = '$toolkitFolder/combine_pages_screen.dart';

List<String> serviceFiles() => <String>[
      for (final entity in Directory(servicesFolder).listSync())
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.replaceAll('\\', '/'),
    ];

List<String> combineSources() =>
    <String>[...serviceFiles(), viewModelPath, viewPath, pagesPath];

/// The messages this checkpoint added.
List<String> addedKeys() {
  final en = arb('en').keys.toList();
  final start = en.indexOf('combineErrSignedOut');
  expect(start, greaterThan(0));
  return en.sublist(start);
}

Set<String> placeholders(String text) =>
    RegExp(r'\{[A-Za-z]+\}').allMatches(text).map((m) => m.group(0)!).toSet();

void main() {
  group('privacy: nothing leaves the phone', () {
    test('the Combine services use no network, Supabase, R2 or upload client',
        () {
      final forbidden = RegExp(
          r'package:(http|dio|supabase|supabase_flutter|firebase_storage)\b|r2_|Cloudflare|SupabaseClient|\.upload\(|HttpClient');
      for (final path in combineSources()) {
        final text = read(path);
        expect(forbidden.hasMatch(text), isFalse, reason: path);
      }
    });

    test('only the usage gate touches the legacy Firestore quota document', () {
      for (final path in combineSources()) {
        final touches = read(path).contains('FirebaseFirestore') ||
            read(path).contains('cloud_firestore');
        expect(touches, path.endsWith('combine_usage_gate.dart'), reason: path);
      }
    });

    test('nothing logs paths, names or document content', () {
      final logging =
          RegExp(r'\b(print|debugPrint|log|developer\.log)\(|printStack');
      for (final path in combineSources()) {
        expect(logging.hasMatch(read(path)), isFalse, reason: path);
      }
    });

    test('the combined PDFs are kept out of Android backup and device transfer',
        () {
      final legacy = read('android/app/src/main/res/xml/backup_rules.xml');
      expect(legacy, contains('app_flutter/combine_pdfs'));
      final modern =
          read('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect('app_flutter/combine_pdfs'.allMatches(modern), hasLength(2));
      final cloud = modern.substring(
          modern.indexOf('<cloud-backup'), modern.indexOf('</cloud-backup>'));
      final transfer = modern.substring(modern.indexOf('<device-transfer'),
          modern.indexOf('</device-transfer>'));
      expect(cloud, contains('app_flutter/combine_pdfs'));
      expect(transfer, contains('app_flutter/combine_pdfs'));
      // The store's folder name is the one the rules name.
      expect(read('$servicesFolder/combine_pdf_store.dart'),
          contains("rootFolderName = 'combine_pdfs'"));
    });

    test('iPhone backup exclusion is requested for the Combine root folder',
        () {
      final vm = read(viewModelPath);
      expect(vm, contains('_backup.exclude(root.path)'));
      expect(vm, contains('CombinePdfStore.rootFolderName'));
    });
  });

  group('permissions', () {
    test('no storage permission is requested to pick or to combine', () {
      for (final path in [viewPath, pagesPath, viewModelPath]) {
        final text = read(path);
        expect(text.contains('permission_handler'), isFalse, reason: path);
        expect(text.contains('CleanPermissionService'), isFalse, reason: path);
        expect(text.contains('requestStoragePermissions'), isFalse,
            reason: path);
      }
      expect(read('$servicesFolder/combine_pdf_platform.dart'),
          isNot(contains('permission_handler')));
    });

    test(
        'only the legacy Android 9 storage permission is ever asked, in the '
        'wiring', () {
      final wiring = read('$servicesFolder/combine_wiring.dart');
      expect('Permission.storage'.allMatches(wiring), hasLength(1));
      for (final path in combineSources()) {
        expect(read(path).contains('MANAGE_EXTERNAL_STORAGE'), isFalse,
            reason: path);
      }
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(
          RegExp(r'<uses-permission[^>]*MANAGE_EXTERNAL_STORAGE')
              .hasMatch(manifest),
          isFalse);
    });
  });

  group('honesty', () {
    test('no artificial delay or made-up progress', () {
      for (final path in combineSources()) {
        final text = read(path);
        expect(text.contains('Future.delayed'), isFalse, reason: path);
        expect(text.contains('_processingProgress'), isFalse, reason: path);
        expect(text.contains('* 100).toInt()'), isFalse, reason: path);
      }
      final view = read(viewPath);
      expect(view.contains('LinearProgressIndicator'), isFalse);
      expect(view.contains('value: _'), isFalse);
    });

    test('the combine uses one page-template route and refuses encryption', () {
      final engine = read('$servicesFolder/combine_pdf_engine.dart');
      expect(engine, contains('createTemplate()'));
      expect(engine, contains('isEncrypted'));
      expect(engine, contains('CombinePdfFailure.encryptedSource'));
      expect(engine, contains('CombinePdfFailure.signedSource'));
      // The old A4-scaling route is gone: pages keep their own size.
      expect(engine.contains('PdfPageSize.a4'), isFalse);
      expect(engine.contains('scaleX'), isFalse);
      // A page that cannot be copied ends the combine; it is never skipped.
      expect(engine.contains('continue;'), isFalse);
    });

    test('a combine is counted once, after the document was stored', () {
      final vm = read(viewModelPath);
      expect('recordCombine('.allMatches(vm), hasLength(1));
      expect(vm.indexOf('store.add('),
          lessThan(vm.indexOf('_usage.recordCombine(uid)')));
      // The view never writes the quota itself.
      expect(read(viewPath).contains('increment('), isFalse);
    });

    test('legacy documents are only counted: never listed, moved or deleted',
        () {
      final wiring = read('$servicesFolder/combine_wiring.dart');
      expect(wiring,
          contains("legacyCombinedPdfIndexKey = 'combined_pdf_documents'"));
      expect(
          wiring, contains('getStringList(legacyCombinedPdfIndexKey)?.length'));
      for (final path in combineSources()) {
        if (path.endsWith('combine_wiring.dart')) continue;
        expect(read(path).contains('combined_pdf_documents'), isFalse,
            reason: path);
      }
      expect(read(viewPath).contains('SharedPreferences'), isTrue,
          reason: 'only the grid/list preference');
      expect(read(viewPath).contains("'combined_pdf_documents'"), isFalse);
    });

    test('the share and export routes carry the title, never the internal id',
        () {
      final platform = read('$servicesFolder/combine_pdf_platform.dart');
      expect(platform, contains('exportFileName'));
      final vm = read(viewModelPath);
      expect(vm, contains('document.exportFileName'));
      expect(read(viewPath), contains('ShareLive.sendFiles'));
    });
  });

  group('localization', () {
    test('every literal key the Combine screens use exists in both languages',
        () {
      final en = arb('en');
      final ar = arb('ar');
      final used = <String>{};
      for (final path in [viewPath, pagesPath]) {
        used.addAll(RegExp(r"translate\(\s*'([A-Za-z0-9_]+)'\s*\)")
            .allMatches(read(path))
            .map((m) => m.group(1)!));
      }
      expect(used, isNotEmpty);
      for (final key in used) {
        expect(en.containsKey(key), isTrue, reason: 'en is missing $key');
        expect(ar.containsKey(key), isTrue, reason: 'ar is missing $key');
      }
    });

    test(
        'the added messages exist in both languages with the same placeholders',
        () {
      final en = arb('en');
      final ar = arb('ar');
      final keys = addedKeys();
      expect(keys.length, greaterThanOrEqualTo(50));
      for (final key in keys) {
        expect(ar.containsKey(key), isTrue, reason: 'ar is missing $key');
        expect(placeholders(ar[key] as String), placeholders(en[key] as String),
            reason: key);
        expect((en[key] as String).trim(), isNotEmpty, reason: key);
        expect((ar[key] as String).trim(), isNotEmpty, reason: key);
      }
    });

    test('every failure the view can show has a message', () {
      final view = read(viewPath);
      final enumBody = RegExp(r'enum CombinePdfFailure \{([\s\S]*?)\n\}')
          .firstMatch(read('$servicesFolder/combine_models.dart'))!
          .group(1)!;
      final kinds = RegExp(r'^  ([a-zA-Z]+),', multiLine: true)
          .allMatches(enumBody)
          .map((m) => m.group(1)!)
          .toList();
      expect(kinds.length, greaterThan(20));
      for (final kind in kinds) {
        expect(view.contains('case CombinePdfFailure.$kind:'), isTrue,
            reason: 'no message for $kind');
      }
    });
  });
}
