import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

Map<String, dynamic> arb(String lang) =>
    jsonDecode(read('lib/src/common/localization/app_$lang.arb'))
        as Map<String, dynamic>;

const String servicesFolder = 'lib/src/services/image_to_pdf';
const String viewModelPath =
    'lib/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart';
const String toolkitFolder = 'lib/src/views/Screens/home/Toolkit';
const String viewPath = '$toolkitFolder/image_to_pdf_view.dart';
const String sheetPath = '$toolkitFolder/image_pdf_settings_sheet.dart';

List<String> serviceFiles() => <String>[
      for (final entity in Directory(servicesFolder).listSync())
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.replaceAll('\\', '/'),
    ];

List<String> sources() =>
    <String>[...serviceFiles(), viewModelPath, viewPath, sheetPath];

/// The messages this checkpoint added.
List<String> addedKeys() =>
    arb('en').keys.where((key) => key.startsWith('i2p')).toList();

Set<String> placeholders(String text) =>
    RegExp(r'\{[A-Za-z]+\}').allMatches(text).map((m) => m.group(0)!).toSet();

void main() {
  group('privacy: nothing leaves the phone', () {
    test('the Image to PDF code uses no network, Supabase, R2 or upload client',
        () {
      final forbidden = RegExp(
          r'package:(http|dio|supabase|supabase_flutter|firebase_storage)\b|r2_|Cloudflare|SupabaseClient|\.upload\(|HttpClient');
      for (final path in sources()) {
        expect(forbidden.hasMatch(read(path)), isFalse, reason: path);
      }
    });

    test('only the usage gate touches the legacy Firestore quota document', () {
      for (final path in sources()) {
        final touches = read(path).contains('FirebaseFirestore') ||
            read(path).contains('cloud_firestore');
        expect(touches, path.endsWith('image_pdf_usage_gate.dart'),
            reason: path);
      }
    });

    test('nothing logs paths, names, passwords or picture content', () {
      final logging =
          RegExp(r'\b(print|debugPrint|log|developer\.log)\(|printStack');
      for (final path in sources()) {
        expect(logging.hasMatch(read(path)), isFalse, reason: path);
      }
    });

    test(
        'the converted PDFs are kept out of Android backup and device transfer',
        () {
      expect(read('android/app/src/main/res/xml/backup_rules.xml'),
          contains('app_flutter/image_to_pdf'));
      final modern =
          read('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect('app_flutter/image_to_pdf'.allMatches(modern), hasLength(2));
      final cloud = modern.substring(
          modern.indexOf('<cloud-backup'), modern.indexOf('</cloud-backup>'));
      final transfer = modern.substring(modern.indexOf('<device-transfer'),
          modern.indexOf('</device-transfer>'));
      expect(cloud, contains('app_flutter/image_to_pdf'));
      expect(transfer, contains('app_flutter/image_to_pdf'));
      expect(read('$servicesFolder/image_pdf_store.dart'),
          contains("rootFolderName = 'image_to_pdf'"));
    });

    test(
        'iPhone backup exclusion is requested for the Image to PDF root folder',
        () {
      final vm = read(viewModelPath);
      expect(vm, contains('_backup.exclude(root.path)'));
      expect(vm, contains('ImagePdfStore.rootFolderName'));
    });

    test('backup scope: everything the tool keeps is under the excluded root',
        () {
      // Android: both rule files are in force and name the root, which covers
      // files/, work/ (drafts) and staging/ (private picture copies).
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(
          manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(manifest,
          contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      final store = read('$servicesFolder/image_pdf_store.dart');
      expect(store, contains("Directory(p.join(accountDir.path, 'staging'))"));
      expect(store, contains("Directory(p.join(accountDir.path, 'work'))"));
      expect(store, contains("Directory(p.join(accountDir.path, 'files'))"));
      expect(store, contains('p.join(base.path, rootFolderName, name)'));
      // Nothing is written anywhere else: temporary copies (share, picker,
      // HEIC output) are in the cache or the staging folder.
      final platform = read('$servicesFolder/image_pdf_platform.dart');
      expect(platform, contains("'image_pdf_share'"));
      expect(platform.contains('getApplicationDocumentsDirectory'), isFalse);
      expect(read('$servicesFolder/image_pdf_wiring.dart'),
          contains('tempRoot: getTemporaryDirectory'));
      // iPhone: the native handler marks whatever path it is given (no
      // allow-list), so the tool's root is covered; its children inherit it.
      final swift = read('ios/Runner/AppDelegate.swift');
      expect(swift, contains('isExcludedFromBackup = true'));
      expect(swift.contains('scanner'), isFalse,
          reason: 'the handler must not be limited to Scanner paths');
    });

    test('the password is never stored, persisted or part of the settings', () {
      final models = read('$servicesFolder/image_pdf_models.dart');
      final settingsClass = RegExp(r'class ImagePdfSettings \{[\s\S]*?\n\}')
          .firstMatch(models)!
          .group(0)!;
      expect(settingsClass.toLowerCase().contains('password:'), isFalse);
      expect(settingsClass.contains('String password'), isFalse);
      // Nothing but the grid/list choice is persisted.
      for (final path in [viewModelPath, sheetPath]) {
        expect(read(path).contains('SharedPreferences'), isFalse, reason: path);
      }
      final view = read(viewPath);
      final writes = RegExp(r'prefs\.set\w+\(([^)]*)\)').allMatches(view);
      expect(writes, isNotEmpty);
      for (final write in writes) {
        expect(write.group(1), contains('_viewModeKey'));
      }
      expect(read(viewModelPath).contains('jsonEncode'), isFalse);
      // The old, unfinished password fields are gone.
      expect(view.contains('_protectWithPassword'), isFalse);
      expect(view.contains('_password'), isFalse);
    });

    test('pictures are stripped of metadata on every path to the PDF', () {
      final processor = read('$servicesFolder/image_pdf_processor.dart');
      expect(processor, contains('stripJpegMetadata'));
      expect(processor, contains('image.exif = img.ExifData()'));
      expect(processor, contains('image.iccProfile = null'));
      // Nothing reads a position or camera tag into the app.
      for (final path in sources()) {
        expect(RegExp(r'gpsIfd|gpsLatitude|GPSLatitude').hasMatch(read(path)),
            isFalse,
            reason: path);
      }
    });
  });

  group('permissions and pickers', () {
    test('no storage or camera permission is requested by the tool itself', () {
      for (final path in [viewPath, sheetPath, viewModelPath]) {
        final text = read(path);
        expect(text.contains('permission_handler'), isFalse, reason: path);
        expect(text.contains('CleanPermissionService'), isFalse, reason: path);
        expect(text.contains('CleanMediaService'), isFalse, reason: path);
        expect(text.contains('requestStoragePermissions'), isFalse,
            reason: path);
        expect(text.contains('requestCameraPermission'), isFalse, reason: path);
      }
      expect(read('$servicesFolder/image_pdf_platform.dart'),
          isNot(contains('permission_handler')));
    });

    test(
        'only the legacy Android 9 storage permission is ever asked, in the wiring',
        () {
      final wiring = read('$servicesFolder/image_pdf_wiring.dart');
      expect('Permission.storage'.allMatches(wiring), hasLength(1));
      for (final path in sources()) {
        expect(read(path).contains('MANAGE_EXTERNAL_STORAGE'), isFalse,
            reason: path);
      }
      expect(
          RegExp(r'<uses-permission[^>]*MANAGE_EXTERNAL_STORAGE')
              .hasMatch(read('android/app/src/main/AndroidManifest.xml')),
          isFalse);
    });

    test(
        'pictures arrive at full size: the picker never shrinks or recompresses',
        () {
      final platform = read('$servicesFolder/image_pdf_platform.dart');
      expect(platform, contains('pickMultiImage()'));
      expect(platform, contains('ImageSource.camera'));
      for (final option in ['imageQuality', 'maxWidth', 'maxHeight']) {
        expect(platform.contains(option), isFalse, reason: option);
      }
    });
  });

  group('honesty', () {
    test('no artificial delay or made-up progress', () {
      for (final path in sources()) {
        final text = read(path);
        expect(text.contains('Future.delayed'), isFalse, reason: path);
        expect(text.contains('_processingProgress'), isFalse, reason: path);
        expect(text.contains('* 100).toInt()'), isFalse, reason: path);
      }
      // The only bar is the real count of pictures already checked.
      final view = read(viewPath);
      expect('LinearProgressIndicator'.allMatches(view), hasLength(1));
      expect(
          view, contains('value: items.isEmpty ? null : done / items.length'));
    });

    test('the PDF is made once, verified, and written atomically', () {
      final engine = read('$servicesFolder/image_pdf_engine.dart');
      expect(engine, contains('_verifyBuilt('));
      expect(engine, contains('_writeAtomically('));
      expect(engine, contains('.part'));
      expect(engine, contains('PdfEncryptionAlgorithm.aesx256BitRevision6'));
      expect(engine, contains('isEncrypted'));
      // Protection is proven both ways before a protected file is accepted.
      expect(engine, contains('open-without-password'));
      // A picture that cannot be placed ends the PDF: it is never skipped.
      final pictureLoop = engine.substring(
          engine.indexOf('for (final placed in planned.images)'),
          engine.indexOf('if (settings.watermark)'));
      expect(pictureLoop.contains('continue;'), isFalse);
      expect(pictureLoop.contains('catch (_) {}'), isFalse);
      // Obsolete ciphers are not offered.
      expect(engine.contains('rc4'), isFalse);
      expect(engine.contains('aesx128Bit'), isFalse);
    });

    test('the old shortcuts are gone: cover crop, fake sizes, silent fallback',
        () {
      final processor = read('$servicesFolder/image_pdf_processor.dart');
      final engine = read('$servicesFolder/image_pdf_engine.dart');
      final view = read(viewPath);
      expect(engine.contains('BoxFit.cover'), isFalse);
      expect(view.contains('BoxFit.cover'), isTrue,
          reason: 'thumbnails only; the PDF layout is in the planner');
      expect(
          RegExp(r'BoxFit\.cover')
              .hasMatch(read('$servicesFolder/image_pdf_layout.dart')),
          isFalse);
      expect(processor.contains('processImageSimple'), isFalse);
      expect(view.contains('processImageSimple'), isFalse);
      expect(view.contains('pdf/widgets.dart'), isFalse);
      expect(engine.contains('pdf/widgets.dart'), isFalse);
    });

    test('a conversion is counted once, after the PDF was stored', () {
      final vm = read(viewModelPath);
      expect('recordConversion('.allMatches(vm), hasLength(1));
      expect(vm.indexOf('store.add('),
          lessThan(vm.indexOf('_usage.recordConversion(uid)')));
      // Making a draft never counts.
      final prepare = vm.substring(
          vm.indexOf('Future<DraftOutcome> prepareDraft('),
          vm.indexOf('bool _needsUnicodeFont'));
      expect(prepare.contains('recordConversion'), isFalse);
      // The view never writes the quota itself.
      expect(read(viewPath).contains('increment('), isFalse);
      expect(read(viewPath).contains('FirebaseFirestore'), isFalse);
    });

    test('legacy documents are only counted: never listed, moved or deleted',
        () {
      final wiring = read('$servicesFolder/image_pdf_wiring.dart');
      expect(wiring,
          contains("legacyConvertedPdfIndexKey = 'converted_pdf_documents'"));
      expect(wiring,
          contains('getStringList(legacyConvertedPdfIndexKey)?.length'));
      for (final path in sources()) {
        if (path.endsWith('image_pdf_wiring.dart')) continue;
        expect(read(path).contains('converted_pdf_documents'), isFalse,
            reason: path);
      }
      expect(
          read(viewPath).contains('getApplicationDocumentsDirectory'), isFalse);
    });

    test('the share and export routes carry the title, never the internal id',
        () {
      final platform = read('$servicesFolder/image_pdf_platform.dart');
      expect(platform, contains('exportFileName'));
      expect(platform, contains('exportFile('));
      expect(read(viewModelPath), contains('document.exportFileName'));
      expect(read(viewPath), contains('ShareLive.sendFiles('));
      expect(read(viewPath), contains('PdfViewerScreen('));
    });

    test('an account switch drops pending work and the selection', () {
      final vm = read(viewModelPath);
      expect(vm, contains('_epoch++'));
      expect(vm, contains('_token?.cancel()'));
      expect(vm, contains('currentUserId() != uid'));
      expect(vm, contains('onError: (Object _, StackTrace __) {}'));
      expect(vm, contains('sweepStaging()'));
    });

    test('the heavy work runs on worker isolates, never on the UI isolate', () {
      final executor = read('$servicesFolder/image_pdf_executor.dart');
      expect(executor, contains('Isolate.run('));
      expect(executor, contains('Isolate.spawn<'));
      expect(executor, contains('isolate.kill(priority: Isolate.immediate)'));
      expect(read('lib/src/services/image_to_pdf/image_pdf_wiring.dart'),
          contains('IsolateImagePdfExecutor()'));
    });
  });

  group('localization', () {
    test(
        'every literal key the Image to PDF screens use exists in both languages',
        () {
      final en = arb('en');
      final ar = arb('ar');
      final used = <String>{};
      for (final path in [viewPath, sheetPath]) {
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
        'keys the settings sheet builds from an enum name exist for every value',
        () {
      final en = arb('en');
      final ar = arb('ar');
      String cap(String s) => s[0].toUpperCase() + s.substring(1);
      final keys = <String>[
        for (final q in ['low', 'medium', 'high', 'ultra'])
          'i2pQuality${cap(q)}',
        for (final c in ['none', 'low', 'medium', 'high', 'maximum'])
          'i2pCompression${cap(c)}',
        for (final l in [
          'fitToPage',
          'originalSize',
          'centerFit',
          'tileMultiple'
        ])
          'i2pLayoutHint${cap(l)}',
      ];
      for (final key in keys) {
        expect(en.containsKey(key), isTrue, reason: 'en is missing $key');
        expect(ar.containsKey(key), isTrue, reason: 'ar is missing $key');
      }
      final sheet = read(sheetPath);
      expect(sheet, contains("'i2pQuality\${_cap(v.name)}'"));
      expect(sheet, contains("'i2pCompression\${_cap(v.name)}'"));
      expect(sheet, contains("'i2pLayoutHint\${_cap(_s.layout.name)}'"));
    });

    test(
        'the added messages exist in both languages with the same placeholders',
        () {
      final en = arb('en');
      final ar = arb('ar');
      final keys = addedKeys();
      expect(keys.length, greaterThanOrEqualTo(80));
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
      final enumBody = RegExp(r'enum ImagePdfFailure \{([\s\S]*?)\n\}')
          .firstMatch(read('$servicesFolder/image_pdf_models.dart'))!
          .group(1)!;
      final kinds = RegExp(r'^  ([a-zA-Z]+),', multiLine: true)
          .allMatches(enumBody)
          .map((m) => m.group(1)!)
          .toList();
      expect(kinds.length, greaterThan(20));
      for (final kind in kinds) {
        expect(view.contains('case ImagePdfFailure.$kind:'), isTrue,
            reason: 'no message for $kind');
      }
    });
  });

  group('the old behaviour that was wrong is not back', () {
    test('margins are in millimetres, not "px"', () {
      final sheet = read(sheetPath);
      expect(sheet.contains("px'"), isFalse);
      expect(sheet, contains("'i2pMillimetres'"));
      expect(arb('en')['i2pMillimetres'], '{value} mm');
    });

    test('the timestamp is a date, not an image size', () {
      final engine = read('$servicesFolder/image_pdf_engine.dart');
      expect(engine, contains('ImagePdfText.formatTimestamp(job.timestamp)'));
      expect(engine.contains('KB'), isFalse);
      expect(engine.contains('DateTime.now()'), isFalse,
          reason: 'one moment is captured per PDF and passed in');
    });

    test('a cover page only exists when asked for', () {
      final layout = read('$servicesFolder/image_pdf_layout.dart');
      expect(layout, contains('if (settings.coverPage)'));
      expect(layout.contains('timestamp || '), isFalse);
      expect(layout.contains('watermark ||'), isFalse);
    });

    test('Tile Multiple is a real grid, not a stretched single picture', () {
      final layout = read('$servicesFolder/image_pdf_layout.dart');
      expect(layout, contains('tilesPerPage'));
      expect(layout, contains('_grid('));
    });

    test('the settings sheet is not the old inline class any more', () {
      expect(read(viewPath).contains('_AdvancedSettingsSheet'), isFalse);
      expect(read(viewPath), contains('ImagePdfSettingsSheet('));
    });
  });
}
