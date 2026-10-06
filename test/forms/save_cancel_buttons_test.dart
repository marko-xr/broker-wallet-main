// The floating Save / Cancel actions of the add/edit form screens: nothing sits
// behind the buttons (no full-width panel, no shadow dock), the bottom system
// inset is cleared, the buttons are opaque so scrolled content never shows
// through them, and the room a form reserves at the end of its scroll keeps the
// last field above them at every text scale and inset. Behaviour that was not
// meant to change — callbacks, the loading and "nothing to save yet" states,
// "Update" in edit mode, RTL order — is pinned too, and every form screen is
// checked to use the shared component with no panel of its own.
//
// The buttons' size is the app's one form-action height
// ([AppControlSizes.formActionHeight], 48): Save and Cancel are exactly that
// tall and level in every state, language and theme, and the room a form keeps
// for them is built from the same value.
//
// Local widget and source tests; they prove the layout rules and the wiring, not
// how the screens look on a device.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/views/Widgets/save_cancel_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

late final Map<String, dynamic> en;
late final Map<String, dynamic> ar;

/// Every form screen that uses the shared Save / Cancel actions.
const _formScreens = <String>[
  'lib/src/views/Screens/ViewAdd/add_requested_view.dart',
  'lib/src/views/Screens/ViewAdd/add_offers_view.dart',
  'lib/src/views/Screens/ViewAdd/add_owners_view.dart',
  'lib/src/views/Screens/ViewAdd/add_brokers_view.dart',
  'lib/src/views/Screens/ViewAdd/add_offices_view.dart',
  'lib/src/views/Screens/ViewAdd/add_watchmen_view.dart',
  'lib/src/views/Screens/home/quotation/add_quotation_view.dart',
];

String _read(String path) => File(path).readAsStringSync();

Future<void> _pump(
  WidgetTester tester, {
  required WidgetBuilder body,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  double width = 360,
  double height = 800,
  double textScale = 1,
  double bottomInset = 0,
  double leftInset = 0,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
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
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: EdgeInsets.only(left: leftInset, bottom: bottomInset),
          viewPadding: EdgeInsets.only(left: leftInset, bottom: bottomInset),
        ),
        child: Directionality(
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: inner ?? const SizedBox.shrink(),
        ),
      ),
      home: Scaffold(body: Builder(builder: body)),
    ),
  );
  await tester.pumpAndSettle();
}

/// The actions placed as the form screens place them: at the bottom of a Stack.
Widget _floating({
  bool isLoading = false,
  bool isEnabled = true,
  bool isEditMode = false,
  VoidCallback? onSave,
  VoidCallback? onCancel,
  String? saveButtonText,
  String? cancelButtonText,
}) =>
    Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SaveCancelButtons(
        isLoading: isLoading,
        isEnabled: isEnabled,
        isEditMode: isEditMode,
        onSave: onSave ?? () {},
        onCancel: onCancel ?? () {},
        saveButtonText: saveButtonText,
        cancelButtonText: cancelButtonText,
      ),
    );

Widget _screen(Widget actions) =>
    Stack(fit: StackFit.expand, children: [actions]);

Color _background(ButtonStyleButton button) =>
    button.style!.backgroundColor!.resolve(<WidgetState>{})!;

void main() {
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
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('the actions render as before', () {
    testWidgets('Save and Cancel, in English', (tester) async {
      await _pump(tester, body: (_) => _screen(_floating()));

      expect(find.text(en['save'] as String), findsOneWidget);
      expect(find.text(en['cancel'] as String), findsOneWidget);
      expect(find.text(en['update'] as String), findsNothing);
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('edit mode says Update instead of Save', (tester) async {
      await _pump(tester, body: (_) => _screen(_floating(isEditMode: true)));

      expect(find.text(en['update'] as String), findsOneWidget);
      expect(find.text(en['save'] as String), findsNothing);
      expect(find.text(en['cancel'] as String), findsOneWidget);
    });

    testWidgets('custom button texts are still honoured', (tester) async {
      await _pump(
        tester,
        body: (_) => _screen(
          _floating(saveButtonText: 'Send', cancelButtonText: 'Back'),
        ),
      );

      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets(
        'the buttons are the canonical height; spacing and margins are '
        'unchanged', (tester) async {
      await _pump(tester, body: (_) => _screen(_floating()));

      final save = find.byType(ElevatedButton);
      final cancel = find.byType(OutlinedButton);
      // Was 56 (18 above and below the label); now the shared form-action height.
      expect(tester.getSize(save).height, AppControlSizes.formActionHeight);
      expect(tester.getSize(save).height, 48);
      expect(tester.getSize(cancel).height, tester.getSize(save).height);
      expect(tester.getTopLeft(save).dx, 16, reason: 'left margin');
      expect(tester.getTopRight(cancel).dx, 360 - 16, reason: 'right margin');
      expect(
        tester.getTopLeft(cancel).dx - tester.getTopRight(save).dx,
        SaveCancelButtons.buttonGap,
        reason: 'the gap between the buttons',
      );
      expect(SaveCancelButtons.buttonGap, 18);
      expect(tester.getBottomLeft(save).dy, 800 - 16,
          reason: 'a 16 px bottom margin');
    });

    testWidgets('Arabic and RTL: both actions render, Save on the right',
        (tester) async {
      await _pump(
        tester,
        locale: const Locale('ar'),
        body: (_) => _screen(_floating()),
      );

      expect(find.text(ar['save'] as String), findsOneWidget);
      expect(find.text(ar['cancel'] as String), findsOneWidget);
      expect(
        tester.getCenter(find.byType(ElevatedButton)).dx,
        greaterThan(tester.getCenter(find.byType(OutlinedButton)).dx),
        reason: 'the order still follows the reading direction',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('English: Save on the left', (tester) async {
      await _pump(tester, body: (_) => _screen(_floating()));
      expect(
        tester.getCenter(find.byType(ElevatedButton)).dx,
        lessThan(tester.getCenter(find.byType(OutlinedButton)).dx),
      );
    });

    testWidgets('Arabic edit mode says Update', (tester) async {
      await _pump(
        tester,
        locale: const Locale('ar'),
        body: (_) => _screen(_floating(isEditMode: true)),
      );
      expect(find.text(ar['update'] as String), findsOneWidget);
    });
  });

  group('nothing sits behind the buttons', () {
    testWidgets('no widget under the actions paints a full-width background',
        (tester) async {
      await _pump(tester, body: (_) => _screen(_floating()));

      final painters = find.descendant(
        of: find.byType(SaveCancelButtons),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox ||
              widget is ColoredBox ||
              widget is PhysicalModel ||
              widget is PhysicalShape ||
              widget is Material ||
              widget is Container ||
              widget is Card,
        ),
      );
      expect(painters.evaluate(), isNotEmpty,
          reason: 'the buttons themselves paint');
      for (final element in painters.evaluate()) {
        final size = (element.renderObject! as RenderBox).size;
        expect(size.width, lessThan(360 * 0.6),
            reason: '${element.widget.runtimeType} is ${size.width} wide: '
                'a panel behind the buttons would span the screen');
      }
    });

    testWidgets('the margins and the gap let touches through to the page',
        (tester) async {
      var page = 0;
      var saved = 0;
      await _pump(
        tester,
        body: (_) => Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => page++,
            ),
            _floating(onSave: () => saved++),
          ],
        ),
      );
      final save = find.byType(ElevatedButton);
      final top = tester.getTopLeft(save).dy;

      await tester.tapAt(Offset(180, top - 8)); // the actions' top margin
      await tester.tapAt(Offset(180, top + 28)); // the gap between the buttons
      expect(page, 2, reason: 'the page behind receives both');
      expect(saved, 0);

      await tester.tap(save);
      expect(saved, 1, reason: 'a button still takes its own touches');
      expect(page, 2);
    });
  });

  group('Save and Cancel are one canonical height', () {
    void expectCanonical(WidgetTester tester, String reason) {
      final save = tester.getRect(find.byType(ElevatedButton));
      final cancel = tester.getRect(find.byType(OutlinedButton));
      expect(save.height, AppControlSizes.formActionHeight,
          reason: 'Save: $reason');
      expect(cancel.height, AppControlSizes.formActionHeight,
          reason: 'Cancel: $reason');
      expect(cancel.top, save.top, reason: 'level: $reason');
      expect(cancel.bottom, save.bottom, reason: 'level: $reason');
      expect(save.height, greaterThanOrEqualTo(AppControlSizes.minTouchTarget),
          reason: 'a comfortable touch target: $reason');
    }

    for (final locale in const [Locale('en'), Locale('ar')]) {
      for (final entry in {
        'light': AppTheme.lightTheme,
        'dark': AppTheme.darkTheme,
      }.entries) {
        final tag = '${locale.languageCode}, ${entry.key}';

        testWidgets('Save, Update and the "nothing to save yet" look: $tag',
            (tester) async {
          for (final actions in [
            _floating(),
            _floating(isEditMode: true),
            _floating(isEnabled: false),
            _floating(isEditMode: true, isEnabled: false),
          ]) {
            await _pump(
              tester,
              locale: locale,
              theme: entry.value,
              body: (_) => _screen(actions),
            );
            expectCanonical(tester, tag);
            expect(tester.takeException(), isNull);
          }
        });

        testWidgets('saving does not change either height: $tag',
            (tester) async {
          final loading = ValueNotifier<bool>(false);
          addTearDown(loading.dispose);
          await _pump(
            tester,
            locale: locale,
            theme: entry.value,
            body: (_) => _screen(ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (_, isLoading, __) => _floating(isLoading: isLoading),
            )),
          );
          expectCanonical(tester, '$tag, idle');
          final idle = tester.getSize(find.byType(SaveCancelButtons)).height;

          loading.value = true;
          await tester.pump();

          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expectCanonical(tester, '$tag, saving');
          expect(tester.getSize(find.byType(SaveCancelButtons)).height, idle,
              reason: 'the whole strip keeps its height while saving');
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('${locale.languageCode}: no label is clipped or overflows',
          (tester) async {
        final table = locale.languageCode == 'ar' ? ar : en;
        for (final edit in [false, true]) {
          await _pump(
            tester,
            locale: locale,
            body: (_) => _screen(_floating(isEditMode: edit)),
          );

          final saveLabel = tester.getRect(
            find.text(table[edit ? 'update' : 'save'] as String),
          );
          final cancelLabel = tester.getRect(
            find.text(table['cancel'] as String),
          );
          final save = tester.getRect(find.byType(ElevatedButton));
          final cancel = tester.getRect(find.byType(OutlinedButton));

          for (final pair in [(saveLabel, save), (cancelLabel, cancel)]) {
            final label = pair.$1;
            final button = pair.$2;
            expect(label.left, greaterThanOrEqualTo(button.left - 0.01));
            expect(label.right, lessThanOrEqualTo(button.right + 0.01));
            expect(label.top, greaterThanOrEqualTo(button.top - 0.01));
            expect(label.bottom, lessThanOrEqualTo(button.bottom + 0.01));
          }
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('the whole strip is the margins around one button height',
        (tester) async {
      late double strip;
      await _pump(tester, body: (context) {
        strip = SaveCancelButtons.heightOf(context);
        return _screen(_floating());
      });

      expect(strip, 2 * SaveCancelButtons.margin + 48);
      expect(tester.getSize(find.byType(SaveCancelButtons)).height, strip,
          reason: 'the height the form reserves is the height it renders');
    });

    // Up to 1.5 the label line plus its padding still fits the canonical height.
    // Beyond that the buttons grow just enough that the label is never clipped,
    // and Save and Cancel stay level.
    for (final scale in const [0.85, 1.0, 1.3, 1.5, 2.0]) {
      testWidgets('text scale $scale: level, never below 48, label inside',
          (tester) async {
        late double expected;
        await _pump(
          tester,
          textScale: scale,
          body: (context) {
            expected = SaveCancelButtons.buttonHeightOf(context);
            return _screen(_floating());
          },
        );

        final save = tester.getRect(find.byType(ElevatedButton));
        final cancel = tester.getRect(find.byType(OutlinedButton));
        expect(save.height, greaterThanOrEqualTo(48));
        expect(save.height, closeTo(expected, 0.01));
        expect(cancel.height, save.height);
        expect(cancel.top, save.top);
        if (scale <= 1.5) {
          expect(save.height, 48, reason: 'the canonical height holds');
        } else {
          expect(save.height, greaterThan(48),
              reason: 'it grows with the text');
        }
        final label = tester.getRect(find.text(en['save'] as String));
        expect(label.height, lessThanOrEqualTo(save.height));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the clearance is built from the shared action height',
        (tester) async {
      late double clearance;
      late double strip;
      await _pump(
        tester,
        bottomInset: 20,
        body: (context) {
          clearance = SaveCancelButtons.clearanceOf(context);
          strip = SaveCancelButtons.heightOf(context);
          return _screen(_floating());
        },
      );

      expect(
        clearance,
        20 + 2 * SaveCancelButtons.margin + 48 + SaveCancelButtons.contentGap,
        reason: 'inset + margins + 48 + the gap, not the old 56-high buttons',
      );
      expect(clearance - 20 - SaveCancelButtons.contentGap, strip);
    });
  });

  group('the size comes from the shared token, not scattered numbers', () {
    final source = _read('lib/src/views/Widgets/save_cancel_buttons.dart');

    test('the component reads AppControlSizes.formActionHeight', () {
      expect(source.contains('app_control_sizes.dart'), isTrue);
      expect(source.contains('AppControlSizes.formActionHeight'), isTrue);
    });

    test('the old padded height is gone', () {
      expect(source.contains('_buttonPadding'), isFalse);
      expect(RegExp(r'EdgeInsets\.symmetric\(vertical:').hasMatch(source),
          isFalse);
    });

    test('no deprecated Color channel getters remain in the component', () {
      expect(RegExp(r'\.(red|green|blue)\b').hasMatch(source), isFalse);
    });

    // Each screen places the component bare — straight inside a Positioned, as
    // the placement test below pins — so none can size the actions on its own.
  });

  group('the buttons are opaque, in light and dark', () {
    for (final entry in {
      'light': AppTheme.lightTheme,
      'dark': AppTheme.darkTheme,
    }.entries) {
      testWidgets(
          '${entry.key}: Cancel is filled with the page colour and '
          'Save is never translucent', (tester) async {
        final theme = entry.value;
        final surface = theme.colorScheme.surface;
        final primary = theme.colorScheme.primary;

        for (final enabled in [true, false]) {
          await _pump(
            tester,
            theme: theme,
            body: (_) => _screen(_floating(isEnabled: enabled)),
          );
          final cancel = tester.widget<OutlinedButton>(
            find.byType(OutlinedButton),
          );
          final save = tester.widget<ElevatedButton>(
            find.byType(ElevatedButton),
          );

          expect(_background(cancel), surface, reason: '${entry.key} Cancel');
          expect(_background(save).a, 1.0,
              reason: '${entry.key} Save (enabled: $enabled) is opaque');
          expect(
            _background(save),
            enabled
                ? primary
                : Color.alphaBlend(primary.withAlpha(77), surface),
            reason: 'the same colours the buttons always showed on the page',
          );
        }
      });
    }

    test('no hard-coded panel: the component paints only theme colours', () {
      final source = _read('lib/src/views/Widgets/save_cancel_buttons.dart');
      expect(source.contains('Colors.white'), isTrue,
          reason: 'label colour on the primary button, as before');
      expect(source.contains('BoxDecoration'), isFalse);
      expect(source.contains('BoxShadow'), isFalse);
      expect(source.contains('Container('), isFalse);
      expect(source.contains('colors.surface'), isTrue);
    });
  });

  group('SafeArea', () {
    testWidgets('the buttons clear the bottom system inset', (tester) async {
      await _pump(
        tester,
        bottomInset: 34,
        body: (_) => _screen(_floating()),
      );

      expect(tester.getBottomLeft(find.byType(ElevatedButton)).dy,
          800 - 34 - SaveCancelButtons.margin);
      expect(tester.getBottomLeft(find.byType(OutlinedButton)).dy,
          800 - 34 - SaveCancelButtons.margin);
    });

    testWidgets('without an inset the margin alone remains', (tester) async {
      await _pump(tester, body: (_) => _screen(_floating()));
      expect(tester.getBottomLeft(find.byType(ElevatedButton)).dy,
          800 - SaveCancelButtons.margin);
    });

    testWidgets('only the bottom is inset, as the app\'s own SafeArea does',
        (tester) async {
      await _pump(
        tester,
        bottomInset: 20,
        leftInset: 24,
        body: (_) => _screen(_floating()),
      );
      expect(tester.getTopLeft(find.byType(ElevatedButton)).dx, 16);
    });

    test('the component has a SafeArea that skips the top', () {
      final source = _read('lib/src/views/Widgets/save_cancel_buttons.dart');
      expect(source.contains('SafeArea('), isTrue);
      expect(RegExp(r'SafeArea\(\s*top: false').hasMatch(source), isTrue);
    });
  });

  group('the form keeps its last field above the actions', () {
    const lastKey = ValueKey<String>('last-field');

    // Up to 1.5: beyond that the test font (every glyph a full em wide) wraps
    // the labels, which real fonts do not at these sizes.
    for (final scale in const [0.85, 1.0, 1.3, 1.5]) {
      for (final inset in const [0.0, 34.0]) {
        testWidgets('scrolled to the end at text scale $scale, inset $inset',
            (tester) async {
          await _pump(
            tester,
            textScale: scale,
            bottomInset: inset,
            body: (context) => Stack(
              fit: StackFit.expand,
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: SaveCancelButtons.clearanceOf(context),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < 30; i++)
                        SizedBox(
                          height: 60,
                          key: i == 29 ? lastKey : null,
                        ),
                    ],
                  ),
                ),
                _floating(),
              ],
            ),
          );

          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -5000),
          );
          await tester.pumpAndSettle();

          final actionsTop =
              tester.getTopLeft(find.byType(SaveCancelButtons)).dy;
          final lastBottom = tester.getBottomLeft(find.byKey(lastKey)).dy;
          expect(lastBottom, lessThanOrEqualTo(actionsTop),
              reason: 'the last field must never sit behind the actions');
          expect(
              actionsTop - lastBottom,
              inInclusiveRange(SaveCancelButtons.contentGap - 0.5,
                  SaveCancelButtons.contentGap + 4.5),
              reason: 'a comfortable gap, not a blank block');
        });
      }
    }

    testWidgets('the clearance follows the text scale and the inset',
        (tester) async {
      // Read it from a real context at each setting.
      final readings = <String, double>{};
      for (final scale in const [1.0, 2.0]) {
        for (final inset in const [0.0, 34.0]) {
          await _pump(
            tester,
            textScale: scale,
            bottomInset: inset,
            body: (context) {
              readings['$scale/$inset'] =
                  SaveCancelButtons.clearanceOf(context);
              return const SizedBox.shrink();
            },
          );
        }
      }
      expect(readings['2.0/0.0']!, greaterThan(readings['1.0/0.0']!));
      expect(readings['1.0/34.0']! - readings['1.0/0.0']!, closeTo(34, 0.01));
      expect(readings['2.0/34.0']! - readings['2.0/0.0']!, closeTo(34, 0.01));
    });

    testWidgets('the saving state still fits inside the clearance',
        (tester) async {
      final loading = ValueNotifier<bool>(false);
      addTearDown(loading.dispose);
      double? clearance;
      await _pump(
        tester,
        textScale: 0.85,
        body: (context) {
          clearance = SaveCancelButtons.clearanceOf(context);
          return _screen(ValueListenableBuilder<bool>(
            valueListenable: loading,
            builder: (_, isLoading, __) => _floating(isLoading: isLoading),
          ));
        },
      );

      loading.value = true;
      await tester.pump();
      final saving = tester.getSize(find.byType(SaveCancelButtons)).height;

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(saving + SaveCancelButtons.contentGap,
          lessThanOrEqualTo(clearance! + 0.01));
    });
  });

  group('save and cancel behave as they did', () {
    testWidgets('both callbacks fire', (tester) async {
      var saved = 0;
      var cancelled = 0;
      await _pump(
        tester,
        body: (_) => _screen(
          _floating(onSave: () => saved++, onCancel: () => cancelled++),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.tap(find.byType(OutlinedButton));

      expect(saved, 1);
      expect(cancelled, 1);
    });

    testWidgets('while saving: a progress indicator, both buttons inert',
        (tester) async {
      var saved = 0;
      var cancelled = 0;
      final loading = ValueNotifier<bool>(false);
      addTearDown(loading.dispose);
      await _pump(
        tester,
        body: (_) => _screen(ValueListenableBuilder<bool>(
          valueListenable: loading,
          builder: (_, isLoading, __) => _floating(
            isLoading: isLoading,
            onSave: () => saved++,
            onCancel: () => cancelled++,
          ),
        )),
      );

      loading.value = true;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(en['save'] as String), findsNothing);
      expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNull);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull);
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      expect(saved, 0);
      expect(cancelled, 0);
    });

    testWidgets(
        'showProgress: false keeps Save\'s label with no spinner, both still inert',
        (tester) async {
      await _pump(
        tester,
        body: (_) => _screen(Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SaveCancelButtons(
            isLoading: true,
            showProgress: false,
            isEnabled: true,
            isEditMode: false,
            onSave: () {},
            onCancel: () {},
          ),
        )),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(en['save'] as String), findsOneWidget);
      expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNull);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull);
    });

    testWidgets(
        '"nothing to save yet" only dims Save: it still reports the tap',
        (tester) async {
      var saved = 0;
      await _pump(
        tester,
        body: (_) =>
            _screen(_floating(isEnabled: false, onSave: () => saved++)),
      );

      await tester.tap(find.byType(ElevatedButton));

      expect(saved, 1,
          reason: 'the view-models decide whether there is anything to save');
    });
  });

  group('every form screen uses the one shared presentation', () {
    for (final path in _formScreens) {
      final name = path.split('/').last;

      test('$name: the actions float, with no panel of its own', () {
        final source = _read(path);
        expect(source.contains('SaveCancelButtons('), isTrue);

        // Straight inside a Positioned: no Container, decoration or shadow
        // wrapped around them.
        expect(
          RegExp(
            r'Positioned\(\s*bottom: 0,\s*left: 0,\s*right: 0,\s*child: SaveCancelButtons\(',
          ).hasMatch(source),
          isTrue,
          reason: '$name must place SaveCancelButtons directly',
        );
        expect(source.contains('boxShadow'), isFalse, reason: name);
        expect(source.contains('Fixed buttons at bottom'), isFalse);
        expect(
          RegExp(r'colors\.surface,\s*boxShadow').hasMatch(source),
          isFalse,
          reason: name,
        );
      });

      test('$name: the scroll view reserves the actions\' real height', () {
        final source = _read(path);
        expect(
            source.contains('SaveCancelButtons.clearanceOf(context)'), isTrue,
            reason: name);
        expect(
          RegExp(r'keyboardHeight \+ 20\s*:\s*100').hasMatch(source),
          isFalse,
          reason: '$name still hard-codes the old panel allowance',
        );
      });

      test('$name: the keyboard rules are untouched', () {
        final source = _read(path);
        expect(source.contains('if (keyboardHeight == 0)'), isTrue,
            reason: 'the actions are still hidden while the keyboard is open');
        expect(
          RegExp(r'bottom: keyboardHeight > 0\s*\? keyboardHeight \+ 20')
              .hasMatch(source),
          isTrue,
          reason: 'the scroll view still pads for the keyboard',
        );
      });

      test(
          '$name: the page is painted with the surface colour the buttons '
          'are filled with', () {
        expect(
          RegExp(r'return Scaffold\(\s*backgroundColor: colors\.surface')
              .hasMatch(_read(path)),
          isTrue,
        );
      });
    }

    test('the six screens that keep the keyboard from moving them still do',
        () {
      for (final path in _formScreens.where((p) => !p.contains('quotation'))) {
        expect(_read(path).contains('resizeToAvoidBottomInset: false'), isTrue,
            reason: path);
      }
    });

    test('SaveCancelButtons is used only by these screens', () {
      final users = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('SaveCancelButtons('))
          .map((f) => f.path.replaceAll('\\', '/'))
          .where((p) => !p.endsWith('save_cancel_buttons.dart'))
          .toList()
        ..sort();
      expect(users, [..._formScreens]..sort());
    });
  });
}
