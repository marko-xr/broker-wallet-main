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

/// The ways code waits a while before doing something. A share is never
/// sequenced by one of these: the next step waits for the person's own tap. A
/// plain handler, a method-call handler, or a name that merely contains one of
/// these words is not timing.
final List<RegExp> timingApis = <RegExp>[
  RegExp(r'\bFuture\s*\.\s*delayed\b'),
  RegExp(r'\bTimer\s*(\.\s*periodic\s*)?\('),
  RegExp(r'\bCountDownTimer\b'),
  RegExp(r'\bpostDelayed\b'),
  RegExp(r'\bpostAtTime\b'),
  RegExp(r'\bsendMessageDelayed\b'),
  RegExp(r'\bscheduleAtFixedRate\b'),
  RegExp(r'\bThread\s*\.\s*sleep\b'),
  RegExp(r'\bsleep\s*\('),
  RegExp(r'\bdelay\s*\('),
];

bool usesTiming(String code) => timingApis.any((api) => api.hasMatch(code));

/// The argument text of every `translate(` call in [source], with whitespace
/// collapsed. The arguments are read with balanced parentheses, so a
/// conditional, a nested call or a line break cannot hide a key.
List<String> translateArguments(String source) {
  final arguments = <String>[];
  for (final call in RegExp(r'\btranslate\(').allMatches(source)) {
    var depth = 1;
    var end = call.end;
    while (end < source.length && depth > 0) {
      final char = source[end];
      if (char == '(') depth++;
      if (char == ')') depth--;
      end++;
    }
    arguments.add(
      source
          .substring(call.end, end - 1)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }
  return arguments;
}

/// The quoted localization keys inside [text]: both branches of a conditional.
Set<String> quotedKeys(String text) => RegExp(r"'([A-Za-z][A-Za-z0-9]*)'")
    .allMatches(text)
    .map((match) => match.group(1)!)
    .toSet();

/// The keys a widget names as literals: in `translate(...)` calls, and as the
/// text of the dialog's note lines.
Set<String> literalKeys(String source) => <String>{
      for (final argument in translateArguments(source))
        ...quotedKeys(argument),
      for (final match in RegExp(r"_buildNote\(\s*context,\s*'([A-Za-z0-9]+)'")
          .allMatches(source))
        match.group(1)!,
    };

/// The keys the Share screens ask for through a value instead of a literal,
/// read from the code that holds them: the row titles, the title of each kind
/// of record, and the sentence of each failure. A key added there is checked; a
/// key removed there is not demanded.
Set<String> dynamicShareKeys() {
  final models = read('lib/src/services/share/share_models.dart');
  final sources = read('lib/src/services/share/share_sources.dart');
  final rows = models.substring(
    models.indexOf('enum ShareSection {'),
    models.indexOf('const ShareSection('),
  );
  final failures = models.substring(
    models.indexOf('String get messageKey'),
    models.indexOf('/// A share that could not be prepared or opened.'),
  );
  return <String>{
    for (final match in RegExp(r"\('([A-Za-z0-9]+)'\)").allMatches(rows))
      match.group(1)!,
    for (final match in RegExp(r"=> '([A-Za-z0-9]+)'").allMatches(failures))
      match.group(1)!,
    for (final match
        in RegExp(r'String get titleKey =>([^;]*);').allMatches(sources))
      ...quotedKeys(match.group(1)!),
    for (final match in RegExp(
      r'String sectionTitleKey\(ShareSection section\) =>([^;]*);',
    ).allMatches(sources))
      ...quotedKeys(match.group(1)!),
  };
}

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

    test(
        'the message of a media batch is also copied through one clipboard '
        'that can never stop the share', () {
      // Only the clipboard file touches the platform clipboard, and nothing in
      // it logs the text or lets a failure escape. The platform services are
      // imported by it and by the Android sink's method channel only.
      for (final file in dartFilesUnder(shareFolder)) {
        final path = relative(file);
        final source = read(file.path);
        if (path != '$shareFolder/share_clipboard.dart') {
          expect(source.contains('Clipboard.'), isFalse,
              reason: '$path reaches the clipboard itself');
        }
        if (path != '$shareFolder/share_clipboard.dart' &&
            path != '$shareFolder/share_android_sink.dart') {
          expect(source.contains('package:flutter/services.dart'), isFalse,
              reason: '$path imports the platform services');
        }
      }
      final clipboard = read('$shareFolder/share_clipboard.dart');
      expect(clipboard, contains('Clipboard.setData('));
      expect(clipboard, contains('} catch (_) {\n      return false;'));
      expect(clipboard.contains('print('), isFalse);
      expect(clipboard.contains('debugPrint('), isFalse);

      // The app's engine really has it, so the copy is not test-only.
      expect(read('$shareFolder/share_live.dart'),
          contains('clipboard: const SystemShareClipboard()'));

      final controller = read('$shareFolder/share_flow_controller.dart');
      expect(controller, contains('copied = await clipboard.copy(text);'));
      // The clipboard is never restored or cleared afterwards.
      expect(controller.contains("copy('')"), isFalse);
      expect(controller.contains('previousClipboard'), isFalse);
      expect(controller.contains('getData('), isFalse);
    });

    test(
        'the request for a record\'s media is made in one place, and a batch of '
        'several files carries no message of its own', () {
      // `ShareRequest(` is built by the payload rule for media, by the live
      // helpers for the Toolkit's own files, and nowhere else: not by the flow,
      // a dialog or a picker.
      final builders = <String>[
        for (final file in dartFilesUnder('lib'))
          if (read(file.path).contains('ShareRequest(')) relative(file),
      ]..sort();
      expect(builders, <String>[
        '$shareFolder/share_live.dart',
        '$shareFolder/share_models.dart',
        '$shareFolder/share_payload.dart',
      ]);

      final controller = read('$shareFolder/share_flow_controller.dart');
      expect(controller.contains('ShareRequest('), isFalse);
      expect(controller, contains('SharePayload.plan('));
      expect(controller, contains('payload.toRequest(origin)'));
      expect(controller, contains('if (!payload.isLaunchable) {'));

      // The rule depends on how many files there are and on whether they are
      // all of one family; it never relabels a family or looks at the platform.
      final payload = read('$shareFolder/share_payload.dart');
      expect(payload, contains('static const int severalFiles = 2;'));
      expect(payload, contains('list.every((file) => file.isMedia)'));
      expect(payload, contains('mediaBatch: isMediaBatch,'));
      expect(
          payload,
          contains(
              'return SharePayload._(kind: SharePayloadKind.mediaBatch, files: list);'),
          reason: 'a media batch is built from its files alone');
      expect(payload.contains('isVideo'), isFalse);
      expect(payload.contains('isImage'), isFalse);
      expect(payload.contains('Platform.'), isFalse,
          reason: 'the rule is product policy, not a platform check');
    });

    test(
        'photos and videos together are never one batch: refused where the '
        'batch is made, before anything is copied or opened, and again where '
        'Android is handed it', () {
      // Dart. The family of a file is read in exactly one place, and that place
      // is the check that a batch is of one family. It comes after the cases
      // that are not batches and before the only way to a media batch.
      final payload = read('$shareFolder/share_payload.dart');
      const mixed = 'if (list.map((file) => file.family).toSet().length > 1) {';
      final familyReads = <String>[
        for (final line in payload.split('\n'))
          if (!line.trimLeft().startsWith('//') && line.contains('.family'))
            line.trim(),
      ];
      expect(familyReads, <String>[mixed],
          reason: 'the family is only compared, to refuse a mix');
      final refusal = payload.indexOf(mixed);
      final refused =
          payload.indexOf('kind: SharePayloadKind.inconsistentBatch,');
      final batch = payload.indexOf(
          'return SharePayload._(kind: SharePayloadKind.mediaBatch, files: list);');
      expect(
          refusal, greaterThan(payload.indexOf('factory SharePayload.plan(')));
      expect(refused, greaterThan(refusal));
      expect(batch, greaterThan(refused));
      expect(
          payload.indexOf('SharePayloadKind.filesWithText'), lessThan(refusal),
          reason: 'a whole selection is not a batch and is not refused');
      // A refused mix carries no message and no subject: it goes nowhere.
      expect(
          payload
              .substring(refused, payload.indexOf(');', refused))
              .contains('text:'),
          isFalse);
      expect(
          payload,
          contains('bool get isLaunchable => '
              'kind != SharePayloadKind.inconsistentBatch;'));

      // The flow: a payload that cannot be launched ends the step as a failure
      // before the busy check, the copy and the launch.
      final controller = read('$shareFolder/share_flow_controller.dart');
      final check = controller.indexOf('if (!payload.isLaunchable) {');
      final step = controller.substring(
          check, controller.indexOf('if (engine.launcher.isOpen) {'));
      expect(check, greaterThan(0));
      expect(step,
          contains('throw const ShareFailure(ShareFailureKind.generic);'));
      expect(step.contains('_copy('), isFalse);
      expect(step.contains('launch('), isFalse);

      // Kotlin. The adapter declares the type of its files and refuses a mix
      // while it builds the intent, which happens before the sheet is started.
      const kotlinFolder =
          'android/app/src/main/kotlin/com/example/broker_wallet';
      final format = read('$kotlinFolder/MultiMediaShareFormat.kt');
      final plugin = read('$kotlinFolder/MultiMediaSharePlugin.kt');
      expect(format,
          contains('require(families.size == 1 && families.first() != "*") {'));
      expect(plugin, contains('buildSendIntent(uris: List<Uri>'));
      final build = plugin.substring(plugin.indexOf('fun buildSendIntent('));
      expect(
          build.substring(0, build.indexOf('\n    }\n')),
          contains(
              'intent.type = MultiMediaShareFormat.commonMimeType(mimeTypes)'));
      expect(
          RegExp(r'val intent = buildSendIntent\(uris, mimeTypes\)\s+'
                  r'activity\.startActivity\(')
              .hasMatch(plugin),
          isTrue,
          reason:
              'the intent is built, and so a mix refused, before the sheet');
      expect(plugin.indexOf('catch (e: IllegalArgumentException) {'),
          lessThan(plugin.indexOf('catch (e: Exception) {')));
    });

    test(
        'one decision order: prepare, plan from the prepared files, refuse a '
        'busy sheet, then copy once, then one native call', () {
      final controller = read('$shareFolder/share_flow_controller.dart');
      int at(String text) {
        final index = controller.indexOf(text);
        expect(index, greaterThan(0), reason: 'missing $text');
        return index;
      }

      final preparing = at('_setStatus(ShareFlowStatus.preparing);');
      final prepare = at('await engine.preparer.prepare(');
      final cancelled = at('if (token.isCancelled || _disposed) {');
      final plan = at('SharePayload.plan(');
      final launchable = at('if (!payload.isLaunchable) {');
      final open = at('if (engine.launcher.isOpen) {');
      final sharing = at('_setStatus(ShareFlowStatus.sharing);');
      final copy = at('await _copy(copyText)');
      final launch = at('await engine.launcher.launch(');
      final order = <int>[
        preparing,
        prepare,
        cancelled,
        plan,
        launchable,
        open,
        sharing,
        copy,
        launch,
      ];
      expect(order, orderedEquals(<int>[...order]..sort()));
      expect('engine.launcher.launch('.allMatches(controller).length, 1);
      expect('await _copy('.allMatches(controller).length, 1);
      // Only the step's own files are turned into attachments.
      expect(controller, contains('for (final item in media) {'));
      expect(
          controller,
          contains(
              'final media = family == null ? batches.master : batches.itemsOf(family);'));
    });

    test(
        'the pinned share_plus is the one whose Android source was inspected '
        '(upgrading it is its own checkpoint)', () {
      final lock = read('pubspec.lock');
      final match = RegExp(
        r'\n  share_plus:\n(?:    .*\n)*?    version: "([^"]+)"',
      ).firstMatch(lock);
      expect(match, isNotNull);
      expect(match!.group(1), '11.1.0');
    });

    test(
        'no widget decides platform policy: no MIME, no platform check, no '
        'native parameter in the dialog or the picker', () {
      for (final path in <String>[
        'lib/src/views/Widgets/share_options_dialog.dart',
        'lib/src/views/Widgets/share_media_picker.dart',
      ]) {
        final source = read(path);
        for (final word in <String>[
          "'image/",
          "'video/",
          'ShareParams',
          'ShareRequest',
          'SharePayload',
          'ShareDelivery',
          'AndroidMediaBatchSink',
          'MethodChannel',
          'Platform.',
          'ACTION_SEND',
          'mimeType',
          '.family',
          'Clipboard',
        ]) {
          expect(source.contains(word), isFalse, reason: '$path has $word');
        }
      }
      // The platform is asked in one place, which picks the Android sink and
      // the delivery.
      for (final file in dartFilesUnder(shareFolder)) {
        final path = relative(file);
        if (path == '$shareFolder/share_live.dart') continue;
        expect(read(file.path).contains('Platform.is'), isFalse,
            reason: '$path decides by platform');
      }
      final live = read('$shareFolder/share_live.dart');
      expect(live, contains('Platform.isAndroid'));
      expect(live,
          contains('AndroidMediaBatchSink(system: const SharePlusSink())'));
      expect('AndroidMediaBatchSink('.allMatches(live).length, 1);
      expect(live, contains('? ShareDelivery.familyBatches'));
      expect(live, contains(': ShareDelivery.wholeSelection'));
    });

    test(
        'the dialog says what will happen before anything is shared, where the '
        'person is already reading, and asks nothing', () {
      final dialog = read('lib/src/views/Widgets/share_options_dialog.dart');
      expect(dialog, contains('controller.copiesDetails'));
      expect(dialog, contains('controller.twoStepShare'));
      expect(dialog, contains('controller.hasPendingStep'));
      for (final key in <String>[
        'shareDetailsCopyNote',
        'shareTwoStepNote',
        'shareStepVideosReady',
        'share-details-note',
        'share-two-step-note',
        'share-step-status',
      ]) {
        expect(dialog, contains("'$key'"), reason: key);
      }
      expect(dialog, contains("'continueLabel'"));
      // Not a SnackBar or toast raised as the native sheet opens, and no
      // dialog, sheet or modal of its own: the notes are lines in the dialog.
      for (final word in <String>[
        'AppNotifier',
        'showSnackBar',
        'Fluttertoast',
        'onDetailsCopied',
        'AlertDialog',
        'SimpleDialog',
        'showModalBottomSheet',
        'ShareBatchChoice',
      ]) {
        expect(dialog.contains(word), isFalse, reason: word);
      }
      expect('showDialog<'.allMatches(dialog).length, 1,
          reason: 'only the dialog opens itself; nothing opens another');
    });

    test(
        'a mixed choice is shared in explicit steps: one call per tap, the '
        'dialog only continues, and nothing is timed', () {
      final dialog = read('lib/src/views/Widgets/share_options_dialog.dart');
      expect('controller.share('.allMatches(dialog).length, 1,
          reason: 'one call per tap; the dialog never starts a second step');
      expect(dialog, contains('if (result == ShareFlowResult.shared)'));
      expect(dialog.contains('ShareFlowResult.stepShared'), isFalse,
          reason: 'a step leaves the dialog open without special handling');
      final controller = read('$shareFolder/share_flow_controller.dart');
      expect(controller, contains('return ShareFlowResult.stepShared;'));
      expect(controller, contains('final Set<MediaFamily> _completed'));
      // No timer sequences the steps: not in the flow, the dialog, the picker or
      // the native transport. Only code that really waits is refused; a plain
      // handler or a method-call handler is not that.
      for (final path in <String>[
        ...dartFilesUnder(shareFolder).map(relative),
        'lib/src/views/Widgets/share_options_dialog.dart',
        'lib/src/views/Widgets/share_media_picker.dart',
        'android/app/src/main/kotlin/com/example/broker_wallet/MultiMediaSharePlugin.kt',
        'android/app/src/main/kotlin/com/example/broker_wallet/MultiMediaShareFormat.kt',
      ]) {
        final offenders = <String>[
          for (final api in timingApis)
            if (api.hasMatch(read(path))) api.pattern,
        ];
        expect(offenders, isEmpty, reason: '$path waits: $offenders');
      }
    });

    test('the timing guard refuses real timing and lets plain handlers be', () {
      for (final timed in <String>[
        'Future.delayed(const Duration(milliseconds: 500), second);',
        'await Future .delayed(d);',
        'Timer(const Duration(seconds: 1), second);',
        'Timer.periodic(d, tick);',
        'Handler(Looper.getMainLooper()).postDelayed({ second() }, 500)',
        'handler.sendMessageDelayed(message, 500)',
        'handler.postAtTime(task, 500)',
        'object : CountDownTimer(500, 100) {}',
        'Thread.sleep(500)',
        'sleep(const Duration(seconds: 1));',
        'delay(500)',
      ]) {
        expect(usesTiming(timed), isTrue, reason: timed);
      }
      for (final plain in <String>[
        'MethodChannel.MethodCallHandler {',
        '.setMethodCallHandler(MultiMediaSharePlugin(activity))',
        'val handler = Handler(Looper.getMainLooper())',
        'handler.post { show() }',
        'connectTimeout',
        'idleTimeout',
        'final retryDelayLabel = loc.translate(key);',
      ]) {
        expect(usesTiming(plain), isFalse, reason: plain);
      }
    });

    test(
        'the Share button has one loading indicator, drawn only while files '
        'are prepared, and the notes follow the reading direction', () {
      final dialog = read('lib/src/views/Widgets/share_options_dialog.dart');
      final controller = read('$shareFolder/share_flow_controller.dart');
      // One spinner, on the button, and only for the one status that means
      // files are being prepared: not while the share sheet is open.
      expect('CircularProgressIndicator('.allMatches(dialog).length, 1);
      expect(dialog, contains('child: controller.isPreparing'));
      expect(
          controller,
          contains(
              'bool get isPreparing => _status == ShareFlowStatus.preparing;'));
      expect(dialog.contains("'sharing'"), isFalse,
          reason: 'no "Sharing..." state: nothing spins behind the sheet');
      // No second line of progress, and nobody is told about each file.
      for (final word in <String>[
        'sharePreparingCount',
        'share-preparing-count',
        'preparedFiles',
        'filesToPrepare',
      ]) {
        expect(dialog.contains(word), isFalse, reason: 'the dialog has $word');
        expect(controller.contains(word), isFalse,
            reason: 'the flow has $word');
      }
      expect(controller.contains('onProgress'), isFalse);
      expect(controller.contains('_preparedFiles'), isFalse);
      // The notes take the whole width of their row and begin at the reading
      // edge, from the one Directionality: never at a named side.
      expect(dialog, contains('textAlign: TextAlign.start,'));
      expect(dialog, contains('width: double.infinity,'));
      for (final word in <String>[
        'TextAlign.right',
        'TextAlign.left',
        'TextAlign.center',
        'Alignment.centerRight',
        'Alignment.centerLeft',
      ]) {
        expect(dialog.contains(word), isFalse, reason: 'the dialog has $word');
      }
    });

    test(
        'the master selection is never changed by sharing, and progress is '
        'tracked by family, never by position', () {
      final controller = read('$shareFolder/share_flow_controller.dart');
      final start = controller.indexOf('Future<ShareFlowResult> share(');
      final end = controller.indexOf('/// The first family of [batches]');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final shareBody = controller.substring(start, end);
      // Sharing reads the choice; it never writes it.
      expect(shareBody.contains('_mediaKeys'), isFalse);
      expect(shareBody.contains('_selected.'), isFalse);
      // Only a change of the media choice resets the progress.
      expect(controller, contains('void _mediaChanged() {'));
      expect(controller, contains('_completed.add(family);'));
      // Stable identity: items are kept and told apart by their key.
      final batches = read('$shareFolder/share_media_batches.dart');
      expect(batches, contains('seen.add(item.key)'));
      for (final source in <String>[controller, batches]) {
        expect(source.contains('.indexOf('), isFalse);
        expect(source.contains('.elementAt('), isFalse);
        expect(RegExp(r'\bmaster\[').hasMatch(source), isFalse);
      }
      expect(controller, contains('final Set<String> _mediaKeys;'));
    });

    test(
        'the batches are derived from the choice and never decided by '
        'majority, count or a label the files do not have', () {
      final sources = <String, String>{
        for (final file in dartFilesUnder(shareFolder))
          relative(file): read(file.path),
        'lib/src/views/Widgets/share_options_dialog.dart':
            read('lib/src/views/Widgets/share_options_dialog.dart'),
        'android/MultiMediaShareFormat.kt': read(
            'android/app/src/main/kotlin/com/example/broker_wallet/MultiMediaShareFormat.kt'),
        'android/MultiMediaSharePlugin.kt': read(
            'android/app/src/main/kotlin/com/example/broker_wallet/MultiMediaSharePlugin.kt'),
      };
      sources.forEach((path, source) {
        for (final word in <String>[
          'dominantFamily',
          'majority',
          'maxByOrNull',
          'groupingBy',
          'eachCount',
          'majorityFamily',
        ]) {
          expect(source.contains(word), isFalse, reason: '$path has $word');
        }
      });
      // The steps are the fixed order photos then videos.
      final batches = read('$shareFolder/share_media_batches.dart');
      expect(batches, contains('if (images.isNotEmpty) MediaFamily.images,'));
      expect(batches, contains('if (videos.isNotEmpty) MediaFamily.videos,'));
      expect(
          batches.indexOf('if (images.isNotEmpty) MediaFamily.images,'),
          lessThan(
              batches.indexOf('if (videos.isNotEmpty) MediaFamily.videos,')));
      // Nothing declares a batch as all types, in Dart or in Kotlin: a receiver
      // reads such a share as text only and drops the files.
      sources.forEach((path, source) {
        expect(source.contains("'*/*'") || source.contains('"*/*"'), isFalse,
            reason: '$path declares all types');
      });
      // A mixed set is never relabelled as one family anywhere in Dart.
      final payload = read('$shareFolder/share_payload.dart');
      expect(payload.contains("'image/*'"), isFalse);
      expect(payload.contains("'video/*'"), isFalse);
      expect(payload.contains('"image/*"'), isFalse);
      expect(payload.contains('"video/*"'), isFalse);
    });

    test('the copy is written once for the whole share, from the message only',
        () {
      final controller = read('$shareFolder/share_flow_controller.dart');
      expect(controller, contains('String? _detailsToCopy('));
      expect(
          controller,
          contains(
              'if (engine.clipboard == null || _clipboardWritten) return null;'));
      expect(controller,
          contains('if (!batches.hasSeveralInAFamily) return null;'));
      expect(controller, contains('    return text;\n  }'));
      expect('_clipboardWritten = true;'.allMatches(controller).length, 1);
      expect(controller,
          contains('final copyText = _detailsToCopy(batches, text);'));
      // What is copied is the composed message and nothing else: no link, id or
      // key is ever put into it.
      expect(controller.contains('signedUrl'), isFalse);
      expect(controller.contains('mediaObjectId'), isFalse);
      expect(controller.contains('cacheKey'), isFalse);
    });

    test(
        'there is no media-family choice: the picker is the only place the '
        'person chooses which media goes', () {
      for (final path in <String>[
        'lib/src/views/Widgets/share_batch_choice.dart',
        'lib/src/services/share/share_media_plan.dart',
        'test/share/share_media_plan_test.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: '$path is gone');
      }
      final retired = <RegExp>[
        RegExp('ShareBatchChoice'),
        RegExp(r'\bMediaBatch\b'),
        RegExp('MediaSharePlan'),
        RegExp('MediaShareKind'),
        RegExp('ShareTransport'),
        RegExp('chooseBatch'),
        RegExp('batchShared'),
        RegExp('sharedBatch'),
        RegExp('withMessageInPayload'),
        RegExp('share-batch'),
        RegExp('shareBatch'),
        RegExp('mixedFamilies'),
        RegExp('filesOnly'),
        RegExp('buildCaptionList'),
        RegExp('putCharSequenceArrayListExtra'),
      ];
      for (final file in <File>[
        ...dartFilesUnder('lib'),
        ...dartFilesUnder('test/share'),
      ]) {
        final path = relative(file);
        if (path == 'test/share/share_source_guards_test.dart') continue;
        final source = read(file.path);
        for (final word in retired) {
          expect(word.hasMatch(source), isFalse,
              reason: '$path still has $word');
        }
      }
      for (final key in <String>[
        'shareBatchExplain',
        'shareBatchPhotos',
        'shareBatchVideos',
        'shareBatchRemainingVideos',
        'shareBatchRemainingPhotos',
      ]) {
        expect(en.containsKey(key), isFalse, reason: key);
        expect(ar.containsKey(key), isFalse, reason: key);
      }
      // The controller shares what was chosen: no call takes a family.
      final controller = read('$shareFolder/share_flow_controller.dart');
      expect(controller,
          contains('Future<ShareFlowResult> share({ShareOrigin? origin})'));
    });
  });

  group(
      'the native Android transport is narrow and shaped as Android describes',
      () {
    const androidMain = 'android/app/src/main';
    const kotlinFolder = '$androidMain/kotlin/com/example/broker_wallet';
    late String plugin;
    late String format;
    late String provider;
    late String manifest;
    late String paths;

    setUpAll(() {
      plugin = read('$kotlinFolder/MultiMediaSharePlugin.kt');
      format = read('$kotlinFolder/MultiMediaShareFormat.kt');
      provider = read('$kotlinFolder/BrokerWalletShareFileProvider.kt');
      manifest = read('$androidMain/AndroidManifest.xml');
      paths = read('$androidMain/res/xml/brokerwallet_share_paths.xml');
    });

    test('the channel, the method and the staging folder agree with Dart', () {
      final sink = read('$shareFolder/share_android_sink.dart');
      final live = read('$shareFolder/share_live.dart');
      expect(sink, contains("'com.example.broker_wallet/multi_media_share'"));
      expect(
          plugin,
          contains(
              'const val CHANNEL = "com.example.broker_wallet/multi_media_share"'));
      expect(sink, contains("shareMethod = 'shareMultipleMedia'"));
      expect(plugin, contains('const val METHOD_SHARE = "shareMultipleMedia"'));
      expect(live, contains("_stagingFolder = 'broker_wallet_share'"));
      expect(
          plugin, contains('const val STAGING_FOLDER = "broker_wallet_share"'));
      expect(paths, contains('path="broker_wallet_share/"'));
      // The arguments Dart sends are the ones Kotlin reads, and nothing else:
      // files and their types; no message, no subject, no link.
      expect(sink, contains("'paths':"));
      expect(sink, contains("'mimeTypes':"));
      expect(sink.contains("'text':"), isFalse);
      expect(sink.contains("'subject':"), isFalse);
      for (final name in <String>['paths', 'mimeTypes']) {
        expect(plugin, contains('"$name"'), reason: name);
      }
      expect(RegExp(r'call\.argument<').allMatches(plugin).length, 2);
      expect(plugin.contains('"text"'), isFalse);
      final activity = read('$kotlinFolder/MainActivity.kt');
      expect(activity,
          contains('MultiMediaSharePlugin.registerWith(flutterEngine, this)'));
      expect(
          'MultiMediaSharePlugin.registerWith('.allMatches(activity).length, 1);
    });

    test('one ACTION_SEND_MULTIPLE with every URI, a ClipData and a read grant',
        () {
      expect(plugin, contains('Intent(Intent.ACTION_SEND_MULTIPLE)'));
      expect(plugin.contains('Intent.ACTION_SEND)'), isFalse,
          reason: 'never the single-file action');
      expect(
          plugin,
          contains(
              'putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))'));
      // One clip item per URI, in order, and nothing in them but the URI.
      expect(plugin,
          contains('ClipData(description, ClipData.Item(uris.first()))'));
      expect(plugin, contains('for (uri in uris.drop(1)) {'));
      expect(plugin, contains('clip.addItem(ClipData.Item(uri))'));
      expect(RegExp(r'ClipData\.Item\(').allMatches(plugin).length, 2);
      expect(plugin, contains('ClipDescription('));
      expect(plugin,
          contains('MultiMediaShareFormat.distinctMimeTypes(mimeTypes)'));
      expect(
          plugin, contains('intent.clipData = clipDataFor(uris, mimeTypes)'));
      expect(plugin, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
      expect(plugin.contains('FLAG_GRANT_WRITE_URI_PERMISSION'), isFalse);
      expect(plugin, contains('Intent.createChooser(intent, null)'));
      expect('startActivity('.allMatches(plugin).length, 1,
          reason: 'one share sheet');
      expect(
          plugin,
          contains(
              'intent.type = MultiMediaShareFormat.commonMimeType(mimeTypes)'));
      // The URIs are in the order the files were given.
      expect(plugin, contains('for (path in paths)'));
      expect(
          plugin,
          contains(
              'uris.add(FileProvider.getUriForFile(activity, authority, file))'));
    });

    test(
        'a batch carries no message at all: no text extra, no list, no '
        'subject, nothing in the clip items but the URI', () {
      expect(plugin.contains('EXTRA_TEXT'), isFalse);
      expect(plugin.contains('EXTRA_HTML_TEXT'), isFalse);
      expect(plugin.contains('EXTRA_SUBJECT'), isFalse);
      expect(plugin.contains('putExtra('), isFalse);
      expect(plugin.contains('putCharSequenceArrayListExtra'), isFalse);
      expect(plugin.contains('buildCaptionList'), isFalse);
      expect(format.contains('buildCaptionList'), isFalse);
      expect(format.contains('ArrayList<CharSequence>'), isFalse);
      expect(plugin.contains('captions'), isFalse);
    });

    test(
        'the declared type is the one the files proved, or the wildcard of '
        'their one family; a mix is refused, never labelled', () {
      expect(format,
          contains('fun commonMimeType(mimeTypes: List<String>): String'));
      expect(format, contains('if (types.all { it == first }) return first'));
      expect(format,
          contains('require(families.size == 1 && families.first() != "*") {'));
      expect(format, contains(r'return "${families.first()}/*"'));
      expect(format, contains('require(types.isNotEmpty())'));
      // Nothing is declared as all types, and nothing is chosen by majority.
      expect(format.contains('"*/*"'), isFalse);
      expect(format.contains('ANY'), isFalse);
      for (final word in <String>[
        'dominantFamily',
        'maxByOrNull',
        'groupingBy',
        'eachCount',
        'majority',
      ]) {
        expect(format.contains(word), isFalse, reason: word);
      }
      // Pure Kotlin: no Android class, so each rule reads on its own.
      expect(format.contains('import android.'), isFalse);
      expect(format.contains('import androidx.'), isFalse);
      // Nothing here names a type to suit a receiver: only the ones it is given.
      expect(RegExp(r'"(image|video|audio|application)/').hasMatch(format),
          isFalse);
      // A mix reaching the plugin is refused before any sheet opens.
      expect(plugin, contains('catch (e: IllegalArgumentException) {'));
    });

    test('only prepared share files, as content URIs, never a path or a link',
        () {
      expect(plugin,
          contains('File(activity.cacheDir, STAGING_FOLDER).canonicalFile'));
      expect(
          plugin, contains('file.path.startsWith(root.path + File.separator)'));
      expect(plugin, contains('file.isFile && file.canRead()'));
      expect(plugin, contains('require(paths.size >= 2)'));
      expect(plugin, contains('require(paths.size == mimeTypes.size)'));
      for (final forbidden in <String>[
        'Uri.fromFile',
        'Uri.parse',
        'file://',
        'http',
        'getExternalStorage',
        'Environment.',
        'MediaStore',
      ]) {
        expect(plugin.contains(forbidden), isFalse, reason: forbidden);
      }
      // Errors say fixed words: no path, name or message.
      expect(
          plugin,
          contains(
              'result.error("invalid-request", "The media batch could not be shared.", null)'));
      expect(
          plugin,
          contains(
              'result.error("share-failed", "The share sheet could not be opened.", null)'));
      expect(plugin.contains('e.message'), isFalse);
      expect(plugin.contains('printStackTrace'), isFalse);
      expect(plugin.contains('Log.'), isFalse);
      // The authority is the manifest's, with the app's own provider.
      expect(
          plugin,
          contains(
              'const val PROVIDER_SUFFIX = ".brokerwallet.shareprovider"'));
      expect(plugin, contains('activity.packageName + PROVIDER_SUFFIX'));
    });

    test('the provider is its own, not exported, and serves one folder only',
        () {
      expect(provider,
          contains('class BrokerWalletShareFileProvider : FileProvider()'));
      expect(
          manifest, contains('android:name=".BrokerWalletShareFileProvider"'));
      expect(
          manifest,
          contains(
              r'android:authorities="${applicationId}.brokerwallet.shareprovider"'));
      final entry = RegExp(
        r'<provider\s+android:name="\.BrokerWalletShareFileProvider".*?</provider>',
        dotAll: true,
      ).firstMatch(manifest)!.group(0)!;
      expect(entry, contains('android:exported="false"'));
      expect(entry, contains('android:grantUriPermissions="true"'));
      expect(entry, contains('@xml/brokerwallet_share_paths'));
      expect(entry, contains('android.support.FILE_PROVIDER_PATHS'));
      // Exactly one exposed path: the share staging folder in the cache.
      final elements =
          RegExp(r'<(?!paths|\?xml|!--)[a-z-]+ ').allMatches(paths).toList();
      expect(elements, hasLength(1), reason: paths);
      expect(
          paths,
          contains(
              '<cache-path name="brokerwallet_share" path="broker_wallet_share/" />'));
      expect(paths.contains('path="."'), isFalse);
      expect(paths.contains('external'), isFalse);
      expect(paths.contains('files-path'), isFalse);
    });

    test('the build names the library its FileProvider subclass comes from',
        () {
      expect(read('android/app/build.gradle'),
          contains("implementation 'androidx.core:core:1.13.1'"));
    });
  });

  group('the media notes and breakdown exist in both languages', () {
    const keys = <String>[
      'shareDetailsCopyNote',
      'shareBreakdown',
      'shareTwoStepNote',
      'shareStepVideosReady',
      'continueLabel',
    ];

    test('present and not empty', () {
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: '$key missing in English');
        expect(ar[key], isA<String>(), reason: '$key missing in Arabic');
        expect((en[key] as String).trim(), isNotEmpty, reason: key);
        expect((ar[key] as String).trim(), isNotEmpty, reason: key);
      }
    });

    test('placeholders match between the languages', () {
      Set<String?> names(String text) =>
          RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)).toSet();
      for (final key in keys) {
        expect(names(ar[key] as String), names(en[key] as String), reason: key);
      }
      expect(en['shareBreakdown'], contains('{photos}'));
      expect(en['shareBreakdown'], contains('{videos}'));
      for (final key in <String>[
        'shareDetailsCopyNote',
        'shareTwoStepNote',
        'shareStepVideosReady',
        'continueLabel',
      ]) {
        expect(names(en[key] as String), isEmpty, reason: key);
      }
    });

    test('the notes say what the contract says, and claim nothing early', () {
      expect(en['shareTwoStepNote'],
          'Photos and videos will be shared in two steps to ensure all selected media are sent.');
      expect(ar['shareTwoStepNote'],
          'سيتم إرسال الصور ومقاطع الفيديو على خطوتين لضمان مشاركة جميع الوسائط.');
      expect(en['shareStepVideosReady'],
          'Photos shared. Videos are ready to share.');
      expect(ar['shareStepVideosReady'],
          'تمت مشاركة الصور. مقاطع الفيديو جاهزة للمشاركة.');
      // The details note is read before the copy happens, so it says what will
      // happen; it names no app and no link.
      for (final key in <String>[
        'shareDetailsCopyNote',
        'shareTwoStepNote',
        'shareStepVideosReady',
      ]) {
        for (final text in <String>[en[key] as String, ar[key] as String]) {
          expect(text.contains('http'), isFalse, reason: key);
          expect(text.toLowerCase().contains('whatsapp'), isFalse, reason: key);
          expect(text.contains('{'), isFalse, reason: key);
        }
      }
      expect(
          en['shareDetailsCopyNote'],
          'When you share several photos or videos, the details are copied. '
          'Paste them into the chat once, after the media.');
      expect(
          ar['shareDetailsCopyNote'],
          'عند مشاركة عدة صور أو مقاطع فيديو، يتم نسخ التفاصيل. '
          'الصقها في المحادثة مرة واحدة بعد إرسال الوسائط.');
      // The two-step note is informational: it asks nothing.
      expect((en['shareTwoStepNote'] as String).contains('?'), isFalse);
      expect((ar['shareTwoStepNote'] as String).contains('؟'), isFalse);
    });
  });

  group('a video is previewed the way the gallery previews it', () {
    const picker = 'lib/src/views/Widgets/share_media_picker.dart';

    test('the picker and the compact summary draw one widget', () {
      final dialog = read('lib/src/views/Widgets/share_options_dialog.dart');
      expect(
          dialog, contains('ShareMediaPreview(item: item, cacheWidth: 126)'));
      expect(read(picker), contains('ShareMediaPreview(item: item)'));
    });

    test('that widget uses the gallery\'s own video-frame widget', () {
      expect(read(picker), contains('OfferVideoPoster('));
      for (final path in <String>[
        'lib/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart',
        'lib/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart',
        'lib/src/views/Widgets/unified_media_preview_grid.dart',
      ]) {
        expect(read(path), contains('OfferVideoPoster('), reason: path);
      }
      // The old divergent shortcut that skipped the on-demand frame is gone.
      expect(read(picker).contains('localPoster('), isFalse);
      expect(read(picker).contains('OfferVideoPosterService'), isFalse);
    });

    test('a preview refreshes no link and downloads no video', () {
      final source = read(picker);
      for (final word in <String>[
        'refreshLink',
        'LinkRefresher',
        'ShareMediaFetcher',
        'package:http',
        'HttpClient',
        'Dio(',
        'ensureMediaIdCached',
      ]) {
        expect(source.contains(word), isFalse, reason: 'the picker has $word');
      }
      // The frame maker reads the video's index and first frame, never all of it.
      expect(read('lib/src/services/offer_video_poster_service.dart'),
          contains('VideoThumbnail.thumbnailFile('));
    });

    test('the play badge is drawn over a real frame only', () {
      final poster = read('lib/src/views/Widgets/offer_video_poster.dart');
      expect(poster, contains('frameOverlay'));
      expect(poster, contains('frameBuilder: overlay == null'));
      final source = read(picker);
      expect(source, contains('frameOverlay: const _PlayBadge()'));
      // The tile no longer layers a second badge of its own.
      expect('share-media-video-indicator'.allMatches(source).length, 1);
    });
  });

  group('every string the Share screens show exists in both languages', () {
    const dialog = 'lib/src/views/Widgets/share_options_dialog.dart';
    const picker = 'lib/src/views/Widgets/share_media_picker.dart';

    /// What the two screens ask the localization for: the literals they name
    /// and the keys held in values, which come from the code that holds them.
    Set<String> shownKeys() => <String>{
          ...literalKeys(read(dialog)),
          ...literalKeys(read(picker)),
          ...dynamicShareKeys(),
        };

    test('the keys the dialog and media picker ask for', () {
      final keys = shownKeys();
      // The scan finds what the screens really use, so it cannot pass on an
      // empty set: the key of the Share button (one branch of a conditional),
      // of the Continue button, of the notes, and of the dynamic titles.
      expect(
          keys,
          containsAll(<String>[
            'share',
            'continueLabel',
            'shareDetailsCopyNote',
            'shareTwoStepNote',
            'shareStepVideosReady',
            'shareBreakdown',
            'shareMediaCount',
            'shareItemUnavailable',
            'shareOffer',
            'shareQuotation',
            'shareErrorGeneric',
            'mediaFiles',
          ]));
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: '$key missing in English');
        expect(ar[key], isA<String>(), reason: '$key missing in Arabic');
        expect((en[key] as String).trim(), isNotEmpty, reason: key);
        expect((ar[key] as String).trim(), isNotEmpty, reason: key);
      }
    });

    test('a key held in a value comes from code this guard reads', () {
      // Every `translate(` call whose argument names no literal is listed here
      // with where its key comes from; a new one has to be added to
      // `dynamicShareKeys`, so no key can reach the screen unchecked.
      final held = <String>{
        for (final path in <String>[dialog, picker])
          for (final argument in translateArguments(read(path)))
            if (!argument.contains("'")) argument,
      };
      expect(held, <String>{
        'controller.source.titleKey',
        'failure.kind.messageKey',
        'source.sectionTitleKey(section)',
        'textKey',
      });
      final sources = dynamicShareKeys();
      expect(
          sources,
          containsAll(<String>[
            'shareOffer',
            'shareRequest',
            'shareOwner',
            'shareBroker',
            'shareWatchman',
            'shareOffice',
            'shareQuotation',
            'quotationPdf',
            'mediaFiles',
            'documents',
            'shareErrorNetwork',
            'shareErrorUnavailable',
            'shareErrorSession',
            'shareErrorGeneric',
          ]));
    });

    test('placeholders match between the languages', () {
      Set<String?> names(String text) =>
          RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)).toSet();
      for (final key in shownKeys()) {
        expect(names(ar[key] as String), names(en[key] as String), reason: key);
      }
      // The placeholders the screens fill in are the ones the sentences have.
      expect(names(en['shareMediaCount'] as String),
          <String?>{'selected', 'total'});
      expect(
          names(en['shareBreakdown'] as String), <String?>{'photos', 'videos'});
      final screens = '${read(dialog)}\n${read(picker)}';
      for (final name in <String>[
        'selected',
        'total',
        'photos',
        'videos',
      ]) {
        expect(screens, contains("'{$name}'"), reason: name);
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

    test('the keys added for Share appear once in each file and are used', () {
      const added = <String>[
        'shareOwner',
        'shareBroker',
        'shareWatchman',
        'shareOffice',
        'shareQuotation',
        'shareSelectAtLeastOne',
        'shareMediaCount',
        'shareMediaNotSelected',
        'shareItemUnavailable',
        'shareErrorNetwork',
        'shareErrorUnavailable',
        'shareErrorSession',
        'shareErrorGeneric',
        'shareDetailsCopyNote',
        'shareBreakdown',
        'shareTwoStepNote',
        'shareStepVideosReady',
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
      // A key nothing asks for is a dead string: each one above is named as a
      // literal by the code that shows it.
      final code = <String>[
        for (final file in dartFilesUnder('lib')) read(file.path),
      ].join('\n');
      for (final key in added) {
        expect(code, contains("'$key'"), reason: '$key is not used anywhere');
      }
    });
  });
}
