// iOS push readiness (2026-11-21). Reads the real iOS project files: the app
// identity, the Firebase configuration (same project as Android), the
// entitlement and the Info.plist keys firebase_messaging needs, plus the APNs
// token wait. Static checks only: real delivery still needs the APNs key, an
// Apple-signed build and an iPhone (docs/NOTIFICATIONS_PRODUCTION_PLAN.md).
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/push/firebase_push_platform.dart';
import 'package:flutter_test/flutter_test.dart';

const _bundleId = 'com.nmodigital.brokerwallet';

String _read(String path) => File(path).readAsStringSync();

/// The `<string>` or boolean right after `<key>key</key>`. Booleans come as
/// `<true/>` (Xcode) or `<true></true>` (the Firebase console's plist).
String? _plistValue(String plist, String key) {
  final match = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*'
    '(?:<string>([^<]*)</string>|<(true|false)\\s*/>|<(true|false)></(?:true|false)>)',
  ).firstMatch(plist);
  return match?.group(1) ?? match?.group(2) ?? match?.group(3);
}

void main() {
  group('iOS app identity', () {
    final project = _read('ios/Runner.xcodeproj/project.pbxproj');

    test('Runner and RunnerTests use the NMO Digital bundle id only', () {
      final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(project)
          .map((m) => m.group(1))
          .toList();
      expect(ids, hasLength(6));
      expect(ids.where((id) => id == _bundleId), hasLength(3));
      expect(ids.where((id) => id == '$_bundleId.RunnerTests'), hasLength(3));
      expect(project.contains('com.example.broker-wallet'), isFalse);
    });

    test('every Runner configuration signs with the push entitlement', () {
      expect(
        'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
            .allMatchesIn(project),
        3,
      );
    });

    test('GoogleService-Info.plist is bundled with the app', () {
      // Referenced, in the Runner group and in the Resources build phase;
      // otherwise FirebaseApp.configure() finds no configuration at launch.
      expect(
        RegExp(r'/\* GoogleService-Info\.plist in Resources \*/,')
            .hasMatch(project),
        isTrue,
      );
      expect(
        RegExp(r'path = "GoogleService-Info\.plist"').hasMatch(project),
        isTrue,
      );
    });
  });

  group('Firebase configuration', () {
    final plist = _read('ios/Runner/GoogleService-Info.plist');
    final android = jsonDecode(_read('android/app/google-services.json'))
        as Map<String, dynamic>;
    final projectInfo = android['project_info'] as Map<String, dynamic>;

    test('iOS uses the same Firebase project as Android', () {
      expect(_plistValue(plist, 'PROJECT_ID'), projectInfo['project_id']);
      expect(_plistValue(plist, 'PROJECT_ID'), 'broker-wallet');
      expect(
          _plistValue(plist, 'GCM_SENDER_ID'), projectInfo['project_number']);
    });

    test('the plist belongs to this iOS app, with Cloud Messaging on', () {
      expect(_plistValue(plist, 'BUNDLE_ID'), _bundleId);
      expect(_plistValue(plist, 'GOOGLE_APP_ID'),
          startsWith('1:${projectInfo['project_number']}:ios:'));
      expect(_plistValue(plist, 'IS_GCM_ENABLED'), 'true');
    });
  });

  group('push capability files', () {
    test('the entitlement asks for APNs', () {
      final entitlements = _read('ios/Runner/Runner.entitlements');
      expect(_plistValue(entitlements, 'aps-environment'), 'development');
    });

    test('Info.plist keeps swizzling on and remote-notification mode', () {
      final info = _read('ios/Runner/Info.plist');
      // firebase_messaging requires method swizzling on Apple platforms.
      expect(_plistValue(info, 'FirebaseAppDelegateProxyEnabled'), 'true');
      expect(info.contains('<string>remote-notification</string>'), isTrue);
    });

    test('Firebase is configured once, natively', () {
      final delegate = _read('ios/Runner/AppDelegate.swift');
      expect('FirebaseApp.configure()'.allMatchesIn(delegate), 1);
    });

    test('push is switched on for iOS', () {
      expect(iosPushReady, isTrue);
    });
  });

  group('APNs token wait', () {
    test('a token that is already there is returned at once', () async {
      final slept = <Duration>[];
      final token = await waitForApnsToken(
        () async => 'apns',
        sleep: (d) async => slept.add(d),
      );
      expect(token, 'apns');
      expect(slept, isEmpty);
    });

    test('a token that arrives later is waited for', () async {
      var reads = 0;
      final slept = <Duration>[];
      final token = await waitForApnsToken(
        () async => ++reads < 3 ? null : 'apns',
        sleep: (d) async => slept.add(d),
      );
      expect(token, 'apns');
      expect(slept, apnsTokenWaits.take(2).toList());
    });

    test('no token at all ends with ApnsTokenUnavailable', () async {
      var reads = 0;
      await expectLater(
        waitForApnsToken(
          () async {
            reads++;
            return '';
          },
          sleep: (_) async {},
        ),
        throwsA(isA<ApnsTokenUnavailable>()),
      );
      expect(reads, apnsTokenWaits.length + 1);
    });
  });
}

extension on String {
  int allMatchesIn(String text) => text.split(this).length - 1;
}
