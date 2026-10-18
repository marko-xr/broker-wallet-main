import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signature/signature.dart';

import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_pad_view.dart';

import 'signature_fixtures.dart';
import 'signature_test_support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];
  SignatureDrawing? result;
  var popped = false;

  setUpAll(() => setUpSignatureWidgetTests(binding, toasts));
  setUp(() {
    toasts.clear();
    result = null;
    popped = false;
  });

  const padKey = ValueKey<String>('signature-pad');

  Future<void> openPad(
    WidgetTester tester, {
    SignatureDrawing? initial,
    bool isInitials = false,
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) async {
    useScreen(tester);
    await tester.pumpWidget(signatureApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<SignatureDrawing>(
                  MaterialPageRoute<SignatureDrawing>(
                    builder: (_) => SignaturePadView(
                        initialDrawing: initial, isInitials: isInitials),
                  ),
                );
                popped = true;
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
    await tester.pumpAndSettle();
  }

  SignatureController controller(WidgetTester tester) =>
      tester.widget<Signature>(find.byKey(padKey)).controller;

  /// One stroke across the pad, in several moves.
  Future<void> stroke(WidgetTester tester, {double yOffset = 0}) async {
    final rect = tester.getRect(find.byKey(padKey));
    final gesture =
        await tester.startGesture(rect.center + Offset(-100, yOffset));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(25, 8));
    }
    await gesture.up();
    await tester.pump();
  }

  bool enabled(WidgetTester tester, String key) {
    final finder = find.byKey(ValueKey<String>(key));
    final widget = tester.widget(finder);
    if (widget is ElevatedButton) return widget.onPressed != null;
    if (widget is OutlinedButton) return widget.onPressed != null;
    if (widget is IconButton) return widget.onPressed != null;
    throw StateError('not a button: $key');
  }

  group('drawing', () {
    testWidgets('a blank pad cannot be confirmed, cleared, undone or redone',
        (tester) async {
      await openPad(tester);
      expect(enabled(tester, 'pad-confirm'), isFalse);
      expect(enabled(tester, 'pad-clear'), isFalse);
      expect(enabled(tester, 'pad-undo'), isFalse);
      expect(enabled(tester, 'pad-redo'), isFalse);
    });

    testWidgets(
        'a stroke enables the buttons and Confirm hands back the strokes',
        (tester) async {
      await openPad(tester);
      await stroke(tester);
      expect(enabled(tester, 'pad-confirm'), isTrue);
      expect(enabled(tester, 'pad-clear'), isTrue);
      expect(enabled(tester, 'pad-undo'), isTrue);
      final padSize = tester.getSize(find.byKey(padKey));
      await tester.tap(find.byKey(const ValueKey<String>('pad-confirm')));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      final drawing = result!;
      expect(drawing.hasMeaningfulInk, isTrue);
      expect(drawing.points.first.isStrokeStart, isTrue);
      expect(drawing.colorValue, Colors.black.toARGB32());
      expect(drawing.strokeWidth, 3.5);
      expect(drawing.canvasWidth, closeTo(padSize.width, 1));
      expect(drawing.canvasHeight, closeTo(padSize.height, 1));
      // Every point is inside the pad.
      for (final point in drawing.points) {
        expect(point.x, inInclusiveRange(0, padSize.width));
        expect(point.y, inInclusiveRange(0, padSize.height));
      }
    });

    testWidgets('a tap or a dot is not accepted as a signature',
        (tester) async {
      await openPad(tester);
      await tester.tapAt(tester.getCenter(find.byKey(padKey)));
      await tester.pump();
      expect(enabled(tester, 'pad-confirm'), isTrue,
          reason: 'there is ink, so the button is live');
      await tester.tap(find.byKey(const ValueKey<String>('pad-confirm')));
      await tester.pumpAndSettle();
      expect(popped, isFalse);
      expect(find.byKey(padKey), findsOneWidget);
      expect(toasts, contains(message('sigPadTooSmall')));
      // A real stroke is accepted afterwards.
      await stroke(tester);
      await tester.tap(find.byKey(const ValueKey<String>('pad-confirm')));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(result, isNotNull);
    });

    testWidgets('closing the pad hands back nothing', (tester) async {
      await openPad(tester);
      await stroke(tester);
      await tester.tap(find.byTooltip(message('cancel')));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(result, isNull);
    });
  });

  group('undo, redo and clear', () {
    testWidgets('each undo takes a stroke back and each redo brings it again',
        (tester) async {
      await openPad(tester);
      await stroke(tester);
      final one = controller(tester).points.length;
      await stroke(tester, yOffset: 40);
      final two = controller(tester).points.length;
      expect(two, greaterThan(one));

      await tester.tap(find.byKey(const ValueKey<String>('pad-undo')));
      await tester.pump();
      expect(controller(tester).points.length, one);
      expect(enabled(tester, 'pad-redo'), isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('pad-undo')));
      await tester.pump();
      expect(controller(tester).points, isEmpty);
      expect(enabled(tester, 'pad-confirm'), isFalse);
      expect(enabled(tester, 'pad-undo'), isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('pad-redo')));
      await tester.tap(find.byKey(const ValueKey<String>('pad-redo')));
      await tester.pump();
      expect(controller(tester).points.length, two);
      expect(enabled(tester, 'pad-redo'), isFalse);
    });

    testWidgets('a new stroke after an undo ends the redo', (tester) async {
      await openPad(tester);
      await stroke(tester);
      await tester.tap(find.byKey(const ValueKey<String>('pad-undo')));
      await tester.pump();
      expect(enabled(tester, 'pad-redo'), isTrue);
      await stroke(tester, yOffset: 30);
      expect(enabled(tester, 'pad-redo'), isFalse);
    });

    testWidgets('clearing is itself one undo step', (tester) async {
      await openPad(tester);
      await stroke(tester);
      await stroke(tester, yOffset: 40);
      final before = controller(tester).points.length;
      await tester.tap(find.byKey(const ValueKey<String>('pad-clear')));
      await tester.pump();
      expect(controller(tester).points, isEmpty);
      expect(enabled(tester, 'pad-confirm'), isFalse);
      expect(enabled(tester, 'pad-clear'), isFalse);
      await tester.tap(find.byKey(const ValueKey<String>('pad-undo')));
      await tester.pump();
      expect(controller(tester).points.length, before);
      expect(enabled(tester, 'pad-confirm'), isTrue);
    });
  });

  group('the pen', () {
    testWidgets(
        'another colour keeps the strokes, and what is drawn next uses it',
        (tester) async {
      await openPad(tester);
      await stroke(tester);
      final before = controller(tester).points.length;
      await tester.tap(
          find.byKey(ValueKey<String>('pen-color-${Colors.blue.toARGB32()}')));
      await tester.pump();
      expect(controller(tester).points.length, before);
      expect(controller(tester).penColor.toARGB32(), Colors.blue.toARGB32());
      await stroke(tester, yOffset: 40);
      await tester.tap(find.byKey(const ValueKey<String>('pad-confirm')));
      await tester.pumpAndSettle();
      expect(result!.colorValue, Colors.blue.toARGB32());
    });

    testWidgets('undo still works after the pen was changed', (tester) async {
      await openPad(tester);
      await stroke(tester);
      final one = controller(tester).points.length;
      await tester.tap(
          find.byKey(ValueKey<String>('pen-color-${Colors.red.toARGB32()}')));
      await tester.pump();
      await stroke(tester, yOffset: 40);
      await tester.tap(find.byKey(const ValueKey<String>('pad-undo')));
      await tester.pump();
      expect(controller(tester).points.length, one);
    });

    testWidgets('the thickness can be chosen', (tester) async {
      await openPad(tester);
      expect(controller(tester).penStrokeWidth, 3.5);
      await tester.tap(find.byKey(const ValueKey<String>('pen-width-2')));
      await tester.pump();
      expect(controller(tester).penStrokeWidth, 5.5);
      await tester.tap(find.byKey(const ValueKey<String>('pen-width-0')));
      await tester.pump();
      expect(controller(tester).penStrokeWidth, 2.0);
      await stroke(tester);
      await tester.tap(find.byKey(const ValueKey<String>('pad-confirm')));
      await tester.pumpAndSettle();
      expect(result!.strokeWidth, 2.0);
    });

    testWidgets('the ink is drawn on the controller with round caps',
        (tester) async {
      await openPad(tester);
      expect(controller(tester).strokeCap, StrokeCap.round);
      expect(controller(tester).strokeJoin, StrokeJoin.round);
      expect(controller(tester).exportBackgroundColor, Colors.transparent);
    });
  });

  group('editing a signature', () {
    testWidgets('the strokes and the colour come back, in proportion',
        (tester) async {
      final initial = drawingOf(colorValue: 0xFFFF0000);
      await openPad(tester, initial: initial);
      await tester.pumpAndSettle();
      final points = controller(tester).points;
      expect(points.length, initial.points.length);
      expect(controller(tester).penColor.toARGB32(), 0xFFFF0000);
      final padSize = tester.getSize(find.byKey(padKey));
      for (final point in points) {
        expect(point.offset.dx, inInclusiveRange(0, padSize.width));
        expect(point.offset.dy, inInclusiveRange(0, padSize.height));
      }
      double extent(Iterable<double> values) =>
          values.reduce((a, b) => a > b ? a : b) -
          values.reduce((a, b) => a < b ? a : b);
      final width = extent(points.map((p) => p.offset.dx));
      final height = extent(points.map((p) => p.offset.dy));
      final originalBox = initial.bounds!;
      expect(
          width / height,
          closeTo(
              (originalBox.right - originalBox.left) /
                  (originalBox.bottom - originalBox.top),
              0.01));
      expect(points.first.type, PointType.tap);
      // Nothing to undo: the restore is not a stroke.
      expect(enabled(tester, 'pad-undo'), isFalse);
      expect(enabled(tester, 'pad-confirm'), isTrue);
      await tester.tap(find.byKey(const ValueKey<String>('pad-confirm')));
      await tester.pumpAndSettle();
      expect(result!.colorValue, 0xFFFF0000);
      expect(result!.points.length, initial.points.length);
    });

    testWidgets('a restored signature can be cleared and brought back',
        (tester) async {
      await openPad(tester, initial: drawingOf());
      await tester.pumpAndSettle();
      final count = controller(tester).points.length;
      await tester.tap(find.byKey(const ValueKey<String>('pad-clear')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('pad-undo')));
      await tester.pump();
      expect(controller(tester).points.length, count);
    });
  });

  group('the screen', () {
    testWidgets('initials have their own title and hint', (tester) async {
      await openPad(tester, isInitials: true);
      expect(find.text(message('sigDrawInitials')), findsOneWidget);
      expect(find.text(message('sigInitialsInstructions')), findsOneWidget);
    });

    testWidgets('signatures have the original title and hint', (tester) async {
      await openPad(tester);
      expect(find.text(message('drawSignature')), findsOneWidget);
      expect(find.text(message('signatureInstructions')), findsOneWidget);
    });

    testWidgets('in Arabic it reads right to left, in Arabic', (tester) async {
      await openPad(tester, locale: const Locale('ar'));
      expect(Directionality.of(tester.element(find.byType(SignaturePadView))),
          TextDirection.rtl);
      expect(find.text('${message('sigThickness', language: 'ar')}: '),
          findsOneWidget);
      expect(find.text(message('sigSignHere', language: 'ar')), findsOneWidget);
      await stroke(tester);
      expect(enabled(tester, 'pad-confirm'), isTrue);
    });

    testWidgets('in the dark theme it still draws', (tester) async {
      await openPad(tester, theme: ThemeData.dark());
      await stroke(tester);
      expect(enabled(tester, 'pad-confirm'), isTrue);
    });

    testWidgets('leaving while the pen was changed disposes cleanly',
        (tester) async {
      await openPad(tester);
      await stroke(tester);
      await tester.tap(
          find.byKey(ValueKey<String>('pen-color-${Colors.green.toARGB32()}')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the pad does not scroll the page behind it', (tester) async {
      await openPad(tester);
      await stroke(tester);
      expect(find.byType(Scrollable), findsNothing);
    });
  });
}
