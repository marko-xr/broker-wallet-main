// The Search field and its rotating hint.
//
// The reported defect: the hint appeared, then visibly slid toward the centre and
// snapped back. While one hint is replaced by another both are on screen at once;
// AnimatedSwitcher's default layout CENTRES them, so the shorter one sat in the
// middle of the longer one's width for the length of the fade, and moved to the
// start when the old one left. These tests pin that a hint never changes its
// horizontal position — at the first frame, at every moment of a swap, focused or
// not — in English and in Arabic (RTL), and that the field's other behaviour
// (focus, clear, typing, submit, hidden tab) is as intended.
//
// Local widget tests with Flutter's test font, which gives every glyph the same
// width: they prove the layout rules, not how a real device renders.

import 'dart:io';
import 'dart:math' as math;

import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/animated_search_hints.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_bar.dart';
import 'package:flutter/material.dart' hide SearchBar;
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Different widths on purpose: a long hint, a short one, a medium one.
const _long = 'AAAAAAAAAAAA';
const _short = 'BB';
const _medium = 'CCCCCCC';
const _static = 'Search anything';

Widget _app({
  Locale locale = const Locale('en'),
  List<String>? hints,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  bool tickers = true,
  ThemeData? theme,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: theme,
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection:
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Scaffold(
      body: TickerMode(
        enabled: tickers,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: SearchBar(
              hint: _static,
              onChanged: onChanged ?? (_) {},
              onSubmitted: onSubmitted,
              animatedHints: hints ?? <String>[_long, _short, _medium],
            ),
          ),
        ),
      ),
    ),
  );
}

void _size(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The edge of [text] that a hint is anchored to: its left edge in English, its
/// right edge in Arabic.
double _anchor(WidgetTester tester, String text, {required bool rtl}) {
  final finder = find.text(text);
  return rtl ? tester.getTopRight(finder).dx : tester.getTopLeft(finder).dx;
}

/// Where the GLYPHS of [text] are on screen, as global x of the leftmost and
/// rightmost glyph — not the box the text sits in.
///
/// The distinction matters. The field hands its own hint a tight box as wide as
/// the whole input slot (the SDK lays a hint out with `tighten(width: inputWidth)`),
/// so the static hint's box is wider than its words: 272 against 247.5 for
/// "Search anything" at 360 px. What a person sees, and what must not move, is
/// where the words begin and end.
({double left, double right}) _glyphs(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty, reason: 'the text "$text" has glyphs on screen');
  final origin = paragraph.localToGlobal(Offset.zero).dx;
  var left = double.infinity;
  var right = double.negativeInfinity;
  for (final box in boxes) {
    left = math.min(left, box.left);
    right = math.max(right, box.right);
  }
  return (left: origin + left, right: origin + right);
}

/// The edge of the glyphs of [text] that a hint starts from: the left in
/// English, the right in Arabic.
double _glyphStart(WidgetTester tester, String text, {required bool rtl}) {
  final glyphs = _glyphs(tester, text);
  return rtl ? glyphs.right : glyphs.left;
}

/// The top of the box the text is in.
double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

/// A bare app around [child], in [locale], for building a counter-example.
Widget _host(Locale locale, Widget child) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, inner) => Directionality(
      textDirection:
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: inner!,
    ),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

/// Shows the next hint: waits out the pause, which swaps it in.
Future<void> _swap(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 2500));

void main() {
  for (final entry in {
    'English': (const Locale('en'), false),
    'Arabic (RTL)': (const Locale('ar'), true),
  }.entries) {
    final locale = entry.value.$1;
    final rtl = entry.value.$2;

    group('the hint holds its position: ${entry.key}', () {
      testWidgets('the first frame is already the final position',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        final first = _anchor(tester, _long, rtl: rtl);

        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 500));
        expect(_anchor(tester, _long, rtl: rtl), first,
            reason: 'nothing moved after the first frame');
        expect(tester.takeException(), isNull);
      });

      testWidgets('a swap to a shorter hint moves nothing sideways',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        final start = _anchor(tester, _long, rtl: rtl);

        await _swap(tester); // _short comes in, _long goes out
        var elapsed = 0;
        // Every moment of the 350 ms fade: +0, +40, +100, +160, +220, +280.
        for (final step in [0, 40, 60, 60, 60, 60]) {
          if (step > 0) await tester.pump(Duration(milliseconds: step));
          elapsed += step;
          expect(find.text(_short), findsOneWidget,
              reason: 'incoming at +$elapsed');
          if (find.text(_long).evaluate().isNotEmpty) {
            expect(_anchor(tester, _long, rtl: rtl), start,
                reason: 'the leaving hint stays put at +$elapsed');
          }
          expect(_anchor(tester, _short, rtl: rtl), start,
              reason: 'the arriving, shorter hint is at the start, not '
                  'centred in the longer one, at +$elapsed');
        }

        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(_long), findsNothing);
        expect(_anchor(tester, _short, rtl: rtl), start,
            reason: 'and it does not snap anywhere when the old hint is gone');
      });

      testWidgets('a swap to a longer hint moves nothing sideways',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(
          locale: locale,
          hints: <String>[_short, _long, _medium],
        ));
        final start = _anchor(tester, _short, rtl: rtl);

        await _swap(tester); // _long comes in, _short goes out
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 55));
          if (find.text(_short).evaluate().isNotEmpty) {
            expect(_anchor(tester, _short, rtl: rtl), start,
                reason: 'the shorter, leaving hint was centred before');
          }
          expect(_anchor(tester, _long, rtl: rtl), start);
        }
        await tester.pumpAndSettle();
        expect(_anchor(tester, _long, rtl: rtl), start);
      });

      testWidgets('every hint of a full rotation starts in the same place',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        final start = _anchor(tester, _long, rtl: rtl);

        for (final hint in [_short, _medium, _long, _short]) {
          await _swap(tester);
          await tester.pump(const Duration(milliseconds: 30));
          expect(_anchor(tester, hint, rtl: rtl), start, reason: hint);
          await tester.pump(const Duration(milliseconds: 400));
        }
      });

      testWidgets('the rotating hint starts where the static hint does',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        final rotating = _anchor(tester, _long, rtl: rtl);

        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AnimatedSearchHints), findsNothing);
        expect(_anchor(tester, _static, rtl: rtl), closeTo(rotating, 0.01),
            reason: 'focusing hands over to the static hint without a shift');
      });

      testWidgets(
          'the hint text is the same text in the same place as the static hint',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale, hints: [_static]));
        // One hint only: it does not rotate. Same words, so what is compared
        // after focusing is the field's own hint against ours.
        final rotating = _glyphs(tester, _static);
        final rotatingTop = _top(tester, _static);
        final rotatingHeight = tester.getSize(find.text(_static)).height;

        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AnimatedSearchHints), findsNothing);

        final handedOver = _glyphs(tester, _static);

        // Where the words begin: the start edge — left in English, right in
        // Arabic — does not move when focus hands over to the static hint.
        expect(
          rtl ? handedOver.right : handedOver.left,
          closeTo(rtl ? rotating.right : rotating.left, 0.5),
          reason: 'the start of the words is the same before and after focus',
        );
        // How far they run: the same words in the same style take the same room.
        expect(
          handedOver.right - handedOver.left,
          closeTo(rotating.right - rotating.left, 0.5),
        );
        // Not at the other end of the field.
        expect(
          rtl ? handedOver.left : handedOver.right,
          closeTo(rtl ? rotating.left : rotating.right, 0.5),
        );
        // Vertically: the same line box, in the same place.
        expect(tester.getSize(find.text(_static)).height,
            closeTo(rotatingHeight, 0.01));
        expect(_top(tester, _static), closeTo(rotatingTop, 1.0));
      });

      testWidgets(
          'the field gives the hint its whole width and the words still start '
          'at the start edge', (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));

        final box = find.byType(AnimatedSearchHints);
        final boxLeft = tester.getTopLeft(box).dx;
        final boxRight = tester.getTopRight(box).dx;
        final words = _glyphs(tester, _long);

        // The box is the input slot, far wider than the words in it...
        expect(boxRight - boxLeft, greaterThan(words.right - words.left + 40),
            reason: 'the SDK hands a hint a tight, full-width box');
        // ...which is exactly why a centred layout would show: the words must
        // hug the START edge of that wide box, not sit in the middle of it.
        if (rtl) {
          expect(words.right, closeTo(boxRight, 0.5));
          expect(words.left, greaterThan(boxLeft + 40));
        } else {
          expect(words.left, closeTo(boxLeft, 0.5));
          expect(words.right, lessThan(boxRight - 40));
        }
      });

      testWidgets('the words keep their edge and their line through a swap',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        final startEdge = _glyphStart(tester, _long, rtl: rtl);
        final startTop = _top(tester, _long);

        await _swap(tester); // _short comes in, _long goes out
        for (final step in [0, 50, 100, 100]) {
          if (step > 0) await tester.pump(Duration(milliseconds: step));
          expect(_glyphStart(tester, _short, rtl: rtl), closeTo(startEdge, 0.5),
              reason: 'the arriving words begin at the start edge mid-swap');
          expect(_glyphStart(tester, _long, rtl: rtl), closeTo(startEdge, 0.5),
              reason: 'and so do the leaving words');
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(_glyphStart(tester, _short, rtl: rtl), closeTo(startEdge, 0.5));
        expect(_top(tester, _short), closeTo(startTop, 0.01),
            reason: 'at rest the new hint is on the same line, same height');
      });

      testWidgets(
          'the same measurements would catch a centred switcher (counter-'
          'example)', (tester) async {
        _size(tester);
        // The bug, rebuilt: the same field, the same hint slot, and an
        // AnimatedSwitcher left on its DEFAULT layout.
        final hint = ValueNotifier<String>(_long);
        addTearDown(hint.dispose);
        await tester.pumpWidget(
          _host(
            locale,
            TextField(
              decoration: InputDecoration(
                prefixIcon: const SizedBox(width: 48, height: 48),
                hint: ValueListenableBuilder<String>(
                  valueListenable: hint,
                  builder: (context, text, _) => AnimatedSwitcher(
                    duration: AnimatedSearchHints.transitionDuration,
                    child: Text(text, key: ValueKey<String>(text)),
                  ),
                ),
              ),
            ),
          ),
        );
        final before = _glyphStart(tester, _long, rtl: rtl);

        hint.value = _short;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(_long), findsOneWidget);
        expect(find.text(_short), findsOneWidget);

        final leaving = _glyphStart(tester, _long, rtl: rtl);
        final arriving = _glyphStart(tester, _short, rtl: rtl);
        expect((arriving - leaving).abs(), greaterThan(20),
            reason: 'centred, the two hints do not share a start edge: this is '
                'the movement the real widget must not have');
        expect((arriving - before).abs(), greaterThan(20),
            reason:
                'and the arriving hint is nowhere near where the first was');
      });
    });
  }

  group('how the hint is built', () {
    testWidgets('it does not use the centred default layout', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      final switcher = tester.widget<AnimatedSwitcher>(
        find.descendant(
          of: find.byType(AnimatedSearchHints),
          matching: find.byType(AnimatedSwitcher),
        ),
      );
      expect(
          switcher.layoutBuilder, same(AnimatedSearchHints.startAlignedLayout));
      expect(switcher.layoutBuilder,
          isNot(same(AnimatedSwitcher.defaultLayoutBuilder)));
    });

    testWidgets('the layout anchors every child to the start', (tester) async {
      final stack = AnimatedSearchHints.startAlignedLayout(
        const SizedBox(key: ValueKey('now')),
        const <Widget>[SizedBox(key: ValueKey('before'))],
      ) as Stack;
      expect(stack.alignment, AlignmentDirectional.centerStart);
      expect(stack.children.map((c) => (c.key! as ValueKey<String>).value),
          ['before', 'now']);
    });

    testWidgets('the hint is the field\'s own, not an overlay', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hint, isNotNull);
      expect(field.decoration!.hintText, isNull,
          reason: 'a decoration takes a hint widget or hint text, never both');
      // No second layer drawn over the field to be positioned by hand.
      expect(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(PositionedDirectional),
        ),
        findsNothing,
      );
    });

    testWidgets('screen readers get the stable hint', (tester) async {
      _size(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app());
      expect(find.bySemanticsLabel(RegExp(_static)), findsWidgets);
      await _swap(tester);
      await tester.pump(const Duration(milliseconds: 400));
      // The label stays the stable hint; the suggestion on screen is not read.
      expect(find.bySemanticsLabel(RegExp(_static)), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(_short)), findsNothing);
      expect(find.bySemanticsLabel(RegExp(_long)), findsNothing);
      handle.dispose();
    });
  });

  group('rebuilds and the hidden tab', () {
    testWidgets('a rebuild that changes nothing does not reset the rotation',
        (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      await _swap(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_short), findsOneWidget);

      // The parent builds a NEW list with the same words, as it does on every
      // rebuild.
      await tester.pumpWidget(_app(hints: <String>[_long, _short, _medium]));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(_short), findsOneWidget,
          reason: 'still showing the second hint');
      expect(find.text(_long), findsNothing);
    });

    testWidgets('rebuilds do not restart the timer', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpWidget(_app(hints: <String>[_long, _short, _medium]));
      await tester.pump(const Duration(milliseconds: 600)); // 2600 in all
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_short), findsOneWidget,
          reason: 'the swap came on its original schedule');
    });

    testWidgets('different words do start over, within range', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      await _swap(tester);
      await _swap(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_medium), findsOneWidget);

      await tester.pumpWidget(_app(hints: <String>['One', 'Two']));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('One'), findsOneWidget,
          reason: 'index 2 does not exist in the new list');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hidden tab does not keep rotating', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(tickers: false));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 2500));
      }
      expect(find.text(_long), findsOneWidget);
      expect(find.text(_short), findsNothing);
      expect(find.text(_medium), findsNothing);
    });

    testWidgets('and it resumes, one step at a time, when shown again',
        (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(tickers: false));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 2500));
      }
      await tester.pumpWidget(_app(tickers: true));
      // No pile-up of half-finished swaps: still the first hint, alone.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_long), findsOneWidget);
      expect(find.text(_short), findsNothing);

      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_short), findsOneWidget);
      expect(find.text(_long), findsNothing);
    });

    testWidgets('one hint, or none, never rotates', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(hints: [_long]));
      await tester.pump(const Duration(milliseconds: 6000));
      expect(find.text(_long), findsOneWidget);

      await tester.pumpWidget(_app(hints: const <String>[]));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AnimatedSearchHints), findsNothing);
      expect(find.text(_static), findsOneWidget,
          reason: 'with no rotating hints the static hint is shown');
    });
  });

  group('focus, typing, clear and submit', () {
    testWidgets('focusing shows the static hint; leaving brings rotation back',
        (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      expect(find.byType(AnimatedSearchHints), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.byType(AnimatedSearchHints), findsNothing);
      expect(find.text(_static), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.byType(AnimatedSearchHints), findsOneWidget);
      expect(find.text(_long), findsOneWidget,
          reason: 'starts again at the first');
    });

    testWidgets('typing reports each change once', (tester) async {
      _size(tester);
      final seen = <String>[];
      await tester.pumpWidget(_app(onChanged: seen.add));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(seen, ['abc']);
      expect(find.byType(AnimatedSearchHints), findsNothing);
    });

    testWidgets('moving the cursor is not a new query', (tester) async {
      _size(tester);
      final seen = <String>[];
      await tester.pumpWidget(_app(onChanged: seen.add));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(seen, ['abc']);

      final state = tester.state<EditableTextState>(find.byType(EditableText));
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(
          selection: const TextSelection.collapsed(offset: 1),
        ),
        SelectionChangedCause.tap,
      );
      await tester.pump();
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(
          selection: const TextSelection.collapsed(offset: 2),
        ),
        SelectionChangedCause.keyboard,
      );
      await tester.pump();

      expect(seen, ['abc'], reason: 'the text did not change');
    });

    testWidgets('the clear button empties the field once and keeps focus',
        (tester) async {
      _size(tester);
      final seen = <String>[];
      await tester.pumpWidget(_app(onChanged: seen.add));
      expect(find.byType(IconButton), findsNothing, reason: 'nothing to clear');

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.byType(IconButton), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(seen, ['abc', ''], reason: 'one report, not two');
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          '');
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('the clear button is easy to hit', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(40));
      expect(size.height, greaterThanOrEqualTo(40));
    });

    testWidgets('the keyboard Search action reports the text', (tester) async {
      _size(tester);
      final submitted = <String>[];
      await tester.pumpWidget(_app(onSubmitted: submitted.add));
      await tester.enterText(find.byType(TextField), 'dubai');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(submitted, ['dubai']);
    });

    testWidgets('without an onSubmitted, Search reports through onChanged',
        (tester) async {
      _size(tester);
      final seen = <String>[];
      await tester.pumpWidget(_app(onChanged: seen.add));
      await tester.enterText(find.byType(TextField), 'dubai');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(seen, ['dubai', 'dubai']);
    });

    testWidgets('the field asks the keyboard for a Search key', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      expect(tester.widget<TextField>(find.byType(TextField)).textInputAction,
          TextInputAction.search);
    });
  });

  group('typing direction in an Arabic UI', () {
    testWidgets('ASCII text reads left to right, and nothing else moves',
        (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(locale: const Locale('ar')));
      final icon = find.byIcon(Icons.search_rounded);
      final iconBefore = tester.getCenter(icon);
      expect(tester.widget<TextField>(find.byType(TextField)).textDirection,
          isNull);

      await tester.enterText(find.byType(TextField), 'abc 0501');
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.ltr);
      expect(tester.getCenter(icon), iconBefore,
          reason: 'the search icon stays on its side while typing');
    });

    testWidgets('Arabic text follows the UI direction', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(locale: const Locale('ar')));
      await tester.enterText(find.byType(TextField), 'أحمد');
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).textDirection,
          isNull);
    });

    testWidgets('mixed text follows the UI direction', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(locale: const Locale('ar')));
      await tester.enterText(find.byType(TextField), 'abc أحمد');
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).textDirection,
          isNull);
    });

    testWidgets('the icon sits at the start edge in both languages',
        (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      final left = tester.getCenter(find.byIcon(Icons.search_rounded)).dx;
      await tester.pumpWidget(_app(locale: const Locale('ar')));
      final right = tester.getCenter(find.byIcon(Icons.search_rounded)).dx;
      expect(left, lessThan(180));
      expect(right, greaterThan(180));
    });
  });

  group('responsive and themed', () {
    for (final width in [320.0, 412.0, 800.0]) {
      testWidgets(
          'lays out without overflow at ${width.toInt()} px, both '
          'languages', (tester) async {
        _size(tester, width: width);
        for (final locale in const [Locale('en'), Locale('ar')]) {
          await tester.pumpWidget(_app(locale: locale));
          await _swap(tester);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('a long hint is cut, not wrapped or overflowing',
        (tester) async {
      _size(tester, width: 320);
      await tester.pumpWidget(_app(hints: ['Z' * 80, _short]));
      expect(tester.takeException(), isNull);
      final box = tester.getSize(find.text('Z' * 80));
      expect(box.height, lessThan(40), reason: 'one line');
    });

    testWidgets('large text does not break the field', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(textScale: 1.8));
      await _swap(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('light and dark both render', (tester) async {
      _size(tester);
      for (final theme in [ThemeData.light(), ThemeData.dark()]) {
        await tester.pumpWidget(_app(theme: theme));
        await _swap(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('the field\'s height and its focus border', () {
    // The field is one 24 dp text line (16 sp on the theme's 1.5) with 12 above
    // and below: 48, Flutter's own minimum interactive size. It was 56.
    const lineHeight = 24.0;

    double heightOf(WidgetTester tester) =>
        tester.getSize(find.byType(SearchBar)).height;

    double widthOf(WidgetTester tester) =>
        tester.getSize(find.byType(SearchBar)).width;

    OutlineInputBorder focusedBorder(WidgetTester tester) => tester
        .widget<TextField>(find.byType(TextField))
        .decoration!
        .focusedBorder! as OutlineInputBorder;

    OutlineInputBorder enabledBorder(WidgetTester tester) => tester
        .widget<TextField>(find.byType(TextField))
        .decoration!
        .enabledBorder! as OutlineInputBorder;

    ColorScheme colors(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(TextField))).colorScheme;

    test('the sizes: the minimum interactive height, and a thin line', () {
      expect(AppControlSizes.searchFieldHeight, 48);
      expect(AppControlSizes.searchFieldHeight, kMinInteractiveDimension,
          reason: 'a text field is never laid out shorter than this');
      expect(
        2 * AppControlSizes.searchFieldVerticalPadding + lineHeight,
        AppControlSizes.searchFieldHeight,
        reason: 'the padding around the one text line makes the height',
      );
      expect(AppControlSizes.searchFieldVerticalPadding, lessThan(16),
          reason: 'it was 16, which made the field 56');

      expect(
          AppControlSizes.focusedFieldBorderWidth, inInclusiveRange(1.2, 1.5));
      expect(AppControlSizes.focusedFieldBorderWidth, lessThan(2),
          reason: 'it was 2');
      expect(AppControlSizes.focusedFieldBorderWidth,
          AppControlSizes.chipBorderWidth,
          reason: 'the same thin line the chips draw');
    });

    for (final entry in {
      'English': const Locale('en'),
      'Arabic (RTL)': const Locale('ar'),
    }.entries) {
      final locale = entry.value;

      testWidgets('${entry.key}: 48 high at normal text', (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        expect(
            heightOf(tester), closeTo(AppControlSizes.searchFieldHeight, 0.01));
        expect(tester.getSize(find.byType(TextField)).height,
            closeTo(AppControlSizes.searchFieldHeight, 0.01));
        expect(tester.takeException(), isNull);
      });

      testWidgets('${entry.key}: the same box focused, typed in and cleared',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        final height = heightOf(tester);
        final width = widthOf(tester);
        final topLeft = tester.getTopLeft(find.byType(SearchBar));

        void sameBox(String when) {
          expect(heightOf(tester), closeTo(height, 0.01),
              reason: 'height $when');
          expect(widthOf(tester), closeTo(width, 0.01), reason: 'width $when');
          expect(tester.getTopLeft(find.byType(SearchBar)), topLeft,
              reason: 'position $when');
        }

        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        sameBox('when focused (the primary border is on)');

        await tester.enterText(find.byType(TextField), 'abc');
        await tester.pump();
        sameBox('with text and the clear button');
        expect(find.byType(IconButton), findsOneWidget);

        await tester.tap(find.byType(IconButton));
        await tester.pump();
        sameBox('after clearing');

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        sameBox('when focus leaves');
        expect(height, closeTo(AppControlSizes.searchFieldHeight, 0.01));
      });

      testWidgets('${entry.key}: the icons and text fit the 48',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(locale: locale));
        await tester.enterText(find.byType(TextField), 'abc');
        await tester.pump();

        final field = tester.getRect(find.byType(TextField));
        final icon = tester.getRect(find.byIcon(Icons.search_rounded));
        final clear = tester.getRect(find.byType(IconButton));
        expect(icon.top, greaterThanOrEqualTo(field.top));
        expect(icon.bottom, lessThanOrEqualTo(field.bottom));
        expect(clear.height, lessThanOrEqualTo(field.height + 0.01),
            reason: 'the clear button is 48 and the field 48');
        expect(clear.height, greaterThanOrEqualTo(40));

        // The typed line sits in the middle of the field: equal room above and below.
        final text = tester.getRect(find.byType(EditableText));
        expect(text.center.dy, closeTo(field.center.dy, 1.0));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a larger system font makes the field taller, not clipped',
        (tester) async {
      _size(tester);
      for (final scale in [1.0, 1.3, 2.0]) {
        await tester.pumpWidget(_app(textScale: scale));
        await tester.enterText(find.byType(TextField), 'abc');
        await tester.pump();
        final expected = (lineHeight * scale +
                2 * AppControlSizes.searchFieldVerticalPadding)
            .clamp(AppControlSizes.searchFieldHeight, double.infinity);
        expect(heightOf(tester), closeTo(expected, 2.0),
            reason: 'scale $scale');
        expect(heightOf(tester),
            greaterThanOrEqualTo(AppControlSizes.searchFieldHeight));
        expect(tester.takeException(), isNull);
      }
    });

    for (final entry in {
      'light': ThemeData.light(),
      'dark': ThemeData.dark(),
    }.entries) {
      testWidgets('${entry.key}: the focus border is thin and primary',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(theme: entry.value));
        final focused = focusedBorder(tester);

        expect(
            focused.borderSide.width, AppControlSizes.focusedFieldBorderWidth);
        expect(focused.borderSide.width, inInclusiveRange(1.2, 1.5));
        expect(focused.borderSide.width, lessThan(2),
            reason: 'thinner than the 2 it was');
        expect(focused.borderSide.color, colors(tester).primary,
            reason: 'the theme\'s own primary colour, not a new one');
        expect(focused.borderRadius, BorderRadius.circular(24));
      });

      testWidgets('${entry.key}: the idle border is the subtle one it was',
          (tester) async {
        _size(tester);
        await tester.pumpWidget(_app(theme: entry.value));
        final idle = enabledBorder(tester);
        expect(idle.borderSide.width, 1);
        expect(idle.borderSide.color,
            colors(tester).outline.withValues(alpha: 0.12));
        expect(idle.borderRadius, BorderRadius.circular(24));
        expect(idle.borderSide.color, isNot(colors(tester).primary));
      });
    }

    testWidgets('focused and idle borders share one shape', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      final idle = enabledBorder(tester);
      final focused = focusedBorder(tester);
      expect(focused.borderRadius, idle.borderRadius,
          reason: 'only the colour and the line change when focus arrives');
      expect(focused.borderSide.width - idle.borderSide.width, lessThan(0.5),
          reason: 'no heavy step between idle and focused');
    });

    testWidgets('the primary border comes on with focus', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app());
      // The icon takes the primary colour with focus, as the border does.
      Icon icon() => tester.widget<Icon>(find.byIcon(Icons.search_rounded));
      final idleColor = icon().color;
      expect(idleColor, isNot(colors(tester).primary));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(icon().color, colors(tester).primary);
    });

    test('the bar takes its height and border from the shared sizes', () {
      final source = File(
        'lib/src/views/Screens/home/search/widgets/search_bar.dart',
      ).readAsStringSync();
      expect(source.contains('AppControlSizes.searchFieldVerticalPadding'),
          isTrue);
      expect(
          source.contains('AppControlSizes.focusedFieldBorderWidth'), isTrue);
      expect(source.contains('vertical: 16'), isFalse,
          reason: 'the 56 high padding is gone');
      expect(RegExp(r'width:\s*2\b').hasMatch(source), isFalse,
          reason: 'the 2 wide focus border is gone');
      // Nothing about the hint, the icon or the text styles was touched here.
      expect(source.contains('size: 22'), isTrue);
      expect(source.contains('fontSize: 16'), isTrue);
      expect(source.contains('BorderRadius.circular(24)'), isTrue);
    });
  });
}
