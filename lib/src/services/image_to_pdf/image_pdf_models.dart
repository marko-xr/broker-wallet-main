import 'dart:typed_data';

import 'package:broker_wallet/src/services/scanner/scan_models.dart';

/// The page sizes the tool offers. [custom] uses the width and height the user
/// typed in [ImagePdfSettings].
enum PdfPageSize { a4, letter, legal, a3, a5, custom }

enum PdfOrientation { portrait, landscape, auto }

/// How much of the picture's detail the PDF keeps, as a print resolution at the
/// size the picture is placed on the page (never above the original's own).
enum ImageQuality { low, medium, high, ultra }

enum PdfLayout { fitToPage, originalSize, centerFit, tileMultiple }

/// How hard the pictures are compressed. [none] never re-compresses with loss:
/// an upright JPEG is kept as it is (only its metadata is removed) and anything
/// that has to change is stored losslessly, so the file can be large.
enum CompressionLevel { none, low, medium, high, maximum }

/// Why selecting, converting, storing or exporting did not work. The view maps
/// each one to a localized message; none carries platform text, a path or
/// anything from a picture.
enum ImagePdfFailure {
  /// The signed-in account is not known (signed out, or switched away).
  signedOut,

  /// A pick, conversion or library action is already running.
  busy,

  /// The user cancelled. Nothing was stored or counted.
  cancelled,

  /// The account changed while the work was running, so its result was dropped.
  accountChanged,

  /// No picture is selected.
  noImages,

  /// More pictures than one PDF accepts.
  tooManyImages,

  /// Some pictures are still being checked.
  imagesNotReady,

  /// A picture is gone or cannot be opened.
  missingSource,

  /// A picture file is empty.
  emptySource,

  /// A picture is damaged or cannot be read completely.
  corruptSource,

  /// The picture's format is not one the tool can place in a PDF.
  unsupportedFormat,

  /// A picture file is larger than the phone can process safely.
  tooLargeSource,

  /// A picture has more pixels than the phone can process safely.
  tooManyPixels,

  /// A picture changed on disk after it was selected.
  sourceChanged,

  /// The finished PDF would be larger than the phone can build in memory.
  outputTooLarge,

  /// A setting is out of range (custom size, margin, watermark text).
  invalidSettings,

  /// Password protection is on but the password is empty, too short or uses
  /// characters other PDF viewers may not accept.
  invalidPassword,

  /// The finished file did not verify (pages, sizes, numbers, protection).
  outputInvalid,

  /// The conversion itself failed.
  buildFailed,

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

  /// Permission (camera, or public storage on old Android) was not given.
  permissionDenied,

  /// The system picker or camera could not deliver the picture.
  pickerFailed,

  /// Exporting to the Downloads folder or Files failed.
  exportFailed,
}

/// A failure carrying only its [kind] (and, for a problem with one picture, the
/// [sourceId] of that picture). Never a path, a name or picture content.
class ImagePdfException implements Exception {
  const ImagePdfException(this.kind, {this.sourceId, this.detail});

  final ImagePdfFailure kind;
  final String? sourceId;

  /// A fixed diagnostic category, never user data.
  final String? detail;

  @override
  String toString() => 'ImagePdfException(${kind.name})';
}

/// Limits that keep a conversion inside what a phone can hold. The picture
/// libraries decode whole images, so these are about memory, not policy.
class ImagePdfLimits {
  const ImagePdfLimits._();

  /// The most pictures one PDF accepts.
  static const int maxImages = 100;

  /// The largest single picture file that is opened.
  static const int maxSourceBytes = 100 * 1024 * 1024;

  /// The most pixels one picture may have (a 50 MP sensor, 8160 x 6144, fits).
  /// Decoding a rotated photograph holds it twice, about 300 MB at this size,
  /// which is the most a worker can be asked for.
  static const int maxPixels = 50500000;

  /// Custom page sides, in millimetres.
  static const double minCustomMm = 50;
  static const double maxCustomMm = 1000;

  /// The page margin, in millimetres.
  static const double maxMarginMm = 30;

  /// Password and watermark text lengths.
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 64;
  static const int maxWatermarkLength = 40;

  /// The most picture data one PDF holds while it is being built (it is kept
  /// in memory until the file is written).
  static const int maxOutputBytes = 300 * 1024 * 1024;

  /// Pictures per sheet that Tile Multiple offers.
  static const List<int> tileCounts = <int>[2, 4, 6];
}

/// Everything the user chooses about the PDF, except the pictures and the
/// password. The password is never part of this value: it is not stored,
/// compared or printed with the other settings.
class ImagePdfSettings {
  const ImagePdfSettings({
    this.pageSize = PdfPageSize.a4,
    this.customWidthMm = 210,
    this.customHeightMm = 297,
    this.orientation = PdfOrientation.auto,
    this.quality = ImageQuality.high,
    this.compression = CompressionLevel.medium,
    this.layout = PdfLayout.fitToPage,
    this.tilesPerPage = 4,
    this.marginMm = 7,
    this.pageNumbers = false,
    this.timestamp = false,
    this.watermark = false,
    this.watermarkText = '',
    this.coverPage = false,
    this.passwordProtect = false,
  });

  final PdfPageSize pageSize;

  /// The custom page, as typed (portrait or not): the shorter side is the
  /// portrait width.
  final double customWidthMm;
  final double customHeightMm;
  final PdfOrientation orientation;
  final ImageQuality quality;
  final CompressionLevel compression;
  final PdfLayout layout;

  /// Pictures per sheet for [PdfLayout.tileMultiple] (2, 4 or 6).
  final int tilesPerPage;

  /// The margin on all four sides, in millimetres (the PDF itself is in points;
  /// 1 mm is 72 / 25.4 points).
  final double marginMm;
  final bool pageNumbers;
  final bool timestamp;
  final bool watermark;

  /// Empty means the app's own name.
  final String watermarkText;
  final bool coverPage;
  final bool passwordProtect;

  static const String defaultWatermark = 'Broker Wallet';

  String get effectiveWatermark {
    final text = watermarkText.trim();
    return text.isEmpty ? defaultWatermark : text;
  }

  ImagePdfSettings copyWith({
    PdfPageSize? pageSize,
    double? customWidthMm,
    double? customHeightMm,
    PdfOrientation? orientation,
    ImageQuality? quality,
    CompressionLevel? compression,
    PdfLayout? layout,
    int? tilesPerPage,
    double? marginMm,
    bool? pageNumbers,
    bool? timestamp,
    bool? watermark,
    String? watermarkText,
    bool? coverPage,
    bool? passwordProtect,
  }) =>
      ImagePdfSettings(
        pageSize: pageSize ?? this.pageSize,
        customWidthMm: customWidthMm ?? this.customWidthMm,
        customHeightMm: customHeightMm ?? this.customHeightMm,
        orientation: orientation ?? this.orientation,
        quality: quality ?? this.quality,
        compression: compression ?? this.compression,
        layout: layout ?? this.layout,
        tilesPerPage: tilesPerPage ?? this.tilesPerPage,
        marginMm: marginMm ?? this.marginMm,
        pageNumbers: pageNumbers ?? this.pageNumbers,
        timestamp: timestamp ?? this.timestamp,
        watermark: watermark ?? this.watermark,
        watermarkText: watermarkText ?? this.watermarkText,
        coverPage: coverPage ?? this.coverPage,
        passwordProtect: passwordProtect ?? this.passwordProtect,
      );

  /// The first setting that is out of range, or null.
  ImagePdfFailure? validate() {
    if (pageSize == PdfPageSize.custom) {
      for (final side in <double>[customWidthMm, customHeightMm]) {
        if (!side.isFinite ||
            side < ImagePdfLimits.minCustomMm ||
            side > ImagePdfLimits.maxCustomMm) {
          return ImagePdfFailure.invalidSettings;
        }
      }
    }
    if (!marginMm.isFinite ||
        marginMm < 0 ||
        marginMm > ImagePdfLimits.maxMarginMm) {
      return ImagePdfFailure.invalidSettings;
    }
    if (!ImagePdfLimits.tileCounts.contains(tilesPerPage)) {
      return ImagePdfFailure.invalidSettings;
    }
    if (watermark && !ImagePdfText.isValidWatermark(watermarkText)) {
      return ImagePdfFailure.invalidSettings;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ImagePdfSettings &&
      other.pageSize == pageSize &&
      other.customWidthMm == customWidthMm &&
      other.customHeightMm == customHeightMm &&
      other.orientation == orientation &&
      other.quality == quality &&
      other.compression == compression &&
      other.layout == layout &&
      other.tilesPerPage == tilesPerPage &&
      other.marginMm == marginMm &&
      other.pageNumbers == pageNumbers &&
      other.timestamp == timestamp &&
      other.watermark == watermark &&
      other.watermarkText.trim() == watermarkText.trim() &&
      other.coverPage == coverPage &&
      other.passwordProtect == passwordProtect;

  @override
  int get hashCode => Object.hash(
        pageSize,
        customWidthMm,
        customHeightMm,
        orientation,
        quality,
        compression,
        layout,
        tilesPerPage,
        marginMm,
        pageNumbers,
        timestamp,
        watermark,
        watermarkText.trim(),
        coverPage,
        passwordProtect,
      );
}

/// Text rules for what the tool writes into a PDF.
class ImagePdfText {
  const ImagePdfText._();

  /// Whether every character of [text] is one the PDF can show: printable Latin
  /// (the standard PDF font) or Arabic (the bundled Noto Naskh Arabic font).
  static bool isRenderable(String text) {
    for (final rune in text.runes) {
      if (!_latin(rune) && !_arabic(rune)) return false;
    }
    return true;
  }

  static bool isValidWatermark(String text) {
    final trimmed = text.trim();
    if (trimmed.runes.length > ImagePdfLimits.maxWatermarkLength) return false;
    return isRenderable(trimmed);
  }

  /// Whether [text] needs the Arabic font (it has any non-Latin character).
  static bool needsUnicodeFont(String text) =>
      text.runes.any((rune) => !_latin(rune));

  static bool _latin(int rune) => rune >= 0x20 && rune <= 0x7E;

  static bool _arabic(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) ||
      (rune >= 0x0750 && rune <= 0x077F) ||
      (rune >= 0xFB50 && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF) ||
      rune == 0x200C ||
      rune == 0x200D ||
      // Arabic-Indic digits and the Arabic comma, question mark, semicolon.
      (rune >= 0x0660 && rune <= 0x0669);

  /// A password the PDF can carry in a way every viewer reads the same:
  /// printable ASCII, [ImagePdfLimits.minPasswordLength]..max long.
  static bool isValidPassword(String password) {
    if (password.length < ImagePdfLimits.minPasswordLength ||
        password.length > ImagePdfLimits.maxPasswordLength) {
      return false;
    }
    return password.runes.every(_latin);
  }

  /// The timestamp the PDF shows: Latin digits in one fixed layout, so it reads
  /// the same in every language and viewer.
  static String formatTimestamp(DateTime moment) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${moment.year.toString().padLeft(4, '0')}-${two(moment.month)}-'
        '${two(moment.day)} ${two(moment.hour)}:${two(moment.minute)}';
  }

  /// The footer number of page [index] (zero-based) of [total].
  static String pageNumber(int index, int total) => '${index + 1} / $total';
}

/// What the file of one selected picture proved to be. Plain data, so it can
/// cross to a worker isolate.
class ImageAnalysis {
  const ImageAnalysis({
    required this.size,
    required this.format,
    required this.width,
    required this.height,
    required this.orientation,
    required this.hasAlpha,
    required this.isBaselineJpeg,
    required this.thumbnail,
    this.dpi,
  });

  /// The file's size in bytes.
  final int size;

  /// `jpeg`, `png`, `gif`, `bmp` or `webp`.
  final String format;

  /// The picture as it is shown: after the EXIF orientation is applied.
  final int width;
  final int height;

  /// The EXIF orientation (1..8) the file stores; 1 when it has none.
  final int orientation;

  /// Whether any pixel is not fully opaque.
  final bool hasAlpha;

  /// A baseline JPEG that can be kept byte for byte (minus its metadata).
  final bool isBaselineJpeg;

  /// The picture's own print resolution, when the file states a sane one.
  final double? dpi;

  /// A small upright JPEG for the list. Not part of any output.
  final Uint8List thumbnail;
}

/// A selected picture, reduced to what the layout and the engine need.
class ImageSpec {
  const ImageSpec({
    required this.id,
    required this.path,
    required this.size,
    required this.format,
    required this.width,
    required this.height,
    required this.orientation,
    required this.hasAlpha,
    required this.isBaselineJpeg,
    this.dpi,
  });

  final String id;
  final String path;
  final int size;
  final String format;

  /// Upright (oriented) pixel size.
  final int width;
  final int height;
  final int orientation;
  final bool hasAlpha;
  final bool isBaselineJpeg;
  final double? dpi;
}

/// A PDF kept for the signed-in account. [fileName] is the private stored
/// file's own name (an internal id plus `.pdf`) and never a name the user typed;
/// [name] is the visible title.
class ImagePdfDocument {
  const ImagePdfDocument({
    required this.id,
    required this.fileName,
    required this.name,
    required this.createdAt,
    required this.fileSize,
    required this.pageCount,
    required this.imageCount,
    this.encrypted = false,
  });

  final String id;
  final String fileName;
  final String name;
  final DateTime createdAt;
  final int fileSize;

  /// The PDF's pages, read from the file. 0 only for a password-protected file
  /// rebuilt after its list was lost (its pages cannot be counted).
  final int pageCount;

  /// The pictures it was made from. 0 when unknown (rebuilt).
  final int imageCount;

  /// Whether the file needs a password to open.
  final bool encrypted;

  /// The name an exported or shared copy carries.
  String get exportFileName => '$name.pdf';

  ImagePdfDocument copyWith({String? name}) => ImagePdfDocument(
        id: id,
        fileName: fileName,
        name: name ?? this.name,
        createdAt: createdAt,
        fileSize: fileSize,
        pageCount: pageCount,
        imageCount: imageCount,
        encrypted: encrypted,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fileName': fileName,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'fileSize': fileSize,
        'pageCount': pageCount,
        'imageCount': imageCount,
        'encrypted': encrypted,
      };

  /// Reads one stored record. Throws a [FormatException] for anything that is
  /// not a well-formed record, so a damaged entry is never half trusted.
  factory ImagePdfDocument.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Image PDF record is not an object');
    }
    String text(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Image PDF record has no $key');
      }
      return value;
    }

    int whole(String key) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw FormatException('Image PDF record has a bad $key');
      }
      return value;
    }

    final fileName = text('fileName');
    if (!ImagePdfNaming.isStoredFileName(fileName)) {
      throw const FormatException('Image PDF record names an unsafe file');
    }
    final encrypted = json['encrypted'] == true;
    final pageCount = whole('pageCount');
    if (pageCount < 1 && !encrypted) {
      throw const FormatException('Image PDF record has no pages');
    }
    return ImagePdfDocument(
      id: text('id'),
      fileName: fileName,
      name: text('name'),
      createdAt: DateTime.parse(text('createdAt')),
      fileSize: whole('fileSize'),
      pageCount: pageCount,
      imageCount: whole('imageCount'),
      encrypted: encrypted,
    );
  }
}

/// Names for stored PDFs. Titles follow the Scanner's rules (Unicode kept,
/// separators and bidi controls removed, unique per account); the stored file is
/// always an internal id.
class ImagePdfNaming {
  const ImagePdfNaming._();

  static final RegExp _storedFileName = RegExp(r'^[A-Za-z0-9_-]{1,64}\.pdf$');

  static bool isStoredFileName(String fileName) =>
      _storedFileName.hasMatch(fileName);

  static String? sanitizeDisplayName(String raw) =>
      ScannerNaming.sanitizeDisplayName(raw);

  static String uniqueName(String base, Iterable<String> taken) =>
      ScannerNaming.uniqueName(base, taken);

  /// The default title of a new PDF, e.g. "PDF_Document_20261018_1432".
  static String defaultName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'PDF_Document_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}';
  }
}
