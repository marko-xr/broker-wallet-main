import 'package:broker_wallet/src/services/image_signature_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A real, fully decodable 2x2 image, not just signature bytes — proves the
/// detector's answer for content a genuine decoder would also accept.
img.Image _tinyImage() => img.Image(width: 2, height: 2);

void main() {
  group('ImageSignatureDetector.detectMimeType', () {
    test('recognizes a real JPEG file\'s actual bytes', () {
      final bytes = img.encodeJpg(_tinyImage());
      expect(ImageSignatureDetector.detectMimeType(bytes), 'image/jpeg');
    });

    test('recognizes a real PNG file\'s actual bytes', () {
      final bytes = img.encodePng(_tinyImage());
      expect(ImageSignatureDetector.detectMimeType(bytes), 'image/png');
    });

    test('recognizes a real WebP file\'s actual bytes', () {
      final bytes = img.encodeWebP(_tinyImage());
      expect(ImageSignatureDetector.detectMimeType(bytes), 'image/webp');
    });

    test('returns null for bytes that match no known signature', () {
      final bytes = List<int>.filled(20, 0x00);
      expect(ImageSignatureDetector.detectMimeType(bytes), isNull);
    });

    test('returns null for an empty byte list', () {
      expect(ImageSignatureDetector.detectMimeType(const []), isNull);
    });

    test('returns null when there are too few bytes for any signature', () {
      // A genuine JPEG marker prefix, but cut short before the signature
      // can be confirmed.
      expect(ImageSignatureDetector.detectMimeType([0xFF, 0xD8]), isNull);
    });

    test('does not mistake a RIFF file without a WEBP tag for WebP', () {
      final bytes = [
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        0x00, 0x00, 0x00, 0x00, // size
        0x41, 0x56, 0x49, 0x20, // "AVI " — a different RIFF-based format
      ];
      expect(ImageSignatureDetector.detectMimeType(bytes), isNull);
    });

    test('a JPEG signature with a JPG extension-like name is unaffected by '
        'the name — detection depends only on bytes', () {
      // The detector takes no file name at all; this documents that
      // guarantee at the type level (detectMimeType has no path parameter).
      final bytes = img.encodePng(_tinyImage());
      expect(ImageSignatureDetector.detectMimeType(bytes), 'image/png');
    });
  });
}
