import 'dart:typed_data';

import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/signature/signature_geometry.dart';

/// Why opening, placing, saving or exporting a signed document did not work.
/// The view maps each one to a localized message; none carries platform text, a
/// path or anything from a document.
enum SignatureFailure {
  /// The signed-in account is not known (signed out, or switched away).
  signedOut,

  /// A pick, an open, a save or a library action is already running.
  busy,

  /// The user cancelled. Nothing was stored or counted.
  cancelled,

  /// The account changed while the work was running, so its result was dropped.
  accountChanged,

  /// The picked file is gone or cannot be opened.
  missingSource,

  /// The picked file is empty.
  emptySource,

  /// The picked file is not a readable PDF (damaged, truncated, not a PDF).
  corruptSource,

  /// The picked file is password protected / encrypted. It is refused, never
  /// opened or bypassed.
  encryptedSource,

  /// The picked file already carries a digital signature that adding anything
  /// would put at risk.
  signedSource,

  /// The picked file is larger than the phone can edit safely.
  tooLargeSource,

  /// The picked file has more pages than the tool accepts.
  tooManyPages,

  /// A page's size or boxes cannot be mapped to the screen exactly, so a
  /// placement could not be trusted. The file is refused rather than guessed.
  geometryUnsupported,

  /// The source file changed on disk after it was opened.
  sourceChanged,

  /// There is nothing to save: no signature, initials, date or text is placed.
  noPlacements,

  /// A placement is outside its page or has no usable size.
  invalidPlacement,

  /// A signature, initials, date or text image could not be made.
  stampFailed,

  /// More items than one document may carry.
  tooManyItems,

  /// The signed copy did not verify (page count, geometry, forms, links).
  outputInvalid,

  /// Writing the signed copy failed.
  writeFailed,

  /// The phone is out of storage space.
  storageFull,

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

  /// Something went wrong that none of the reasons above describes (a bug,
  /// not a problem with the file). It is reported as such instead of being
  /// blamed on the file.
  unexpected,
}

/// A failure carrying only its [kind]. Never a path, a name or document text.
class SignatureException implements Exception {
  const SignatureException(this.kind, {this.detail});

  final SignatureFailure kind;

  /// A fixed diagnostic category, never user data.
  final String? detail;

  @override
  String toString() => 'SignatureException(${kind.name})';
}

/// What a PDF holds that a signed copy has to leave alone. Read from the file
/// itself while it is checked.
class SignatureFeatures {
  const SignatureFeatures({
    this.hasSignatures = false,
    this.hasFormFields = false,
    this.hasAnnotations = false,
  });

  /// A digital (certificate based) signature. The file is refused: anything
  /// added after it could invalidate it, and a visible stamp must never look as
  /// if it kept it valid.
  final bool hasSignatures;

  /// Fillable form fields. They are left exactly as they are.
  final bool hasFormFields;

  /// Links, comments or markup. They are left exactly as they are.
  final bool hasAnnotations;
}

/// What a PDF proved to be, read from the file itself.
class SignatureAnalysis {
  const SignatureAnalysis({
    required this.size,
    required this.pageCount,
    required this.pages,
    required this.features,
    this.formFieldCount = 0,
    this.annotationCounts = const <int>[],
  });

  final int size;
  final int pageCount;

  /// The geometry of every page, in page order.
  final List<PageGeometry> pages;
  final SignatureFeatures features;

  /// How many form fields the file has. A signed copy must have the same.
  final int formFieldCount;

  /// How many annotations (links, comments, markup) each page has. A signed copy
  /// must have the same on every page.
  final List<int> annotationCounts;
}

/// The visible size of one page, in points, as the page renderer draws it.
class RenderedPageSize {
  const RenderedPageSize(this.width, this.height);

  final double width;
  final double height;
}

/// Limits that keep editing inside what a phone can hold.
class SignatureLimits {
  const SignatureLimits._();

  /// The largest source PDF that is opened. The PDF library loads whole files.
  static const int maxSourceBytes = 50 * 1024 * 1024;

  /// The largest PDF the store reads back (a stored copy is a source plus the
  /// appended signatures).
  static const int maxStoredBytes = 120 * 1024 * 1024;

  /// The most pages a source may have.
  static const int maxPages = 1000;

  /// The most placed items one document may carry.
  static const int maxItems = 100;

  /// The largest single stamp image, as PNG bytes.
  static const int maxStampBytes = 4 * 1024 * 1024;

  /// The largest stamp image side, in pixels.
  static const int maxStampPixels = 4096;
}

/// What a placed item is.
enum StampKind { signature, initials, date, text }

/// One stroke point of a drawn signature, in the pad's own pixels.
class InkPoint {
  const InkPoint(this.x, this.y, {this.isStrokeStart = false});

  final double x;
  final double y;

  /// The finger went down here: a new stroke begins.
  final bool isStrokeStart;

  @override
  bool operator ==(Object other) =>
      other is InkPoint &&
      other.x == x &&
      other.y == y &&
      other.isStrokeStart == isStrokeStart;

  @override
  int get hashCode => Object.hash(x, y, isStrokeStart);
}

/// A drawn signature or initials as the user made it: the strokes, the pen and
/// the pad they were drawn on. Kept so that editing a signature restores it, not
/// just its picture.
class SignatureDrawing {
  const SignatureDrawing({
    required this.points,
    required this.colorValue,
    required this.strokeWidth,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  final List<InkPoint> points;

  /// The pen colour as an ARGB integer.
  final int colorValue;
  final double strokeWidth;

  /// The size of the pad the points were drawn on.
  final double canvasWidth;
  final double canvasHeight;

  bool get isEmpty => points.isEmpty;

  /// The points split into strokes: a new one begins at every point that says so.
  /// The pad's own painter splits its points the same way, so the exported image
  /// shows what the user saw.
  List<List<InkPoint>> get strokes {
    final result = <List<InkPoint>>[];
    var current = <InkPoint>[];
    for (final point in points) {
      if (point.isStrokeStart && current.isNotEmpty) {
        result.add(current);
        current = <InkPoint>[];
      }
      current.add(point);
    }
    if (current.isNotEmpty) result.add(current);
    return result;
  }

  SignatureDrawing copyWith({
    List<InkPoint>? points,
    int? colorValue,
    double? strokeWidth,
    double? canvasWidth,
    double? canvasHeight,
  }) =>
      SignatureDrawing(
        points: points ?? this.points,
        colorValue: colorValue ?? this.colorValue,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        canvasWidth: canvasWidth ?? this.canvasWidth,
        canvasHeight: canvasHeight ?? this.canvasHeight,
      );

  /// The smallest rectangle holding every point, or null when there are none.
  ({double left, double top, double right, double bottom})? get bounds {
    if (points.isEmpty) return null;
    var left = points.first.x;
    var right = left;
    var top = points.first.y;
    var bottom = top;
    for (final point in points) {
      if (point.x < left) left = point.x;
      if (point.x > right) right = point.x;
      if (point.y < top) top = point.y;
      if (point.y > bottom) bottom = point.y;
    }
    return (left: left, top: top, right: right, bottom: bottom);
  }

  /// Whether the ink is something a person would call a signature: more than a
  /// stray dot or a tap. A pad with only a dot is treated as empty.
  bool get hasMeaningfulInk {
    final box = bounds;
    if (box == null) return false;
    final extent = (box.right - box.left) > (box.bottom - box.top)
        ? box.right - box.left
        : box.bottom - box.top;
    return extent >= minimumInkExtent;
  }

  /// The least extent (in pad pixels) of ink that counts as a signature.
  static const double minimumInkExtent = 12;
}

/// The image of one signature, initials, date or text, ready to be placed any
/// number of times. The image is a transparent PNG; its pixel size fixes the
/// aspect ratio, so a placed item can never be stretched.
class StampAsset {
  const StampAsset({
    required this.id,
    required this.kind,
    required this.png,
    required this.pixelWidth,
    required this.pixelHeight,
    this.label,
    this.drawing,
    this.colorValue,
  });

  final String id;
  final StampKind kind;

  /// A PNG with an alpha channel and a transparent background.
  final Uint8List png;
  final int pixelWidth;
  final int pixelHeight;

  /// The text of a typed item (initials, date or text), kept so it can be edited.
  final String? label;

  /// The strokes of a drawn signature or initials, kept so it can be edited.
  final SignatureDrawing? drawing;

  /// The colour of a typed item, as an ARGB integer.
  final int? colorValue;

  double get aspect => pixelHeight == 0 ? 1.0 : pixelWidth / pixelHeight;

  bool get isDrawn => drawing != null;

  /// A signature and initials count as signatures in the document's metadata;
  /// a date and a text do not.
  bool get countsAsSignature =>
      kind == StampKind.signature || kind == StampKind.initials;

  StampAsset copyWith({
    String? id,
    Uint8List? png,
    int? pixelWidth,
    int? pixelHeight,
    String? label,
    SignatureDrawing? drawing,
    int? colorValue,
  }) =>
      StampAsset(
        id: id ?? this.id,
        kind: kind,
        png: png ?? this.png,
        pixelWidth: pixelWidth ?? this.pixelWidth,
        pixelHeight: pixelHeight ?? this.pixelHeight,
        label: label ?? this.label,
        drawing: drawing ?? this.drawing,
        colorValue: colorValue ?? this.colorValue,
      );
}

/// One item placed on one page: which image, which page, and the rectangle it
/// covers in the page's visible points (top-left origin, y down). A placed item
/// is independent of every other one, including other placements of the same
/// image.
class PlacedStamp {
  const PlacedStamp({
    required this.id,
    required this.assetId,
    required this.pageIndex,
    required this.rect,
  });

  final String id;
  final String assetId;

  /// Zero-based page.
  final int pageIndex;
  final PageRect rect;

  PlacedStamp copyWith({String? assetId, int? pageIndex, PageRect? rect}) =>
      PlacedStamp(
        id: id,
        assetId: assetId ?? this.assetId,
        pageIndex: pageIndex ?? this.pageIndex,
        rect: rect ?? this.rect,
      );

  @override
  bool operator ==(Object other) =>
      other is PlacedStamp &&
      other.id == id &&
      other.assetId == assetId &&
      other.pageIndex == pageIndex &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(id, assetId, pageIndex, rect);
}

/// A signed document kept for the signed-in account. [fileName] is the private
/// stored file's own name (an internal id plus `.pdf`) and never a name the user
/// typed; [name] is the visible title.
class SignedDocument {
  const SignedDocument({
    required this.id,
    required this.fileName,
    required this.name,
    required this.createdAt,
    required this.fileSize,
    required this.pageCount,
    required this.signatureCount,
    required this.itemCount,
  });

  final String id;
  final String fileName;
  final String name;
  final DateTime createdAt;
  final int fileSize;

  /// The page count read from the stored file itself.
  final int pageCount;

  /// Signatures and initials placed in the document.
  final int signatureCount;

  /// Every placed item: signatures, initials, dates and texts.
  final int itemCount;

  /// The name an exported or shared copy carries.
  String get exportFileName => '$name.pdf';

  SignedDocument copyWith({String? name}) => SignedDocument(
        id: id,
        fileName: fileName,
        name: name ?? this.name,
        createdAt: createdAt,
        fileSize: fileSize,
        pageCount: pageCount,
        signatureCount: signatureCount,
        itemCount: itemCount,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fileName': fileName,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'fileSize': fileSize,
        'pageCount': pageCount,
        'signatureCount': signatureCount,
        'itemCount': itemCount,
      };

  /// Reads one stored record. Throws a [FormatException] for anything that is
  /// not a well-formed record, so a damaged entry is never half trusted.
  factory SignedDocument.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Signed record is not an object');
    }
    String text(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Signed record has no $key');
      }
      return value;
    }

    int whole(String key, {int minimum = 0}) {
      final value = json[key];
      if (value is! int || value < minimum) {
        throw FormatException('Signed record has a bad $key');
      }
      return value;
    }

    final fileName = text('fileName');
    if (!SignatureNaming.isStoredFileName(fileName)) {
      throw const FormatException('Signed record names an unsafe file');
    }
    return SignedDocument(
      id: text('id'),
      fileName: fileName,
      name: text('name'),
      createdAt: DateTime.parse(text('createdAt')),
      fileSize: whole('fileSize'),
      pageCount: whole('pageCount', minimum: 1),
      signatureCount: whole('signatureCount'),
      itemCount: whole('itemCount'),
    );
  }
}

/// Names for signed documents. Titles follow the Scanner's rules (Unicode kept,
/// separators and bidi controls removed, unique per account); the stored file is
/// always an internal id.
class SignatureNaming {
  const SignatureNaming._();

  static final RegExp _storedFileName = RegExp(r'^[A-Za-z0-9_-]{1,64}\.pdf$');

  static bool isStoredFileName(String fileName) =>
      _storedFileName.hasMatch(fileName);

  static String? sanitizeDisplayName(String raw) =>
      ScannerNaming.sanitizeDisplayName(raw);

  static String uniqueName(String base, Iterable<String> taken) =>
      ScannerNaming.uniqueName(base, taken);

  /// The default title of a signed copy: the picked file's own name without
  /// `.pdf`, then [suffix] ("signed"). Falls back to "signed_20261018_1432".
  static String defaultName(String? pickedName, String suffix, DateTime now) {
    var base = (pickedName ?? '').trim();
    if (base.toLowerCase().endsWith('.pdf')) {
      base = base.substring(0, base.length - 4);
    }
    final cleaned = sanitizeDisplayName(base);
    if (cleaned != null) {
      final combined = sanitizeDisplayName('$cleaned - $suffix');
      if (combined != null) return combined;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return 'signed_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}';
  }
}

/// What is true of a typed text before it becomes an image.
class StampText {
  const StampText._();

  static const int maxTextRunes = 80;
  static const int maxInitialsRunes = 6;

  static final RegExp _controls =
      RegExp(r'[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E\u2066-\u2069]');

  /// The text with control and bidirectional override characters removed and
  /// white space collapsed; null when nothing visible is left or it is longer
  /// than [maxRunes] letters.
  static String? clean(String raw, {required int maxRunes}) {
    final value =
        raw.replaceAll(_controls, ' ').replaceAll(RegExp(r'\s+'), ' ');
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.runes.length > maxRunes) return null;
    return trimmed;
  }

  /// Whether [text] reads right to left: its first strong letter is Arabic,
  /// Hebrew or another right to left script. A text without letters reads left to
  /// right.
  static bool isRightToLeft(String text) {
    for (final rune in text.runes) {
      if (_isRtlLetter(rune)) return true;
      if (_isLtrLetter(rune)) return false;
    }
    return false;
  }

  static bool _isRtlLetter(int r) =>
      (r >= 0x0590 && r <= 0x08FF) ||
      (r >= 0xFB1D && r <= 0xFDFF) ||
      (r >= 0xFE70 && r <= 0xFEFF) ||
      (r >= 0x10800 && r <= 0x10FFF) ||
      (r >= 0x1E800 && r <= 0x1EFFF);

  static bool _isLtrLetter(int r) =>
      (r >= 0x41 && r <= 0x5A) ||
      (r >= 0x61 && r <= 0x7A) ||
      (r >= 0xC0 && r <= 0x24F) ||
      (r >= 0x370 && r <= 0x58F) ||
      (r >= 0x900 && r <= 0x1FFF) ||
      (r >= 0x3040 && r <= 0xD7FF);
}

/// The date shown by a date stamp, in digits so it reads the same on every
/// page and in every viewer.
class StampDate {
  const StampDate._();

  static const List<String> _monthsEn = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _monthsAr = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  /// "18/10/2026".
  static String numeric(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  /// "18 Oct 2026" or "18 أكتوبر 2026".
  static String long(DateTime date, {required bool arabic}) {
    final months = arabic ? _monthsAr : _monthsEn;
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
