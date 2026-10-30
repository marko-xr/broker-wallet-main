import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical dimensions and intrusions used by production-widget layout tests.
class ResponsiveCase {
  const ResponsiveCase(
    this.size, {
    this.locale = const Locale('en'),
    this.dark = false,
    this.textScale = 1,
    this.safeArea = EdgeInsets.zero,
    this.keyboard = 0,
    this.pixelRatio = 2,
  });

  final Size size;
  final Locale locale;
  final bool dark;
  final double textScale;
  final EdgeInsets safeArea;
  final double keyboard;
  final double pixelRatio;

  @override
  String toString() => '${size.width}x${size.height} '
      '${locale.languageCode} ${dark ? 'dark' : 'light'} '
      '${textScale}x inset=$safeArea keyboard=$keyboard';
}

/// Installs real localization assets; no production repository is initialized.
Future<void> prepareResponsiveAssets() async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      final sourceFile = File(key);
      final file = sourceFile.existsSync()
          ? sourceFile
          : File('build/unit_test_assets/$key');
      if (!file.existsSync()) return null;
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      return ByteData.view(bytes.buffer);
    },
  );
  await AppLocalizations.preloadAllLanguages();
}

Future<void> pumpResponsive(
  WidgetTester tester,
  ResponsiveCase scenario, {
  required Widget home,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = scenario.pixelRatio;
  tester.view.physicalSize = Size(
    scenario.size.width * scenario.pixelRatio,
    scenario.size.height * scenario.pixelRatio,
  );
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: scenario.locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: scenario.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scenario.textScale),
        padding: scenario.safeArea,
        viewPadding: scenario.safeArea,
        viewInsets: EdgeInsets.only(bottom: scenario.keyboard),
      ),
      child: child!,
    ),
    home: home,
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  final exception = tester.takeException();
  expect(
      exception is FlutterError ? exception.toStringDeep() : exception, isNull,
      reason: scenario.toString());
}

void expectNoLayoutException(WidgetTester tester, ResponsiveCase scenario) {
  expect(tester.takeException(), isNull, reason: scenario.toString());
}
