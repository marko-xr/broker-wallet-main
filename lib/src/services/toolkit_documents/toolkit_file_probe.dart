// Reads only the first and last bytes of a file to check that it is a complete
// container of the format it is declared to be (see
// [ToolkitContentType.hasValidFraming]). Used before an upload (a local file that
// is truncated or is not what its type says is never sent) and after a download.

import 'dart:io';
import 'dart:math' as math;

import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';

abstract final class ToolkitFileProbe {
  static const int headBytes = 32;
  static const int tailBytes = 1024;

  /// Whether [file] is a complete [type] container. False for anything unreadable.
  static Future<bool> isCompleteContainer(
    File file,
    ToolkitContentType type,
  ) async {
    RandomAccessFile? access;
    try {
      access = await file.open();
      final size = await access.length();
      if (size < 1) return false;
      final head = await access.read(math.min(headBytes, size));
      final tailLength = math.min(tailBytes, size);
      await access.setPosition(size - tailLength);
      final tail = await access.read(tailLength);
      return type.hasValidFraming(head, tail, size);
    } on FileSystemException {
      return false;
    } finally {
      try {
        await access?.close();
      } catch (_) {}
    }
  }
}
