import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Sanitized, per-item diagnostics for the Offer media pipeline.
///
/// Every line starts with `[offer-media]` so one `adb logcat` filter captures
/// a whole device session. Lines name an item only by the last six characters
/// of its `mediaObjectId` and carry sizes, timings, states, HTTP statuses and
/// error *categories* — never a URL, a token, a file name or provider text.
/// Nothing is printed in release builds.
abstract final class OfferMediaDiagnostics {
  /// Replaceable in tests.
  @visibleForTesting
  static void Function(String line) sink = _print;

  static bool enabled = !kReleaseMode;

  static void _print(String line) => debugPrint(line);

  static void log(String event, {String? id, Map<String, Object?>? fields}) {
    if (!enabled) return;
    final buffer = StringBuffer('[offer-media] $event');
    if (id != null) buffer.write(' id=${shortId(id)}');
    fields?.forEach((key, value) {
      if (value != null) buffer.write(' $key=$value');
    });
    sink(buffer.toString());
  }

  /// The last six characters of a media id: enough to follow one item
  /// through a session, not enough to address it.
  static String shortId(String id) =>
      id.length > 6 ? '…${id.substring(id.length - 6)}' : id;

  /// A fixed category for [error], safe to log: the exception's type and, for
  /// socket errors, the OS error number — never its message, which can hold a
  /// host name or a signed URL.
  static String categorize(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is SocketException) {
      final code = error.osError?.errorCode;
      return code == null ? 'socket' : 'socket:$code';
    }
    if (error is HandshakeException || error is TlsException) return 'tls';
    if (error is HttpException) return 'http-protocol';
    if (error is FileSystemException) return 'file';
    return error.runtimeType.toString();
  }

  /// A fixed category for a video player failure message, which may contain
  /// a signed URL and is therefore never logged itself.
  static String playerErrorCategory(String message) {
    final lower = message.toLowerCase();
    final status = RegExp(r'response code:?\s*(\d{3})').firstMatch(lower);
    if (status != null) return 'http:${status.group(1)}';
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'timeout';
    }
    if (lower.contains('mediacodec') || lower.contains('decoder')) {
      return 'codec';
    }
    if (lower.contains('source error')) return 'source';
    if (lower.contains('unrecognizedinputformat') ||
        lower.contains('none of the available extractors')) {
      return 'format';
    }
    if (lower.contains('filenotfound') || lower.contains('enoent')) {
      return 'file-missing';
    }
    if (lower.contains('invalid video data')) return 'no-duration';
    return 'other';
  }
}
