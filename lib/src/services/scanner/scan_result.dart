import 'package:broker_wallet/src/services/scanner/scan_models.dart';

/// Why a scan or a save did not produce a document. The view maps each one to
/// a localized message; none of them carries text from the platform, a path or
/// anything from a document.
enum ScannerFailure {
  /// The signed-in account is not known (signed out, or switched away).
  signedOut,

  /// The scanner (or a save) is already running.
  busy,

  /// The native scanner's result was lost (its Activity detached while it was
  /// open) and can never arrive. Nothing was saved.
  scanAbandoned,

  /// The native scanner could not be started or reported an error.
  engineFailed,

  /// The scanner answered with something that is not a scan result.
  malformedResult,

  /// The scanner returned one kind of output where the other was asked for.
  wrongFormat,

  /// The result names a file the Scanner may not read.
  untrustedSource,

  /// A file the scanner named is gone or cannot be opened.
  missingOutput,

  /// A scanner file is empty.
  emptyOutput,

  /// A scanner file is not a readable PDF or JPEG/PNG image.
  corruptOutput,

  /// A scanner file is larger than the Scanner will open.
  tooLarge,

  /// The phone is out of storage space.
  storageFull,

  /// The private store could not be written or verified.
  writeFailed,

  /// The document to act on is not in the list any more.
  notFound,

  /// The title is empty or unusable.
  invalidName,

  /// Another document already has this title.
  nameInUse,

  /// The stored file is missing from the phone.
  fileMissing,

  /// The user turned the free-plan limit down (the dialog was shown).
  quotaBlocked,

  /// The account changed while the work was running, so its result was dropped.
  accountChanged,

  /// Permission to write to the phone's public storage was not given.
  permissionDenied,

  /// Exporting to the Downloads folder or Files failed.
  exportFailed,
}

/// A scan failure carrying only its [kind]. Detail for diagnostics may be the
/// masked [detail] category, never a path or a document name.
class ScannerException implements Exception {
  const ScannerException(this.kind, [this.detail]);

  final ScannerFailure kind;
  final String? detail;

  @override
  String toString() => 'ScannerException(${kind.name})';
}

/// Where a scanner output lives.
enum ScanSourceKind {
  /// A path the app can open directly.
  file,

  /// An Android `content://` URI that must be read through the platform.
  content,
}

/// One output of the scanner: a `file://` URI, a plain absolute path, or a
/// `content://` URI.
class ScanSource {
  const ScanSource._(this.uri, this.kind);

  final String uri;
  final ScanSourceKind kind;

  /// Reads a value the scanner returned. Throws a [ScannerException] for
  /// anything that is not a file or content location (an empty string, a web
  /// address, a relative path).
  factory ScanSource.parse(Object? value) {
    if (value is! String) {
      throw const ScannerException(ScannerFailure.malformedResult, 'source');
    }
    final text = value.trim();
    if (text.isEmpty) {
      throw const ScannerException(ScannerFailure.malformedResult, 'source');
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('content://')) {
      return ScanSource._(text, ScanSourceKind.content);
    }
    if (lower.startsWith('file://')) {
      return ScanSource._(text, ScanSourceKind.file);
    }
    // A plain absolute path (POSIX, or a drive-letter path in a Windows test).
    final absolute = text.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(text) ||
        text.startsWith(r'\\');
    if (absolute && !text.contains('://')) {
      return ScanSource._(text, ScanSourceKind.file);
    }
    throw const ScannerException(ScannerFailure.malformedResult, 'scheme');
  }

  /// The local path of a file source, with `%20` and the like decoded.
  String get localPath {
    if (uri.toLowerCase().startsWith('file://')) {
      return Uri.parse(uri).toFilePath();
    }
    return uri;
  }
}

/// What the scanner returned, once its raw answer is understood.
sealed class ScanOutput {
  const ScanOutput();
}

/// One PDF. [reportedPageCount] is what the scanner said; the Scanner always
/// counts the pages of the file itself.
class ScanPdfOutput extends ScanOutput {
  const ScanPdfOutput(this.source, {this.reportedPageCount});

  final ScanSource source;
  final int? reportedPageCount;
}

/// Image pages in the order the scanner returned them.
class ScanImagesOutput extends ScanOutput {
  const ScanImagesOutput(this.sources, {this.reportedCount});

  final List<ScanSource> sources;
  final int? reportedCount;
}

/// Turns the scanner plugin's answer into a [ScanOutput]. The plugin answers
/// differently per platform and version: a map with `pdfUri` (Android PDF), a
/// bare path string (iPhone PDF), a map with `images` (Android images; older
/// versions used `Uri`/`Count`), or a list of paths (iPhone images). This is
/// the one place that knows those shapes.
class ScanResultParser {
  const ScanResultParser._();

  /// Returns null when the user cancelled (the plugin answers null). Throws a
  /// [ScannerException] for an answer that is not what [expected] asks for.
  static ScanOutput? parse(Object? raw, {required ExportFormat expected}) {
    if (raw == null) return null;
    return expected == ExportFormat.pdf ? _parsePdf(raw) : _parseImages(raw);
  }

  static ScanOutput _parsePdf(Object raw) {
    if (raw is String) {
      return ScanPdfOutput(ScanSource.parse(raw));
    }
    if (raw is Map) {
      final pdf = raw['pdfUri'];
      if (pdf == null) {
        if (raw.containsKey('images') || raw.containsKey('Uri')) {
          throw const ScannerException(ScannerFailure.wrongFormat, 'images');
        }
        throw const ScannerException(ScannerFailure.malformedResult, 'map');
      }
      return ScanPdfOutput(
        ScanSource.parse(pdf),
        reportedPageCount: _positiveInt(raw['pageCount']),
      );
    }
    if (raw is List) {
      // A list is image output: it is never silently reduced to its first page.
      throw const ScannerException(ScannerFailure.wrongFormat, 'list');
    }
    throw const ScannerException(ScannerFailure.malformedResult, 'type');
  }

  static ScanOutput _parseImages(Object raw) {
    if (raw is List) {
      return ScanImagesOutput(_sources(raw));
    }
    if (raw is String) {
      return ScanImagesOutput(<ScanSource>[ScanSource.parse(raw)]);
    }
    if (raw is Map) {
      if (raw.containsKey('pdfUri') &&
          !raw.containsKey('images') &&
          !raw.containsKey('Uri')) {
        throw const ScannerException(ScannerFailure.wrongFormat, 'pdf');
      }
      final list = raw['images'] ?? raw['Uri'];
      if (list is! List) {
        throw const ScannerException(ScannerFailure.malformedResult, 'map');
      }
      return ScanImagesOutput(
        _sources(list),
        reportedCount: _positiveInt(raw['count'] ?? raw['Count']),
      );
    }
    throw const ScannerException(ScannerFailure.malformedResult, 'type');
  }

  static List<ScanSource> _sources(List<dynamic> list) {
    if (list.isEmpty) {
      throw const ScannerException(ScannerFailure.emptyOutput, 'images');
    }
    return <ScanSource>[for (final item in list) ScanSource.parse(item)];
  }

  static int? _positiveInt(Object? value) {
    return value is int && value > 0 ? value : null;
  }
}
