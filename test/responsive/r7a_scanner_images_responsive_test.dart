import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_review_screen.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_image_viewer.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/image_to_pdf_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/image_pdf_settings_sheet.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'r7a_test_fakes.dart';
import 'responsive_harness.dart';

const sizes = [
  Size(280, 600),
  Size(320, 568),
  Size(360, 640),
  Size(393, 852),
  Size(430, 932),
  Size(640, 360),
  Size(600, 800),
  Size(800, 1280)
];
ResponsiveCase scenario(int i, {double keyboard = 0}) =>
    ResponsiveCase(sizes[i],
        locale: Locale(i.isEven ? 'ar' : 'en'),
        dark: i.isOdd,
        textScale: const [2.0, 1.6, 1.3, 1.0, 2.0, 2.0, 1.3, 1.0][i],
        safeArea: const EdgeInsets.only(top: 24, bottom: 16),
        keyboard: keyboard);
AppLocalizations loc(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));
Future<void> reach(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, 180,
        scrollable: find.byType(Scrollable).first);
  }
  await Scrollable.ensureVisible(t.element(f), alignment: .5);
  await t.pumpAndSettle();
}

void expectFabLabelContained(WidgetTester t) {
  final fab = find.byType(FloatingActionButton);
  final label = find.descendant(of: fab, matching: find.byType(Text));
  final button = t.getRect(fab).inflate(.1);
  final text = t.getRect(label);
  expect(button.contains(text.topLeft) && button.contains(text.bottomRight),
      isTrue);
}

void track(LocalScannerModel vm) {
  addTearDown(() {
    expect(vm.unexpectedCalls, 0);
    vm.dispose();
  });
}

void trackImages(LocalImagesModel vm) {
  addTearDown(() {
    expect(vm.unexpectedCalls, 0);
    vm.dispose();
  });
}

Future<LocalScannerModel> scanner(
    WidgetTester t, ResponsiveCase c, String state) async {
  final vm = LocalScannerModel();
  track(vm);
  vm.loading = state == 'loading';
  vm.waiting = state == 'waiting';
  vm.failed = state == 'error';
  vm.fetching = state == 'fetching';
  if (state == 'list') {
    vm.documents = scannerFixtures();
    vm.remoteOnly.add(vm.documents.last.id);
  }
  await pumpResponsive(t, c,
      home: ScannerView(viewModel: vm),
      settle: !['loading', 'waiting', 'fetching'].contains(state));
  await t.pump(const Duration(milliseconds: 300));
  expectNoLayoutException(t, c);
  expect(vm.starts, 1);
  expectFabLabelContained(t);
  return vm;
}

Future<LocalImagesModel> images(
    WidgetTester t, ResponsiveCase c, String state) async {
  final vm = LocalImagesModel();
  trackImages(vm);
  vm.waiting = state == 'waiting';
  vm.failed = state == 'error';
  vm.fetching = state == 'fetching';
  vm.building = state == 'building';
  if (['items', 'checking', 'failedItems', 'building', 'settings']
      .contains(state)) vm.items = imageFixtures();
  if (state == 'checking') vm.items.first.status = ImageItemStatus.checking;
  if (state == 'failedItems') {
    vm.items.first.status = ImageItemStatus.failed;
    vm.items.first.failure = ImagePdfFailure.corruptSource;
  }
  if (state == 'list' || state == 'grid') {
    vm.documents = imageDocumentFixtures();
    vm.remoteOnly.add(vm.documents.last.id);
  }
  await pumpResponsive(t, c,
      home: ImageToPdfView(viewModel: vm),
      settle: !['waiting', 'fetching', 'building', 'checking'].contains(state));
  await t.pump(const Duration(milliseconds: 300));
  expectNoLayoutException(t, c);
  expect(vm.starts, 1);
  expect(vm.recoveries, 1);
  expectFabLabelContained(t);
  return vm;
}

void main() {
  setUpAll(prepareResponsiveAssets);
  setUp(() => SharedPreferences.setMockInitialValues(
      {'scanner_grid_view_mode': false, 'image_pdf_list_view_mode': true}));
  testWidgets('Scanner FAB 280 EN 2x label is contained', (t) async {
    await scanner(
        t, const ResponsiveCase(Size(280, 600), textScale: 2), 'empty');
  });
  testWidgets('Images FAB 280 EN 2x label is contained', (t) async {
    await images(
        t, const ResponsiveCase(Size(280, 600), textScale: 2), 'empty');
  });
  for (var i = 0; i < sizes.length; i++) {
    final c = scenario(i);
    for (final state in ['empty', 'loading', 'waiting', 'error', 'fetching']) {
      testWidgets('Scanner non-grid $state $c', (t) async {
        final vm = await scanner(t, c, state);
        if (state == 'error') {
          final retry =
              find.widgetWithText(OutlinedButton, loc(t).translate('retry'));
          await reach(t, retry);
          await t.tap(retry);
          await t.pump();
          expect(vm.retries, 1);
        }
      });
    }
    testWidgets('Scanner list metadata/selection/menu $c', (t) async {
      final vm = await scanner(t, c, 'list');
      for (final index in [0, 3, 5]) {
        final key = find.byKey(ValueKey<String>(vm.documents[index].id));
        await t.scrollUntilVisible(key, 250,
            scrollable: find.byType(Scrollable).first);
        final preview = find.descendant(
            of: key, matching: find.byTooltip(loc(t).translate('preview')));
        await reach(t, preview);
        expect(preview.hitTestable(), findsOneWidget);
        expectNoLayoutException(t, c);
      }
      final select = find.byTooltip(loc(t).translate('selectDocuments'));
      await t.tap(select);
      await t.pumpAndSettle();
      vm.toggleSelection(vm.documents.last.id);
      await t.pumpAndSettle();
      expect(vm.selectedCount, 1);
      expect(find.byTooltip(loc(t).translate('shareSelected')).hitTestable(),
          findsOneWidget);
      await t.tap(find.byTooltip(loc(t).translate('cancelSelection')));
      await t.pumpAndSettle();
      expect(vm.isSelectionMode, isFalse);
      expect(vm.starts, 1);
    });
    testWidgets('Scanner settings $c', (t) async {
      final vm = await scanner(t, c, 'empty');
      await t.tap(find.byTooltip(loc(t).translate('scanSettings')));
      await t.pumpAndSettle();
      expectNoLayoutException(t, c);
      final mode = find.widgetWithText(
          RadioListTile<ScanMode>, loc(t).translate('receipt'));
      await reach(t, mode);
      await t.tap(mode);
      await t.pumpAndSettle();
      expect(vm.scanMode, ScanMode.receipt);
      final pages = find.widgetWithText(ChoiceChip, '20');
      await reach(t, pages);
      await t.tap(pages);
      await t.pumpAndSettle();
      expect(vm.maxPages, 20);
      expectNoLayoutException(t, c);
    });
    for (final state in [
      'empty',
      'waiting',
      'error',
      'fetching',
      'building',
      'checking',
      'failedItems',
      'list',
      'grid',
      'items'
    ]) {
      testWidgets('Images to PDF $state $c', (t) async {
        if (state == 'grid')
          SharedPreferences.setMockInitialValues(
              {'image_pdf_list_view_mode': false});
        final vm = await images(t, c, state);
        if (state == 'error') {
          final retry =
              find.widgetWithText(TextButton, loc(t).translate('retry'));
          await reach(t, retry);
          await t.tap(retry);
          await t.pump();
          expect(vm.retries, 1);
        }
        if (['items', 'list', 'grid', 'failedItems'].contains(state)) {
          for (final index in [0, 3, 5]) {
            final target = state == 'items' || state == 'failedItems'
                ? find.byKey(ValueKey(vm.items[index].id))
                : find.text(vm.documents[index].name);
            await t.scrollUntilVisible(target, 250,
                scrollable: find.byType(Scrollable).first);
            await reach(t, target);
            expect(target.hitTestable(), findsOneWidget);
            expectNoLayoutException(t, c);
          }
          if (state == 'items') {
            t
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await t.pumpAndSettle();
            final field = find.byType(TextField);
            await reach(t, field);
            await t.enterText(field, 'قيمة محلية طويلة retained PDF name');
            expect(t.widget<TextField>(field).controller!.text,
                'قيمة محلية طويلة retained PDF name');
          }
        }
      });
    }
    testWidgets('Images settings options/validation/apply $c', (t) async {
      final vm = await images(t, c, 'settings');
      vm.settings = const ImagePdfSettings(
          pageSize: PdfPageSize.custom,
          watermark: true,
          watermarkText: 'Local watermark');
      vm.notifyListeners();
      await t.pumpAndSettle();
      await t.tap(find.byTooltip(loc(t).translate('settings')));
      await t.pumpAndSettle();
      expect(find.byType(ImagePdfSettingsSheet), findsOneWidget);
      expectNoLayoutException(t, c);
      final width = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.labelText == loc(t).translate('i2pWidth'));
      await reach(t, width);
      await t.enterText(width, '0');
      await t.pumpAndSettle();
      expect(find.text(loc(t).translate('i2pCustomRange')), findsOneWidget);
      await t.enterText(width, '210');
      await t.pumpAndSettle();
      final apply = find.widgetWithText(
          ElevatedButton, loc(t).translate('applySettings'));
      await reach(t, apply);
      expect(apply.hitTestable(), findsOneWidget);
      await t.tap(apply);
      await t.pumpAndSettle();
      expect(vm.settingsChanges, 1);
      expect(vm.settings.pageSize, PdfPageSize.custom);
    });
    testWidgets('Scanner review pages/name/discard cancel $c', (t) async {
      final vm = LocalScannerModel()..draft = scanFixture();
      track(vm);
      await pumpResponsive(t, c,
          home: ScannerReviewScreen(
              viewModel: vm,
              imageProviderForPath: (_) => MemoryImage(r7aPreview)));
      final grid = find.byType(Scrollable).first;
      await t.drag(grid, const Offset(0, -240));
      await t.pumpAndSettle();
      expectNoLayoutException(t, c);
      final name = find.byType(TextField);
      await reach(t, name);
      await t.enterText(name, 'local review name');
      final discard =
          find.widgetWithText(OutlinedButton, loc(t).translate('discard'));
      await reach(t, discard);
      expect(discard.hitTestable(), findsOneWidget);
      await t.tap(discard);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final cancel =
          find.widgetWithText(TextButton, loc(t).translate('cancel'));
      await reach(t, cancel);
      await t.tap(cancel);
      await t.pumpAndSettle();
      expect(vm.draft, isNotNull);
      expect(vm.saveRequests, 0);
      expectNoLayoutException(t, c);
    });
    testWidgets('Scanner review saving presentation $c', (t) async {
      final vm = LocalScannerModel()..draft = scanFixture();
      track(vm);
      await pumpResponsive(t, c,
          home: ScannerReviewScreen(
              viewModel: vm,
              imageProviderForPath: (_) => MemoryImage(r7aPreview)));
      await reach(t, find.byType(TextField));
      vm.saving = true;
      vm.notifyListeners();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNull);
      expect(vm.saveRequests, 0);
      expectNoLayoutException(t, c);
    });
    testWidgets('Scanner image viewer memory/aspect $c', (t) async {
      await pumpResponsive(t, c,
          home: ScannerImageViewer(
              file: File('unused-preview.png'),
              title: r7aName,
              imageProvider: MemoryImage(r7aPreview)),
          settle: false);
      await t.runAsync(() => precacheImage(
          MemoryImage(r7aPreview), t.element(find.byType(PhotoView))));
      await t.pumpAndSettle();
      final viewer = t.widget<PhotoView>(find.byType(PhotoView));
      expect(viewer.imageProvider, isA<MemoryImage>());
      expect(viewer.minScale, PhotoViewComputedScale.contained);
      expect(viewer.maxScale, PhotoViewComputedScale.covered * 4);
      expectNoLayoutException(t, c);
    });
  }
  for (final i in [0, 5]) {
    testWidgets('Images keyboard/resize preserves selection name and focus $i',
        (t) async {
      final c = scenario(i, keyboard: 240);
      final vm = await images(t, c, 'items');
      final field = find.byType(TextField);
      await reach(t, field);
      await t.enterText(field, 'retained image PDF');
      final controller = t.widget<TextField>(field).controller;
      final focus =
          t.widget<EditableText>(find.byType(EditableText).first).focusNode;
      for (final size in [
        const Size(640, 360),
        const Size(280, 600),
        const Size(393, 852)
      ]) {
        await pumpResponsive(t,
            ResponsiveCase(size, locale: c.locale, textScale: 2, keyboard: 240),
            home: ImageToPdfView(viewModel: vm));
        expect(t.widget<TextField>(field).controller, same(controller));
        expect(controller!.text, 'retained image PDF');
        expect(focus.hasFocus, isTrue);
        expect(vm.starts, 1);
        expect(vm.recoveries, 1);
        expect(vm.items.length, 6);
      }
    });
    testWidgets('Scanner review keyboard/resize/error $i', (t) async {
      final vm = LocalScannerModel()..draft = scanFixture();
      track(vm);
      final c =
          ResponsiveCase(const Size(393, 852), locale: scenario(i).locale);
      await pumpResponsive(t, c,
          home: ScannerReviewScreen(
              viewModel: vm,
              imageProviderForPath: (_) => MemoryImage(r7aPreview)));
      final field = find.byType(TextField);
      await reach(t, field);
      await t.enterText(field, 'retained scan name');
      final controller = t.widget<TextField>(field).controller;
      final focus =
          t.widget<EditableText>(find.byType(EditableText).first).focusNode;
      for (final size in [const Size(640, 360), const Size(280, 600)]) {
        await pumpResponsive(t,
            ResponsiveCase(size, locale: c.locale, textScale: 2, keyboard: 240),
            home: ScannerReviewScreen(
                viewModel: vm,
                imageProviderForPath: (_) => MemoryImage(r7aPreview)));
        expect(t.widget<TextField>(field).controller, same(controller));
        expect(focus.hasFocus, isTrue);
        expect(controller!.text, 'retained scan name');
      }
      final save = find.byType(ElevatedButton);
      await reach(t, save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(vm.saveRequests, 1);
      expect(vm.draft!.pages.length, 12);
      expect(
          find.text(loc(t).translate('scannerErrStorageFull')), findsOneWidget);
      await reach(t, save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(vm.saveRequests, 2);
      expect(controller!.text, 'retained scan name');
      expectNoLayoutException(t, c);
    });
    testWidgets('Images modal settings stays above keyboard $i', (t) async {
      final c = scenario(i, keyboard: 240);
      final vm = await images(t, c, 'settings');
      await t.tap(find.byTooltip(loc(t).translate('settings')));
      await t.pumpAndSettle();
      final sheet = find.byType(ImagePdfSettingsSheet);
      final content =
          find.descendant(of: sheet, matching: find.byType(Container)).first;
      expect(t.getRect(content).bottom,
          lessThanOrEqualTo(c.size.height - c.keyboard));
      final apply = find.widgetWithText(
          ElevatedButton, loc(t).translate('applySettings'));
      await reach(t, apply);
      expect(t.getCenter(apply).dy, lessThan(c.size.height - c.keyboard));
      await t.tap(apply);
      await t.pumpAndSettle();
      expect(vm.settingsChanges, 1);
      expectNoLayoutException(t, c);
    });
    testWidgets('Images settings keyboard resize retains fields $i', (t) async {
      ImagePdfSettingsResult? result;
      Widget sheet() => Scaffold(
          resizeToAvoidBottomInset: false,
          body: ImagePdfSettingsSheet(
              settings: const ImagePdfSettings(pageSize: PdfPageSize.custom),
              hasPassword: false,
              onApply: (value) => result = value));
      await pumpResponsive(t, scenario(i), home: sheet());
      final label = loc(t).translate('i2pWidth');
      final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label);
      await reach(t, field);
      await t.enterText(field, '222');
      final controller = t.widget<TextField>(field).controller;
      final focus = t
          .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)))
          .focusNode;
      for (final size in [
        const Size(640, 360),
        const Size(280, 600),
        const Size(393, 852)
      ]) {
        await pumpResponsive(
            t,
            ResponsiveCase(size,
                locale: scenario(i).locale, textScale: 2, keyboard: 240),
            home: sheet());
        expect(t.widget<TextField>(field).controller, same(controller));
        expect(controller!.text, '222');
        expect(focus.hasFocus, isTrue);
      }
      expect(result, isNull);
      expectNoLayoutException(t, scenario(i));
    });
  }
}
