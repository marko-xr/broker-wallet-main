import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

Map<String, dynamic> arb(String lang) =>
    jsonDecode(read('lib/src/common/localization/app_$lang.arb'))
        as Map<String, dynamic>;

const String servicesFolder = 'lib/src/services/scanner';

/// The messages this checkpoint added (the older ones are checked by use).
const List<String> addedKeys = <String>[
  'scannerReviewTitle',
  'scannerReviewHint',
  'scannerPageCountLabel',
  'scannerSaving',
  'scannerDiscardTitle',
  'scannerDiscardMessage',
  'scannerImagesSaved',
  'scannerExportedToDownloads',
  'scannerExportedToFiles',
  'scannerMaxPages',
  'scannerModeNote',
  'scannerQualityNote',
  'scannerBuiltInToolsTitle',
  'scannerBuiltInToolsBody',
  'scannerMaxPagesChip',
  'scannerFileMissingBadge',
  'scannerLoadFailed',
  'scannerLegacyNotice',
  'scannerErrSignedOut',
  'scannerErrBusy',
  'scannerErrEngine',
  'scannerErrMalformed',
  'scannerErrWrongFormat',
  'scannerErrUnreadable',
  'scannerErrEmpty',
  'scannerErrCorrupt',
  'scannerErrTooLarge',
  'scannerErrStorageFull',
  'scannerErrWrite',
  'scannerErrNotFound',
  'scannerErrInvalidName',
  'scannerErrNameInUse',
  'scannerErrAccountChanged',
  'scannerErrExport',
  'scannerErrOpen',
  'scannerErrAbandoned',
];
const String toolkitFolder = 'lib/src/views/Screens/home/Toolkit';

List<String> scannerSourcePaths({bool includeWiring = true}) => <String>[
      for (final entity in Directory(servicesFolder).listSync())
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            (includeWiring || !entity.path.endsWith('scanner_wiring.dart')))
          entity.path.replaceAll('\\', '/'),
      'lib/src/viewmodels/scanner/scanner_viewmodel.dart',
      '$toolkitFolder/scanner_view.dart',
      '$toolkitFolder/scanner_review_screen.dart',
      '$toolkitFolder/scanner_image_viewer.dart',
    ];

void main() {
  group('permissions and storage', () {
    test('All Files Access is not declared; other media features keep theirs',
        () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(
          RegExp(r'<uses-permission[^>]*MANAGE_EXTERNAL_STORAGE')
              .hasMatch(manifest),
          isFalse);
      expect(manifest, contains('android.permission.READ_MEDIA_IMAGES'));
      expect(manifest, contains('android.permission.READ_MEDIA_VIDEO'));
      expect(manifest, contains('android.permission.WRITE_EXTERNAL_STORAGE'));
      expect(manifest, contains('android:maxSdkVersion="29"'));
    });

    test('nothing in the app asks for All Files Access any more', () {
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        expect(read(entity.path).contains('manageExternalStorage'), isFalse,
            reason: entity.path);
      }
    });

    test('the Scanner asks for no camera, photo or broad storage permission',
        () {
      for (final path in scannerSourcePaths(includeWiring: false)) {
        final source = read(path);
        expect(source.contains('Permission.'), isFalse, reason: path);
        expect(source.contains('CleanPermissionService'), isFalse,
            reason: path);
        expect(source.contains('permission_handler'), isFalse, reason: path);
        expect(source.contains('/storage/emulated'), isFalse, reason: path);
        expect(source.contains('getExternalStorageDirectory'), isFalse,
            reason: path);
      }
      // The one place a permission is requested: the legacy Android 9 export.
      final wiring = read('$servicesFolder/scanner_wiring.dart');
      expect('Permission.'.allMatches(wiring).length, 1);
      expect(wiring, contains('Permission.storage.request()'));
    });

    test(
        'the iOS project targets at least what the scanner plugin and the '
        'app\'s Firebase plugins need (13.0 and 15.0)', () {
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);')
          .allMatches(project)
          .map((m) => double.parse(m.group(1)!))
          .toList();
      expect(targets, isNotEmpty);
      expect(targets.every((t) => t >= 15.0), isTrue, reason: '$targets');
      expect(read('ios/Flutter/AppFrameworkInfo.plist'),
          contains('<string>15.0</string>'));
    });

    test('the Scanner writes no log of paths, names or contents', () {
      for (final path in scannerSourcePaths()) {
        final source = read(path);
        for (final call in <String>[
          'print(',
          'debugPrint(',
          'developer.log(',
          'dart:developer',
          'printStackTrace',
        ]) {
          expect(source.contains(call), isFalse, reason: '$path uses $call');
        }
      }
      final kotlin = read(
          'android/app/src/main/kotlin/com/example/broker_wallet/FileSaverPlugin.kt');
      expect(kotlin.contains('Log.'), isFalse);
      expect(kotlin.contains('printStackTrace'), isFalse);
    });

    test('the iPhone camera purpose string covers scanning documents', () {
      final plist = read('ios/Runner/Info.plist');
      expect(
          RegExp(r'NSCameraUsageDescription</key>\s*<string>[^<]*scan documents')
              .hasMatch(plist),
          isTrue);
    });
  });

  group('the native saver', () {
    final kotlin = read(
        'android/app/src/main/kotlin/com/example/broker_wallet/FileSaverPlugin.kt');

    test('keeps the contract the other Toolkit tools use', () {
      expect(kotlin, contains('"saveFileToDownloads" -> saveBytes'));
      expect(kotlin, contains('call.argument<ByteArray>("fileBytes")'));
      expect(kotlin, contains('"success" to true'));
      // Every Toolkit tool has now moved to the streaming route, so the old
      // route is kept only as the native contract above, for no caller.
    });

    test('Document Signature moved to the streaming route and no longer uses it',
        () {
      // Document Signature exports through the same file-based route as the
      // Scanner (Signature S4), so it must not pass whole documents through the
      // channel or ask for storage permissions of its own any more.
      final view = read('$toolkitFolder/signature/signature_view.dart');
      expect(view.contains('saveFileToDownloads'), isFalse);
      expect(view.contains('fileBytes'), isFalse);
      expect(view.contains('Permission.storage'), isFalse);
      final platform = read('lib/src/services/signature/signature_platform.dart');
      expect(platform, contains('exportFile('));
    });

    test('Combine PDFs moved to the streaming route and no longer uses it', () {
      // Combine PDFs exports through the same file-based route as the Scanner
      // (Combine PDF S2), so it must not pass whole documents through the
      // channel any more.
      final view = read('$toolkitFolder/combine_pdfs_view.dart');
      expect(view.contains('saveFileToDownloads'), isFalse);
      expect(view.contains('fileBytes'), isFalse);
      final platform = read('lib/src/services/combine_pdf/combine_pdf_platform.dart');
      expect(platform, contains('exportFile('));
    });

    test('Images to PDF moved to the streaming route and no longer uses it', () {
      // Images to PDF exports through the same file-based route as the Scanner
      // (Images to PDF S3), so it must not pass whole documents through the
      // channel any more.
      final view = read('$toolkitFolder/image_to_pdf_view.dart');
      expect(view.contains('saveFileToDownloads'), isFalse);
      expect(view.contains('fileBytes'), isFalse);
      final platform =
          read('lib/src/services/image_to_pdf/image_pdf_platform.dart');
      expect(platform, contains('exportFile('));
    });

    test('Scanner export streams a file, never a whole document in memory', () {
      expect(kotlin, contains('"exportFileToDownloads" -> exportFile'));
      expect(kotlin, contains('input.copyTo(out, COPY_BUFFER_BYTES)'));
      expect(kotlin.contains('readBytes()'), isFalse);
      expect(kotlin.contains('/storage/emulated'), isFalse);
    });

    test(
        'a Downloads entry stays pending until complete, is removed if '
        'writing fails, and a null stream is a failure', () {
      expect(kotlin, contains('MediaStore.MediaColumns.IS_PENDING, 1'));
      expect(kotlin, contains('MediaStore.MediaColumns.IS_PENDING, 0'));
      expect(kotlin, contains('resolver.openOutputStream(uri, "w")'));
      expect(kotlin, contains('?: throw IOException("No output stream'));
      expect(kotlin, contains('resolver.delete(uri, null, null)'));
      expect(kotlin, contains('queryDisplayName(uri)'));
    });

    test(
        'only files inside the app\'s own data folder can be exported or '
        'written', () {
      expect(kotlin, contains('context.filesDir.parentFile?.canonicalFile'));
      expect(
          kotlin, contains('file.path.startsWith(root.path + File.separator)'));
      expect(kotlin, contains('uri.scheme != "content"'));
    });

    test('an old-Android export never overwrites a file that is there', () {
      expect(kotlin, contains('uniqueFile(folder, name)'));
      expect(kotlin, contains('part.renameTo(target)'));
    });
  });

  group('a lost scan result and backup', () {
    const kotlinFolder =
        'android/app/src/main/kotlin/com/example/broker_wallet';
    final guard = read('$kotlinFolder/ScanLifecycleGuard.kt');

    test(
        'the native listener reports a loss only while a scan is watched, '
        'once, and uses no timer', () {
      expect(guard, contains('if (!watching) return'));
      expect(
          RegExp(r'watching = false\s+channel\?\.invokeMethod\("scanAbandoned", null\)')
              .hasMatch(guard),
          isTrue);
      expect(guard,
          contains('override fun onDetachedFromActivityForConfigChanges()'));
      expect(guard, contains('override fun onDetachedFromActivity()'));
      for (final timer in <String>[
        'android.os.Handler',
        'postDelayed',
        'Timer',
        'sleep('
      ]) {
        expect(guard.contains(timer), isFalse, reason: timer);
      }
      expect(read('$kotlinFolder/MainActivity.kt'),
          contains('flutterEngine.plugins.add(ScanLifecycleGuard())'));
      expect(guard, contains('"com.example.broker_wallet/scan_lifecycle"'));
      expect(read('$servicesFolder/scan_lifecycle_probe.dart'),
          contains("'com.example.broker_wallet/scan_lifecycle'"));
    });

    test('no Scanner Dart file ends a scan by time', () {
      for (final path in scannerSourcePaths()) {
        final source = read(path);
        for (final timer in <String>[
          'Timer(',
          'Timer.periodic',
          'Future.delayed',
          'Future<void>.delayed',
          '.timeout(',
        ]) {
          expect(source.contains(timer), isFalse, reason: '$path uses $timer');
        }
      }
    });

    test(
        'the engine ends the watch in all cases and races the plugin against '
        'the loss report', () {
      final engine = read('$servicesFolder/scanner_engine.dart');
      expect(engine, contains('Future.any<Object?>'));
      expect(engine, contains('ScannerFailure.scanAbandoned'));
      expect(engine, contains('await watch.end();'));
      expect(read('$servicesFolder/scanner_wiring.dart'),
          contains('PlatformScanLifecycleProbe()'));
    });

    test(
        'Scanner folders are excluded from Android cloud backup and '
        'device transfer, and the Offer exclusions and the rest stay', () {
      final full = read('android/app/src/main/res/xml/backup_rules.xml');
      final extraction =
          read('android/app/src/main/res/xml/data_extraction_rules.xml');
      for (final rules in <String>[full, extraction]) {
        expect(rules,
            contains('<exclude domain="root" path="app_flutter/scanner" />'));
        expect(
            rules,
            contains(
                '<exclude domain="file" path="mlkit_docscan_ui_client" />'));
        expect(rules, contains('app_flutter/offer_media'));
        expect(RegExp(r'path="(\.|app_flutter|)"').hasMatch(rules), isFalse,
            reason: 'no rule may exclude the whole app');
      }
      expect('app_flutter/scanner'.allMatches(extraction).length, 2,
          reason: 'cloud-backup and device-transfer');
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest.contains('android:allowBackup="false"'), isFalse);
      expect(manifest, contains('@xml/backup_rules'));
      expect(manifest, contains('@xml/data_extraction_rules'));
    });

    test(
        'iPhone: the app marks the Scanner folder and outputs as excluded '
        'from backup', () {
      final delegate = read('ios/Runner/AppDelegate.swift');
      expect(
          delegate, contains('"com.example.broker_wallet/backup_exclusion"'));
      expect(delegate, contains('values.isExcludedFromBackup = true'));
      expect(delegate, contains('call.method == "excludeFromBackup"'));
      expect(read('$servicesFolder/scanner_backup_guard.dart'),
          contains("'com.example.broker_wallet/backup_exclusion'"));
      final vm = read('lib/src/viewmodels/scanner/scanner_viewmodel.dart');
      expect(vm, contains("p.join(base.path, 'scanner')"));
      expect(vm, contains('_backup.exclude(scannerRoot.path)'));
    });
  });

  group('local-only processing and the account boundary', () {
    test('no Scanner file imports a network, Supabase, R2 or upload client',
        () {
      for (final path in scannerSourcePaths()) {
        final source = read(path);
        final imports = RegExp(r"^import '([^']+)'", multiLine: true)
            .allMatches(source)
            .map((m) => m.group(1)!)
            .toList();
        for (final import in imports) {
          for (final forbidden in <String>[
            'package:http/',
            'package:dio/',
            'supabase',
            'firebase_storage',
            'r2_',
            'cloudflare',
            'offer_media',
            'profile_image',
          ]) {
            expect(import.contains(forbidden), isFalse,
                reason: '$path imports $import');
          }
        }
        expect(source.contains('HttpClient('), isFalse, reason: path);
      }
    });

    test('the legacy Firestore limit is reached only through the usage gate',
        () {
      for (final path in scannerSourcePaths()) {
        if (path.endsWith('scanner_usage_gate.dart')) continue;
        final source = read(path);
        expect(source.contains('cloud_firestore'), isFalse, reason: path);
        expect(source.contains('FirebaseFirestore'), isFalse, reason: path);
        expect(source.contains('QuotaHelper'), isFalse, reason: path);
      }
      final gate = read('$servicesFolder/scanner_usage_gate.dart');
      expect(gate, contains('NOT'));
      expect(gate, contains('fail-open'));
    });

    test('a scan is counted once, after it was stored', () {
      final vm = read('lib/src/viewmodels/scanner/scanner_viewmodel.dart');
      expect('recordScan('.allMatches(vm).length, 1);
      final save = vm.substring(vm.indexOf('Future<ScanSaveResult> saveDraft'));
      expect(save.indexOf('store.add(items)'),
          lessThan(save.indexOf('_usage.recordScan')));
      expect(read('$toolkitFolder/scanner_view.dart').contains('recordScan'),
          isFalse);
    });

    test('the device-wide document list is only counted, in one place', () {
      final hits = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            read(entity.path).contains("'scanned_documents'")) {
          hits.add(entity.path.replaceAll('\\', '/'));
        }
      }
      expect(hits, <String>['$servicesFolder/scanner_wiring.dart']);
      final wiring = read('$servicesFolder/scanner_wiring.dart');
      expect(wiring.contains('setStringList'), isFalse);
      expect(wiring.contains('remove('), isFalse);
    });

    test(
        'every store, share and export path is built from the signed-in '
        'account', () {
      final store = read('$servicesFolder/scanner_document_store.dart');
      expect(store, contains("p.join(base.path, 'scanner', name)"));
      expect(store, contains("decoded['userId'] != userId"));
      expect(store, contains('index belongs to another account'));
      expect(store, contains('p.join(_filesDir.path, document.fileName)'));
    });
  });

  group('the screen says only what the scanner really does', () {
    final view = read('$toolkitFolder/scanner_view.dart');

    test('no fake AI, enhance, crop or background-removal controls', () {
      for (final forbidden in <String>[
        'aiEnhanced',
        "'AI'",
        'autoEnhance',
        'automaticallyEnhanceImageQuality',
        'removeBackground',
        'automaticallyDetectAndCrop',
        '_ocrEnabled',
        '_autoCrop',
        '_batchMode',
      ]) {
        expect(view.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('quality choices are disabled, with the reason shown', () {
      expect(view, contains('enabled: false'));
      expect(
          RegExp(r"translate\(\s*'scannerQualityNote'").hasMatch(view), isTrue);
      expect(RegExp(r"translate\(\s*'scannerBuiltInToolsBody'").hasMatch(view),
          isTrue);
    });

    test('a scan is reviewed before it is saved', () {
      expect(view, contains('ScannerReviewScreen('));
      expect(view.contains('saveDraft'), isFalse,
          reason: 'only the review screen saves');
      expect(read('$toolkitFolder/scanner_review_screen.dart'),
          contains('saveDraft('));
    });

    test('sharing still goes through the one shared launcher', () {
      expect(view, contains('ShareLive.sendFiles('));
      expect(view.contains('XFile('), isFalse);
      expect(view, contains('_vm.prepareShare('));
    });

    test('actions work on document ids, not list positions', () {
      expect(view.contains('_selectedDocuments'), isFalse);
      expect(view.contains('Set<int>'), isFalse);
      expect(view.contains('removeAt('), isFalse);
      expect(
          RegExp(r'_deleteDocuments\(\s*\[document\]').hasMatch(view), isTrue);
    });

    test('the engine package is the reviewed version', () {
      expect(read('pubspec.yaml'), contains('flutter_doc_scanner: ^0.0.21'));
      expect(
          RegExp(r'flutter_doc_scanner:[\s\S]*?version: "0\.0\.21"')
              .hasMatch(read('pubspec.lock')),
          isTrue);
    });
  });

  group('localization', () {
    test('every literal key the Scanner screens use exists in both languages',
        () {
      final en = arb('en');
      final ar = arb('ar');
      final used = <String>{};
      for (final path in <String>[
        '$toolkitFolder/scanner_view.dart',
        '$toolkitFolder/scanner_review_screen.dart',
      ]) {
        for (final match in RegExp(r"translate\(\s*'([A-Za-z0-9_]+)'")
            .allMatches(read(path))) {
          used.add(match.group(1)!);
        }
      }
      expect(used, isNotEmpty);
      for (final key in used) {
        expect(en[key], isA<String>(), reason: 'en $key');
        expect((en[key] as String).trim(), isNotEmpty, reason: 'en $key');
        expect(ar[key], isA<String>(), reason: 'ar $key');
        expect((ar[key] as String).trim(), isNotEmpty, reason: 'ar $key');
      }
    });

    test(
        'the new Scanner messages exist in both languages with the same '
        'placeholders', () {
      final en = arb('en');
      final ar = arb('ar');
      expect(addedKeys.length, greaterThan(30));
      for (final key in addedKeys) {
        expect(en.containsKey(key), isTrue, reason: 'en $key');
        expect(ar.containsKey(key), isTrue, reason: key);
        final enHolders = RegExp(r'\{(\w+)\}')
            .allMatches(en[key] as String)
            .map((m) => m.group(1))
            .toSet();
        final arHolders = RegExp(r'\{(\w+)\}')
            .allMatches(ar[key] as String)
            .map((m) => m.group(1))
            .toSet();
        expect(arHolders, enHolders, reason: key);
      }
    });

    test('the mode descriptions no longer promise processing', () {
      final en = arb('en');
      for (final key in <String>[
        'optimizedForTextDocuments',
        'highContrastForReceipts',
        'preservesColorsAndDetails',
        'maintainsOriginalColors',
        'reducesShadowsImproves',
        'enhancedColorReproduction',
      ]) {
        final text = (en[key] as String).toLowerCase();
        for (final claim in <String>[
          'enhanc',
          'optimiz',
          'processing',
          'reduces',
          'preserves',
          'maintains',
          'security features',
        ]) {
          expect(text.contains(claim), isFalse, reason: '$key: $text');
        }
      }
    });
  });
}
