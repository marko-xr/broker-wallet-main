// Internal diagnostics for the Toolkit document library. Nothing here reaches a
// screen: it only makes a failure that the UI deliberately keeps quiet (a list
// that could not be read, a document that could not be opened) findable in the
// debug console (`flutter run` prints it under the name `toolkit-docs`).
//
// A line names a document only by the last six characters of its id and says
// WHAT failed as a fixed category: the library step, the tool, the failure
// category, an HTTP status and the Worker's stable code. It never holds a signed
// URL, a storage key, an account id, a file path, a title or raw error text
// (which can embed the URL). Release builds print nothing.

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';

abstract final class ToolkitDiagnostics {
  /// The log name the console shows.
  static const String logName = 'toolkit-docs';

  /// Receives every line instead of the console. For tests.
  @visibleForTesting
  static void Function(String line)? sink;

  /// The last six characters of [id], or `-`.
  static String maskedId(String? id) {
    if (id == null || id.isEmpty) return '-';
    return id.length <= 6 ? id : id.substring(id.length - 6);
  }

  /// One line: `step=<step> tool=<tool> doc=<masked> failure=<category> ...`.
  static void report(
    String step, {
    ToolkitDocumentType? type,
    String? documentId,
    Object? error,
    int? count,
  }) {
    final capture = sink;
    if (capture == null && !kDebugMode) return;
    final parts = <String>['step=$step'];
    if (type != null) parts.add('tool=${type.wireName}');
    if (documentId != null) parts.add('doc=${maskedId(documentId)}');
    if (count != null) parts.add('count=$count');
    if (error is ToolkitDocumentException) {
      parts.add('failure=${error.failure.name}');
      final status = error.statusCode;
      if (status != null) parts.add('status=$status');
      final code = error.workerCode;
      if (code != null && _stableCode.hasMatch(code)) parts.add('code=$code');
    } else if (error != null) {
      parts.add('error=${error.runtimeType}');
    }
    final line = parts.join(' ');
    if (capture != null) {
      capture(line);
    } else {
      developer.log(line, name: logName);
    }
  }

  static final RegExp _stableCode = RegExp(r'^[a-z0-9_]{1,64}$');
}
