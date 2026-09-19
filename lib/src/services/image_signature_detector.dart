/// Detects an image's real MIME type from its actual leading bytes,
/// independent of any file name or extension.
///
/// This is the client-side counterpart to the Offer Media Worker's own
/// server-side byte-signature check (`detectImageMimeFromBytes` in
/// `cloudflare/workers/r2-profile-upload/worker.js`): both sides identify
/// the same three container formats from the same physical signatures, so
/// a file the client classifies as JPEG/PNG/WebP is the type the Worker
/// will independently confirm it as too. Returns `null` when the bytes
/// don't match any of these signatures, or there aren't enough of them to
/// decide — this only recognizes a format, it never decodes or validates
/// that the image data past the signature is well-formed.
abstract final class ImageSignatureDetector {
  static const List<int> _jpegSignature = [0xFF, 0xD8, 0xFF];
  static const List<int> _pngSignature = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  ];
  static const List<int> _riffTag = [0x52, 0x49, 0x46, 0x46]; // "RIFF"
  static const int _webpTagOffset = 8;
  static const List<int> _webpTag = [0x57, 0x45, 0x42, 0x50]; // "WEBP"

  /// The number of leading bytes this detector needs to recognize any
  /// signature it supports. Passing fewer bytes is safe — they are simply
  /// treated as not matching anything.
  static const int minimumBytesNeeded = _webpTagOffset + 4;

  /// Returns the detected MIME type ('image/jpeg', 'image/png',
  /// 'image/webp') for [bytes], or `null` if it matches none of them.
  static String? detectMimeType(List<int> bytes) {
    if (_startsWith(bytes, 0, _jpegSignature)) return 'image/jpeg';
    if (_startsWith(bytes, 0, _pngSignature)) return 'image/png';
    if (_startsWith(bytes, 0, _riffTag) &&
        _startsWith(bytes, _webpTagOffset, _webpTag)) {
      return 'image/webp';
    }
    return null;
  }

  static bool _startsWith(List<int> bytes, int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }
}
