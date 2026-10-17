import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Widgets/plan_attachment_section.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The land / plot plan section of the Add/Edit Offer and Owner forms: every
/// state it can be in, the actions each state offers, English and Arabic (RTL),
/// Light and Dark, and that it never draws a link, a storage key or an id.
///
/// Local widget tests only; not device verification.

const String _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

late Directory _tempDir;
late File _image;
late Map<String, dynamic> _en;
late Map<String, dynamic> _ar;

const _add = Key('planAttachment.add');
const _card = Key('planAttachment.card');
const _state = Key('planAttachment.state');
const _keep = Key('planAttachment.keep');
const _retry = Key('planAttachment.retry');
const _replace = Key('planAttachment.replace');
const _remove = Key('planAttachment.remove');

class _Taps {
  int select = 0;
  int remove = 0;
  int keep = 0;
  int retry = 0;
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) =>
    MaterialApp(
      theme: theme,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _section(PlanAttachmentView view, _Taps taps) => Builder(
      builder: (context) => PlanAttachmentSection(
        view: view,
        localization: AppLocalizations.of(context),
        onSelect: () => taps.select += 1,
        onRemove: () => taps.remove += 1,
        onKeep: () => taps.keep += 1,
        onRetry: () => taps.retry += 1,
      ),
    );

Future<void> _show(
  WidgetTester tester,
  PlanAttachmentView view,
  _Taps taps, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  await tester
      .pumpWidget(_app(_section(view, taps), locale: locale, theme: theme));
  await tester.pump();
}

const _draft = PlanAttachmentView(
  display: PlanDisplay.draft,
  kind: PlanAttachmentKind.pdf,
  displayName: 'Plot 14 plan.pdf',
  byteLength: 4096,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('plan_section_test');
    _image = File('${_tempDir.path}/plan.png')
      ..writeAsBytesSync(base64Decode(_onePixelPngBase64));

    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async => true,
    );
    await AppLocalizations.preloadAllLanguages();
    _en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    _ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  tearDownAll(() async {
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('with no plan', () {
    testWidgets('is one tappable field that offers to add the plan',
        (tester) async {
      final taps = _Taps();
      await _show(
          tester, const PlanAttachmentView(display: PlanDisplay.none), taps);

      expect(find.text(_en['planAttachmentHint'] as String), findsOneWidget);
      expect(find.byKey(_add), findsOneWidget);
      expect(find.byKey(_card), findsNothing);

      await tester.tap(find.byKey(_add));
      expect(taps.select, 1);
      expect(taps.remove + taps.keep + taps.retry, 0);
    });

    testWidgets('says so in Arabic, laid out right to left', (tester) async {
      await _show(
          tester, const PlanAttachmentView(display: PlanDisplay.none), _Taps(),
          locale: const Locale('ar'));

      expect(find.text(_ar['planAttachmentHint'] as String), findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(_add))),
          TextDirection.rtl);
    });
  });

  group('a chosen file', () {
    testWidgets('shows what it is and that it is sent when the record is saved',
        (tester) async {
      final taps = _Taps();
      await _show(tester, _draft, taps);

      expect(find.byKey(_card), findsOneWidget);
      expect(find.text('Plot 14 plan.pdf'), findsOneWidget);
      expect(find.text('${_en['planAttachmentTypePdf']} · 4.0 KB'),
          findsOneWidget);
      expect(
          find.text(_en['planAttachmentWillUpload'] as String), findsOneWidget);
      expect(find.byKey(_replace), findsOneWidget);
      expect(find.byKey(_remove), findsOneWidget);
      expect(find.byKey(_keep), findsNothing);
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_add), findsNothing);

      await tester.tap(find.byKey(_replace));
      await tester.tap(find.byKey(_remove));
      expect(taps.select, 1);
      expect(taps.remove, 1);
    });

    testWidgets(
        'one that replaces the current plan says the old one stays '
        'until it is saved', (tester) async {
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.replacing,
          kind: PlanAttachmentKind.word,
          displayName: 'Plot 14 plan.docx',
          byteLength: 5 * 1024 * 1024,
          hasServerPlan: true,
        ),
        _Taps(),
      );
      expect(
          find.text(_en['planAttachmentReplaces'] as String), findsOneWidget);
      expect(find.text('${_en['planAttachmentTypeWord']} · 5.0 MB'),
          findsOneWidget);
    });

    testWidgets('an image is drawn from its own file, with no network',
        (tester) async {
      await _show(
        tester,
        PlanAttachmentView(
          display: PlanDisplay.draft,
          kind: PlanAttachmentKind.image,
          displayName: 'Plan photo.png',
          byteLength: 68,
          localPath: _image.path,
        ),
        _Taps(),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('${_en['planAttachmentTypeImage']} · 68 B'),
          findsOneWidget);
    });

    testWidgets('without a name it is called by its type', (tester) async {
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.draft,
          kind: PlanAttachmentKind.pdf,
          byteLength: 2048,
        ),
        _Taps(),
      );
      // Two lines name the file, and both are right. The title is the file's
      // name, or its type's own name when it has none; the line under it is
      // always the type, with the size when it is known. Given a size, the
      // title is the one line that is the type alone.
      expect(find.text(_en['planAttachmentTypePdf'] as String), findsOneWidget);
      expect(find.text('${_en['planAttachmentTypePdf']} · 2.0 KB'),
          findsOneWidget);
    });
  });

  group('the plan the record already has', () {
    testWidgets('has no pending-change line and can be replaced or removed',
        (tester) async {
      final taps = _Taps();
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.existing,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          byteLength: 4096,
          hasServerPlan: true,
        ),
        taps,
      );

      expect(find.byKey(_card), findsOneWidget);
      expect(find.byKey(_state), findsNothing);
      expect(find.byKey(_replace), findsOneWidget);
      expect(find.byKey(_remove), findsOneWidget);

      await tester.tap(find.byKey(_remove));
      expect(taps.remove, 1);
    });

    testWidgets('marked for removal it offers only to keep it', (tester) async {
      final taps = _Taps();
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.removalPending,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          hasServerPlan: true,
        ),
        taps,
      );

      expect(
          find.text(_en['planAttachmentWillRemove'] as String), findsOneWidget);
      expect(find.byKey(_keep), findsOneWidget);
      expect(find.text(_en['planAttachmentKeep'] as String), findsOneWidget);
      expect(find.byKey(_replace), findsNothing);
      expect(find.byKey(_remove), findsNothing);

      await tester.tap(find.byKey(_keep));
      expect(taps.keep, 1);
    });
  });

  group('while a change is being sent', () {
    testWidgets('an upload shows progress and offers nothing to tap',
        (tester) async {
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.working,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          byteLength: 4096,
        ),
        _Taps(),
      );
      expect(
          find.text(_en['planAttachmentUploading'] as String), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      for (final key in [_replace, _remove, _keep, _retry]) {
        expect(find.byKey(key), findsNothing);
      }
    });

    testWidgets('a removal says it is removing', (tester) async {
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.working,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          hasServerPlan: true,
          isRemoval: true,
        ),
        _Taps(),
      );
      expect(
          find.text(_en['planAttachmentRemoving'] as String), findsOneWidget);
      expect(find.text(_en['planAttachmentUploading'] as String), findsNothing);
    });
  });

  group('a change that did not complete', () {
    testWidgets('keeps the chosen file, says why, and offers Retry',
        (tester) async {
      final taps = _Taps();
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.failed,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          byteLength: 4096,
          failure: PlanAttachmentFailure.interrupted,
        ),
        taps,
      );

      expect(find.text('Plot 14 plan.pdf'), findsOneWidget);
      expect(find.text(_en['planAttachmentUploadFailed'] as String),
          findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
      expect(find.text(_en['planAttachmentRetry'] as String), findsOneWidget);
      expect(find.byKey(_replace), findsOneWidget);
      expect(find.byKey(_remove), findsOneWidget);

      await tester.tap(find.byKey(_retry));
      expect(taps.retry, 1);
    });

    testWidgets('a plan changed on another device says exactly that',
        (tester) async {
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.failed,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          failure: PlanAttachmentFailure.staleReplacement,
        ),
        _Taps(),
      );
      expect(find.text(_en['planAttachmentChangedElsewhere'] as String),
          findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
    });

    testWidgets('a refusal that repeating cannot fix offers no Retry',
        (tester) async {
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.failed,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          failure: PlanAttachmentFailure.unsupportedType,
        ),
        _Taps(),
      );
      expect(find.text(_en['planAttachmentUnsupportedType'] as String),
          findsOneWidget);
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_replace), findsOneWidget);
    });
  });

  group('presentation', () {
    testWidgets('Arabic: every line is Arabic and the card reads right to left',
        (tester) async {
      await _show(tester, _draft, _Taps(), locale: const Locale('ar'));

      expect(
          find.text(_ar['planAttachmentWillUpload'] as String), findsOneWidget);
      expect(find.text('${_ar['planAttachmentTypePdf']} · 4.0 KB'),
          findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(_card))),
          TextDirection.rtl);
      expect(
          find.text(_en['planAttachmentWillUpload'] as String), findsNothing);
    });

    testWidgets('Dark theme renders every state without an error',
        (tester) async {
      for (final view in const [
        PlanAttachmentView(display: PlanDisplay.none),
        _draft,
        PlanAttachmentView(
          display: PlanDisplay.failed,
          kind: PlanAttachmentKind.word,
          failure: PlanAttachmentFailure.interrupted,
        ),
        PlanAttachmentView(
          display: PlanDisplay.removalPending,
          kind: PlanAttachmentKind.pdf,
          hasServerPlan: true,
        ),
      ]) {
        await _show(tester, view, _Taps(), theme: ThemeData.dark());
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'on a narrow phone nothing overflows and the explanation keeps '
        'room to be read', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const failed = PlanAttachmentView(
        display: PlanDisplay.failed,
        kind: PlanAttachmentKind.pdf,
        displayName: 'A very long plot plan file name for the Marina tower.pdf',
        byteLength: 4096,
        failure: PlanAttachmentFailure.interrupted,
      );
      for (final locale in const [Locale('en'), Locale('ar')]) {
        for (final view in const [
          PlanAttachmentView(display: PlanDisplay.none),
          _draft,
          failed,
          PlanAttachmentView(
            display: PlanDisplay.removalPending,
            kind: PlanAttachmentKind.word,
            displayName: 'Plot 14 plan.docx',
            hasServerPlan: true,
          ),
          PlanAttachmentView(
            display: PlanDisplay.working,
            kind: PlanAttachmentKind.pdf,
            displayName: 'Plot 14 plan.pdf',
          ),
          PlanAttachmentView(
            display: PlanDisplay.existing,
            kind: PlanAttachmentKind.pdf,
            displayName: 'Plot 14 plan.pdf',
            hasServerPlan: true,
          ),
        ]) {
          await _show(tester, view, _Taps(), locale: locale);
          expect(tester.takeException(), isNull,
              reason: '${view.display.name} in ${locale.languageCode}');
        }
      }

      await _show(tester, failed, _Taps());
      expect(tester.getSize(find.byKey(_state)).width, greaterThan(100),
          reason: 'Retry sits under the explanation, not beside it');
    });

    testWidgets('never draws a link, a storage key or an id', (tester) async {
      await _show(
        tester,
        const PlanAttachmentView(
          display: PlanDisplay.existing,
          kind: PlanAttachmentKind.pdf,
          displayName: 'Plot 14 plan.pdf',
          signedUrl:
              'https://r2.example.test/bucket/key?X-Amz-Signature=secret',
          hasServerPlan: true,
        ),
        _Taps(),
      );
      for (final secret in [
        'http',
        'r2.example',
        'secret',
        'profiles/',
        'offer-plans'
      ]) {
        expect(find.textContaining(secret), findsNothing, reason: secret);
      }
    });
  });

  group('the source sheet', () {
    testWidgets('offers Camera, Gallery and Files, and returns the choice',
        (tester) async {
      PlanAttachmentSource? chosen;
      var asked = 0;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            asked += 1;
            chosen = await showPlanAttachmentSourceSheet(context);
          },
          child: const Text('OPEN'),
        ),
      )));
      await tester.pump();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text(_en['planAttachmentTitle'] as String), findsOneWidget);
      expect(find.text(_en['planAttachmentSheetSubtitle'] as String),
          findsOneWidget);
      for (final key in ['camera', 'gallery', 'files']) {
        expect(find.byKey(Key('planAttachmentSource.$key')), findsOneWidget);
      }
      for (final label in [
        'planAttachmentSourceCamera',
        'planAttachmentSourceGallery',
        'planAttachmentSourceFiles',
      ]) {
        expect(find.text(_en[label] as String), findsOneWidget, reason: label);
      }

      await tester.tap(find.byKey(const Key('planAttachmentSource.files')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(chosen, PlanAttachmentSource.files);

      for (final entry in {
        'camera': PlanAttachmentSource.camera,
        'gallery': PlanAttachmentSource.gallery,
      }.entries) {
        chosen = null;
        await tester.tap(find.text('OPEN'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('planAttachmentSource.${entry.key}')));
        await tester.pumpAndSettle();
        expect(chosen, entry.value);
      }
    });

    testWidgets('dismissing it chooses nothing', (tester) async {
      PlanAttachmentSource? chosen = PlanAttachmentSource.camera;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              chosen = await showPlanAttachmentSourceSheet(context),
          child: const Text('OPEN'),
        ),
      )));
      await tester.pump();

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('planAttachmentSource.files')), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('planAttachmentSource.files')), findsNothing);
      expect(chosen, isNull);
    });

    testWidgets('speaks Arabic in Arabic', (tester) async {
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlanAttachmentSourceSheet(context),
            child: const Text('OPEN'),
          ),
        ),
        locale: const Locale('ar'),
      ));
      await tester.pump();
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      for (final label in [
        'planAttachmentSourceCamera',
        'planAttachmentSourceGallery',
        'planAttachmentSourceFiles',
      ]) {
        expect(find.text(_ar[label] as String), findsOneWidget, reason: label);
      }
    });
  });

  group('file sizes', () {
    test('are written in the plain units the app already shows', () {
      expect(planFileSize(0), '0 B');
      expect(planFileSize(512), '512 B');
      expect(planFileSize(1023), '1023 B');
      expect(planFileSize(1024), '1.0 KB');
      expect(planFileSize(1536), '1.5 KB');
      expect(planFileSize(4096), '4.0 KB');
      expect(planFileSize(1024 * 1024), '1.0 MB');
      expect(planFileSize(25 * 1024 * 1024), '25.0 MB');
    });
  });
}
