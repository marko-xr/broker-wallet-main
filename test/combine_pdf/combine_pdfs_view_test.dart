import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/Views/Screens/home/Toolkit/combine_pages_screen.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/combine_pdfs_view.dart';
import 'package:broker_wallet/src/Views/Widgets/tool_progress_overlay.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_executor.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_platform.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';

import 'combine_fixtures.dart';

class FakeGate implements CombineUsageGate {
  FakeGate(this.recorder, {this.allow = true});

  final RecordingUsage recorder;
  bool allow;
  int asked = 0;

  @override
  Future<bool> allowNewCombine(BuildContext context, String userId) async {
    asked++;
    return allow;
  }

  @override
  Future<void> recordCombine(String userId) => recorder.recordCombine(userId);
}

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the condition was never reached');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];
  late CombineHarness h;
  late FakeGate gate;

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

  Future<void> pumpView(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(700, 1100);
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
      home: CombinePdfsView(viewModel: h.viewModel, usageGate: gate),
    ));
    await tester.pump();
    await pumpUntil(tester, () => !h.viewModel.isLoading);
  }

  Future<List<File>> files(WidgetTester tester) async {
    late List<File> made;
    await tester.runAsync(() async {
      made = [
        await h.pdf('lease.pdf', 'L', count: 3),
        await h.pdf('plan.pdf', 'P', count: 2),
      ];
    });
    return made;
  }

  Future<void> choose(WidgetTester tester, List<File> picked,
      {String button = 'Create First PDF'}) async {
    h.picker.next = [
      for (final f in picked)
        PickedPdf(path: f.path, name: f.uri.pathSegments.last)
    ];
    await tester.tap(find.text(button));
    await pumpUntil(tester, () => !h.viewModel.isChecking);
    await tester.pump();
  }

  Future<void> start(WidgetTester tester, {CombineHarness? harness}) async {
    h = harness ?? CombineHarness();
    gate = FakeGate(h.usage);
    await tester.runAsync(h.viewModel.start);
  }

  tearDown(() async {
    await h.dispose();
  });

  testWidgets('empty state, then two picked files with totals and a review',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    expect(find.text('No combined documents'), findsOneWidget);
    final picked = await files(tester);
    await choose(tester, picked, button: 'Create First PDF');
    expect(find.text('lease.pdf'), findsOneWidget);
    expect(find.text('plan.pdf'), findsOneWidget);
    expect(find.text('Total pages: 5'), findsOneWidget);
    expect(find.textContaining('3 of 3 pages selected'), findsOneWidget);
    expect(find.text('Combine PDFs'), findsWidgets);

    await tester.tap(find.text('Review page order'));
    await tester.pumpAndSettle();
    expect(find.byType(CombinePagesScreen), findsOneWidget);
    expect(find.text('lease.pdf · page 1'), findsOneWidget);
    expect(find.text('plan.pdf · page 2'), findsOneWidget);
    // Rotating shows the turn; removing a page lowers the total everywhere.
    await tester.tap(find.byTooltip('Rotate page').first);
    await tester.pump();
    expect(find.text('+90°'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove page').first);
    await tester.pump();
    expect(find.text('Total pages: 4'), findsOneWidget);
    expect(find.text('lease.pdf · page 1'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Total pages: 4'), findsOneWidget);
    expect(find.textContaining('2 of 3 pages selected'), findsOneWidget);
  });

  testWidgets('a file with form fields and links tells the user what changes',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    late File rich;
    late File plain;
    await tester.runAsync(() async {
      rich = await writeFile(h.inputs, 'rich.pdf',
          buildPdf('R', form: true, link: true, bookmark: true));
      plain = await h.pdf('plain.pdf', 'P');
    });
    await choose(tester, [rich, plain], button: 'Create First PDF');
    expect(find.textContaining('Form fields are merged into the page'),
        findsOneWidget);
    expect(find.textContaining('links stop being clickable'), findsOneWidget);
    expect(find.text('Bookmarks are not kept.'), findsOneWidget);
  });

  testWidgets('problem files are listed by name with a plain reason',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    late List<File> picked;
    await tester.runAsync(() async {
      picked = [
        await h.pdf('good.pdf', 'G'),
        await writeFile(h.inputs, 'locked.pdf',
            buildPdf('L', userPassword: 'u', ownerPassword: 'o')),
        await writeFile(h.inputs, 'broken.pdf', 'nope'.codeUnits),
      ];
    });
    await choose(tester, picked, button: 'Create First PDF');
    await tester.pumpAndSettle();
    expect(find.text('Some files were not added'), findsOneWidget);
    expect(find.text('locked.pdf'), findsOneWidget);
    expect(find.textContaining('password protected'), findsOneWidget);
    expect(find.text('broken.pdf'), findsOneWidget);
    expect(find.textContaining('damaged'), findsOneWidget);
    expect(find.text('1 files added'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('good.pdf'), findsOneWidget);
  });

  testWidgets(
      'combining shows one honest indicator and blocks a second tap',
      (tester) async {
    final gated = GatedExecutor(const InlineCombineExecutor())
      ..release = Completer<void>();
    await start(tester, harness: CombineHarness(executor: gated));
    await pumpView(tester);
    final picked = await files(tester);
    await choose(tester, picked, button: 'Create First PDF');

    await tester.tap(find.text('Combine PDFs').last);
    await pumpUntil(tester, () => h.viewModel.isMerging);
    await tester.pump();
    // One indicator only: the centered overlay, with no spinner on the button.
    expect(find.text('Combining PDFs…'), findsOneWidget);
    expect(find.byType(ToolProgressOverlay), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // No invented percentage anywhere.
    expect(find.textContaining('%'), findsNothing);
    final fab =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    expect(fab.onPressed, isNull);
    expect(gate.asked, 1);

    // The overlay has no Cancel button.
    expect(find.text('Cancel combining'), findsNothing);
    gated.release!.complete();
    await pumpUntil(tester,
        () => h.viewModel.documents.isNotEmpty && !h.viewModel.isMerging);
    await tester.pumpAndSettle();
    expect(find.byType(ToolProgressOverlay), findsNothing);
    expect(toasts.last, 'PDFs combined successfully');
    expect(h.usage.recorded, ['user-a']);
  });

  testWidgets('a finished combine appears in the list and is counted once',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    final picked = await files(tester);
    await choose(tester, picked, button: 'Create First PDF');
    await tester.enterText(find.byType(TextField).first, 'عقد الإيجار');
    await tester.tap(find.text('Combine PDFs').last);
    await pumpUntil(tester,
        () => h.viewModel.documents.isNotEmpty && !h.viewModel.isMerging);
    await tester.pumpAndSettle();
    expect(toasts.last, 'PDFs combined successfully');
    expect(find.text('عقد الإيجار'), findsOneWidget);
    expect(find.text('5 pages • PDF'), findsOneWidget);
    expect(h.usage.recorded, ['user-a']);
    expect(find.text('Total pages: 5'), findsNothing);
  });

  testWidgets('a refused plan limit does nothing else', (tester) async {
    await start(tester);
    await pumpView(tester);
    final picked = await files(tester);
    await choose(tester, picked, button: 'Create First PDF');
    gate.allow = false;
    await tester.tap(find.text('Combine PDFs').last);
    await pumpUntil(tester, () => gate.asked == 1 && !h.viewModel.isMerging);
    await tester.pump();
    expect(h.viewModel.documents, isEmpty);
    expect(h.usage.recorded, isEmpty);
    expect(toasts, isEmpty, reason: 'the plan dialog speaks for itself');
  });

  testWidgets('a failure is shown in words, with Retry for what can be retried',
      (tester) async {
    await start(tester);
    await pumpView(tester);
    final picked = await files(tester);
    await choose(tester, picked, button: 'Create First PDF');
    await tester.runAsync(() async => picked[1].deleteSync());
    await tester.tap(find.text('Combine PDFs').last);
    await pumpUntil(tester, () => toasts.isNotEmpty);
    expect(toasts.last, 'The file could not be found or opened.');
    expect(h.usage.recorded, isEmpty);
  });

  testWidgets('Arabic: right-to-left with Arabic text', (tester) async {
    await start(tester);
    await pumpView(tester, locale: const Locale('ar'));
    final ar = AppLocalizations(const Locale('ar'));
    await ar.load();
    expect(Directionality.of(tester.element(find.byType(CombinePdfsView))),
        TextDirection.rtl);
    expect(find.text(ar.translate('combineMultiplePdfs')), findsOneWidget);
    final picked = await files(tester);
    await choose(tester, picked, button: ar.translate('createFirstPdf'));
    expect(
        find.text(ar.translate('combineTotalPages').replaceAll('{count}', '5')),
        findsOneWidget);
    expect(find.text(ar.translate('combineReviewPages')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme renders without layout errors', (tester) async {
    await start(tester);
    await pumpView(tester, theme: ThemeData.dark());
    final picked = await files(tester);
    await choose(tester, picked, button: 'Create First PDF');
    expect(find.text('lease.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the screen during a combine is safe', (tester) async {
    final gated = GatedExecutor(const InlineCombineExecutor())
      ..release = Completer<void>();
    await start(tester, harness: CombineHarness(executor: gated));
    await pumpView(tester);
    final picked = await files(tester);
    await choose(tester, picked, button: 'Create First PDF');
    await tester.tap(find.text('Combine PDFs').last);
    await pumpUntil(tester, () => h.viewModel.isMerging);
    await tester.pumpWidget(const SizedBox());
    h.viewModel.dispose();
    gated.release!.complete();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(h.usage.recorded, isEmpty);
  });
}
