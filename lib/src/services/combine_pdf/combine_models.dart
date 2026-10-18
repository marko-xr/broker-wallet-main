import 'package:broker_wallet/src/services/scanner/scan_models.dart';

/// Why selecting, combining, storing or exporting PDFs did not work. The view
/// maps each one to a localized message; none carries platform text, a path or
/// anything from a document.
enum CombinePdfFailure {
  /// The signed-in account is not known (signed out, or switched away).
  signedOut,

  /// A combine, pick or library action is already running.
  busy,

  /// The user cancelled the combine. Nothing was stored or counted.
  cancelled,

  /// The account changed while the work was running, so its result was dropped.
  accountChanged,

  /// Fewer than two files are selected.
  tooFewFiles,

  /// No page is selected at all.
  noPages,

  /// A selected file has every one of its pages removed, so it would
  /// silently contribute nothing.
  fileHasNoPages,

  /// A file is gone or cannot be opened.
  missingSource,

  /// A file is empty.
  emptySource,

  /// A file is not a readable PDF (damaged, truncated, not a PDF).
  corruptSource,

  /// A file is password protected / encrypted. It is refused, never opened.
  encryptedSource,

  /// A file carries a digital signature that a combined copy would break.
  signedSource,

  /// A file is larger than the limit the phone can combine safely.
  tooLargeSource,

  /// The selection as a whole is larger than the phone can combine safely.
  selectionTooLarge,

  /// A file changed on disk after it was selected.
  sourceChanged,

  /// The combined file did not verify (page count, page order or readability).
  outputInvalid,

  /// The combine itself failed.
  mergeFailed,

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

  /// Permission to write to the phone's public storage was not given.
  permissionDenied,

  /// Exporting to the Downloads folder or Files failed.
  exportFailed,
}

/// A failure carrying only its [kind] (and, for a problem with one selected
/// file, the [sourceId] of that file). Never a path, a name or document text.
class CombinePdfException implements Exception {
  const CombinePdfException(this.kind, {this.sourceId, this.detail});

  final CombinePdfFailure kind;
  final String? sourceId;

  /// A fixed diagnostic category, never user data.
  final String? detail;

  @override
  String toString() => 'CombinePdfException(${kind.name})';
}

/// What a PDF holds that a combined copy cannot carry over unchanged. Read from
/// the file itself while it is checked, so the user is told before combining.
class CombineFeatures {
  const CombineFeatures({
    this.hasSignatures = false,
    this.hasFormFields = false,
    this.hasAnnotations = false,
    this.hasBookmarks = false,
  });

  /// A signed signature field. The file is refused: a combined copy would not
  /// carry a valid signature and must not look as if it did.
  final bool hasSignatures;

  /// Fillable form fields. They are flattened: the values stay on the page as
  /// plain content and the fields stop being editable.
  final bool hasFormFields;

  /// Links, comments or markup. Markup is flattened onto the page; links stay
  /// as text but stop being clickable.
  final bool hasAnnotations;

  /// A bookmark outline. It is not carried into the combined file.
  final bool hasBookmarks;

  /// Whether combining changes anything the user could notice beyond joining
  /// pages.
  bool get changesOnCombine => hasFormFields || hasAnnotations || hasBookmarks;

  Map<String, Object?> toMap() => <String, Object?>{
        'sig': hasSignatures,
        'form': hasFormFields,
        'annot': hasAnnotations,
        'bm': hasBookmarks,
      };

  factory CombineFeatures.fromMap(Map<Object?, Object?> map) => CombineFeatures(
        hasSignatures: map['sig'] == true,
        hasFormFields: map['form'] == true,
        hasAnnotations: map['annot'] == true,
        hasBookmarks: map['bm'] == true,
      );
}

/// One PDF the user selected, as the file itself proved it. [path] is a private
/// copy (the file picker's cache copy), never the user's original.
class CombineSource {
  const CombineSource({
    required this.id,
    required this.path,
    required this.displayName,
    required this.size,
    required this.pageCount,
    this.features = const CombineFeatures(),
  });

  final String id;
  final String path;

  /// The picked file's own name, for display only.
  final String displayName;
  final int size;

  /// The real page count read from the file.
  final int pageCount;
  final CombineFeatures features;
}

/// One page in the pending combine: which page of which source, and how many
/// extra quarter turns (clockwise) the user asked for.
class CombinePageRef {
  const CombinePageRef({
    required this.sourceId,
    required this.pageIndex,
    this.quarterTurns = 0,
  });

  final String sourceId;

  /// Zero-based page of the source.
  final int pageIndex;

  /// 0..3, added to the page's own rotation.
  final int quarterTurns;

  CombinePageRef withQuarterTurns(int turns) => CombinePageRef(
      sourceId: sourceId,
      pageIndex: pageIndex,
      quarterTurns: ((turns % 4) + 4) % 4);

  @override
  bool operator ==(Object other) =>
      other is CombinePageRef &&
      other.sourceId == sourceId &&
      other.pageIndex == pageIndex &&
      other.quarterTurns == quarterTurns;

  @override
  int get hashCode => Object.hash(sourceId, pageIndex, quarterTurns);
}

/// A combined PDF kept for the signed-in account. [fileName] is the private
/// stored file's own name (an internal id plus `.pdf`) and never a name the
/// user typed; [name] is the visible title.
class CombinedPdf {
  const CombinedPdf({
    required this.id,
    required this.fileName,
    required this.name,
    required this.createdAt,
    required this.fileSize,
    required this.pageCount,
  });

  final String id;
  final String fileName;
  final String name;
  final DateTime createdAt;
  final int fileSize;

  /// The page count read from the stored file itself.
  final int pageCount;

  /// The name an exported or shared copy carries.
  String get exportFileName => '$name.pdf';

  CombinedPdf copyWith({String? name}) => CombinedPdf(
        id: id,
        fileName: fileName,
        name: name ?? this.name,
        createdAt: createdAt,
        fileSize: fileSize,
        pageCount: pageCount,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fileName': fileName,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'fileSize': fileSize,
        'pageCount': pageCount,
      };

  /// Reads one stored record. Throws a [FormatException] for anything that is
  /// not a well-formed record, so a damaged entry is never half trusted.
  factory CombinedPdf.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Combine record is not an object');
    }
    String text(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Combine record has no $key');
      }
      return value;
    }

    int whole(String key, {int minimum = 0}) {
      final value = json[key];
      if (value is! int || value < minimum) {
        throw FormatException('Combine record has a bad $key');
      }
      return value;
    }

    final fileName = text('fileName');
    if (!CombineNaming.isStoredFileName(fileName)) {
      throw const FormatException('Combine record names an unsafe file');
    }
    return CombinedPdf(
      id: text('id'),
      fileName: fileName,
      name: text('name'),
      createdAt: DateTime.parse(text('createdAt')),
      fileSize: whole('fileSize'),
      pageCount: whole('pageCount', minimum: 1),
    );
  }
}

/// Names for combined PDFs. Titles follow the Scanner's rules (Unicode kept,
/// separators and bidi controls removed, unique per account); the stored file
/// is always an internal id.
class CombineNaming {
  const CombineNaming._();

  static final RegExp _storedFileName = RegExp(r'^[A-Za-z0-9_-]{1,64}\.pdf$');

  static bool isStoredFileName(String fileName) =>
      _storedFileName.hasMatch(fileName);

  static String? sanitizeDisplayName(String raw) =>
      ScannerNaming.sanitizeDisplayName(raw);

  static String uniqueName(String base, Iterable<String> taken) =>
      ScannerNaming.uniqueName(base, taken);

  /// The default title of a new combined PDF, e.g. "combined_20261018_1432".
  static String defaultName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'combined_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}';
  }
}

/// Limits that keep a combine inside what a phone can hold. The PDF library
/// loads whole documents, so these are about memory, not about policy.
class CombineLimits {
  const CombineLimits._();

  /// The largest single PDF that is opened.
  static const int maxSourceBytes = 80 * 1024 * 1024;

  /// The most bytes of source PDFs one combine accepts.
  static const int maxTotalSourceBytes = 200 * 1024 * 1024;

  /// The most pages one combined file may have.
  static const int maxTotalPages = 1500;

  /// The most files in one combine.
  static const int maxSources = 30;
}
