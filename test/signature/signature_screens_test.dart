import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/services/signature/signature_executor.dart';
import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';
import 'package:broker_wallet/src/services/signature/signature_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/document_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_view.dart';

import 'signature_fixtures.dart';
import 'signature_test_support.dart';

/// The plan-limit check, answered by the test. [hold] keeps the answer pending
/// until the test completes it.
class FakeGate implements SignatureUsageGate {
  FakeGate(this.recorder, {this.allow = true});

  final RecordingSignatureUsage recorder;
  bool allow;
  int asked = 0;
  Completer<bool>? hold;

  @override
  Future<bool> allowNewSignedDocument(BuildContext context, String userId) {
    asked++;
    final pending = hold;
    if (pending != null) return pending.future;
    return Future<bool>.value(allow);
  }

  @override
  Future<void> recordSignedDocument(String userId) =>
      recorder.recordSignedDocument(userId);
}

class FailingExecutor implements SignatureExecutor {
  FailingExecutor(this.failure);

  final SignatureFailure failure;

  @override
  Future<SignatureAnalysis> analyze(String path, {int? maxBytes}) =>
      const InlineSignatureExecutor().analyze(path, maxBytes: maxBytes);

  @override
  Future<SignatureWriteResult> write(
          SignatureWriteJob job, SignatureCancelToken token) async =>
      throw SignatureException(failure);
}

ValueKey<String> key(String value) => ValueKey<String>(value);

Future<PickedSignaturePdf> pickedFile(
    SignatureHarness h, String name, List<int> bytes) async {
  final file = await writeFile(h.inputs, name, bytes);
  return PickedSignaturePdf(path: file.path, name: name);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];
  late SignatureHarness h;
  late FakeGate gate;

  setUpAll(() => setUpSignatureWidgetTests(binding, toasts));
  setUp(() {
    toasts.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() async {
    await h.dispose();
  });

  void begin([SignatureHarness? harness]) {
    h = harness ?? SignatureHarness();
    gate = FakeGate(h.usage);
  }

  // --------------------------------------------------------------- the library

  /// Saves one signed document for the current account.
  Future<SignedDocument> saveOne(String title) async {
    final file = await h.pdf('$title.pdf', 'T', count: 2);
    final session = await h.session(file, name: '$title.pdf');
    await h.place(session);
    final outcome = await h.save(session, name: title);
    session.dispose();
    await h.pumpFutures();
    return outcome.document!;
  }

  Future<List<SignedDocument>> seed(
      WidgetTester tester, List<String> titles) async {
    final saved = <SignedDocument>[];
    await tester.runAsync(() async {
      await h.viewModel.start();
      for (final title in titles) {
        saved.add(await saveOne(title));
      }
    });
    return saved;
  }

  Future<void> pumpLibrary(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
    Size size = const Size(420, 900),
  }) async {
    useScreen(tester, size: size);
    await tester.pumpWidget(signatureApp(
      SignatureScreen(
        viewModel: h.viewModel,
        usageGate: gate,
        rendererFactory: () => FakePageRenderer(),
      ),
      locale: locale,
      theme: theme,
    ));
    await tester.pump();
    await pumpUntil(tester, () => !h.viewModel.isLoading);
    await tester.pump();
  }

  Finder menuOf(SignedDocument doc) => find.descendant(
      of: find.byKey(key('document-${doc.id}')),
      matching: find.byIcon(Icons.more_vert));

  group('the library', () {
    testWidgets('empty: says so and offers to upload', (tester) async {
      begin();
      await pumpLibrary(tester);
      expect(find.text(message('noSignedDocuments')), findsOneWidget);
      expect(find.text(message('uploadDocument')), findsOneWidget);
      expect(find.text(message('signDocument')), findsOneWidget);
      expect(find.byIcon(Icons.checklist), findsNothing);
    });

    testWidgets('shows the account\'s documents as cards, then as a list',
        (tester) async {
      begin();
      final docs = await seed(tester, ['Lease', 'Plan']);
      await pumpLibrary(tester);
      for (final doc in docs) {
        expect(find.byKey(key('document-${doc.id}')), findsOneWidget);
        expect(find.text(doc.name), findsOneWidget);
      }
      expect(find.text('2 ${message('pages')} • PDF'), findsNWidgets(2));
      expect(find.text('1 ${message('signatures')}'), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.view_list));
      await tester.pump();
      for (final doc in docs) {
        expect(find.byKey(key('document-${doc.id}')), findsOneWidget);
      }
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
    });

    testWidgets('selection works by document, and a bulk delete asks first',
        (tester) async {
      begin();
      final docs = await seed(tester, ['A', 'B', 'C']);
      await pumpLibrary(tester);
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();
      final delete = find.widgetWithIcon(IconButton, Icons.delete);
      expect(tester.widget<IconButton>(delete).onPressed, isNull,
          reason: 'nothing selected, nothing to delete');
      await tester.tap(find.byKey(key('document-${docs[0].id}')));
      await tester.tap(find.byKey(key('document-${docs[2].id}')));
      await tester.pump();
      expect(h.viewModel.selectedCount, 2);
      // Cancelling keeps everything.
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text(message('cancel')));
      await tester.pumpAndSettle();
      expect(h.viewModel.documents, hasLength(3));
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key('confirm-delete')));
      await pumpUntil(tester, () => h.viewModel.documents.length == 1);
      await tester.pumpAndSettle();
      expect(h.viewModel.documents.single.id, docs[1].id);
      expect(h.viewModel.isSelectionMode, isFalse);
      expect(toasts.last, '2 ${message('documentsDeleted')}');
    });

    testWidgets('one document is deleted from its menu, after a question',
        (tester) async {
      begin();
      final docs = await seed(tester, ['Gone', 'Stays']);
      await pumpLibrary(tester);
      await tester.tap(menuOf(docs.first));
      await tester.pumpAndSettle();
      await tester.tap(find.text(message('delete')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(key('confirm-delete')), findsOneWidget);
      await tester.tap(find.byKey(key('confirm-delete')));
      await pumpUntil(tester, () => h.viewModel.documents.length == 1);
      await tester.pumpAndSettle();
      expect(h.viewModel.documents.single.id, docs.last.id);
      expect(toasts, contains(message('documentDeleted')));
    });

    testWidgets('renaming shows why a name is refused and keeps the dialog',
        (tester) async {
      begin();
      await seed(tester, ['Lease', 'Plan']);
      await pumpLibrary(tester);
      final lease = h.viewModel.documents.firstWhere((d) => d.name == 'Lease');
      await tester.tap(menuOf(lease));
      await tester.pumpAndSettle();
      await tester.tap(find.text(message('rename')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(key('rename-field')), findsOneWidget);

      await tester.enterText(find.byKey(key('rename-field')), '   ');
      await tester.tap(find.byKey(key('rename-ok')));
      await pumpUntil(tester,
          () => find.text(message('sigErrInvalidName')).evaluate().isNotEmpty);
      expect(find.byKey(key('rename-field')), findsOneWidget);

      await tester.enterText(find.byKey(key('rename-field')), 'plan');
      await tester.tap(find.byKey(key('rename-ok')));
      await pumpUntil(tester,
          () => find.text(message('sigErrNameInUse')).evaluate().isNotEmpty);

      await tester.enterText(find.byKey(key('rename-field')), 'عقد جديد');
      await tester.tap(find.byKey(key('rename-ok')));
      await pumpUntil(
          tester, () => h.viewModel.documentById(lease.id)!.name == 'عقد جديد');
      await tester.pumpAndSettle();
      expect(find.byKey(key('rename-field')), findsNothing);
      expect(find.text('عقد جديد'), findsOneWidget);
      expect(toasts, contains(message('documentRenamed')));
    });

    testWidgets('Download exports under the title and says where it went',
        (tester) async {
      begin();
      final docs = await seed(tester, ['Lease']);
      await pumpLibrary(tester);
      await tester.tap(menuOf(docs.single));
      await tester.pumpAndSettle();
      await tester.tap(find.text(message('download')).last);
      await pumpUntil(tester, () => h.exporter.names.isNotEmpty);
      await tester.pump();
      expect(h.exporter.names, ['Lease.pdf']);
      expect(toasts.last,
          message('sigSavedToDownloads').replaceAll('{name}', 'x.pdf'));
    });

    testWidgets('an export that fails says so and nothing is claimed saved',
        (tester) async {
      begin();
      final docs = await seed(tester, ['Lease']);
      h.exporter.failWith =
          const SignatureException(SignatureFailure.permissionDenied);
      await pumpLibrary(tester);
      await tester.tap(menuOf(docs.single));
      await tester.pumpAndSettle();
      await tester.tap(find.text(message('download')).last);
      await pumpUntil(tester, () => toasts.isNotEmpty);
      expect(toasts.last, message('sigErrPermission'));
      final savedPrefix = message('sigSavedToDownloads').split('{').first;
      expect(toasts.any((t) => t.startsWith(savedPrefix)), isFalse);
    });

    testWidgets('a signed or protected PDF is refused with the reason',
        (tester) async {
      begin();
      await tester.runAsync(h.viewModel.start);
      await pumpLibrary(tester);
      late PickedSignaturePdf signed;
      late PickedSignaturePdf locked;
      await tester.runAsync(() async {
        signed = await pickedFile(h, 'signed.pdf', buildPdf('S', sign: true));
        locked = await pickedFile(h, 'locked.pdf',
            buildPdf('L', userPassword: 'u', ownerPassword: 'o'));
      });
      h.picker.next = signed;
      await tester.tap(find.byKey(key('upload-document')));
      await pumpUntil(
          tester, () => find.byKey(key('open-refusal')).evaluate().isNotEmpty);
      expect(tester.widget<Text>(find.byKey(key('open-refusal'))).data,
          message('sigErrSigned'));
      await tester.tap(find.text(message('ok')));
      await tester.pumpAndSettle();

      h.picker.next = locked;
      await tester.tap(find.byKey(key('upload-document')));
      await pumpUntil(
          tester, () => find.byKey(key('open-refusal')).evaluate().isNotEmpty);
      expect(tester.widget<Text>(find.byKey(key('open-refusal'))).data,
          message('sigErrEncrypted'));
      await tester.tap(find.text(message('ok')));
      await tester.pumpAndSettle();
      expect(h.viewModel.isEditing, isFalse);
      expect(h.usage.recorded, isEmpty);
    });

    testWidgets('a picker closed without a choice does nothing',
        (tester) async {
      begin();
      await tester.runAsync(h.viewModel.start);
      await pumpLibrary(tester);
      h.picker.next = null;
      await tester.tap(find.byKey(key('upload-document')));
      await pumpUntil(tester, () => h.picker.picks == 1);
      await tester.pump();
      expect(toasts, isEmpty);
      expect(find.byKey(key('open-refusal')), findsNothing);
      expect(h.viewModel.isOpening, isFalse);
    });

    testWidgets('a good PDF opens the editor, and back returns to the list',
        (tester) async {
      begin();
      await tester.runAsync(h.viewModel.start);
      await pumpLibrary(tester);
      late PickedSignaturePdf good;
      await tester.runAsync(() async {
        good = await pickedFile(h, 'lease.pdf', buildPdf('G', count: 2));
      });
      h.picker.next = good;
      await tester.tap(find.byKey(key('upload-document')));
      await pumpUntil(
          tester, () => find.byKey(key('add-button')).evaluate().isNotEmpty);
      expect(h.viewModel.isEditing, isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key('editor-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(key('add-button')), findsNothing);
      expect(h.viewModel.isEditing, isFalse,
          reason: 'the library screen closes the session it opened');
    });

    testWidgets('another account\'s documents are never shown', (tester) async {
      begin();
      await seed(tester, ['Mine']);
      await pumpLibrary(tester);
      expect(find.text('Mine'), findsOneWidget);
      await tester.runAsync(() => h.switchTo('user-b'));
      await tester.pump();
      await pumpUntil(tester, () => !h.viewModel.isLoading);
      await tester.pump();
      expect(find.text('Mine'), findsNothing);
      expect(find.text(message('noSignedDocuments')), findsOneWidget);
      await tester.runAsync(() => h.switchTo('user-a'));
      await tester.pump();
      await pumpUntil(tester, () => h.viewModel.documents.isNotEmpty);
      await tester.pump();
      expect(find.text('Mine'), findsOneWidget);
    });

    testWidgets('in Arabic it reads right to left', (tester) async {
      begin();
      await seed(tester, ['عقد']);
      await pumpLibrary(tester, locale: const Locale('ar'));
      expect(Directionality.of(tester.element(find.byType(SignatureScreen))),
          TextDirection.rtl);
      expect(find.text('عقد'), findsOneWidget);
      expect(
          find.text(message('uploadDocument', language: 'ar')), findsOneWidget);
    });

    testWidgets('in the dark theme and on a small screen it still lays out',
        (tester) async {
      begin();
      await seed(tester, ['Lease', 'Plan', 'Deed']);
      await pumpLibrary(tester,
          theme: ThemeData.dark(), size: const Size(360, 640));
      expect(find.text('Lease'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------- the editor

  Future<SignatureEditorViewModel> openEditor(
    WidgetTester tester, {
    int count = 3,
    List<PageSpec>? pages,
    FakePageRenderer? renderer,
    Locale locale = const Locale('en'),
    ThemeData? theme,
    Size size = const Size(420, 900),
    double density = 1,
  }) async {
    late SignatureEditorViewModel session;
    await tester.runAsync(() async {
      await h.viewModel.start();
      final file = await h.pdf('lease.pdf', 'L', count: count, pages: pages);
      session = await h.session(file, name: 'lease.pdf');
    });
    useScreen(tester, size: size, density: density);
    await tester.pumpWidget(signatureApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
                  builder: (_) => DocumentView(
                    viewModel: session,
                    rendererFactory: () => renderer ?? FakePageRenderer(),
                    usageGate: gate,
                  ),
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: locale,
      theme: theme,
    ));
    // The localization delegates load asynchronously: until one frame has passed
    // the app shows nothing, so there is no button to tap yet.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    // The route finishes its transition, the editor opens the file and the add
    // button scales in; until that animation ends its box has no size to tap.
    await tester.pumpAndSettle();
    return session;
  }

  Finder stampFinder(PlacedStamp stamp) => find.byKey(key('stamp-${stamp.id}'));

  Finder stampImage(PlacedStamp stamp) =>
      find.descendant(of: stampFinder(stamp), matching: find.byType(Image));

  /// Display pixels per page point at zoom 1.
  double pageScale(WidgetTester tester, SignatureEditorViewModel s) {
    final display = tester.getSize(find.byKey(key('page-background')));
    return display.width / s.pages[s.currentPage].width;
  }

  Future<void> add(WidgetTester tester, String option) async {
    await tester.tap(find.byKey(key('add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key(option)));
    await tester.pumpAndSettle();
  }

  /// Adds a date to the current page and returns it.
  Future<PlacedStamp> addDate(
      WidgetTester tester, SignatureEditorViewModel s) async {
    final before = s.placements.length;
    await add(tester, 'add-date');
    await tester.tap(find.byKey(key('date-ok')));
    await tester.pumpAndSettle();
    expect(s.placements.length, before + 1);
    return s.placements.last;
  }

  /// Draws a signature on the pad and places it.
  Future<PlacedStamp> addSignature(
      WidgetTester tester, SignatureEditorViewModel s) async {
    final before = s.placements.length;
    await add(tester, 'add-signature');
    final rect = tester.getRect(find.byKey(key('signature-pad')));
    final gesture =
        await tester.startGesture(rect.center + const Offset(-100, 0));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(25, 8));
    }
    await gesture.up();
    await tester.pump();
    await tester.tap(find.byKey(key('pad-confirm')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => s.placements.length == before + 1);
    await tester.pumpAndSettle();
    return s.placements.last;
  }

  group('the editor: pages', () {
    testWidgets('opens on the first page and moves between pages',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(key('page-prev'))).onPressed,
          isNull);
      await tester.tap(find.byKey(key('page-next')));
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(s.currentPage, 1);
      await tester.tap(find.byKey(key('page-next')));
      await tester.pump();
      expect(tester.widget<IconButton>(find.byKey(key('page-next'))).onPressed,
          isNull);
      await tester.tap(find.byKey(key('page-prev')));
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('a page can be jumped to by number', (tester) async {
      begin();
      final s = await openEditor(tester, count: 6);
      await tester.tap(find.byKey(key('page-indicator')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(key('goto-field')), '5');
      await tester.tap(find.byKey(key('goto-ok')));
      await tester.pumpAndSettle();
      expect(s.currentPage, 4);
      await tester.tap(find.byKey(key('page-indicator')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(key('goto-field')), '99');
      await tester.tap(find.byKey(key('goto-ok')));
      await tester.pumpAndSettle();
      expect(s.currentPage, 5,
          reason: 'a number past the end goes to the last');
    });

    testWidgets('a one-page document has no page controls', (tester) async {
      begin();
      await openEditor(tester, count: 1);
      expect(find.byKey(key('page-indicator')), findsNothing);
    });

    testWidgets('items stay on their own page', (tester) async {
      begin();
      final s = await openEditor(tester);
      final first = await addDate(tester, s);
      await tester.tap(find.byKey(key('page-next')));
      await tester.pump();
      expect(stampFinder(first), findsNothing);
      final second = await addDate(tester, s);
      expect(second.pageIndex, 1);
      await tester.tap(find.byKey(key('page-prev')));
      await tester.pump();
      expect(stampFinder(first), findsOneWidget);
      expect(stampFinder(second), findsNothing);
    });
  });

  group('the editor: adding', () {
    testWidgets('a date goes on the current page, selected, with its handles',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      await add(tester, 'add-date');
      expect(find.byKey(key('date-preview')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(key('date-preview'))).data,
          StampDate.numeric(DateTime.now()));
      await tester.tap(find.byKey(key('date-ok')));
      await tester.pumpAndSettle();
      final stamp = s.placements.single;
      expect(stamp.pageIndex, 0);
      expect(s.selectedId, stamp.id);
      expect(s.assetById(stamp.assetId)!.kind, StampKind.date);
      expect(
          s.assetById(stamp.assetId)!.label, StampDate.numeric(DateTime.now()));
      expect(stampFinder(stamp), findsOneWidget);
      for (final corner in StampCorner.values) {
        expect(find.byKey(key('handle-${corner.name}')), findsOneWidget);
      }
    });

    testWidgets('a date can be written with the month name', (tester) async {
      begin();
      final s = await openEditor(tester);
      await add(tester, 'add-date');
      await tester.tap(find.byKey(key('date-format-long')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(key('date-preview'))).data,
          StampDate.long(DateTime.now(), arabic: false));
      await tester.tap(find.byKey(key('date-ok')));
      await tester.pumpAndSettle();
      expect(s.assetById(s.placements.single.assetId)!.label,
          StampDate.long(DateTime.now(), arabic: false));
    });

    testWidgets('in Arabic the date uses Arabic month names', (tester) async {
      begin();
      final s = await openEditor(tester, locale: const Locale('ar'));
      await add(tester, 'add-date');
      await tester.tap(find.byKey(key('date-format-long')));
      await tester.pump();
      await tester.tap(find.byKey(key('date-ok')));
      await tester.pumpAndSettle();
      expect(s.assetById(s.placements.single.assetId)!.label,
          StampDate.long(DateTime.now(), arabic: true));
    });

    testWidgets('typed text, Arabic or English, is placed with its direction',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      await add(tester, 'add-text');
      await tester.enterText(find.byKey(key('typed-stamp-field')), 'محمد أحمد');
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(key('typed-stamp-field')))
              .textDirection,
          TextDirection.rtl);
      await tester.tap(find.byKey(key('typed-stamp-ok')));
      await tester.pumpAndSettle();
      expect(s.assetById(s.placements.single.assetId)!.label, 'محمد أحمد');
      await add(tester, 'add-text');
      await tester.enterText(find.byKey(key('typed-stamp-field')), 'Mohammed');
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(key('typed-stamp-field')))
              .textDirection,
          TextDirection.ltr);
      await tester.tap(find.byKey(key('typed-stamp-ok')));
      await tester.pumpAndSettle();
      expect(s.placements, hasLength(2));
    });

    testWidgets('an empty text is refused in the dialog and places nothing',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      await add(tester, 'add-text');
      await tester.enterText(find.byKey(key('typed-stamp-field')), '   ');
      await tester.tap(find.byKey(key('typed-stamp-ok')));
      await tester.pump();
      expect(find.text(message('sigTextInvalid')), findsOneWidget);
      expect(s.placements, isEmpty);
    });

    testWidgets('typed initials are limited to six letters', (tester) async {
      begin();
      final s = await openEditor(tester);
      await add(tester, 'add-initials-type');
      await tester.enterText(find.byKey(key('typed-stamp-field')), 'ABCDEFGH');
      await tester.tap(find.byKey(key('typed-stamp-ok')));
      await tester.pumpAndSettle();
      final asset = s.assetById(s.placements.single.assetId)!;
      expect(asset.label!.runes.length,
          lessThanOrEqualTo(StampText.maxInitialsRunes));
      expect(asset.kind, StampKind.initials);
    });

    testWidgets('a drawn signature is placed, and can be used again',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      final first = await addSignature(tester, s);
      expect(s.assetById(first.assetId)!.kind, StampKind.signature);
      expect(h.stamps.drawings, 1);
      // The sheet offers the signature drawn in this session.
      await tester.tap(find.byKey(key('add-button')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(key('reuse-signature-${first.assetId}')), findsOneWidget);
      await tester.tap(find.byKey(key('reuse-signature-${first.assetId}')));
      await tester.pumpAndSettle();
      expect(s.placements, hasLength(2));
      expect(s.placements.last.assetId, first.assetId);
      expect(s.placements.last.id, isNot(first.id));
      expect(h.stamps.drawings, 1, reason: 'reusing draws nothing new');
      expect(s.assets, hasLength(1));
    });

    testWidgets('closing the sheet or the pad places nothing', (tester) async {
      begin();
      final s = await openEditor(tester);
      await tester.tap(find.byKey(key('add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(message('cancel')));
      await tester.pumpAndSettle();
      expect(s.placements, isEmpty);
      await add(tester, 'add-signature');
      await tester.tap(find.byTooltip(message('cancel')));
      await tester.pumpAndSettle();
      expect(s.placements, isEmpty);
      expect(h.stamps.drawings, 0);
    });

    testWidgets('an image that cannot be made says so and places nothing',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      h.stamps.failWith =
          const SignatureException(SignatureFailure.stampFailed);
      await add(tester, 'add-date');
      await tester.tap(find.byKey(key('date-ok')));
      await tester.pumpAndSettle();
      expect(s.placements, isEmpty);
      expect(toasts, contains(message('sigErrStamp')));
    });
  });

  group('the editor: where things go', () {
    testWidgets('a drag moves an item by exactly the finger\'s distance',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      final stamp = await addDate(tester, s);
      final scale = pageScale(tester, s);
      await tester.drag(stampFinder(stamp), const Offset(60, 40));
      await tester.pump();
      final moved = s.stampById(stamp.id)!.rect;
      expect(moved.left - stamp.rect.left, closeTo(60 / scale, 0.5));
      expect(moved.top - stamp.rect.top, closeTo(40 / scale, 0.5));
      expect(moved.width, stamp.rect.width);
      // One undo undoes the whole drag.
      await tester.tap(find.byKey(key('undo-button')));
      await tester.pump();
      expect(s.stampById(stamp.id)!.rect, stamp.rect);
    });

    testWidgets(
        'the same drag moves it by the same page distance when zoomed in',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      final stamp = await addDate(tester, s);
      final scale = pageScale(tester, s);
      await tester.tap(find.byKey(key('zoom-in')));
      await tester.pump();
      final viewer =
          tester.widget<InteractiveViewer>(find.byKey(key('page-viewer')));
      final zoom = viewer.transformationController!.value.getMaxScaleOnAxis();
      expect(zoom, closeTo(1.5, 1e-6));
      await tester.drag(stampFinder(stamp), const Offset(60, 40));
      await tester.pump();
      final moved = s.stampById(stamp.id)!.rect;
      expect(moved.left - stamp.rect.left, closeTo(60 / (scale * zoom), 0.5));
      expect(moved.top - stamp.rect.top, closeTo(40 / (scale * zoom), 0.5));
      // Zooming back out moves nothing.
      await tester.tap(find.byKey(key('zoom-reset')));
      await tester.pump();
      expect(s.stampById(stamp.id)!.rect, moved);
    });

    testWidgets('an item cannot be dragged off its page', (tester) async {
      begin();
      final s = await openEditor(tester);
      final stamp = await addDate(tester, s);
      await tester.drag(stampFinder(stamp), const Offset(2000, 2000));
      await tester.pump();
      final geometry = s.pages[0];
      final r = s.stampById(stamp.id)!.rect;
      expect(r.right, closeTo(geometry.width, 1e-6));
      expect(r.bottom, closeTo(geometry.height, 1e-6));
      await tester.drag(stampFinder(stamp), const Offset(-4000, -4000));
      await tester.pump();
      expect(s.stampById(stamp.id)!.rect.left, closeTo(0, 1e-6));
      expect(s.stampById(stamp.id)!.rect.top, closeTo(0, 1e-6));
    });

    testWidgets('a corner handle resizes about the opposite corner',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      final stamp = await addSignature(tester, s);
      final scale = pageScale(tester, s);
      await tester.drag(
          find.byKey(key('handle-bottomRight')), const Offset(30, 0));
      await tester.pump();
      final bigger = s.stampById(stamp.id)!.rect;
      expect(bigger.left, closeTo(stamp.rect.left, 1e-6));
      expect(bigger.top, closeTo(stamp.rect.top, 1e-6));
      expect(bigger.width - stamp.rect.width, closeTo(30 / scale, 0.7));
      expect(bigger.aspect, closeTo(stamp.rect.aspect, 1e-6));

      await tester.drag(
          find.byKey(key('handle-topLeft')), const Offset(-20, -10));
      await tester.pump();
      final again = s.stampById(stamp.id)!.rect;
      expect(again.right, closeTo(bigger.right, 1e-6));
      expect(again.bottom, closeTo(bigger.bottom, 1e-6));
      expect(again.width, greaterThan(bigger.width));
      expect(again.aspect, closeTo(stamp.rect.aspect, 1e-6));
    });

    testWidgets('two fingers on an item resize it about its centre',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      final stamp = await addSignature(tester, s);
      final center = tester.getCenter(stampFinder(stamp));
      final one = await tester.startGesture(center + const Offset(-10, 0));
      final two = await tester.startGesture(center + const Offset(10, 0));
      await one.moveBy(const Offset(-5, 0));
      await two.moveBy(const Offset(5, 0));
      await one.moveBy(const Offset(-5, 0));
      await two.moveBy(const Offset(5, 0));
      await one.up();
      await two.up();
      await tester.pump();
      final resized = s.stampById(stamp.id)!.rect;
      expect(resized.width, greaterThan(stamp.rect.width));
      expect(resized.aspect, closeTo(stamp.rect.aspect, 1e-6));
      expect(resized.centerX, closeTo(stamp.rect.centerX, 1.0));
      expect(resized.centerY, closeTo(stamp.rect.centerY, 1.0));
    });

    testWidgets('a drag that starts on the page, not on an item, moves no item',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      final stamp = await addDate(tester, s);
      await tester.tap(find.byKey(key('zoom-in')));
      await tester.pump();
      final from = tester.getTopLeft(find.byKey(key('page-background'))) +
          const Offset(8, 8);
      await tester.dragFrom(from, const Offset(40, 30));
      await tester.pump();
      expect(s.stampById(stamp.id)!.rect, stamp.rect);
    });

    testWidgets('selecting, deselecting and the tool bar', (tester) async {
      begin();
      final s = await openEditor(tester);
      final stamp = await addSignature(tester, s);
      expect(find.byKey(key('tool-delete')), findsOneWidget);
      // A tap on the empty corner of the page deselects.
      await tester.tapAt(tester.getTopLeft(find.byKey(key('page-background'))) +
          const Offset(10, 10));
      await tester.pump();
      expect(s.selectedId, isNull);
      expect(find.byKey(key('tool-delete')), findsNothing);
      expect(find.byKey(key('handle-topLeft')), findsNothing);
      await tester.tap(stampFinder(stamp));
      await tester.pump();
      expect(s.selectedId, stamp.id);
      await tester.tap(find.byKey(key('tool-larger')));
      await tester.pump();
      expect(s.stampById(stamp.id)!.rect.width,
          closeTo(stamp.rect.width * 1.15, 1e-6));
      await tester.tap(find.byKey(key('tool-smaller')));
      await tester.pump();
      expect(
          s.stampById(stamp.id)!.rect.width, closeTo(stamp.rect.width, 1e-6));
      await tester.tap(find.byKey(key('tool-delete')));
      await tester.pump();
      expect(s.placements, isEmpty);
      expect(stampFinder(stamp), findsNothing);
      expect(find.byKey(key('tool-delete')), findsNothing);
    });

    testWidgets('two items stay independent', (tester) async {
      begin();
      final s = await openEditor(tester);
      final first = await addDate(tester, s);
      final second = await addSignature(tester, s);
      await tester.drag(stampFinder(second), const Offset(0, 120));
      await tester.pump();
      expect(s.stampById(first.id)!.rect, first.rect);
      expect(s.stampById(second.id)!.rect.top, greaterThan(second.rect.top));
    });
  });

  group('the editor: layout independence', () {
    testWidgets(
        'the item covers the same part of the page in every orientation and density',
        (tester) async {
      begin();
      final s = await openEditor(tester, pages: [a4, a4Landscape, a4]);
      final stamp = await addSignature(tester, s);
      double widthShare() =>
          tester.getSize(stampImage(stamp)).width /
          tester.getSize(find.byKey(key('page-background'))).width;
      double heightShare() =>
          tester.getSize(stampImage(stamp)).height /
          tester.getSize(find.byKey(key('page-background'))).height;

      final wide = widthShare();
      final tall = heightShare();
      expect(wide, closeTo(stamp.rect.width / s.pages[0].width, 0.002));
      expect(tall, closeTo(stamp.rect.height / s.pages[0].height, 0.002));

      useScreen(tester, size: const Size(900, 420), density: 3);
      await tester.pump();
      await tester.pump();
      expect(widthShare(), closeTo(wide, 0.002));
      expect(heightShare(), closeTo(tall, 0.002));
      // The placement itself is still the same number of points.
      expect(s.stampById(stamp.id)!.rect, stamp.rect);
      // And the item is still inside the page on the screen.
      final pageRect = tester.getRect(find.byKey(key('page-background')));
      final itemRect = tester.getRect(stampImage(stamp));
      expect(pageRect.inflate(0.5).contains(itemRect.topLeft), isTrue);
      expect(pageRect.inflate(0.5).contains(itemRect.bottomRight), isTrue);
    });

    testWidgets('a landscape page and a portrait page both fit the screen',
        (tester) async {
      begin();
      final s = await openEditor(tester, pages: [a4, a4Landscape, a4]);
      final portrait = tester.getSize(find.byKey(key('page-background')));
      expect(portrait.width / portrait.height, closeTo(595 / 842, 0.001));
      await tester.tap(find.byKey(key('page-next')));
      await tester.pump();
      await tester.pump();
      final landscape = tester.getSize(find.byKey(key('page-background')));
      expect(landscape.width / landscape.height, closeTo(842 / 595, 0.001));
      expect(s.currentPage, 1);
    });
  });

  group('the editor: other pages, undo, leaving', () {
    testWidgets('an item goes onto other pages only when they are ticked',
        (tester) async {
      begin();
      final s = await openEditor(tester, count: 4);
      final stamp = await addSignature(tester, s);
      await tester.tap(find.byKey(key('tool-pages')));
      await tester.pumpAndSettle();
      // Nothing is ticked for the user, and OK is not available yet.
      for (var i = 1; i < 4; i++) {
        expect(
            tester
                .widget<CheckboxListTile>(find.byKey(key('apply-page-$i')))
                .value,
            isFalse);
      }
      expect(find.byKey(key('apply-page-0')), findsNothing,
          reason: 'the page it is on is not offered');
      expect(tester.widget<TextButton>(find.byKey(key('apply-ok'))).onPressed,
          isNull);
      await tester.tap(find.byKey(key('apply-page-1')));
      await tester.tap(find.byKey(key('apply-page-3')));
      await tester.pump();
      await tester.tap(find.byKey(key('apply-ok')));
      await tester.pumpAndSettle();
      expect(s.placements, hasLength(3));
      expect(s.stampsOnPage(2), isEmpty);
      expect(s.stampsOnPage(1).single.assetId, stamp.assetId);
      expect(toasts.last, message('sigApplied').replaceAll('{count}', '2'));
    });

    testWidgets('select all and clear in that dialog', (tester) async {
      begin();
      final s = await openEditor(tester, count: 3);
      await addSignature(tester, s);
      await tester.tap(find.byKey(key('tool-pages')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key('apply-all')));
      await tester.pump();
      expect(
          tester
              .widget<CheckboxListTile>(find.byKey(key('apply-page-1')))
              .value,
          isTrue);
      await tester.tap(find.byKey(key('apply-none')));
      await tester.pump();
      expect(
          tester
              .widget<CheckboxListTile>(find.byKey(key('apply-page-1')))
              .value,
          isFalse);
    });

    testWidgets('a date has no "other pages" tool', (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      expect(find.byKey(key('tool-delete')), findsOneWidget);
      expect(find.byKey(key('tool-pages')), findsNothing);
    });

    testWidgets('a one-page document has no "other pages" tool',
        (tester) async {
      begin();
      final s = await openEditor(tester, count: 1);
      await addSignature(tester, s);
      expect(find.byKey(key('tool-pages')), findsNothing);
    });

    testWidgets('undo and redo buttons follow the history', (tester) async {
      begin();
      final s = await openEditor(tester);
      expect(
          tester.widget<IconButton>(find.byKey(key('undo-button'))).onPressed,
          isNull);
      final stamp = await addDate(tester, s);
      expect(
          tester.widget<IconButton>(find.byKey(key('undo-button'))).onPressed,
          isNotNull);
      await tester.tap(find.byKey(key('undo-button')));
      await tester.pump();
      expect(s.placements, isEmpty);
      expect(stampFinder(stamp), findsNothing);
      await tester.tap(find.byKey(key('redo-button')));
      await tester.pump();
      expect(s.placements, hasLength(1));
      expect(
          tester.widget<IconButton>(find.byKey(key('redo-button'))).onPressed,
          isNull);
    });

    testWidgets(
        'leaving with unsaved items asks first; without any it just leaves',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      await tester.tap(find.byKey(key('editor-back')));
      await tester.pumpAndSettle();
      expect(find.text(message('sigLeaveTitle')), findsOneWidget);
      await tester.tap(find.byKey(key('leave-stay')));
      await tester.pumpAndSettle();
      expect(find.byKey(key('add-button')), findsOneWidget);
      expect(s.placements, hasLength(1));
      // The system back button asks as well.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(message('sigLeaveTitle')), findsOneWidget);
      await tester.tap(find.byKey(key('leave-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(key('add-button')), findsNothing);
    });

    testWidgets('leaving with nothing placed leaves at once', (tester) async {
      begin();
      await openEditor(tester);
      await tester.tap(find.byKey(key('editor-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(key('add-button')), findsNothing);
      expect(find.text(message('sigLeaveTitle')), findsNothing);
    });
  });

  group('the editor: problems with the file', () {
    testWidgets('a protected file the page renderer refuses', (tester) async {
      begin();
      await openEditor(tester,
          renderer:
              FakePageRenderer(failOpenWith: SignatureFailure.encryptedSource));
      expect(tester.widget<Text>(find.byKey(key('open-failure'))).data,
          message('sigErrEncrypted'));
      expect(find.byKey(key('add-button')), findsNothing);
    });

    testWidgets('a renderer that disagrees with the file\'s page sizes',
        (tester) async {
      begin();
      await openEditor(tester,
          count: 2,
          renderer: FakePageRenderer(sizes: const [
            RenderedPageSize(595, 842),
            RenderedPageSize(600, 900),
          ]));
      expect(tester.widget<Text>(find.byKey(key('open-failure'))).data,
          message('sigErrGeometry'));
      expect(find.byKey(key('add-button')), findsNothing);
      expect(find.byKey(key('save-button')), findsNothing);
    });

    testWidgets('a change of account closes the editor with a message',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      await tester.runAsync(() => h.switchTo('user-b'));
      // The editor pops itself after the next frame, and the route then needs its
      // exit animation; a zero-length pump never gets through that.
      await tester.pumpAndSettle();
      expect(find.byKey(key('add-button')), findsNothing);
      expect(toasts, contains(message('sigErrAccountChanged')));
      expect(s.accountChanged, isTrue);
    });
  });

  group('the editor: in other settings', () {
    testWidgets('in Arabic, right to left, with an item placed',
        (tester) async {
      begin();
      final s = await openEditor(tester, locale: const Locale('ar'));
      expect(Directionality.of(tester.element(find.byKey(key('add-button')))),
          TextDirection.rtl);
      expect(find.text(message('sigAdd', language: 'ar')), findsOneWidget);
      await addDate(tester, s);
      expect(find.text(message('save', language: 'ar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in the dark theme, on a small screen', (tester) async {
      begin();
      final s = await openEditor(tester,
          theme: ThemeData.dark(), size: const Size(320, 640));
      await addDate(tester, s);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------- save and the preview

  Future<void> openPreview(WidgetTester tester) async {
    await tester.tap(find.byKey(key('save-button')));
    await pumpUntil(
        tester, () => find.byKey(key('preview-save')).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }

  group('saving through the preview', () {
    testWidgets('nothing is saved until the preview\'s Save', (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      await openPreview(tester);
      expect(find.text(message('sigPreviewTitle')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(key('visible-note'))).data,
          message('sigVisibleNote'));
      expect(find.byKey(key('preview-page-0')), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(key('preview-name')))
              .controller!
              .text,
          'lease - ${message('sigSignedSuffix')}');
      expect(h.viewModel.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      expect(gate.asked, 0, reason: 'the plan limit is asked when saving');
    });

    testWidgets('Save stores the previewed draft, counts it once and returns',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      await openPreview(tester);
      final previewed = s.draft!.file.readAsBytesSync();
      await tester.enterText(find.byKey(key('preview-name')), 'Final lease');
      await tester.tap(find.byKey(key('preview-save')));
      await pumpUntil(tester, () => h.viewModel.documents.isNotEmpty);
      await tester.pumpAndSettle();
      final doc = h.viewModel.documents.single;
      expect(doc.name, 'Final lease');
      expect(gate.asked, 1);
      expect(h.usage.recorded, ['user-a']);
      expect(toasts, contains(message('documentSavedSuccessfully')));
      final stored = await tester.runAsync(() => h.viewModel.openableFile(doc));
      expect(stored!.readAsBytesSync(), previewed);
      // Both screens closed.
      expect(find.byKey(key('preview-save')), findsNothing);
      expect(find.byKey(key('add-button')), findsNothing);
    });

    testWidgets('a refused plan limit keeps the preview and saves nothing',
        (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      await openPreview(tester);
      gate.allow = false;
      await tester.tap(find.byKey(key('preview-save')));
      await pumpUntil(tester, () => gate.asked == 1);
      await tester.pumpAndSettle();
      expect(find.byKey(key('preview-save')), findsOneWidget);
      expect(h.viewModel.documents, isEmpty);
      expect(h.usage.recorded, isEmpty);
      // Allowed later, the same preview saves.
      gate.allow = true;
      await tester.tap(find.byKey(key('preview-save')));
      await pumpUntil(tester, () => h.viewModel.documents.isNotEmpty);
      await tester.pumpAndSettle();
      expect(h.usage.recorded, ['user-a']);
    });

    testWidgets('Save cannot be pressed twice', (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      await openPreview(tester);
      gate.hold = Completer<bool>();
      await tester.tap(find.byKey(key('preview-save')));
      await pumpUntil(tester, () => gate.asked == 1);
      // The gate is asked inside the tap itself; the button changes on the frame
      // that follows.
      await tester.pump();
      // While the first save waits, the button is not live and a tap does nothing.
      expect(
          tester
              .widget<ElevatedButton>(find.byKey(key('preview-save')))
              .onPressed,
          isNull);
      await tester.tap(find.byKey(key('preview-save')), warnIfMissed: false);
      await tester.pump();
      expect(gate.asked, 1);
      await tester.runAsync(() async => gate.hold!.complete(true));
      await pumpUntil(tester, () => h.viewModel.documents.isNotEmpty);
      await tester.pumpAndSettle();
      expect(h.viewModel.documents, hasLength(1));
      expect(h.usage.recorded, ['user-a']);
    });

    testWidgets(
        'Back to edit keeps every item, and an unchanged draft is reused',
        (tester) async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      begin(SignatureHarness(executor: gated));
      final s = await openEditor(tester);
      final stamp = await addDate(tester, s);
      await openPreview(tester);
      await tester.tap(find.byKey(key('preview-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(key('add-button')), findsOneWidget);
      expect(s.placements.single.id, stamp.id);
      await openPreview(tester);
      expect(gated.writes, 1);
      // A change in between needs a new draft.
      await tester.tap(find.byKey(key('preview-back')));
      await tester.pumpAndSettle();
      await tester.drag(stampFinder(stamp), const Offset(20, 20));
      await tester.pump();
      await openPreview(tester);
      expect(gated.writes, 2);
    });

    testWidgets('a page of the preview opens larger', (tester) async {
      begin();
      final s = await openEditor(tester);
      await addDate(tester, s);
      await openPreview(tester);
      await tester.tap(find.byKey(key('preview-page-0')));
      await tester.pumpAndSettle();
      expect(find.text('${message('sigPage')} 1'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(key('preview-save')), findsOneWidget);
    });
  });

  group('saving: failures', () {
    testWidgets('building the preview can be cancelled; nothing is kept',
        (tester) async {
      final gated = GatedSignatureExecutor(const InlineSignatureExecutor());
      gated.release = Completer<void>();
      begin(SignatureHarness(executor: gated));
      final s = await openEditor(tester);
      await addDate(tester, s);
      await tester.tap(find.byKey(key('save-button')));
      // The build awaits real file work in the test's own zone, so it only moves
      // while the tree is pumped.
      await pumpUntil(tester, () => gated.started.isCompleted);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(message('sigPreparing')), findsOneWidget);
      // The buttons are gone while it works: no second request is possible.
      expect(find.byKey(key('save-button')), findsNothing);
      expect(gated.writes, 1);
      await tester.tap(find.byKey(key('preparing-cancel')));
      await tester.runAsync(() async => gated.release!.complete());
      await pumpUntil(tester, () => !s.isBuilding);
      await tester.pumpAndSettle();
      expect(toasts, contains(message('sigErrCancelled')));
      expect(s.draft, isNull);
      expect(h.usage.recorded, isEmpty);
      expect(h.viewModel.documents, isEmpty);
      expect(find.byKey(key('add-button')), findsOneWidget);
    });

    testWidgets('a failed build offers a retry when a retry can help',
        (tester) async {
      begin(SignatureHarness(
          executor: FailingExecutor(SignatureFailure.writeFailed)));
      final s = await openEditor(tester);
      await addDate(tester, s);
      await tester.tap(find.byKey(key('save-button')));
      await pumpUntil(tester,
          () => find.text(message('sigErrWrite')).evaluate().isNotEmpty);
      expect(find.text(message('retry')), findsOneWidget);
      expect(h.usage.recorded, isEmpty);
    });

    testWidgets('a failure a retry cannot help is a plain message',
        (tester) async {
      begin(SignatureHarness(
          executor: FailingExecutor(SignatureFailure.sourceChanged)));
      final s = await openEditor(tester);
      await addDate(tester, s);
      await tester.tap(find.byKey(key('save-button')));
      await pumpUntil(tester, () => toasts.isNotEmpty);
      expect(toasts.last, message('sigErrChanged'));
      expect(find.text(message('retry')), findsNothing);
    });

    testWidgets('Save is not offered with nothing placed', (tester) async {
      begin();
      await openEditor(tester);
      expect(find.byKey(key('save-button')), findsNothing);
    });
  });
}
