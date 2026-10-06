import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// The longest edge, in pixels, of a logo that is uploaded and drawn.
///
/// The PDF draws the logo inside an 80 x 80 pt box and the editor previews it in
/// a box about 108 dp high. 768 px is about 690 dpi in the PDF box and still
/// 1.7x the preview box on a 4x screen, so the logo stays sharp when printed or
/// zoomed, while a 12 MP camera photo (4000 x 3000) shrinks to 768 x 576, about
/// 3.7% of its pixels.
const int quotationLogoMaxDimension = 768;

/// Makes a smaller copy of a picked office logo for upload and the PDF.
///
/// It runs when the logo is picked, never during Save. The picked file is never
/// modified; the copy is a temporary file the caller removes.
class LogoOptimizationService {
  const LogoOptimizationService();

  /// A temporary resized copy of [source], or null when [source] already fits
  /// within [quotationLogoMaxDimension] or cannot be decoded; it is then used
  /// as it is.
  Future<File?> optimize(File source) async {
    final bytes = await source.readAsBytes();
    final optimized = await compute(optimizeLogoBytes, bytes);
    if (optimized == null) return null;
    final directory = await getTemporaryDirectory();
    final extension = _isJpeg(optimized) ? 'jpg' : 'png';
    final file = File(
      '${directory.path}/quotation_logo_opt_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(optimized, flush: true);
    return file;
  }
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

/// The image in [bytes] resized so its longest edge is
/// [quotationLogoMaxDimension], or null when it already fits or is not a
/// decodable image.
///
/// A JPEG stays a JPEG (it has no transparency); any other format becomes a
/// PNG, which keeps its alpha channel. The camera orientation is applied to the
/// pixels, and no metadata (location, device) is carried into the copy.
Uint8List? optimizeLogoBytes(Uint8List bytes) {
  final isJpeg = _isJpeg(bytes);
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final upright = img.bakeOrientation(decoded);
  if (upright.width <= quotationLogoMaxDimension &&
      upright.height <= quotationLogoMaxDimension) {
    return null;
  }

  final resized = img.copyResize(
    upright.convert(numChannels: isJpeg ? 3 : 4),
    width: upright.width >= upright.height ? quotationLogoMaxDimension : null,
    height: upright.width < upright.height ? quotationLogoMaxDimension : null,
    interpolation: img.Interpolation.average,
  );
  resized.exif = img.ExifData();

  return isJpeg
      ? img.encodeJpg(resized, quality: 90)
      : img.encodePng(resized, level: 6);
}
