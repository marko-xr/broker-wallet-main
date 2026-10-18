import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Serves the ARB files from disk (so tests assert on the real strings), loads
/// both languages and records every toast the screens show.
Future<void> setUpSignatureWidgetTests(
  TestWidgetsFlutterBinding binding,
  List<String> toasts,
) async {
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
}

/// The English or Arabic text of a message, from the ARB file the app ships.
String message(String key, {String language = 'en'}) {
  final text = AppLocalizations.translateFor(language, key);
  if (text == null) throw StateError('no $language text for $key');
  return text;
}

/// [home] in the app's localization set-up.
Widget signatureApp(
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

/// Lets real file work and the view model's awaits finish while the widget tree
/// is pumped: the screen's awaits live in the fake-async zone, so a plain
/// `pumpAndSettle` would never see them progress.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the condition was never reached');
}

/// Sets the phone's logical screen size and pixel density for one test.
void useScreen(
  WidgetTester tester, {
  Size size = const Size(420, 900),
  double density = 1,
}) {
  tester.view.physicalSize = Size(size.width * density, size.height * density);
  tester.view.devicePixelRatio = density;
  addTearDown(tester.view.reset);
}
