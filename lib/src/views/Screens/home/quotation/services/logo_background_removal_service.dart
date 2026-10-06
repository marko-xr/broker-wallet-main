import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/quotation/services/logo_optimization_service.dart'
    show quotationLogoMaxDimension;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class LogoBackgroundRemovalException implements Exception {
  const LogoBackgroundRemovalException();
}

/// Removes a simple, edge-connected logo background locally.
///
/// No image leaves the device for processing. The original picked file is
/// never modified; the result is a temporary transparent PNG used for preview,
/// upload and PDF generation when the user enables background removal.
class LogoBackgroundRemovalService {
  const LogoBackgroundRemovalService();

  Future<File> removeBackground(File source) async {
    final bytes = await source.readAsBytes();
    final processed = await compute(_removeLogoBackgroundBytes, bytes);
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/quotation_logo_bg_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(processed, flush: true);
    return file;
  }
}

Uint8List _removeLogoBackgroundBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width < 2 || decoded.height < 2) {
    throw const LogoBackgroundRemovalException();
  }

  img.Image image = img.bakeOrientation(decoded).convert(numChannels: 4);
  // Work at the size the logo is uploaded and drawn at. The background is cut
  // after the resize, so the transparent edge is never averaged with the old
  // background colour, and there is no more than ~0.6 MP to scan and encode.
  const maxDimension = quotationLogoMaxDimension;
  if (image.width > maxDimension || image.height > maxDimension) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxDimension,
            interpolation: img.Interpolation.average,
          );
    image = image.convert(numChannels: 4);
  }

  final width = image.width;
  final height = image.height;
  final totalPixels = width * height;
  final border = <img.Pixel>[];
  final sampleStep = math.max(1, math.min(width, height) ~/ 120);

  for (var x = 0; x < width; x += sampleStep) {
    border.add(image.getPixel(x, 0));
    border.add(image.getPixel(x, height - 1));
  }
  for (var y = sampleStep; y < height - 1; y += sampleStep) {
    border.add(image.getPixel(0, y));
    border.add(image.getPixel(width - 1, y));
  }

  final transparentBorderCount =
      border.where((pixel) => pixel.a.toInt() <= 20).length;
  if (transparentBorderCount / border.length >= 0.50) {
    return img.encodePng(_trimTransparentMargin(image), level: 9);
  }

  final opaqueBorder = border.where((pixel) => pixel.a.toInt() > 32).toList();
  if (opaqueBorder.isEmpty) {
    return img.encodePng(_trimTransparentMargin(image), level: 9);
  }

  int medianChannel(num Function(img.Pixel) value) {
    final values = opaqueBorder.map((pixel) => value(pixel).toInt()).toList()
      ..sort();
    return values[values.length ~/ 2];
  }

  final backgroundR = medianChannel((pixel) => pixel.r);
  final backgroundG = medianChannel((pixel) => pixel.g);
  final backgroundB = medianChannel((pixel) => pixel.b);

  int distanceSquared(img.Pixel pixel) {
    final dr = pixel.r.toInt() - backgroundR;
    final dg = pixel.g.toInt() - backgroundG;
    final db = pixel.b.toInt() - backgroundB;
    return (dr * dr) + (dg * dg) + (db * db);
  }

  const confidenceDistance = 58;
  final closeBorderCount = opaqueBorder
      .where((pixel) =>
          distanceSquared(pixel) <= confidenceDistance * confidenceDistance)
      .length;
  if (closeBorderCount / opaqueBorder.length < 0.50) {
    throw const LogoBackgroundRemovalException();
  }

  const removalDistance = 78;
  const featherDistance = 118;
  final removed = Uint8List(totalPixels);
  final queue = Queue<int>();

  bool isBackgroundCandidate(int x, int y) {
    final pixel = image.getPixel(x, y);
    if (pixel.a.toInt() <= 20) return true;
    return distanceSquared(pixel) <= removalDistance * removalDistance;
  }

  void seed(int x, int y) {
    final index = (y * width) + x;
    if (removed[index] != 0 || !isBackgroundCandidate(x, y)) return;
    removed[index] = 1;
    queue.add(index);
  }

  for (var x = 0; x < width; x++) {
    seed(x, 0);
    seed(x, height - 1);
  }
  for (var y = 1; y < height - 1; y++) {
    seed(0, y);
    seed(width - 1, y);
  }

  var removedCount = 0;
  while (queue.isNotEmpty) {
    final index = queue.removeFirst();
    final x = index % width;
    final y = index ~/ width;
    final pixel = image.getPixel(x, y);
    image.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, 0);
    removedCount++;

    if (x > 0) seed(x - 1, y);
    if (x + 1 < width) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y + 1 < height) seed(x, y + 1);
  }

  if (removedCount < math.max(16, (totalPixels * 0.02).round())) {
    throw const LogoBackgroundRemovalException();
  }

  var foregroundCount = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = (y * width) + x;
      if (removed[index] != 0) continue;
      final pixel = image.getPixel(x, y);
      if (pixel.a.toInt() <= 8) continue;
      foregroundCount++;

      var touchesRemoved = false;
      if (x > 0 && removed[index - 1] != 0) touchesRemoved = true;
      if (x + 1 < width && removed[index + 1] != 0) touchesRemoved = true;
      if (y > 0 && removed[index - width] != 0) touchesRemoved = true;
      if (y + 1 < height && removed[index + width] != 0) touchesRemoved = true;
      if (!touchesRemoved) continue;

      final distance = math.sqrt(distanceSquared(pixel).toDouble());
      if (distance >= featherDistance) continue;
      final factor =
          ((distance - removalDistance) / (featherDistance - removalDistance))
              .clamp(0.0, 1.0);
      final alpha = (pixel.a.toDouble() * factor).round();
      image.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, alpha);
    }
  }

  if (foregroundCount < math.max(12, (totalPixels * 0.005).round())) {
    throw const LogoBackgroundRemovalException();
  }

  return img.encodePng(_trimTransparentMargin(image), level: 9);
}

img.Image _trimTransparentMargin(img.Image image) {
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a.toInt() <= 8) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < minX || maxY < minY) return image;

  final contentWidth = maxX - minX + 1;
  final contentHeight = maxY - minY + 1;
  final padding = math.max(
    4,
    (math.max(contentWidth, contentHeight) * 0.04).round(),
  );
  final cropX = math.max(0, minX - padding);
  final cropY = math.max(0, minY - padding);
  final cropRight = math.min(image.width - 1, maxX + padding);
  final cropBottom = math.min(image.height - 1, maxY + padding);

  if (cropX == 0 &&
      cropY == 0 &&
      cropRight == image.width - 1 &&
      cropBottom == image.height - 1) {
    return image;
  }

  return img.copyCrop(
    image,
    x: cropX,
    y: cropY,
    width: cropRight - cropX + 1,
    height: cropBottom - cropY + 1,
  );
}
