import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_processor.dart';

import 'image_pdf_fixtures.dart';

/// Photograph-like content: smooth gradients with noise, so JPEG levels differ.
img.Image noisy(int width, int height, {int seed = 7}) {
  final random = math.Random(seed);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 255 ~/ width + random.nextInt(40)).clamp(0, 255),
        (y * 255 ~/ height + random.nextInt(40)).clamp(0, 255),
        ((x + y) * 255 ~/ (width + height) + random.nextInt(40)).clamp(0, 255),
      );
    }
  }
  return image;
}

void main() {
  late PictureFolder folder;
  setUp(() => folder = PictureFolder.create());
  tearDown(() => folder.dispose());

  ImageSpec specOf(File file) => folder.spec(file, analyzeImageFile(file.path));

  ImagePdfException? failureOf(void Function() action) {
    try {
      action();
    } on ImagePdfException catch (error) {
      return error;
    }
    return null;
  }

  group('formats are recognised by their bytes, not their names', () {
    test('JPEG, PNG, GIF, BMP, WebP and HEIC signatures', () {
      expect(ImagePdfFormats.sniff(jpeg(marked(8, 8))), 'jpeg');
      expect(ImagePdfFormats.sniff(png(marked(8, 8))), 'png');
      expect(
          ImagePdfFormats.sniff(
              Uint8List.fromList(img.GifEncoder().encode(marked(8, 8)))),
          'gif');
      expect(
          ImagePdfFormats.sniff(
              Uint8List.fromList(img.BmpEncoder().encode(marked(8, 8)))),
          'bmp');
      expect(
          ImagePdfFormats.sniff(
              Uint8List.fromList('RIFF\x24\x00\x00\x00WEBPVP8 '.codeUnits)),
          'webp');
      expect(
          ImagePdfFormats.sniff(Uint8List.fromList(
              <int>[0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0])),
          'heic');
      expect(ImagePdfFormats.sniff(Uint8List.fromList('%PDF-1.7'.codeUnits)),
          isNull);
      expect(ImagePdfFormats.sniff(Uint8List(0)), isNull);
    });

    test('a picture named .jpg that is a PNG is read as a PNG', () {
      final file = folder.write('lie.jpg', png(marked(40, 30)));
      final analysis = analyzeImageFile(file.path);
      expect(analysis.format, 'png');
      expect(analysis.isBaselineJpeg, isFalse);
    });
  });

  group('selecting a picture proves it can be read', () {
    test('a JPEG reports its real size, format and a thumbnail', () {
      final file = folder.write('a.jpg', jpeg(marked(640, 480)));
      final a = analyzeImageFile(file.path);
      expect((a.width, a.height), (640, 480));
      expect(a.format, 'jpeg');
      expect(a.orientation, 1);
      expect(a.isBaselineJpeg, isTrue);
      expect(a.hasAlpha, isFalse);
      expect(a.size, file.lengthSync());
      final thumb = img.decodeJpg(a.thumbnail)!;
      expect(math.max(thumb.width, thumb.height), 256);
      expect(thumb.width / thumb.height, closeTo(640 / 480, 0.02));
    });

    test('a small picture is not enlarged for its thumbnail', () {
      final file = folder.write('s.png', png(marked(60, 40)));
      final thumb = img.decodeJpg(analyzeImageFile(file.path).thumbnail)!;
      expect((thumb.width, thumb.height), (60, 40));
    });

    test('the EXIF orientation turns the reported size and the thumbnail', () {
      final file =
          folder.write('p.jpg', jpeg(marked(400, 200), orientation: 6));
      final a = analyzeImageFile(file.path);
      expect(a.orientation, 6);
      expect((a.width, a.height), (200, 400));
      final thumb = img.decodeJpg(a.thumbnail)!;
      expect(thumb.height, greaterThan(thumb.width));
      // The red corner marker is at the top-right after a 90 degree turn.
      expect(thumb.getPixel(thumb.width - 3, 3).r, greaterThan(200));
      expect(thumb.getPixel(3, 3).r, lessThan(120));
    });

    test('print resolution is read from JFIF and PNG headers', () {
      // The encoder writes JFIF without a density; patch units=1, 300 dpi.
      final bytes = jpeg(marked(50, 50));
      // SOI(2) APP0 marker(2) length(2) JFIF\0(5) version(2) units(1) X(2) Y(2)
      bytes[13] = 1;
      bytes[14] = 0x01;
      bytes[15] = 0x2C;
      bytes[16] = 0x01;
      bytes[17] = 0x2C;
      expect(ImagePdfFormats.readDpi(bytes, 'jpeg'), 300);
      // pHYs: 11811 pixels per metre is 300 dpi.
      final src = png(marked(20, 20));
      final withPhys = BytesBuilder()
        ..add(src.sublist(0, 33))
        ..add(<int>[0, 0, 0, 9, 0x70, 0x48, 0x59, 0x73])
        ..add(<int>[0, 0, 0x2E, 0x23, 0, 0, 0x2E, 0x23, 1])
        ..add(<int>[0, 0, 0, 0])
        ..add(src.sublist(33));
      final dpi = ImagePdfFormats.readDpi(withPhys.toBytes(), 'png')!;
      expect(dpi, closeTo(300, 0.1));
      expect(ImagePdfFormats.readDpi(jpeg(marked(50, 50)), 'jpeg'), isNull);
    });

    test('transparency is detected only when a pixel is not opaque', () {
      final opaque = marked(20, 20, numChannels: 4);
      expect(analyzeImageFile(folder.write('o.png', png(opaque)).path).hasAlpha,
          isFalse);
      final clear = marked(20, 20, numChannels: 4)
        ..setPixelRgba(10, 10, 0, 0, 0, 0);
      expect(analyzeImageFile(folder.write('c.png', png(clear)).path).hasAlpha,
          isTrue);
    });

    test('missing, empty, unsupported and over-sized files are refused by kind',
        () {
      expect(
          failureOf(() => analyzeImageFile('${folder.directory.path}/no.jpg'))
              ?.kind,
          ImagePdfFailure.missingSource);
      expect(
          failureOf(() =>
              analyzeImageFile(folder.write('e.jpg', Uint8List(0)).path))?.kind,
          ImagePdfFailure.emptySource);
      expect(
          failureOf(() => analyzeImageFile(folder
              .write('t.jpg', Uint8List.fromList('not a picture'.codeUnits))
              .path))?.kind,
          ImagePdfFailure.unsupportedFormat);
      final heic = Uint8List.fromList(
          <int>[0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(
          failureOf(() => analyzeImageFile(folder.write('h.heic', heic).path))
              ?.kind,
          ImagePdfFailure.unsupportedFormat);
      // A header that claims more pixels than a phone can decode is refused
      // before anything is allocated.
      final huge = pngClaiming(png(marked(8, 8)), 9000, 9000);
      expect(
          failureOf(() => analyzeImageFile(folder.write('big.png', huge).path))
              ?.kind,
          ImagePdfFailure.tooManyPixels);
    });

    test('damaged pictures are refused, never read as partial content', () {
      final good = jpeg(noisy(300, 200));
      final truncated = good.sublist(0, good.length * 6 ~/ 10);
      expect(
          failureOf(() =>
              analyzeImageFile(folder.write('cut.jpg', truncated).path))?.kind,
          ImagePdfFailure.corruptSource);
      final pngBytes = png(noisy(200, 200));
      final cutPng = pngBytes.sublist(0, pngBytes.length ~/ 2);
      expect(
          failureOf(
                  () => analyzeImageFile(folder.write('cut.png', cutPng).path))
              ?.kind,
          ImagePdfFailure.corruptSource);
      // Garbage after a valid header.
      final garbage = Uint8List.fromList(
          <int>[...good.sublist(0, 200), ...List<int>.filled(400, 0x55)]);
      expect(
          failureOf(() =>
              analyzeImageFile(folder.write('junk.jpg', garbage).path))?.kind,
          ImagePdfFailure.corruptSource);
    });
  });

  group('EXIF orientation is applied exactly once', () {
    // Where the red top-left marker of the STORED picture ends up once it is
    // upright, per EXIF orientation: (right edge?, bottom edge?).
    const corner = <int, (bool, bool)>{
      1: (false, false),
      2: (true, false),
      3: (true, true),
      4: (false, true),
      5: (false, false),
      6: (true, false),
      7: (true, true),
      8: (false, true),
    };

    for (var orientation = 1; orientation <= 8; orientation++) {
      test('orientation $orientation puts the marker in the right corner', () {
        final file = folder.write('o$orientation.jpg',
            jpeg(marked(120, 80), orientation: orientation));
        final spec = specOf(file);
        final out = processImage(spec, compression: CompressionLevel.none);
        expect(out.isJpeg, orientation == 1);
        final result = img.decodeImage(out.bytes)!;
        final swapped = orientation >= 5;
        expect((result.width, result.height), swapped ? (80, 120) : (120, 80));
        expect((spec.width, spec.height), (result.width, result.height));
        final (right, bottom) = corner[orientation]!;
        final x = right ? result.width - 4 : 3;
        final y = bottom ? result.height - 4 : 3;
        final marker = result.getPixel(x, y);
        expect(marker.r, greaterThan(200), reason: 'marker at $x,$y');
        expect(marker.b, lessThan(80));
        // The opposite corner is background.
        final ox = right ? 3 : result.width - 4;
        final oy = bottom ? 3 : result.height - 4;
        expect(result.getPixel(ox, oy).r, lessThan(120));
      });
    }

    test(
        'the output carries no orientation, so a viewer cannot rotate it again',
        () {
      final file = folder.write('r.jpg', jpeg(marked(120, 80), orientation: 6));
      final out =
          processImage(specOf(file), compression: CompressionLevel.medium);
      final decoded = img.decodeImage(out.bytes)!;
      expect(decoded.exif.imageIfd.hasOrientation, isFalse);
      // Feeding the output back in changes nothing.
      final again =
          folder.write('again.${out.isJpeg ? 'jpg' : 'png'}', out.bytes);
      expect(analyzeImageFile(again.path).orientation, 1);
    });
  });

  group('privacy: no metadata survives', () {
    final secrets = ['Exif', 'GPS', 'PrivateCamera', 'PrivateCameraMaker'];

    void expectClean(Uint8List bytes) {
      for (final s in secrets) {
        expect(containsAscii(bytes, s), isFalse, reason: 'found "$s"');
      }
    }

    test('the source really contains the metadata (the test is meaningful)',
        () {
      final bytes = jpeg(marked(60, 40), privateMetadata: true);
      expect(containsAscii(bytes, 'Exif'), isTrue);
      expect(containsAscii(bytes, 'PrivateCameraMaker'), isTrue);
    });

    for (final level in CompressionLevel.values) {
      test('${level.name}: an upright JPEG leaves with no EXIF or GPS', () {
        final file = folder.write(
            'm.jpg', jpeg(noisy(160, 120), privateMetadata: true, quality: 95));
        final out = processImage(specOf(file), compression: level);
        expectClean(out.bytes);
        expect(img.decodeImage(out.bytes), isNotNull);
      });

      test('${level.name}: a rotated JPEG leaves with no EXIF or GPS', () {
        final file = folder.write('m6.jpg',
            jpeg(noisy(160, 120), privateMetadata: true, orientation: 6));
        final out = processImage(specOf(file), compression: level);
        expectClean(out.bytes);
      });
    }

    test('metadata stripping keeps the pixels exactly and drops trailing data',
        () {
      final original = jpeg(noisy(160, 120), privateMetadata: true);
      final appended = Uint8List.fromList(<int>[
        ...original,
        ...'MOTIONPHOTOVIDEO'.codeUnits,
        ...List<int>.filled(500, 7)
      ]);
      final stripped = ImagePdfFormats.stripJpegMetadata(appended)!;
      expectClean(stripped);
      expect(containsAscii(stripped, 'MOTIONPHOTO'), isFalse);
      expect(stripped.length, lessThan(original.length));
      final a = img.decodeJpg(original)!;
      final b = img.decodeJpg(stripped)!;
      expect((b.width, b.height), (a.width, a.height));
      expect(b.getBytes(), a.getBytes());
    });

    test('a JPEG that is cut off cannot be rewritten', () {
      final original = jpeg(noisy(160, 120));
      expect(
          ImagePdfFormats.stripJpegMetadata(
              original.sublist(0, original.length - 40)),
          isNull);
      expect(ImagePdfFormats.stripJpegMetadata(Uint8List(3)), isNull);
    });
  });

  group('transparency is white, not black', () {
    test('a transparent PNG pixel becomes white at every compression level',
        () {
      final source = marked(60, 40, numChannels: 4);
      for (var y = 10; y < 30; y++) {
        for (var x = 20; x < 30; x++) {
          source.setPixelRgba(x, y, 0, 0, 0, 0);
        }
        for (var x = 40; x < 50; x++) {
          source.setPixelRgba(x, y, 255, 0, 0, 128);
        }
      }
      final file = folder.write('t.png', png(source));
      final spec = specOf(file);
      expect(spec.hasAlpha, isTrue);
      for (final level in CompressionLevel.values) {
        final out = processImage(spec, compression: level);
        final result = img.decodeImage(out.bytes)!;
        expect(result.numChannels, 3, reason: level.name);
        final clear = result.getPixel(25, 20);
        // Fully transparent: the white page, not the black RGB behind it.
        expect(clear.r, greaterThan(215), reason: '${level.name} ${clear.r}');
        expect(clear.g, greaterThan(215));
        expect(clear.b, greaterThan(215));
        // Half-transparent red over white is pink.
        final half = result.getPixel(45, 20);
        expect(half.r, greaterThan(225));
        expect(half.g, inInclusiveRange(100, 160));
      }
    });

    test('an opaque picture is untouched by the white flattening', () {
      final file = folder.write('o.png', png(marked(30, 30)));
      final out =
          processImage(specOf(file), compression: CompressionLevel.none);
      final result = img.decodeImage(out.bytes)!;
      expect(result.getPixel(15, 15).r, 40);
      expect(result.getPixel(15, 15).b, 200);
    });
  });

  group('quality and compression', () {
    test('None keeps an upright JPEG\'s data and never recompresses with loss',
        () {
      final bytes = jpeg(noisy(200, 150), quality: 90);
      final file = folder.write('n.jpg', bytes);
      final out =
          processImage(specOf(file), compression: CompressionLevel.none);
      expect(out.reencoded, isFalse);
      expect(out.isJpeg, isTrue);
      expect(img.decodeJpg(out.bytes)!.getBytes(),
          img.decodeJpg(bytes)!.getBytes());
    });

    test('None stores a PNG losslessly, pixel for pixel', () {
      final source = noisy(80, 60);
      final file = folder.write('n.png', png(source));
      final out =
          processImage(specOf(file), compression: CompressionLevel.none);
      expect(out.isJpeg, isFalse);
      expect(img.decodeImage(out.bytes)!.getBytes(), source.getBytes());
    });

    test('None on a JPEG that must change is lossless too, not JPEG again', () {
      final file = folder.write('r.jpg', jpeg(noisy(80, 60), orientation: 6));
      final out =
          processImage(specOf(file), compression: CompressionLevel.none);
      expect(out.isJpeg, isFalse);
    });

    test('the lossy levels get smaller as compression rises', () {
      final file = folder.write('p.jpg', jpeg(noisy(480, 360), quality: 98));
      final spec = specOf(file);
      int sizeAt(CompressionLevel l) =>
          processImage(spec, compression: l).bytes.length;
      final none = sizeAt(CompressionLevel.none);
      final low = sizeAt(CompressionLevel.low);
      final medium = sizeAt(CompressionLevel.medium);
      final high = sizeAt(CompressionLevel.high);
      final maximum = sizeAt(CompressionLevel.maximum);
      expect(low, lessThanOrEqualTo(none));
      expect(medium, lessThan(low));
      expect(high, lessThan(medium));
      expect(maximum, lessThan(high));
    });

    test('a recompression that would be bigger keeps the original data', () {
      // A low-quality source: re-encoding at q92 would only add bytes.
      final file = folder.write('l.jpg', jpeg(noisy(240, 180), quality: 40));
      final out = processImage(specOf(file), compression: CompressionLevel.low);
      expect(out.reencoded, isFalse);
    });

    test('Maximum visibly loses detail that Low keeps', () {
      final source = noisy(200, 150);
      final file = folder.write('d.png', png(source));
      final spec = specOf(file);
      double error(CompressionLevel level) {
        final out =
            img.decodeImage(processImage(spec, compression: level).bytes)!;
        var sum = 0.0;
        for (var y = 0; y < 150; y++) {
          for (var x = 0; x < 200; x++) {
            final a = source.getPixel(x, y);
            final b = out.getPixel(x, y);
            sum += (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
          }
        }
        return sum / (200 * 150 * 3);
      }

      expect(error(CompressionLevel.low), 0,
          reason: 'PNG stays lossless at Low');
      expect(error(CompressionLevel.medium), greaterThan(0));
      expect(error(CompressionLevel.maximum),
          greaterThan(error(CompressionLevel.medium)));
    });

    test('a target size shrinks the picture, in the upright frame, never up',
        () {
      final file = folder.write('b.jpg', jpeg(noisy(400, 200), orientation: 6));
      final spec = specOf(file); // upright 200 x 400
      final out = processImage(spec,
          compression: CompressionLevel.medium,
          target: (width: 100, height: 200));
      final result = img.decodeImage(out.bytes)!;
      expect((result.width, result.height), (100, 200));
      // A target larger than the picture does not enlarge it.
      final same = processImage(spec,
          compression: CompressionLevel.medium,
          target: (width: 800, height: 1600));
      final unchanged = img.decodeImage(same.bytes)!;
      expect((unchanged.width, unchanged.height), (200, 400));
    });

    test('a resize keeps the aspect ratio of what is shown', () {
      final file = folder.write('a.png', png(noisy(300, 200)));
      final out = processImage(specOf(file),
          compression: CompressionLevel.medium,
          target: (width: 150, height: 100));
      final result = img.decodeImage(out.bytes)!;
      expect(result.width / result.height, closeTo(1.5, 0.01));
    });
  });

  group('processing never silently degrades a bad picture', () {
    test('a picture that changed after it was checked is refused', () {
      final file = folder.write('c.png', png(marked(40, 30)));
      final spec = specOf(file);
      file.writeAsBytesSync(png(marked(50, 40)));
      expect(
          failureOf(() => processImage(spec, compression: CompressionLevel.low))
              ?.kind,
          ImagePdfFailure.sourceChanged);
    });

    test('a picture that vanished is refused by kind', () {
      final file = folder.write('v.png', png(marked(40, 30)));
      final spec = specOf(file);
      file.deleteSync();
      expect(
          failureOf(() => processImage(spec, compression: CompressionLevel.low))
              ?.kind,
          ImagePdfFailure.missingSource);
    });

    test('the original file is never written', () {
      final bytes = jpeg(noisy(100, 80), orientation: 6, privateMetadata: true);
      final file = folder.write('keep.jpg', bytes);
      final before = file.lastModifiedSync();
      for (final level in CompressionLevel.values) {
        processImage(specOf(file), compression: level);
      }
      expect(file.readAsBytesSync(), bytes);
      expect(file.lastModifiedSync(), before);
    });

    test('GIF and BMP pictures are read like the rest', () {
      final gif = folder.write(
          'g.gif', Uint8List.fromList(img.GifEncoder().encode(marked(30, 20))));
      final bmp = folder.write(
          'b.bmp', Uint8List.fromList(img.BmpEncoder().encode(marked(30, 20))));
      for (final file in [gif, bmp]) {
        final spec = specOf(file);
        expect((spec.width, spec.height), (30, 20));
        final out = processImage(spec, compression: CompressionLevel.medium);
        expect(img.decodeImage(out.bytes), isNotNull);
      }
    });
  });
}
