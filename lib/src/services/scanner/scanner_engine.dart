import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';

import 'package:broker_wallet/src/services/scanner/scan_lifecycle_probe.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';

/// Opens the phone's document scanner. The one seam between the Scanner and the
/// native scanner plugin, so everything after it can be exercised without a
/// phone.
abstract interface class ScannerEngine {
  /// Runs the scanner and returns its raw answer for [ScanResultParser], or
  /// null when the user cancelled. Throws a [ScannerException] (`busy`,
  /// `engineFailed`, `malformedResult`) when the scanner could not run.
  Future<Object?> scan({
    required ExportFormat format,
    required int maxPages,
  });
}

/// The production engine: `flutter_doc_scanner` 0.0.21, which opens Google's ML
/// Kit Document Scanner on Android (crop, rotate, retake, filters and page
/// review happen in that screen, inside Google Play services) and Apple's
/// VisionKit document camera on iPhone. Both scan on the device; nothing is
/// uploaded by this code.
///
/// The plugin's Android half drops its pending reply when its Activity detaches
/// (see [ScanLifecycleProbe]); a scan whose result was lost that way ends with a
/// `scanAbandoned` failure instead of waiting forever. A scan that is only slow
/// or in the background is never ended: the probe reports a loss, not time.
class FlutterDocScannerEngine implements ScannerEngine {
  FlutterDocScannerEngine(
      [FlutterDocScanner? scanner, ScanLifecycleProbe? probe])
      : _scanner = scanner ?? FlutterDocScanner(),
        _probe = probe ?? const NoScanLifecycleProbe();

  final FlutterDocScanner _scanner;
  final ScanLifecycleProbe _probe;

  @override
  Future<Object?> scan({
    required ExportFormat format,
    required int maxPages,
  }) async {
    final watch = await _probe.begin();
    try {
      return await Future.any<Object?>(<Future<Object?>>[
        _runPlugin(format, maxPages),
        watch.abandoned.then<Object?>(
          (_) => throw const ScannerException(
              ScannerFailure.scanAbandoned, 'native'),
        ),
      ]);
    } finally {
      await watch.end();
    }
  }

  Future<Object?> _runPlugin(ExportFormat format, int maxPages) async {
    try {
      if (format == ExportFormat.pdf) {
        final result = await _scanner.getScannedDocumentAsPdf(page: maxPages);
        if (result == null) return null;
        return <String, Object?>{
          'pdfUri': result.pdfUri,
          if (result.pageCount > 0) 'pageCount': result.pageCount,
        };
      }
      // The plugin's image format and quality options are not passed: the
      // Android scanner always returns JPEG and the iPhone scanner writes PNG
      // pages whatever is asked, so asking would only suggest a control that
      // does nothing.
      final result = await _scanner.getScannedDocumentAsImages(page: maxPages);
      if (result == null) return null;
      return <String, Object?>{'images': result.images};
    } on DocScanException catch (error) {
      switch (error.code) {
        case DocScanException.codeCancelled:
          return null;
        case DocScanException.codeScanInProgress:
          throw const ScannerException(ScannerFailure.busy, 'engine');
        default:
          throw ScannerException(ScannerFailure.engineFailed, error.code);
      }
    } on PlatformException catch (error) {
      throw ScannerException(ScannerFailure.engineFailed, error.code);
    } on FormatException {
      throw const ScannerException(ScannerFailure.malformedResult, 'plugin');
    } on ArgumentError {
      throw const ScannerException(ScannerFailure.engineFailed, 'arguments');
    }
  }
}
