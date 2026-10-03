// Source guards for Share: every active share entry point goes through the one
// path, nothing private can reach a message, no secret or backend call is in the
// share code, and every string it shows exists in both languages.
//
// These read the source files; they prove how the code is written, not how a
// phone behaves.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

List<File> dartFilesUnder(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String relative(File file) => file.path.replaceAll('\\', '/');

const String shareFolder = 'lib/src/services/share';

const Map<String, String> detailScreens = <String, String>{
  'lib/src/views/Screens/ViewDetails/requested_view_details.dart':
      'PropertyShareSource.request(',
  'lib/src/views/Screens/ViewDetails/offers_view_details.dart':
      'PropertyShareSource.offer(',
  'lib/src/views/Screens/ViewDetails/owners_view_details.dart':
      'OwnerShareSource(',
  'lib/src/views/Screens/ViewDetails/brokers_view_details.dart':
      'BrokerShareSource(',
  'lib/src/views/Screens/ViewDetails/watchmen_view_details.dart':
      'WatchmanShareSource(',
  'lib/src/views/Screens/ViewDetails/offices_view_details.dart':
      'OfficeShareSource(',
};

void main() {
  final en = json.decode(read('lib/src/common/localization/app_en.arb'))
      as Map<String, dynamic>;
  final ar = json.decode(read('lib/src/common/localization/app_ar.arb'))
      as Map<String, dynamic>;

  group('one path out of the app', () {
    test('only the share code talks to the share plugin', () {
      final offenders = <String>[];
      for (final file in dartFilesUnder('lib')) {
        final path = relative(file);
        if (path.startsWith('$shareFolder/')) continue;
        final source = read(file.path);
        if (source.contains('package:share_plus/') ||
            source.contains('SharePlus') ||
            source.contains('ShareParams') ||
            source.contains('Share.share') ||
            source.contains('shareXFiles')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'these call the plugin directly: $offenders');
    });

    test('the plugin is reached from exactly one file', () {
      final users = dartFilesUnder(shareFolder)
          .where((f) => read(f.path).contains('package:share_plus/'))
          .map(relative)
          .toList();
      expect(users, <String>['$shareFolder/share_plus_sink.dart']);
    });

    test('the two old dialogs are gone, replaced by the one shared dialog', () {
      expect(
          File('lib/src/views/Screens/ViewDetails/widgets/share_options_dialog.dart')
              .existsSync(),
          isFalse);
      expect(
          File('lib/src/views/Screens/ViewDetails/widgets/request_share_options_dialog.dart')
              .existsSync(),
          isFalse);
      expect(
          File('lib/src/views/Widgets/share_options_dialog.dart').existsSync(),
          isTrue);
    });

    for (final entry in detailScreens.entries) {
      final name = entry.key.split('/').last;
      test('$name opens the shared dialog with its own record', () {
        final source = read(entry.key);
        expect(source, contains('ShareOptionsDialog.show('));
        expect(source, contains(entry.value));
        // The placeholder that only showed a toast is gone.
        expect(source.contains('shareFunctionality'), isFalse);
        expect(source.contains('checkOutThis'), isFalse);
        // No longer reaches for the signed-in account's phone number.
        expect(source.contains('currentUser?.phoneNumber'), isFalse);
        expect(source.contains('userPhoneNumber'), isFalse);
      });

      test(
          '$name has one Share icon, the same icon and size as the others, '
          'with a label for a screen reader', () {
        final source = read(entry.key);
        expect(RegExp('Icons\\.share_outlined').allMatches(source).length, 1);
        expect(
          source,
          contains(
              "icon: Icon(Icons.share_outlined, color: colors.onSurface, size: 18),\n"
              "            tooltip: AppLocalizations.of(context).translate('share'),"),
        );
        // The same 36 x 36 box as the Back and Delete icons beside it.
        final box = RegExp(
                r'Container\(\s*width: 36,\s*height: 36,\s*margin: [^\n]*\n\s*decoration: _?ShareActionDecoration\(colors\),')
            .hasMatch(source);
        expect(box, isTrue);
      });
    }

    test(
        'the Offer and Owner screens hand over the media they hold, and a '
        'way to refresh a private link', () {
      final offerScreen =
          read('lib/src/views/Screens/ViewDetails/offers_view_details.dart');
      expect(offerScreen,
          contains('ShareMediaItem.fromRefs(_loadCoordinator.displayItems)'));
      expect(offerScreen,
          contains('refreshLink: _loadCoordinator.refreshSignedUrl'));

      final ownerScreen =
          read('lib/src/views/Screens/ViewDetails/owners_view_details.dart');
      expect(ownerScreen, contains('ShareMediaItem.fromRefs(refs)'));
      expect(ownerScreen, contains('refreshLink: loader?.refreshSignedUrl'));
      expect(ownerScreen, contains('loader.displayItems'));
    });

    test('the quotation list shares through the dialog and a share-safe PDF',
        () {
      final view =
          read('lib/src/views/Screens/home/quotation/list_quotation_view.dart');
      expect(view, contains('ShareOptionsDialog.show('));
      expect(view, contains('QuotationShareSource('));
      expect(view, contains('vm.resolvePdfForShare(quotation)'));
      expect(view.contains('XFile('), isFalse);
      expect(view.contains('Quotation for'), isFalse);
      expect(view.contains('Quotation Document'), isFalse);
    });

    test('the PDF viewer shares a named file, never a link, and never an error',
        () {
      final viewer =
          read('lib/src/views/Screens/home/Toolkit/pdf_viewer_screen.dart');
      expect(viewer, contains('ShareLive.sendNamedFile('));
      expect(viewer, contains('ShareLive.originOf(buttonContext)'));
      expect(viewer.contains(r": $e'"), isFalse);
      expect(viewer.contains('text: widget.networkUrl'), isFalse);
      expect(viewer.contains('Fallback: share the link'), isFalse);
      expect(viewer, contains('bool _isSharing'));
    });

    test('the Toolkit shares its own files through the one launcher', () {
      for (final path in <String>[
        'lib/src/views/Screens/home/Toolkit/combine_pdfs_view.dart',
        'lib/src/views/Screens/home/Toolkit/image_to_pdf_view.dart',
        'lib/src/views/Screens/home/Toolkit/scanner_view.dart',
        'lib/src/views/Screens/home/Toolkit/signature/signed_documents_storage.dart',
      ]) {
        final source = read(path);
        expect(source, contains('ShareLive.sendFiles('), reason: path);
        expect(source.contains('XFile('), isFalse, reason: path);
      }
      // A selection of signed documents is one share sheet, not one per file.
      expect(
          read(
              'lib/src/views/Screens/home/Toolkit/signature/signature_view.dart'),
          contains('SignedDocumentsHelper.shareDocuments('));
    });

    test('the icon-only Share button on each Toolkit document card has a label',
        () {
      for (final path in <String>[
        'lib/src/views/Screens/home/Toolkit/combine_pdfs_view.dart',
        'lib/src/views/Screens/home/Toolkit/image_to_pdf_view.dart',
        'lib/src/views/Screens/home/Toolkit/scanner_view.dart',
        'lib/src/views/Screens/home/Toolkit/signature/signature_view.dart',
      ]) {
        final labelled = RegExp(
          r"Tooltip\(\s*message: AppLocalizations\.of\(context\)\.translate\('share'\),\s*child: _buildGridActionButton\(\s*icon: Icons\.share,",
        ).hasMatch(read(path));
        expect(labelled, isTrue, reason: path);
      }
    });

    test(
        'bulk share errors in the Toolkit use a message that exists and is '
        'about sharing', () {
      for (final path in <String>[
        'lib/src/views/Screens/home/Toolkit/combine_pdfs_view.dart',
        'lib/src/views/Screens/home/Toolkit/image_to_pdf_view.dart',
        'lib/src/views/Screens/home/Toolkit/scanner_view.dart',
      ]) {
        expect(read(path), contains("translate('failedToShareDocuments')"),
            reason: path);
      }
      expect(en['failedToShareDocuments'], isNotNull);
      expect(ar['failedToShareDocuments'], isNotNull);
    });

    test('Share App opens the system sheet once and reports only a real share',
        () {
      final view =
          read('lib/src/views/Screens/home/Profile/share_app_view.dart');
      expect(view, contains('ShareLive.sendText('));
      expect(view, contains('_shareFromButton(loc)'));
      expect(view, contains('outcome != ShareOutcome.dismissed'));
    });
  });

  group('nothing private reaches a message or a file name', () {
    final textFiles = <String>[
      '$shareFolder/share_text.dart',
      '$shareFolder/share_format.dart',
      '$shareFolder/share_source.dart',
      '$shareFolder/share_sources.dart',
    ];

    test('the message code never touches a link, an id or a storage key', () {
      for (final path in textFiles) {
        final source = read(path);
        for (final word in <String>[
          'signedUrl',
          'mediaObjectId',
          'cacheKey',
          'mediaUrl',
          'pdfMediaId',
          'officeLogoMediaId',
          'objectKey',
          'X-Amz',
          'cloudflare',
          'r2.dev',
          'supabase',
          'userId',
          'currentUser',
          'AuthViewModel',
          'email',
        ]) {
          expect(source.contains(word), isFalse,
              reason: '$path mentions $word');
        }
      }
    });

    test('the only link a message carries is the public map link', () {
      for (final path in textFiles) {
        final links = RegExp(r"https?://[^'\s]+")
            .allMatches(read(path))
            .map((m) => m.group(0)!)
            .toList();
        expect(
          links.every((l) => l.startsWith('https://www.google.com/maps/')),
          isTrue,
          reason: '$path: $links',
        );
      }
    });

    test('no developer text is written for a missing string', () {
      final labels = read('$shareFolder/share_labels.dart');
      expect(labels, contains("startsWith('** ')"));
      expect(labels, contains("endsWith(' not found')"));
    });

    test('a file name is built from letters and digits only', () {
      final format = read('$shareFolder/share_format.dart');
      expect(format, contains(r"RegExp(r'[^\p{L}\p{N}]+', unicode: true)"));
      final preparer = read('$shareFolder/share_preparer.dart');
      expect(preparer, contains('ShareFormat.fileStem(attachment.baseName'));
    });
  });

  group('no secret, no backend, no new permission', () {
    test('the share code holds no key and makes no backend call', () {
      for (final file in dartFilesUnder(shareFolder)) {
        final source = read(file.path);
        for (final word in <String>[
          'service_role',
          'sb_secret',
          'SUPABASE_SERVICE',
          'serviceKey',
          'apikey',
          'Bearer ',
          'Authorization',
          'Supabase.instance',
          '.rpc(',
          "from('",
          'Firebase',
          'Firestore',
        ]) {
          expect(source.contains(word), isFalse,
              reason: '${relative(file)} mentions $word');
        }
      }
    });

    test(
        'files are prepared in the temporary folder, with no storage permission',
        () {
      final live = read('$shareFolder/share_live.dart');
      expect(live, contains('getTemporaryDirectory()'));
      for (final file in dartFilesUnder(shareFolder)) {
        final source = read(file.path);
        expect(source.contains('permission_handler'), isFalse);
        expect(source.contains('Permission.'), isFalse);
        expect(source.contains('getExternalStorageDirectory'), isFalse);
        expect(source.contains('getDownloadsDirectory'), isFalse);
        expect(source.contains('getApplicationDocumentsDirectory'), isFalse);
      }
    });

    test('a share is only ever as large as the app\'s own media limits allow',
        () {
      final fetcher = read('$shareFolder/share_media_fetcher.dart');
      expect(fetcher, contains('defaultMaxImageBytes'));
      expect(fetcher, contains('defaultMaxVideoBytes'));
      expect(fetcher, contains('connectTimeout'));
      expect(fetcher, contains('idleTimeout'));
    });

    test('the iPad anchor is always passed on', () {
      expect(read('$shareFolder/share_plus_sink.dart'),
          contains('sharePositionOrigin: _rect(request.origin)'));
      final live = read('$shareFolder/share_live.dart');
      expect(
          'origin: origin,'.allMatches(live).length +
              'origin: originOf(context)'.allMatches(live).length,
          greaterThanOrEqualTo(2));
      expect(read('lib/src/views/Widgets/share_options_dialog.dart'),
          contains('ShareLive.originOf(buttonContext)'));
    });
  });

  group('every string the Share screens show exists in both languages', () {
    test('the keys the dialog asks for', () {
      final dialog = read('lib/src/views/Widgets/share_options_dialog.dart');
      final keys = RegExp(r"translate\(\s*'([A-Za-z0-9]+)'\s*\)")
          .allMatches(dialog)
          .map((m) => m.group(1)!)
          .toSet();
      // The dynamic keys too (titles, failures).
      keys.addAll(<String>[
        'shareOffer', 'shareRequest', 'shareOwner', 'shareBroker',
        'shareWatchman', 'shareOffice', 'shareQuotation', //
        'shareErrorNetwork', 'shareErrorUnavailable', 'shareErrorSession',
        'shareErrorGeneric', //
        'shareMediaPhotoN', 'shareMediaVideoN', 'clear', //
        'preparingFiles', 'sharing',
      ]);
      expect(
          keys,
          containsAll(<String>[
            'selectWhatToShare',
            'selectAll',
            'close',
            'cancel',
            'share',
            'sharing',
            'preparingFiles',
            'retry',
            'clear',
            'shareSelectAtLeastOne',
            'shareMediaPhotoN',
            'shareMediaVideoN',
            'shareMediaCount',
            'shareItemUnavailable',
          ]));
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: '$key missing in English');
        expect(ar[key], isA<String>(), reason: '$key missing in Arabic');
        expect((en[key] as String).trim(), isNotEmpty, reason: key);
        expect((ar[key] as String).trim(), isNotEmpty, reason: key);
      }
    });

    test('placeholders match between the languages', () {
      for (final key in <String>[
        'shareMediaPhotoN',
        'shareMediaVideoN',
        'shareMediaCount',
      ]) {
        final inEnglish = RegExp(r'\{(\w+)\}')
            .allMatches(en[key] as String)
            .map((m) => m.group(1))
            .toSet();
        final inArabic = RegExp(r'\{(\w+)\}')
            .allMatches(ar[key] as String)
            .map((m) => m.group(1))
            .toSet();
        expect(inEnglish, isNotEmpty, reason: key);
        expect(inArabic, inEnglish, reason: key);
      }
    });

    test('the failure sentences are plain: no link, no code, no exception', () {
      for (final key in <String>[
        'shareErrorNetwork',
        'shareErrorUnavailable',
        'shareErrorSession',
        'shareErrorGeneric',
      ]) {
        for (final text in <String>[en[key] as String, ar[key] as String]) {
          expect(text.contains('http'), isFalse, reason: key);
          expect(text.toLowerCase().contains('exception'), isFalse,
              reason: key);
          expect(text.contains(RegExp(r'\b[A-Z][a-z]+[A-Z]\w+\b')), isFalse,
              reason: '$key reads like a type name');
        }
      }
    });

    test(
        'Arabic has the labels the Arabic message needs, including the sale '
        'request that used to be missing', () {
      expect(ar['saleRequest'], isA<String>());
      expect((ar['saleRequest'] as String).trim(), isNot('Sale request'));
    });

    test('the keys added for Share appear once in each file', () {
      const added = <String>[
        'shareOwner',
        'shareBroker',
        'shareWatchman',
        'shareOffice',
        'shareQuotation',
        'shareSelectAtLeastOne',
        'shareMediaPhotoN',
        'shareMediaVideoN',
        'shareMediaCount',
        'shareItemUnavailable',
        'shareErrorNetwork',
        'shareErrorUnavailable',
        'shareErrorSession',
        'shareErrorGeneric',
        'saleRequest',
        'failedToShareDocuments',
      ];
      for (final path in <String>[
        'lib/src/common/localization/app_en.arb',
        'lib/src/common/localization/app_ar.arb',
      ]) {
        final source = read(path);
        for (final key in added) {
          final count =
              RegExp('^  "$key":', multiLine: true).allMatches(source).length;
          expect(count, 1, reason: '$path has $key $count times');
        }
      }
    });
  });
}
