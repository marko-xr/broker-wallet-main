// The office-logo downsizing that runs when a logo is picked (never during
// Save): a logo is drawn in an 80 x 80 pt box, so a camera-sized image is
// shrunk to at most [quotationLogoMaxDimension] px on its long edge before it is
// uploaded or embedded in the PDF. Pure image logic, no Flutter engine needed.

import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/quotation/services/logo_optimization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _photo(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 255) ~/ width,
        (y * 255) ~/ height,
        ((x + y) * 255) ~/ (width + height),
      );
    }
  }
  return image;
}

bool _hasExifSegment(Uint8List jpeg) {
  for (var i = 2; i < jpeg.length - 1 && i < 4096; i++) {
    if (jpeg[i] == 0xFF && jpeg[i + 1] == 0xE1) return true;
  }
  return false;
}

void main() {
  test('a camera-sized JPEG is shrunk to 768 px on its long edge, still a JPEG',
      () {
    final source = _photo(1600, 1200);
    source.exif.imageIfd.make = 'TestCam';
    final bytes = img.encodeJpg(source, quality: 92);

    final optimized = optimizeLogoBytes(bytes);

    expect(optimized, isNotNull);
    expect(optimized![0], 0xFF);
    expect(optimized[1], 0xD8, reason: 'a JPEG stays a JPEG');
    final decoded = img.decodeJpg(optimized)!;
    expect(decoded.width, quotationLogoMaxDimension);
    expect(decoded.height, 576, reason: 'the aspect ratio is kept');
    expect(optimized.length, lessThan(bytes.length));
    expect(_hasExifSegment(optimized), isFalse,
        reason: 'no device or location metadata is carried over');
  });

  test('the camera orientation is applied to the pixels', () {
    final source = _photo(1500, 1000);
    source.exif.imageIfd.orientation = 6;

    final optimized = optimizeLogoBytes(img.encodeJpg(source, quality: 85));

    final decoded = img.decodeJpg(optimized!)!;
    expect(decoded.width, 512);
    expect(decoded.height, quotationLogoMaxDimension,
        reason: 'a portrait photo is limited by its height');
  });

  test('a PNG with transparency keeps its alpha channel', () {
    final source = img.Image(width: 1600, height: 1000, numChannels: 4);
    img.fillCircle(source,
        x: 800, y: 500, radius: 300, color: img.ColorRgba8(20, 90, 200, 255));

    final optimized = optimizeLogoBytes(img.encodePng(source));

    final decoded = img.decodePng(optimized!)!;
    expect(decoded.width, quotationLogoMaxDimension);
    expect(decoded.height, 480);
    expect(decoded.numChannels, 4);
    expect(decoded.getPixel(2, 2).a, 0, reason: 'the corner stays transparent');
    expect(decoded.getPixel(384, 240).a, 255, reason: 'the logo stays opaque');
  });

  test('a pixel-fine pattern is averaged to mid-gray when shrunk', () {
    final source = img.Image(width: 1536, height: 1024, numChannels: 3);
    for (var y = 0; y < 1024; y++) {
      for (var x = 0; x < 1536; x++) {
        final v = ((x + y) % 2 == 0) ? 0 : 255;
        source.setPixelRgb(x, y, v, v, v);
      }
    }

    final decoded = img.decodePng(optimizeLogoBytes(img.encodePng(source))!)!;

    expect(decoded.getPixel(100, 100).r, inInclusiveRange(90, 165));
  });

  test('a logo that already fits, or is not an image, is left alone', () {
    expect(optimizeLogoBytes(img.encodePng(_photo(500, 300))), isNull);
    expect(optimizeLogoBytes(img.encodeJpg(_photo(768, 700))), isNull,
        reason: '768 on the long edge is within the limit');
    expect(
      optimizeLogoBytes(Uint8List.fromList(List<int>.generate(64, (i) => i))),
      isNull,
    );
  });
}
