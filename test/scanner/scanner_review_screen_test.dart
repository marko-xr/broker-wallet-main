import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scanner_document_store.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_review_screen.dart';

import 'scanner_harness.dart';

Future<void> pumpHost(
  WidgetTester tester,
  ScannerViewModel vm,
  List<bool?> results, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              results.add(await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => ScannerReviewScreen(viewModel: vm),
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Lets real file work finish and the widgets' own continuations run: the
/// screen's awaits live in the test's fake-async zone, so each round of real
/// waiting is followed by a pump that flushes them.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the condition was never reached');
}

void main() {
  late Harness h;

  final binding = TestWidgetsFlutterBinding.ensureInitialized();

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
  });
  setUp(() => h = Harness());
  tearDown(() => h.close());

  /// A started view model holding a three-page image scan under review.
  Future<ScannerViewModel> reviewing(WidgetTester tester,
      {ScannerFileCopier? copier}) async {
    late ScannerViewModel vm;
    await tester.runAsync(() async {
      vm = await h.started(copier: copier);
      vm.selectExportFormat(ExportFormat.images);
      final pages = <String>[for (var i = 0; i < 3; i++) await h.jpeg(i)];
      h.engine.handler = (_) => <String, Object?>{'images': pages};
      final result = await scanOnce(vm);
      expect(result.draft, isNotNull);
    });
    return vm;
  }

  testWidgets('shows every page in order, the real page count and a name',
      (tester) async {
    final vm = await reviewing(tester);
    await pumpHost(tester, vm, <bool?>[]);

    expect(find.text('Review scan'), findsOneWidget);
    expect(find.textContaining('Pages: 3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Save Document'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, startsWith('document_scan_'));
    // Nothing is saved before Save.
    expect(vm.documents, isEmpty);
    expect(h.usage.recorded, isEmpty);
  });

  testWidgets('is shown in Arabic, right to left, with the Arabic labels',
      (tester) async {
    final vm = await reviewing(tester);
    await pumpHost(tester, vm, <bool?>[], locale: const Locale('ar'));

    expect(find.text('مراجعة المسح'), findsOneWidget);
    expect(find.textContaining('عدد الصفحات: 3'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(TextField))),
        TextDirection.rtl);
  });

  testWidgets('a failed save stays on the scan, says why, and Retry saves it',
      (tester) async {
    var failing = true;
    var attempts = 0;
    final vm = await reviewing(tester, copier: (source, destination) async {
      attempts++;
      if (failing) {
        throw const FileSystemException('No space', '', OSError('ENOSPC', 28));
      }
      await source.copy(destination.path);
    });
    final results = <bool?>[];
    await pumpHost(tester, vm, results);

    await tester.tap(find.text('Save Document'));
    await pumpUntil(tester, () => attempts >= 1 && !vm.isSaving);
    await tester.pump();

    expect(find.textContaining('out of storage space'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Review scan'), findsOneWidget, reason: 'still reviewing');
    expect(vm.draft, isNotNull);
    expect(vm.documents, isEmpty);
    expect(results, isEmpty);

    failing = false;
    await tester.tap(find.text('Retry'));
    await pumpUntil(tester, () => results.isNotEmpty);
    await tester.pumpAndSettle();

    expect(results, <bool?>[true]);
    expect(find.text('Review scan'), findsNothing);
    expect(vm.documents, hasLength(3));
    expect(h.usage.recorded, hasLength(1));
  });

  testWidgets('Discard asks first, then removes the scan and saves nothing',
      (tester) async {
    final vm = await reviewing(tester);
    final results = <bool?>[];
    await pumpHost(tester, vm, results);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this scan?'), findsOneWidget);

    // Cancel keeps everything.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Review scan'), findsOneWidget);
    expect(vm.draft, isNotNull);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Discard')));
    await pumpUntil(tester, () => results.isNotEmpty);
    await tester.pumpAndSettle();

    expect(results, <bool?>[false]);
    expect(vm.documents, isEmpty);
    // (That the scanner's files are removed is proven in the view model test;
    // here Windows may still hold a thumbnail's file open.)
    expect(h.usage.recorded, isEmpty);
  });

  testWidgets('a scan under review disappears when the account changes',
      (tester) async {
    final vm = await reviewing(tester);
    final results = <bool?>[];
    await pumpHost(tester, vm, results);

    await tester.runAsync(() => h.switchTo(vm, 'user-b'));
    await tester.pumpAndSettle();

    expect(results, <bool?>[false]);
    expect(find.text('Review scan'), findsNothing);
    expect(vm.draft, isNull);
  });
}
