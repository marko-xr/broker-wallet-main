import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Facebook Login is permanently removed from Broker Wallet.
///
/// These are source-level guards: they fail if the dependency, the auth
/// contract, a sign-in path, the auth UI or the Android SDK wiring comes back.
///
/// They deliberately target *authentication* symbols rather than the word
/// "Facebook". The app still legitimately mentions Facebook in unrelated
/// features — the Share App screen offers Facebook as a share target, and the
/// company's social profile link lives in email configuration — and those are
/// not auth.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> dartFilesUnder(String directory) => Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  test('flutter_facebook_auth is not a dependency', () {
    expect(read('pubspec.yaml'), isNot(contains('flutter_facebook_auth')));

    final lock = read('pubspec.lock');
    for (final package in const [
      'flutter_facebook_auth',
      'flutter_facebook_auth_platform_interface',
      'flutter_facebook_auth_web',
      'facebook_auth_desktop',
    ]) {
      expect(lock, isNot(contains('  $package:')), reason: package);
    }
  });

  test('no application code can reach a Facebook auth flow', () {
    final forbidden = <Pattern>[
      'package:flutter_facebook_auth',
      'FacebookAuth.instance',
      'FacebookAuthProvider',
      'signInWithFacebook',
      'signUpWithFacebook',
    ];

    for (final file in dartFilesUnder('lib')) {
      final source = file.readAsStringSync();
      for (final pattern in forbidden) {
        expect(source.contains(pattern), isFalse,
            reason: '${file.path} references $pattern');
      }
    }
  });

  test('the auth repository contract has no Facebook provider', () {
    final contract = read('lib/src/repositories/auth_repository.dart');
    expect(contract.toLowerCase(), isNot(contains('facebook')));
  });

  test('the sign-in and sign-up screens offer no Facebook control', () {
    for (final path in const [
      'lib/src/views/Screens/Sign-Up-Log-In/login_view.dart',
      'lib/src/views/Screens/Sign-Up-Log-In/signup_view.dart',
      'lib/src/views/Screens/Sign-Up-Log-In/welcome_view.dart',
    ]) {
      expect(read(path).toLowerCase(), isNot(contains('facebook')),
          reason: path);
    }
  });

  test('the Facebook auth label is gone from both locales', () {
    for (final path in const [
      'lib/src/common/localization/app_en.arb',
      'lib/src/common/localization/app_ar.arb',
    ]) {
      expect(read(path), isNot(contains('"facebook":')), reason: path);
    }
  });

  test('the Android build no longer pulls in the Facebook SDK', () {
    expect(
      read('android/app/build.gradle'),
      isNot(contains('com.facebook.android:facebook-android-sdk')),
    );
  });
}
