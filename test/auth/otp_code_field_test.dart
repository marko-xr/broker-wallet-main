// The shared Broker Wallet OTP field (OtpCodeField, Pinput 5.0.2).
import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/services/sms_user_consent_retriever.dart';
import 'package:broker_wallet/src/views/Widgets/otp_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';

class _FakeRetriever implements SmsRetriever {
  final Completer<String?> code = Completer<String?>();
  int calls = 0;
  bool disposed = false;

  @override
  bool get listenForMultipleSms => false;

  @override
  Future<String?> getSmsCode() {
    calls++;
    return code.future;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

Widget _host(
  Widget child, {
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  bool reduceMotion = true,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) =>
    MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            // The field honours reduce-motion: no blinking cursor, so the
            // tests can settle.
            disableAnimations: reduceMotion,
            viewInsets: viewInsets,
          ),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );

class _Recorder {
  final List<String> changes = [];
  final List<String> completed = [];
}

OtpCodeField _field(
  TextEditingController controller,
  _Recorder rec, {
  bool enabled = true,
  bool verifying = false,
  bool hasError = false,
  String? errorText,
  bool smsAutofill = false,
  SmsRetriever? smsRetriever,
  bool autofocus = true,
}) =>
    OtpCodeField(
      controller: controller,
      semanticLabel: 'Enter OTP',
      enabled: enabled,
      verifying: verifying,
      hasError: hasError,
      errorText: errorText,
      autofocus: autofocus,
      smsAutofill: smsAutofill,
      smsRetriever: smsRetriever,
      onChanged: rec.changes.add,
      onCompleted: rec.completed.add,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('six equal cells, labelled for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(_field(controller, _Recorder())));
    await tester.pumpAndSettle();

    final cells = tester.widgetList<AnimatedContainer>(find.descendant(
        of: find.byType(Pinput), matching: find.byType(AnimatedContainer)));
    expect(cells, hasLength(6));
    final sizes = find.descendant(
        of: find.byType(Pinput), matching: find.byType(AnimatedContainer));
    final widths = [
      for (final e in sizes.evaluate())
        tester.getSize(find.byWidget(e.widget)).width
    ];
    expect(widths.toSet(), hasLength(1), reason: 'all cells are equal');
    expect(find.bySemanticsLabel('Enter OTP'), findsWidgets);
    semantics.dispose();
  });

  testWidgets(
      'digits only: a pasted message keeps just its code and completes '
      'once', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final rec = _Recorder();
    await tester.pumpWidget(_host(_field(controller, rec)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(OtpCodeField), 'Your code: 123-456');
    await tester.pumpAndSettle();
    expect(controller.text, '123456');
    expect(rec.completed, ['123456']);

    await tester.enterText(find.byType(OtpCodeField), 'abc12');
    await tester.pumpAndSettle();
    expect(controller.text, '12', reason: 'letters are dropped');
    expect(rec.completed, ['123456'], reason: 'a partial code never completes');
  });

  testWidgets(
      'a code completes once; editing it and completing again counts '
      'again', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final rec = _Recorder();
    await tester.pumpWidget(_host(_field(controller, rec)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(OtpCodeField), '123456');
    await tester.pump();
    await tester.pump();
    // The keyboard's Done on the same code is not a second completion.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(rec.completed, ['123456']);

    await tester.enterText(find.byType(OtpCodeField), '12345');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(OtpCodeField), '123457');
    await tester.pumpAndSettle();
    expect(rec.completed, ['123456', '123457']);
  });

  testWidgets('digits read left to right in an Arabic (RTL) layout',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        _host(_field(controller, _Recorder()), direction: TextDirection.rtl));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(OtpCodeField), '123');
    await tester.pumpAndSettle();
    final one = tester.getCenter(find.text('1'));
    final three = tester.getCenter(find.text('3'));
    expect(one.dx, lessThan(three.dx), reason: 'first digit on the left');
  });

  testWidgets('backspace removes the last digit', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final rec = _Recorder();
    await tester.pumpWidget(_host(_field(controller, rec)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(OtpCodeField), '1234');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, '123');
    expect(rec.changes.last, '123');
  });

  testWidgets(
      'disabled or verifying: no input and no completion, even from a '
      'programmatic fill', (tester) async {
    for (final (enabled, verifying) in [(false, false), (true, true)]) {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController();
      final rec = _Recorder();
      await tester.pumpWidget(_host(_field(controller, rec,
          enabled: enabled, verifying: verifying, autofocus: false)));
      await tester.pumpAndSettle();
      controller.text = '654321';
      await tester.pumpAndSettle();
      expect(rec.completed, isEmpty,
          reason: 'enabled=$enabled verifying=$verifying');
      final node = tester.getSemantics(find.byType(Pinput));
      // ignore: deprecated_member_use
      expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse,
          reason: 'announced as not editable');
      controller.dispose();
      semantics.dispose();
    }
  });

  testWidgets(
      'an error message is shown and announced; hasError alone shows '
      'no text', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(
        _field(controller, _Recorder(), errorText: 'The code is incorrect.')));
    await tester.pumpAndSettle();
    expect(find.text('The code is incorrect.'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('The code is incorrect.')),
      matchesSemantics(label: 'The code is incorrect.', isLiveRegion: true),
    );

    await tester
        .pumpWidget(_host(_field(controller, _Recorder(), hasError: true)));
    await tester.pumpAndSettle();
    expect(find.text('The code is incorrect.'), findsNothing);
    semantics.dispose();
  });

  testWidgets(
      'the focused cell uses Broker Wallet green; at rest the border '
      'is neutral', (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final controller = TextEditingController();
      await tester
          .pumpWidget(_host(_field(controller, _Recorder()), theme: theme));
      await tester.pumpAndSettle();
      final borders = [
        for (final c in tester.widgetList<AnimatedContainer>(find.descendant(
            of: find.byType(Pinput), matching: find.byType(AnimatedContainer))))
          ((c.decoration as BoxDecoration).border as Border).top.color,
      ];
      expect(borders.first, theme.colorScheme.primary,
          reason: 'focused first cell');
      expect(
          borders.skip(1).every((c) => c != theme.colorScheme.primary), isTrue,
          reason: 'the other cells stay neutral');
      controller.dispose();
    }
  });

  testWidgets('Android SMS autofill fills an open field once', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final rec = _Recorder();
    final retriever = _FakeRetriever();
    await tester.pumpWidget(_host(
        _field(controller, rec, smsAutofill: true, smsRetriever: retriever)));
    await tester.pumpAndSettle();
    expect(retriever.calls, 1);
    retriever.code.complete('654321');
    await tester.pumpAndSettle();
    expect(controller.text, '654321');
    expect(rec.completed, ['654321'],
        reason: 'the flow decides what a completed code does');

    await tester.pumpWidget(const SizedBox());
    expect(retriever.disposed, isTrue,
        reason: 'the listener ends with the field');
  });

  testWidgets('a code that arrives after the field closed is dropped',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final rec = _Recorder();
    final retriever = _FakeRetriever();
    await tester.pumpWidget(_host(
        _field(controller, rec, smsAutofill: true, smsRetriever: retriever)));
    await tester.pumpAndSettle();
    // The flow moved on (verifying, or abandoned after a session change).
    await tester.pumpWidget(_host(_field(controller, rec,
        verifying: true, smsAutofill: true, smsRetriever: retriever)));
    await tester.pumpAndSettle();
    retriever.code.complete('111111');
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(rec.completed, isEmpty);
  });

  testWidgets('without smsAutofill no SMS listener starts', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final retriever = _FakeRetriever();
    await tester.pumpWidget(
        _host(_field(controller, _Recorder(), smsRetriever: retriever)));
    await tester.pumpAndSettle();
    expect(retriever.calls, 0);
  });

  testWidgets(
      'no overflow: narrow width, large text, inside a dialog with the '
      'keyboard open', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    for (final (size, scale) in [
      (const Size(240, 400), 1.0),
      (const Size(320, 640), 2.0),
      (const Size(412, 800), 1.6),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester
          .pumpWidget(_host(_field(controller, _Recorder()), textScale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size x$scale');
    }
    // AlertDialog measures intrinsic width; the keyboard takes 300 px.
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pumpWidget(_host(
      Builder(
        builder: (_) => AlertDialog(
          scrollable: true,
          title: const Text('Verify'),
          content: _field(controller, _Recorder()),
        ),
      ),
      viewInsets: const EdgeInsets.only(bottom: 300),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('text meets contrast guidelines in light and dark',
      (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController(text: '123');
      await tester.pumpWidget(_host(
          _field(controller, _Recorder(), errorText: 'The code is incorrect.'),
          theme: theme));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      controller.dispose();
      semantics.dispose();
    }
  });

  testWidgets(
      'typing in a field that is partly scrolled away brings the '
      'whole row into view, not just the cursor', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(SizedBox(
      height: 160,
      child: SingleChildScrollView(
        child: Column(children: [
          const SizedBox(height: 130),
          _field(controller, _Recorder(), autofocus: false),
          const SizedBox(height: 200),
        ]),
      ),
    )));
    await tester.pump();
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(tester.getRect(find.byType(OtpCodeField)).bottom,
        greaterThan(viewport.bottom),
        reason: 'starts cut off');
    await tester.enterText(find.byType(OtpCodeField), '12');
    await tester.pump();
    await tester.pump();
    final field = tester.getRect(find.byType(OtpCodeField));
    expect(field.top, greaterThanOrEqualTo(viewport.top - 0.5));
    expect(field.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
  });

  testWidgets(
      'dialog margins: narrower only below 390 dp, so the cells '
      'stay readable', (tester) async {
    final seen = <double, List<EdgeInsets?>>{};
    for (final width in [320.0, 359.0, 360.0, 389.0, 390.0, 412.0]) {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(builder: (context) {
          seen[width] = [
            OtpDialogSpacing.insetPadding(context),
            OtpDialogSpacing.contentPadding(context),
          ];
          return const SizedBox();
        }),
      ));
    }
    expect(seen[320]![0]!.left, 16);
    expect(seen[320]![1]!.left, 16);
    expect(seen[359]![0]!.left, 16);
    expect(seen[360]![0]!.left, 24);
    expect(seen[360]![1], isNull, reason: 'default inner padding from 360');
    expect(seen[389]![0]!.left, 24);
    expect(seen[390]![0], isNull, reason: '390 dp and wider: unchanged');
    expect(seen[412]![0], isNull);
    expect(seen[412]![1], isNull);
  });

  test('the field and the SMS retriever never log or store a code', () {
    for (final path in [
      'lib/src/views/Widgets/otp_code_field.dart',
      'lib/src/services/sms_user_consent_retriever.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final banned in [
        'print(',
        'debugPrint',
        'log(',
        'SharedPreferences',
        'FlutterSecureStorage',
        'Hive',
        'Clipboard',
      ]) {
        expect(source, isNot(contains(banned)), reason: '$path: $banned');
      }
    }
    final retriever = File('lib/src/services/sms_user_consent_retriever.dart')
        .readAsStringSync();
    expect(retriever, contains('useUserConsentApi: true'),
        reason: 'User Consent, not the hash-bound Retriever');
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(matches(RegExp('RECEIVE_SMS|READ_SMS'))),
        reason: 'no SMS permission');
  });

  test(
      'the code pattern takes a lone six-digit code, not part of a phone '
      'number', () {
    final pattern = RegExp(SmsUserConsentRetriever.codePattern);
    expect(pattern.firstMatch('Your code is 654321')?.group(0), '654321');
    expect(pattern.firstMatch('Call +971501234567. Code: 123456')?.group(0),
        '123456');
    expect(pattern.hasMatch('Ref 1234567'), isFalse);
  });
}
