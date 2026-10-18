import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';

/// Reading a picture's format and metadata from its bytes, and removing the
/// metadata from a JPEG without touching its pixels.
class ImagePdfFormats {
  const ImagePdfFormats._();

  /// The format a file's own bytes say it is, never what its name says:
  /// `jpeg`, `png`, `gif`, `bmp`, `webp`, `heic` (HEIC/HEIF/AVIF containers) or
  /// null for anything else.
  static String? sniff(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return 'png';
    }
    if (_ascii(b, 0, 'GIF87a') || _ascii(b, 0, 'GIF89a')) {
      return 'gif';
    }
    if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
    if (b.length >= 12 && _ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP')) {
      return 'webp';
    }
    if (b.length >= 12 && _ascii(b, 4, 'ftyp')) {
      for (final brand in const <String>[
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heim',
        'heis',
        'hevm',
        'hevs',
        'mif1',
        'msf1',
        'heif',
        'avif',
        'avis',
      ]) {
        if (_ascii(b, 8, brand)) return 'heic';
      }
    }
    return null;
  }

  static bool _ascii(Uint8List b, int offset, String text) {
    if (offset + text.length > b.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (b[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// The picture's own print resolution when its file states a sane one (JFIF
  /// density in a JPEG, pHYs in a PNG); null otherwise.
  static double? readDpi(Uint8List b, String format) {
    double? dpi;
    if (format == 'jpeg') {
      var i = 2;
      while (i + 4 < b.length && b[i] == 0xFF) {
        final marker = b[i + 1];
        if (marker == 0xDA || marker == 0xD9) break;
        final length = (b[i + 2] << 8) | b[i + 3];
        if (length < 2) break;
        if (marker == 0xE0 && length >= 16 && _ascii(b, i + 4, 'JFIF')) {
          final units = b[i + 11];
          final x = (b[i + 12] << 8) | b[i + 13];
          if (units == 1) dpi = x.toDouble();
          if (units == 2) dpi = x * 2.54;
          break;
        }
        i += 2 + length;
      }
    } else if (format == 'png') {
      var i = 8;
      while (i + 12 <= b.length) {
        final length =
            (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
        if (length < 0) break;
        if (_ascii(b, i + 4, 'IDAT')) break;
        if (_ascii(b, i + 4, 'pHYs') && length >= 9 && i + 8 + 9 <= b.length) {
          final ppu = (b[i + 8] << 24) |
              (b[i + 9] << 16) |
              (b[i + 10] << 8) |
              b[i + 11];
          if (b[i + 16] == 1) dpi = ppu * 0.0254;
          break;
        }
        i += 12 + length;
      }
    }
    if (dpi == null || !dpi.isFinite || dpi < 36 || dpi > 1200) return null;
    return dpi;
  }

  /// The frame header of a JPEG: its SOF marker, bit depth, size and number of
  /// colour components; null when none is found.
  static ({int marker, int precision, int width, int height, int components})?
      jpegFrame(Uint8List b) {
    var i = 2;
    while (i + 4 <= b.length) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return null;
      final length = (b[i + 2] << 8) | b[i + 3];
      if (length < 2 || i + 2 + length > b.length) return null;
      if (_isSof(marker)) {
        if (length < 8) return null;
        return (
          marker: marker,
          precision: b[i + 4],
          height: (b[i + 5] << 8) | b[i + 6],
          width: (b[i + 7] << 8) | b[i + 8],
          components: b[i + 9],
        );
      }
      i += 2 + length;
    }
    return null;
  }

  static bool _isSof(int m) =>
      m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC;

  /// The EXIF orientation (1..8) stored in a JPEG's own bytes; 1 when the file
  /// has none or it is not valid. The JPEG decoder applies this orientation
  /// itself and then forgets it, so it can only be read from the raw file.
  static int readJpegOrientation(Uint8List b) {
    var i = 2;
    while (i + 4 <= b.length && b[i] == 0xFF) {
      final marker = b[i + 1];
      if (marker == 0xDA || marker == 0xD9) break;
      if (marker == 0xFF) {
        i++;
        continue;
      }
      final length = (b[i + 2] << 8) | b[i + 3];
      if (length < 2 || i + 2 + length > b.length) break;
      if (marker == 0xE1 && length >= 14 && _ascii(b, i + 4, 'Exif')) {
        final tiff = i + 10;
        final little = b[tiff] == 0x49;
        int u16(int at) =>
            little ? b[at] | (b[at + 1] << 8) : (b[at] << 8) | b[at + 1];
        int u32(int at) => little
            ? b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
            : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
        final end = i + 2 + length;
        if (tiff + 8 > end) return 1;
        final ifd = tiff + u32(tiff + 4);
        if (ifd < tiff || ifd + 2 > end) return 1;
        final count = u16(ifd);
        for (var n = 0; n < count; n++) {
          final entry = ifd + 2 + n * 12;
          if (entry + 12 > end) return 1;
          if (u16(entry) == 0x0112) {
            final value = u16(entry + 8);
            return value >= 1 && value <= 8 ? value : 1;
          }
        }
        return 1;
      }
      i += 2 + length;
    }
    return 1;
  }

  /// A minimal JFIF header: no thumbnail, no density.
  static const List<int> _jfif = <int>[
    0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, //
    0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  ];

  /// Rewrites a JPEG keeping only what decoding needs: quantisation and Huffman
  /// tables, the frame, restart interval, the Adobe colour marker and the
  /// image data. EXIF (camera, GPS, time), XMP, ICC, comments, thumbnails and
  /// anything appended after the image (motion-photo video) are dropped. The
  /// pixels are not decoded or re-encoded. Null when the file is not a JPEG this
  /// can rewrite safely.
  static Uint8List? stripJpegMetadata(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    final out = BytesBuilder(copy: false)
      ..add(const <int>[0xFF, 0xD8])
      ..add(_jfif);
    var i = 2;
    var sawFrame = false;
    var sawScan = false;
    while (i < b.length) {
      if (b[i] != 0xFF) return null;
      while (i < b.length && b[i] == 0xFF) {
        i++;
      }
      if (i >= b.length) return null;
      final marker = b[i];
      i++;
      if (marker == 0xD9) {
        if (!sawFrame || !sawScan) return null;
        out.add(const <int>[0xFF, 0xD9]);
        return out.takeBytes();
      }
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7) ||
          marker == 0x00) {
        continue;
      }
      if (i + 2 > b.length) return null;
      final length = (b[i] << 8) | b[i + 1];
      if (length < 2 || i + length > b.length) return null;
      final end = i + length;
      final adobe = marker == 0xEE && length >= 7 && _ascii(b, i + 2, 'Adobe');
      final keep = marker == 0xDB ||
          marker == 0xC4 ||
          marker == 0xDD ||
          marker == 0xDA ||
          _isSof(marker) ||
          adobe;
      if (keep) {
        out.add(<int>[0xFF, marker]);
        out.add(Uint8List.sublistView(b, i, end));
      }
      if (_isSof(marker)) sawFrame = true;
      i = end;
      if (marker == 0xDA) {
        sawScan = true;
        final start = i;
        while (i + 1 < b.length) {
          final next = b[i + 1];
          if (b[i] == 0xFF &&
              next != 0x00 &&
              next != 0xFF &&
              !(next >= 0xD0 && next <= 0xD7)) {
            break;
          }
          i++;
        }
        if (i + 1 >= b.length) return null;
        out.add(Uint8List.sublistView(b, start, i));
      }
    }
    return null;
  }
}

/// The result of preparing one picture for the PDF.
class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.isJpeg,
    required this.width,
    required this.height,
    required this.reencoded,
  });

  final Uint8List bytes;

  /// JPEG (true) or PNG (false) data.
  final bool isJpeg;
  final int width;
  final int height;

  /// False when the original JPEG data was kept as it was (metadata removed).
  final bool reencoded;
}

bool _isDiskFull(FileSystemException error) {
  final code = error.osError?.errorCode;
  return code == 28 || code == 112;
}

Uint8List _readSource(String path, {int? expectedSize}) {
  final file = File(path);
  try {
    if (!file.existsSync()) {
      throw const ImagePdfException(ImagePdfFailure.missingSource);
    }
    final size = file.lengthSync();
    if (size <= 0) {
      throw const ImagePdfException(ImagePdfFailure.emptySource);
    }
    if (size > ImagePdfLimits.maxSourceBytes) {
      throw const ImagePdfException(ImagePdfFailure.tooLargeSource);
    }
    if (expectedSize != null && size != expectedSize) {
      throw const ImagePdfException(ImagePdfFailure.sourceChanged);
    }
    return file.readAsBytesSync();
  } on FileSystemException {
    throw const ImagePdfException(ImagePdfFailure.missingSource);
  }
}

/// Whether any pixel of [image] is not fully opaque.
bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  if (image.hasPalette) {
    final palette = image.palette!;
    if (palette.numChannels < 4) return false;
    for (var i = 0; i < palette.numColors; i++) {
      if (palette.getAlpha(i) < palette.maxChannelValue) return true;
    }
    return false;
  }
  if (image.format == img.Format.uint8 && image.numChannels == 4) {
    final bytes = image.buffer.asUint8List();
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] < 255) return true;
    }
    return false;
  }
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}

/// An opaque 8-bit RGB copy: transparent areas become white (the page's own
/// colour), never black.
img.Image _toOpaqueRgb(img.Image image) {
  if (image.hasAlpha || image.hasPalette) {
    final background =
        img.Image(width: image.width, height: image.height, numChannels: 3)
          ..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(background, image);
    return background;
  }
  if (image.format != img.Format.uint8 || image.numChannels != 3) {
    return image.convert(format: img.Format.uint8, numChannels: 3);
  }
  return image;
}

img.Image? _decodeFirstFrame(Uint8List bytes) {
  try {
    return img.decodeImage(bytes, frame: 0);
  } catch (_) {
    return null;
  }
}

/// Reads and fully decodes a picture, so a damaged file is found when it is
/// selected and not when the PDF is made. Throws an [ImagePdfException]
/// (`missingSource`, `emptySource`, `tooLargeSource`, `unsupportedFormat`,
/// `tooManyPixels`, `corruptSource`). Synchronous on purpose: it runs on a
/// worker isolate.
ImageAnalysis analyzeImageFile(String path) {
  final bytes = _readSource(path);
  final format = ImagePdfFormats.sniff(bytes);
  if (format == null || format == 'heic') {
    throw const ImagePdfException(ImagePdfFailure.unsupportedFormat);
  }
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) {
    // The bytes say it is a picture format the tool reads, but its header is
    // not valid.
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'header');
  }
  // The JPEG decoder returns whatever it managed to read of a cut-off file, so
  // completeness is checked on the file's own structure: every scan has to
  // reach its end marker.
  if (format == 'jpeg' && ImagePdfFormats.stripJpegMetadata(bytes) == null) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'incomplete');
  }
  final img.DecodeInfo? info;
  try {
    info = decoder.startDecode(bytes);
  } catch (_) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'header');
  }
  if (info == null || info.width < 1 || info.height < 1) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'header');
  }
  if (info.width * info.height > ImagePdfLimits.maxPixels) {
    throw const ImagePdfException(ImagePdfFailure.tooManyPixels);
  }
  final decoded = _decodeFirstFrame(bytes);
  if (decoded == null || decoded.width < 1 || decoded.height < 1) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'decode');
  }
  // The JPEG decoder has already applied the EXIF orientation, so these are the
  // sizes as shown; the stored orientation only tells whether the file's own
  // data is upright (and can be kept as it is).
  final orientation =
      format == 'jpeg' ? ImagePdfFormats.readJpegOrientation(bytes) : 1;
  final width = decoded.width;
  final height = decoded.height;
  final hasAlpha = _hasTransparency(decoded);

  var baseline = false;
  if (format == 'jpeg') {
    final frame = ImagePdfFormats.jpegFrame(bytes);
    baseline = frame != null &&
        frame.marker == 0xC0 &&
        frame.precision == 8 &&
        (frame.components == 1 || frame.components == 3);
  }

  // The list thumbnail: small, upright, opaque.
  const box = 256;
  final longest = math.max(decoded.width, decoded.height);
  final small = longest > box
      ? img.copyResize(decoded,
          width: decoded.width >= decoded.height ? box : null,
          height: decoded.width < decoded.height ? box : null,
          interpolation: img.Interpolation.average)
      : decoded;
  final thumb = _toOpaqueRgb(small);
  thumb.exif = img.ExifData();
  thumb.iccProfile = null;
  final thumbnail =
      Uint8List.fromList(img.JpegEncoder(quality: 78).encode(thumb));

  return ImageAnalysis(
    size: bytes.length,
    format: format,
    width: width,
    height: height,
    orientation: orientation,
    hasAlpha: hasAlpha,
    isBaselineJpeg: baseline,
    dpi: ImagePdfFormats.readDpi(bytes, format),
    thumbnail: thumbnail,
  );
}

/// How a picture is stored in the PDF for a compression level.
({bool png, int quality, bool chroma420}) _encoding(
    CompressionLevel compression, String format) {
  switch (compression) {
    case CompressionLevel.none:
      return (png: true, quality: 100, chroma420: false);
    case CompressionLevel.low:
      return (png: format != 'jpeg', quality: 92, chroma420: false);
    case CompressionLevel.medium:
      return (png: false, quality: 85, chroma420: false);
    case CompressionLevel.high:
      return (png: false, quality: 75, chroma420: true);
    case CompressionLevel.maximum:
      return (png: false, quality: 60, chroma420: true);
  }
}

/// Prepares one picture for the PDF: upright, at most [target] pixels (never
/// enlarged), opaque, with no metadata, encoded for [compression]. The file is
/// only read, never written. Throws an [ImagePdfException].
///
/// A baseline JPEG that is already upright and needs no resizing keeps its
/// original data (only metadata removed): for [CompressionLevel.none] always,
/// and for the lossy levels whenever re-encoding would not make it smaller.
ProcessedImage processImage(
  ImageSpec spec, {
  required CompressionLevel compression,
  ({int width, int height})? target,
}) {
  final bytes = _readSource(spec.path, expectedSize: spec.size);
  final format = ImagePdfFormats.sniff(bytes);
  if (format == null || format == 'heic' || format != spec.format) {
    throw const ImagePdfException(ImagePdfFailure.sourceChanged);
  }

  Uint8List? kept;
  if (format == 'jpeg' &&
      spec.isBaselineJpeg &&
      spec.orientation == 1 &&
      target == null) {
    final stripped = ImagePdfFormats.stripJpegMetadata(bytes);
    if (stripped != null) {
      final frame = ImagePdfFormats.jpegFrame(stripped);
      if (frame != null &&
          frame.marker == 0xC0 &&
          frame.width == spec.width &&
          frame.height == spec.height) {
        kept = stripped;
      }
    }
    if (kept != null && compression == CompressionLevel.none) {
      return ProcessedImage(
          bytes: kept,
          isJpeg: true,
          width: spec.width,
          height: spec.height,
          reencoded: false);
    }
  }

  var image = _decodeFirstFrame(bytes);
  if (image == null) {
    throw const ImagePdfException(ImagePdfFailure.corruptSource,
        detail: 'decode');
  }
  // The decoder returns the picture upright, so [target] is in the same frame.
  if (target != null &&
      (target.width < image.width || target.height < image.height)) {
    image = img.copyResize(image,
        width: math.max(1, target.width),
        height: math.max(1, target.height),
        interpolation: img.Interpolation.average);
  }
  image = _toOpaqueRgb(image);
  image.exif = img.ExifData();
  image.iccProfile = null;

  final encoding = _encoding(compression, format);
  final Uint8List encoded;
  try {
    if (encoding.png) {
      encoded = Uint8List.fromList(img.PngEncoder().encode(image));
    } else {
      encoded = Uint8List.fromList(img.JpegEncoder(quality: encoding.quality)
          .encode(image,
              chroma: encoding.chroma420
                  ? img.JpegChroma.yuv420
                  : img.JpegChroma.yuv444));
    }
  } catch (_) {
    throw const ImagePdfException(ImagePdfFailure.buildFailed,
        detail: 'encode');
  }
  if (kept != null && kept.length <= encoded.length) {
    return ProcessedImage(
        bytes: kept,
        isJpeg: true,
        width: spec.width,
        height: spec.height,
        reencoded: false);
  }
  return ProcessedImage(
      bytes: encoded,
      isJpeg: !encoding.png,
      width: image.width,
      height: image.height,
      reencoded: true);
}

/// Maps a file-system failure from a worker to the failure the user sees.
ImagePdfException mapImageFileError(FileSystemException error) {
  return _isDiskFull(error)
      ? const ImagePdfException(ImagePdfFailure.storageFull)
      : const ImagePdfException(ImagePdfFailure.writeFailed, detail: 'io');
}
