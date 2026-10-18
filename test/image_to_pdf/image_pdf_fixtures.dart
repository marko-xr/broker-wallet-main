import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';

/// A solid colour picture with a distinct coloured square in its top-left
/// corner, so rotation and flips are visible in the pixels.
img.Image marked(int width, int height,
    {img.Color? fill, img.Color? corner, int numChannels = 3}) {
  final image =
      img.Image(width: width, height: height, numChannels: numChannels)
        ..clear(fill ?? img.ColorRgb8(40, 120, 200));
  final c = corner ?? img.ColorRgb8(255, 0, 0);
  final side = (width < height ? width : height) ~/ 4;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      image.setPixel(x, y, c);
    }
  }
  return image;
}

/// A JPEG with the given EXIF orientation and, optionally, GPS and camera
/// metadata that must never reach a PDF.
Uint8List jpeg(
  img.Image image, {
  int quality = 92,
  int? orientation,
  bool privateMetadata = false,
}) {
  final copy = img.Image.from(image);
  if (orientation != null) copy.exif.imageIfd.orientation = orientation;
  if (privateMetadata) {
    copy.exif.imageIfd.make = 'PrivateCameraMaker';
    copy.exif.imageIfd.model = 'PrivateCameraModel';
    copy.exif.gpsIfd.gpsLatitude = 25.2048;
    copy.exif.gpsIfd.gpsLongitude = 55.2708;
    copy.exif.gpsIfd.gpsLatitudeRef = 'N';
    copy.exif.gpsIfd.gpsLongitudeRef = 'E';
  }
  return Uint8List.fromList(img.JpegEncoder(quality: quality).encode(copy));
}

Uint8List png(img.Image image) =>
    Uint8List.fromList(img.PngEncoder().encode(image));

/// A PNG whose header claims [width] x [height] pixels (its data is untouched),
/// with the header checksum corrected so the file still parses.
Uint8List pngClaiming(Uint8List source, int width, int height) {
  final bytes = Uint8List.fromList(source);
  final data = bytes.buffer.asByteData();
  data.setUint32(16, width);
  data.setUint32(20, height);
  // CRC-32 of the IHDR type and data (bytes 12..28), stored at 29..32.
  var crc = 0xFFFFFFFF;
  for (var i = 12; i < 29; i++) {
    crc ^= bytes[i];
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  data.setUint32(29, crc ^ 0xFFFFFFFF);
  return bytes;
}

/// Whether [bytes] contain [text] (ASCII) anywhere.
bool containsAscii(Uint8List bytes, String text) {
  final needle = ascii.encode(text);
  outer:
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Writes pictures into a scratch folder and describes them for the engine.
class PictureFolder {
  PictureFolder(this.directory);

  final Directory directory;
  int _next = 0;

  static PictureFolder create() =>
      PictureFolder(Directory.systemTemp.createTempSync('image_pdf_test_'));

  File write(String name, Uint8List bytes) {
    final file = File('${directory.path}/$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  /// A fully analysed picture, as the selection screen would hold it.
  ImageSpec spec(File file, ImageAnalysis analysis, {String? id}) => ImageSpec(
        id: id ?? 'img${_next++}',
        path: file.path,
        size: analysis.size,
        format: analysis.format,
        width: analysis.width,
        height: analysis.height,
        orientation: analysis.orientation,
        hasAlpha: analysis.hasAlpha,
        isBaselineJpeg: analysis.isBaselineJpeg,
        dpi: analysis.dpi,
      );

  void dispose() {
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// The bundled Arabic font, read from the repository.
Uint8List arabicFontBytes() =>
    File('assets/fonts/Noto_Naskh_Arabic/NotoNaskhArabic-VariableFont_wght.ttf')
        .readAsBytesSync();
