import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Serves the ARB files from disk, so the tests assert on the real strings.
Future<void> setUpUaeLinksWidgetTests(TestWidgetsFlutterBinding binding) async {
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
}

/// The text of [key] in [language], from the ARB file the app ships.
String text(String key, {String language = 'en'}) {
  final value = AppLocalizations.translateFor(language, key);
  if (value == null) throw StateError('no $language text for $key');
  return value;
}

/// [home] in the app's localization set-up.
Widget uaeLinksApp(
  Widget home, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return MaterialApp(
    locale: locale,
    theme: theme,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

/// Sets the phone's logical size for one test.
void useScreen(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
