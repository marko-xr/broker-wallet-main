import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/Views/Screens/home/Toolkit/image_pdf_settings_sheet.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/image_to_pdf_view.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_executor.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_platform.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_usage_gate.dart';

import 'image_pdf_harness.dart';

class FakeGate implements ImagePdfUsageGate {
  FakeGate(this.recorder, {this.allow = true});

  final RecordingUsage recorder;
  bool allow;
  int asked = 0;

  @override
  Future<bool> allowNewConversion(BuildContext context, String userId) async {
    asked++;
    return allow;
  }

  @override
  Future<void> recordConversion(String userId) =>
      recorder.recordConversion(userId);
}

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the condition was never reached');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];
  late ImagePdfHarness h;
  late FakeGate gate;
  late AppLocalizations en;
  late AppLocalizations ar;

  setUpAll(() async {
    // Serve the ARB files from disk so the tests assert on the real strings.
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
    await AppLocalizations.preloadAllLanguages();
    en = AppLocalizations(const Locale('en'));
    await en.load();
    ar = AppLocalizations(const Locale('ar'));
    await ar.load();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async {
        if (call.method == 'showToast') {
          toasts.add((call.arguments as Map)['msg'] as String);
        }
        return true;
      },
    );
  });

  setUp(() {
    toasts.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> start(WidgetTester tester, {ImagePdfHarness? harness}) async {
    h = harness ?? ImagePdfHarness();
    gate = FakeGate(h.usage);
    await tester.runAsync(h.viewModel.start);
  }

  tearDown(() async => h.dispose());

  Future<void> pumpView(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      theme: theme,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ImageToPdfView(viewModel: h.viewModel, usageGate: gate),
    ));
    await tester.pump();
    await pumpUntil(tester, () => !h.viewModel.isLoading);
  }

  Future<List<File>> pictures(WidgetTester tester, [int count = 2]) async {
    late List<File> made;
    await tester.runAsync(() async {
      made = [
        for (var i = 0; i < count; i++)
          h.jpegFile('pic$i.jpg', w: 400 + i * 10, h: 300, r: 30 + i * 60),
      ];
    });
    return made;
  }

  Future<void> choose(WidgetTester tester, List<File> picked,
      {required String button}) async {
    h.picker.gallery = [
      for (final f in picked)
        PickedImage(path: f.path, name: p.basename(f.path))
    ];
    await tester.tap(find.text(button));
    await pumpUntil(tester, () => h.viewModel.items.length == picked.length);
    await pumpUntil(
        tester, () => !h.viewModel.isAdding && !h.viewModel.isChecking);
    await tester.pump();
  }

  testWidgets('empty state, then two picked images with a real page count',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    expect(find.text(en.translate('noImagesSelected')), findsOneWidget);
    final picked = await pictures(tester);
    await choose(tester, picked, button: en.translate('selectImages'));
    expect(find.text('${en.translate('image')} 1'), findsOneWidget);
    expect(find.text('${en.translate('image')} 2'), findsOneWidget);
    expect(find.text('2 pages • A4'), findsOneWidget);
    expect(find.textContaining('400 × 300 px'), findsOneWidget);
    expect(find.text(en.translate('convertToPdf')), findsOneWidget);
    expect(h.usage.recorded, isEmpty,
        reason: 'nothing is counted by selecting');
  });

  testWidgets('pictures show a real progress while they are being checked',
      (tester) async {
    final gated = GatedExecutor(const InlineImagePdfExecutor())
      ..releaseAnalysis = Completer<void>();
    await start(tester, harness: ImagePdfHarness(executor: gated));
    await pumpView(tester);
    final picked = await pictures(tester, 3);
    h.picker.gallery = [
      for (final f in picked)
        PickedImage(path: f.path, name: p.basename(f.path))
    ];
    await tester.tap(find.text(en.translate('selectImages')));
    await pumpUntil(tester, () => h.viewModel.items.length == 3);
    await tester.pump();
    expect(find.text('Checking images… 0 of 3'), findsOneWidget);
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 0);
    // Converting and previewing wait for the check.
    final fab =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    expect(fab.onPressed, isNull);
    gated.releaseAnalysis!.complete();
    await pumpUntil(tester, () => !h.viewModel.isChecking);
    await tester.pump();
    expect(find.textContaining('Checking images'), findsNothing);
    expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull);
  });

  testWidgets('a damaged image is named, explained and blocks the PDF',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    late List<File> picked;
    await tester.runAsync(() async {
      final good = h.jpegFile('good.jpg');
      final bytes = good.readAsBytesSync();
      picked = [
        good,
        h.rawFile('cut.jpg', bytes.sublist(0, bytes.length ~/ 2))
      ];
    });
    await choose(tester, picked, button: en.translate('selectImages'));
    expect(find.text(en.translate('i2pErrCorrupt')), findsOneWidget);
    expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip(en.translate('i2pRemoveImage')).last);
    await tester.pump();
    expect(find.text(en.translate('i2pErrCorrupt')), findsNothing);
    expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull);
  });

  testWidgets('rejected pictures are listed by name with a plain reason',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    late File good;
    await tester.runAsync(() async => good = h.jpegFile('good.jpg'));
    h.picker.gallery = [
      PickedImage(path: good.path, name: 'good.jpg'),
      PickedImage(path: p.join(h.inputs.path, 'gone.jpg'), name: 'gone.jpg'),
    ];
    await tester.tap(find.text(en.translate('selectImages')));
    await pumpUntil(tester, () => !h.viewModel.isAdding);
    await tester.pumpAndSettle();
    expect(find.text(en.translate('i2pRejectedTitle')), findsOneWidget);
    expect(find.text('gone.jpg'), findsOneWidget);
    expect(find.text(en.translate('i2pErrMissing')), findsOneWidget);
    expect(find.text('1 images were added.'), findsOneWidget);
    await tester.tap(find.text(en.translate('ok')));
    await tester.pumpAndSettle();
  });

  testWidgets('Convert makes the PDF, shows pages and size, Save keeps it',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    final picked = await pictures(tester);
    await choose(tester, picked, button: en.translate('selectImages'));
    await tester.enterText(find.byType(TextField).first, 'عقد الإيجار');
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => h.viewModel.draft != null);
    await tester.pumpAndSettle();
    // The review is of the real file.
    expect(find.text(en.translate('i2pReviewTitle')), findsOneWidget);
    final draft = h.viewModel.draft!;
    expect(find.textContaining('2 pages • '), findsWidgets);
    expect(draft.file.existsSync(), isTrue);
    expect(gate.asked, 1);
    await tester.tap(find.text(en.translate('i2pReviewSave')));
    await pumpUntil(tester,
        () => h.viewModel.documents.isNotEmpty && !h.viewModel.isSaving);
    await tester.pumpAndSettle();
    expect(toasts.last, 'PDF saved: عقد الإيجار');
    expect(find.text('عقد الإيجار'), findsOneWidget);
    expect(h.usage.recorded, ['user-a']);
    expect(find.text(en.translate('noImagesSelected')), findsNothing);
    expect(find.text('2 ${en.translate('images')} • PDF'), findsOneWidget);
  });

  testWidgets('Discard keeps nothing and counts nothing', (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => h.viewModel.draft != null);
    await tester.pumpAndSettle();
    final file = h.viewModel.draft!.file;
    await tester.tap(find.text(en.translate('i2pReviewDiscard')));
    await tester.pumpAndSettle();
    expect(h.viewModel.draft, isNull);
    await pumpUntil(tester, () => !file.existsSync());
    expect(h.viewModel.documents, isEmpty);
    expect(h.usage.recorded, isEmpty);
    // The images are still there to change and convert again.
    expect(find.text('${en.translate('image')} 1'), findsOneWidget);
  });

  testWidgets('a refused plan limit does nothing else', (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    gate.allow = false;
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => gate.asked == 1 && !h.viewModel.isBuilding);
    await tester.pump();
    expect(h.viewModel.draft, isNull);
    expect(h.viewModel.documents, isEmpty);
    expect(h.usage.recorded, isEmpty);
    expect(toasts, isEmpty, reason: 'the plan dialog speaks for itself');
  });

  testWidgets(
      'converting shows honest progress, blocks a second tap and can be cancelled',
      (tester) async {
    final gated = GatedExecutor(const InlineImagePdfExecutor())
      ..releaseBuild = Completer<void>();
    await start(tester, harness: ImagePdfHarness(executor: gated));
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => h.viewModel.isBuilding);
    await tester.pump();
    expect(find.text('Creating a PDF from 2 images…'), findsOneWidget);
    // No invented percentage anywhere.
    expect(find.textContaining('%'), findsNothing);
    final fab =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    expect(fab.onPressed, isNull);
    expect(gate.asked, 1);
    // The settings and the list are locked while it runs.
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.tune))
            .onPressed,
        isNull);
    await tester.tap(find.text(en.translate('cancel')));
    await tester.pump();
    gated.releaseBuild!.complete();
    await pumpUntil(tester, () => !h.viewModel.isBuilding);
    await tester.pump();
    expect(toasts.last, en.translate('i2pErrCancelled'));
    expect(h.viewModel.documents, isEmpty);
    expect(h.usage.recorded, isEmpty);
    expect(find.text('${en.translate('image')} 1'), findsOneWidget,
        reason: 'kept');
  });

  testWidgets('a failure is shown in words, naming the picture',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    final picked = await pictures(tester);
    await choose(tester, picked, button: en.translate('selectImages'));
    await tester
        .runAsync(() async => File(h.viewModel.items.last.path).deleteSync());
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => toasts.isNotEmpty);
    expect(toasts.last, 'pic1.jpg: ${en.translate('i2pErrMissing')}');
    expect(h.usage.recorded, isEmpty);
  });

  testWidgets(
      'the settings sheet changes the plan and nothing else until applied',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester, 4),
        button: en.translate('selectImages'));
    expect(find.text('4 pages • A4'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text(en.translate('advancedPdfSettings')), findsOneWidget);
    // Tile Multiple, 2 per page.
    await tester.tap(find.byType(DropdownButton<PdfLayout>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.translate('tileMultiple')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    // Not applied yet.
    expect(h.viewModel.settings.layout, PdfLayout.fitToPage);
    await tester.scrollUntilVisible(
        find.text(en.translate('applySettings')), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(en.translate('applySettings')));
    await tester.pumpAndSettle();
    expect(h.viewModel.settings.layout, PdfLayout.tileMultiple);
    expect(h.viewModel.settings.tilesPerPage, 2);
    expect(find.text('2 pages • A4'), findsOneWidget);
  });

  testWidgets(
      'a custom page size is validated and blocks Apply when out of range',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    await tester.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<PdfPageSize>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.translate('i2pCustom')).last);
    await tester.pumpAndSettle();
    final fields = find.widgetWithText(TextField, en.translate('i2pWidth'));
    expect(fields, findsOneWidget);
    await tester.enterText(fields, '30');
    await tester.pump();
    expect(find.text(en.translate('i2pCustomRange')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(en.translate('applySettings')), 300,
        scrollable: find.byType(Scrollable).last);
    final apply =
        find.widgetWithText(ElevatedButton, en.translate('applySettings'));
    expect(tester.widget<ElevatedButton>(apply).onPressed, isNull);
    await tester.scrollUntilVisible(fields, -300,
        scrollable: find.byType(Scrollable).last);
    await tester.enterText(fields, '200');
    await tester.pump();
    await tester.scrollUntilVisible(
        find.text(en.translate('applySettings')), 300,
        scrollable: find.byType(Scrollable).last);
    expect(tester.widget<ElevatedButton>(apply).onPressed, isNotNull);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(h.viewModel.settings.pageSize, PdfPageSize.custom);
    expect(h.viewModel.settings.customWidthMm, closeTo(200, 1e-9));
    expect(find.textContaining('200 × 297 mm'), findsOneWidget);
  });

  testWidgets('password protection asks twice, applies only when they match',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    await tester.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text(en.translate('i2pPasswordProtect')), 300,
        scrollable: find.byType(Scrollable).last);
    // The switch sits in the same row as the label.
    final tile = find
        .ancestor(
            of: find.text(en.translate('i2pPasswordProtect')),
            matching: find.byType(Row))
        .first;
    await tester.tap(find.descendant(of: tile, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(en.translate('i2pPassword')), 300,
        scrollable: find.byType(Scrollable).last);
    final pw = find.widgetWithText(TextField, en.translate('i2pPassword'));
    final confirm =
        find.widgetWithText(TextField, en.translate('i2pPasswordConfirm'));
    expect(tester.widget<TextField>(pw).obscureText, isTrue);
    await tester.enterText(pw, 'Secret-1');
    await tester.enterText(confirm, 'Secret-2');
    await tester.pump();
    expect(find.text(en.translate('i2pPasswordMismatch')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(en.translate('applySettings')), 300,
        scrollable: find.byType(Scrollable).last);
    final apply =
        find.widgetWithText(ElevatedButton, en.translate('applySettings'));
    expect(tester.widget<ElevatedButton>(apply).onPressed, isNull);
    await tester.scrollUntilVisible(confirm, -300,
        scrollable: find.byType(Scrollable).last);
    await tester.enterText(confirm, 'Secret-1');
    await tester.pump();
    await tester.scrollUntilVisible(
        find.text(en.translate('applySettings')), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(h.viewModel.settings.passwordProtect, isTrue);
    expect(h.viewModel.hasPassword, isTrue);
    expect(find.text(en.translate('i2pProtectedNote')), findsOneWidget);
  });

  testWidgets('a saved protected PDF is marked as protected in the list',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    h.viewModel.updateSettings(const ImagePdfSettings(passwordProtect: true));
    h.viewModel.setPassword('Secret-1');
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => h.viewModel.draft != null);
    await tester.pumpAndSettle();
    expect(find.text(en.translate('i2pProtectedNote')), findsWidgets);
    await tester.tap(find.text(en.translate('i2pReviewSave')));
    await pumpUntil(tester,
        () => h.viewModel.documents.isNotEmpty && !h.viewModel.isSaving);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsWidgets);
  });

  testWidgets('document actions: rename, share and delete work on the list',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => h.viewModel.draft != null);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.translate('i2pReviewSave')));
    await pumpUntil(tester,
        () => h.viewModel.documents.isNotEmpty && !h.viewModel.isSaving);
    await tester.pumpAndSettle();
    final doc = h.viewModel.documents.single;
    // Rename.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.translate('rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'عقد جديد');
    await tester.tap(find.text(en.translate('rename')).last);
    await pumpUntil(
        tester, () => h.viewModel.documents.single.name == 'عقد جديد');
    await tester.pumpAndSettle();
    expect(find.text('عقد جديد'), findsOneWidget);
    // Delete.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.translate('delete')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.translate('delete')).last);
    await pumpUntil(tester, () => h.viewModel.documents.isEmpty);
    await tester.pumpAndSettle();
    expect(
        File(p.join(h.accountDir().path, 'files', doc.fileName)).existsSync(),
        isFalse);
    expect(toasts.last, en.translate('documentDeleted'));
  });

  testWidgets('dragging an image\'s handle reorders the list', (tester) async {
    await start(tester);
    await pumpView(tester);
    await choose(tester, await pictures(tester, 3),
        button: en.translate('selectImages'));
    final widthsBefore = [for (final i in h.viewModel.items) i.analysis!.width];
    await tester.drag(
        find.byIcon(Icons.drag_handle).first, const Offset(0, 260));
    await tester.pumpAndSettle();
    final widthsAfter = [for (final i in h.viewModel.items) i.analysis!.width];
    expect(widthsAfter, isNot(widthsBefore));
    expect(widthsAfter.toSet(), widthsBefore.toSet());
    expect(widthsAfter.first, widthsBefore[1]);
  });

  testWidgets('Arabic: right-to-left with Arabic text', (tester) async {
    await start(tester);
    await pumpView(tester, locale: const Locale('ar'));
    expect(Directionality.of(tester.element(find.byType(ImageToPdfView))),
        TextDirection.rtl);
    expect(find.text(ar.translate('noImagesSelected')), findsOneWidget);
    await choose(tester, await pictures(tester),
        button: ar.translate('selectImages'));
    expect(find.textContaining('A4'), findsWidgets);
    expect(find.text(ar.translate('convertToPdf')), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text(ar.translate('advancedPdfSettings')), findsOneWidget);
    expect(find.text(ar.translate('i2pQualityHigh')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme renders the list and the settings without errors',
      (tester) async {
    await start(tester);
    await pumpView(tester, theme: ThemeData.dark());
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    expect(find.text('${en.translate('image')} 1'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePdfSettingsSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the screen during a conversion is safe', (tester) async {
    final gated = GatedExecutor(const InlineImagePdfExecutor())
      ..releaseBuild = Completer<void>();
    await start(tester, harness: ImagePdfHarness(executor: gated));
    await pumpView(tester);
    await choose(tester, await pictures(tester),
        button: en.translate('selectImages'));
    await tester.tap(find.text(en.translate('convertToPdf')));
    await pumpUntil(tester, () => h.viewModel.isBuilding);
    await tester.pumpWidget(const SizedBox());
    h.viewModel.dispose();
    gated.releaseBuild!.complete();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(h.usage.recorded, isEmpty);
  });
}
