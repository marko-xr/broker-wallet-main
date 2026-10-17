import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the Scanner's private documents and working files out of cloud and
/// device backup where the platform needs the app to say so.
///
/// Android is configured declaratively (`backup_rules.xml` and
/// `data_extraction_rules.xml` exclude `app_flutter/scanner` and the scanner's
/// own output folder), so nothing is done here. iPhone needs the item itself
/// marked (`isExcludedFromBackup`, via `AppDelegate.swift`). Scans are therefore
/// not restored from a backup or onto a new phone; an export or share is the
/// way to keep a copy.
abstract interface class ScannerBackupGuard {
  /// Marks [path] (a folder or a file) as excluded from backup. Best effort:
  /// returns false when it could not be done, and never throws.
  Future<bool> exclude(String path);
}

/// The production guard: only iOS has anything to do.
class PlatformScannerBackupGuard implements ScannerBackupGuard {
  PlatformScannerBackupGuard({MethodChannel? channel, bool? isIOS})
      : _channel = channel ?? const MethodChannel(channelName),
        _isIOS = isIOS ?? Platform.isIOS;

  /// The channel `AppDelegate.swift` answers on.
  static const String channelName =
      'com.example.broker_wallet/backup_exclusion';

  final MethodChannel _channel;
  final bool _isIOS;

  @override
  Future<bool> exclude(String path) async {
    if (!_isIOS) return true;
    try {
      final result =
          await _channel.invokeMethod<Object?>('excludeFromBackup', path);
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// A guard that does nothing (tests).
class NoScannerBackupGuard implements ScannerBackupGuard {
  const NoScannerBackupGuard();

  @override
  Future<bool> exclude(String path) async => true;
}
