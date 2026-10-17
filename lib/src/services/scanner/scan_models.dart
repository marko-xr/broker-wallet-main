/// What kind of paper the user says they are scanning. The native scanner does
/// not change with it: it is a label the user chooses, kept with the document
/// and used for the default file name.
enum ScanMode {
  document,
  receipt,
  businessCard,
  passport,
  book,
  magazine,
}

/// One PDF holding every page, or one image file per page.
enum ExportFormat {
  pdf,
  images,
}

/// The quality choices the settings sheet lists. Neither platform's scanner
/// accepts a quality from the app (Android's Google scanner and iPhone's
/// VisionKit pick their own), so the sheet shows them as unavailable and nothing
/// reads the value.
enum ScanQuality {
  low,
  medium,
  high,
  ultra,
}

/// The only file kinds a scan can produce and the Scanner stores.
enum ScanFileKind {
  pdf('pdf', 'application/pdf', ExportFormat.pdf),
  jpeg('jpg', 'image/jpeg', ExportFormat.images),
  png('png', 'image/png', ExportFormat.images);

  const ScanFileKind(this.extension, this.mimeType, this.format);

  final String extension;
  final String mimeType;
  final ExportFormat format;

  static ScanFileKind? fromExtension(String extension) {
    final lower = extension.toLowerCase();
    for (final kind in values) {
      if (kind.extension == lower) return kind;
    }
    return null;
  }
}

/// A saved scan, as the Scanner lists it. [fileName] is the private stored
/// file's own name (an internal id plus the extension) and never a name the
/// user typed; [name] is the user-visible title.
class ScannerDocument {
  const ScannerDocument({
    required this.id,
    required this.fileName,
    required this.name,
    required this.scanType,
    required this.format,
    required this.mimeType,
    required this.createdAt,
    required this.fileSize,
    required this.pageCount,
    this.batchId,
    this.batchIndex = 0,
  });

  final String id;
  final String fileName;
  final String name;
  final ScanMode scanType;
  final ExportFormat format;
  final String mimeType;
  final DateTime createdAt;
  final int fileSize;

  /// The page count read from the stored file itself.
  final int pageCount;

  /// Image scans are one document per page; the pages of one scan share a
  /// [batchId] and keep their order in [batchIndex].
  final String? batchId;
  final int batchIndex;

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1);
  }

  /// The name an exported or shared copy carries: the title plus the extension.
  String get exportFileName => '$name.$extension';

  ScannerDocument copyWith({String? name, int? fileSize}) {
    return ScannerDocument(
      id: id,
      fileName: fileName,
      name: name ?? this.name,
      scanType: scanType,
      format: format,
      mimeType: mimeType,
      createdAt: createdAt,
      fileSize: fileSize ?? this.fileSize,
      pageCount: pageCount,
      batchId: batchId,
      batchIndex: batchIndex,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fileName': fileName,
        'name': name,
        'scanType': scanType.name,
        'format': format.name,
        'mimeType': mimeType,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'fileSize': fileSize,
        'pageCount': pageCount,
        if (batchId != null) 'batchId': batchId,
        'batchIndex': batchIndex,
      };

  /// Reads one stored record. Throws a [FormatException] for anything that is
  /// not a well-formed record, so a damaged entry is never half trusted.
  factory ScannerDocument.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Scanner record is not an object');
    }
    String text(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Scanner record has no $key');
      }
      return value;
    }

    int whole(String key, {int minimum = 0}) {
      final value = json[key];
      if (value is! int || value < minimum) {
        throw FormatException('Scanner record has a bad $key');
      }
      return value;
    }

    final fileName = text('fileName');
    if (!ScannerNaming.isStoredFileName(fileName)) {
      throw const FormatException('Scanner record names an unsafe file');
    }
    final format = ExportFormat.values.where((e) => e.name == json['format']);
    final mode = ScanMode.values.where((e) => e.name == json['scanType']);
    final batchId = json['batchId'];
    return ScannerDocument(
      id: text('id'),
      fileName: fileName,
      name: text('name'),
      scanType: mode.isEmpty ? ScanMode.document : mode.first,
      format: format.isEmpty
          ? throw const FormatException('Scanner record has a bad format')
          : format.first,
      mimeType: text('mimeType'),
      createdAt: DateTime.parse(text('createdAt')),
      fileSize: whole('fileSize'),
      pageCount: whole('pageCount', minimum: 1),
      batchId: batchId is String && batchId.isNotEmpty ? batchId : null,
      batchIndex: json['batchIndex'] is int ? json['batchIndex'] as int : 0,
    );
  }
}

/// Names: what the user sees, and what the private store writes.
class ScannerNaming {
  const ScannerNaming._();

  static const int maxNameRunes = 80;

  static final RegExp _storedFileName =
      RegExp(r'^[A-Za-z0-9_-]{1,64}\.(pdf|jpg|png)$');

  /// Whether [fileName] is a name the private store itself would have made.
  /// A record naming anything else (a path, a parent folder, another
  /// extension) is refused, so a damaged or edited index cannot point the
  /// Scanner at a file outside its own folder.
  static bool isStoredFileName(String fileName) =>
      _storedFileName.hasMatch(fileName);

  static final RegExp _forbidden = RegExp(
    r'[\u0000-\u001F\u007F\\/:*?"<>|\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );

  /// A title safe to show and to use as an exported file name: Unicode (Arabic
  /// included) is kept; path separators, control characters, characters Android
  /// and iOS refuse in names and bidirectional overrides are removed; runs of
  /// white space collapse; leading and trailing dots and spaces go. Returns null
  /// when nothing usable is left.
  static String? sanitizeDisplayName(String raw) {
    var value = raw.replaceAll(_forbidden, ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (value.isEmpty) return null;
    final runes = value.runes.toList();
    if (runes.length > maxNameRunes) {
      value = String.fromCharCodes(runes.take(maxNameRunes)).trim();
      value = value.replaceAll(RegExp(r'[.\s]+$'), '');
    }
    return value.isEmpty ? null : value;
  }

  /// The title that is not yet used by any of [taken] (compared without regard
  /// to case): [base] itself, or "base (2)", "base (3)"...
  static String uniqueName(String base, Iterable<String> taken) {
    final used = <String>{for (final name in taken) name.toLowerCase()};
    if (!used.contains(base.toLowerCase())) return base;
    var counter = 2;
    while (used.contains('$base ($counter)'.toLowerCase())) {
      counter++;
    }
    return '$base ($counter)';
  }

  /// The default title of a new scan, e.g. "document_scan_20261017_1432".
  static String defaultName(ScanMode mode, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    return '${mode.name}_scan_$stamp';
  }
}
