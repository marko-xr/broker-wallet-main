// The Google Maps SDK freezes the phone's main thread the first time a map is
// shown, which stalls whatever is animating then (the map page sliding in).
// MapSdkWarmup does that work once, in the background, a few seconds after the
// app is up. Local tests of when it runs and that it can never break startup;
// what it does to the opening on a device is for the device.

import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/services/map_sdk_warmup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MapSdkWarmup.debugReset);

  test('warms up once, however many times it is started', () async {
    var calls = 0;
    Future<void> warmup() async => calls++;

    await MapSdkWarmup.start(
      after: Duration.zero,
      isAndroid: true,
      warmup: warmup,
    );
    await MapSdkWarmup.start(
      after: Duration.zero,
      isAndroid: true,
      warmup: warmup,
    );

    expect(calls, 1);
  });

  test('does nothing on a phone that is not an Android', () async {
    var calls = 0;

    await MapSdkWarmup.start(
      after: Duration.zero,
      isAndroid: false,
      warmup: () async => calls++,
    );

    expect(calls, 0);
  });

  test('a warm-up that fails never reaches the app', () async {
    // No Play services, or a plugin that is not there: the map still opens.
    await MapSdkWarmup.start(
      after: Duration.zero,
      isAndroid: true,
      warmup: () async => throw StateError('no maps service'),
    );
  });

  testWidgets('waits for the app to settle before it starts', (tester) async {
    var calls = 0;

    unawaited(
      MapSdkWarmup.start(
        after: const Duration(seconds: 3),
        isAndroid: true,
        warmup: () async => calls++,
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);

    await tester.pump(const Duration(seconds: 2));
    expect(calls, 1);
  });

  test('the app starts it after the app is running, and never waits for it',
      () {
    final main =
        File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    expect(main.contains('unawaited(MapSdkWarmup.start());'), isTrue);
    expect(
      main.indexOf('unawaited(MapSdkWarmup.start());'),
      greaterThan(main.indexOf('runApp(')),
      reason: 'it must not delay the first frame',
    );
  });
}
