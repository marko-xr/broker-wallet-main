import 'dart:async';

import 'package:flutter/services.dart';

/// One watched scan. [abandoned] completes if the native side lost the scan's
/// result for good; [end] stops watching.
class ScanWatch {
  ScanWatch({required this.abandoned, required Future<void> Function() onEnd})
      : _onEnd = onEnd;

  /// Completes (never with an error) when the scanner's result can no longer
  /// arrive. It stays pending for a scan that is merely slow or in the
  /// background.
  final Future<void> abandoned;
  final Future<void> Function() _onEnd;

  Future<void> end() => _onEnd();

  /// A watch that never reports a loss (iPhone, and tests).
  static ScanWatch never() => ScanWatch(
        abandoned: Completer<void>().future,
        onEnd: () async {},
      );
}

/// Tells the Scanner when the native scanner's pending result was lost.
///
/// `flutter_doc_scanner` 0.0.21 keeps the Dart call's reply in a field that its
/// Android plugin sets to null, without answering it, whenever its Activity
/// detaches — including a detach for a configuration change that the Flutter
/// engine survives. The scanner's answer then arrives to a plugin that no longer
/// has a reply to give it, and the call never completes. Nothing in Dart can see
/// that, so a small native listener (`ScanLifecycleGuard.kt`, registered next to
/// the plugin) watches the same Activity lifecycle and reports it. When the
/// whole Activity and engine are destroyed instead, Dart is gone too and the app
/// restarts, so there is nothing left waiting.
abstract interface class ScanLifecycleProbe {
  /// Starts watching one scan. Never throws.
  Future<ScanWatch> begin();
}

class PlatformScanLifecycleProbe implements ScanLifecycleProbe {
  PlatformScanLifecycleProbe({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  /// The channel `ScanLifecycleGuard.kt` listens on.
  static const String channelName = 'com.example.broker_wallet/scan_lifecycle';

  final MethodChannel _channel;
  Completer<void>? _current;

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method == 'scanAbandoned') {
      final current = _current;
      if (current != null && !current.isCompleted) current.complete();
    }
    return null;
  }

  @override
  Future<ScanWatch> begin() async {
    final completer = Completer<void>();
    _current = completer;
    try {
      await _channel.invokeMethod<Object?>('begin');
    } on MissingPluginException {
      // No native listener on this platform: nothing can be reported.
    } on PlatformException {
      // The scan still runs; it just cannot be watched.
    }
    return ScanWatch(
      abandoned: completer.future,
      onEnd: () async {
        if (identical(_current, completer)) _current = null;
        try {
          await _channel.invokeMethod<Object?>('end');
        } on MissingPluginException {
          // see above
        } on PlatformException {
          // see above
        }
      },
    );
  }
}

/// A probe that watches nothing.
class NoScanLifecycleProbe implements ScanLifecycleProbe {
  const NoScanLifecycleProbe();

  @override
  Future<ScanWatch> begin() async => ScanWatch.never();
}
