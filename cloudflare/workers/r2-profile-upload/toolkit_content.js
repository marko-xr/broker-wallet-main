/**
 * What a Toolkit document may be, and how a stored object is recognized.
 *
 * Three binary formats, all kept as the ORIGINAL bytes (nothing is converted):
 * PDF, JPEG and PNG. The SOURCE TOOL (scanner, combine_pdfs, image_to_pdf,
 * signature) and the BINARY FORMAT are separate fields: every tool produces PDFs,
 * only the Scanner may also store JPEG / PNG scans.
 *
 * The extension of an object key comes from here and nowhere else; a client name,
 * extension or MIME label is never used to build a key. A stored object is
 * accepted only if (1) its stored content type equals the declared one exactly,
 * (2) its leading bytes identify the declared format and (3) its leading and
 * trailing bytes have that format's framing. That proves the container is what
 * it claims and is not truncated; it does NOT prove the image or page data is
 * decodable, and it is not a digest (see the integrity contract in
 * docs/toolbox/cloud-documents-rollout.md).
 *
 * Pure and import-free so it runs under Node and workerd alike.
 */

const MIB = 1024 * 1024;

export const TOOLKIT_CONTENT_TYPES = Object.freeze({
  'application/pdf': Object.freeze({ extension: 'pdf', kind: 'pdf', hardMaxBytes: 250 * MIB }),
  'image/jpeg': Object.freeze({ extension: 'jpg', kind: 'image', hardMaxBytes: 64 * MIB }),
  'image/png': Object.freeze({ extension: 'png', kind: 'image', hardMaxBytes: 64 * MIB }),
});

/** Bytes read from the start and the end of a stored object to check it. */
export const HEAD_BYTES = 32;
export const TAIL_BYTES = 1024;

export function isToolkitContentType(value) {
  return typeof value === 'string' && Object.hasOwn(TOOLKIT_CONTENT_TYPES, value);
}

/** Every tool may store a PDF; only the Scanner may store an image. */
export function contentTypeAllowedForTool(tool, contentType) {
  if (!isToolkitContentType(contentType)) return false;
  return contentType === 'application/pdf' || tool === 'scanner';
}

/** The extension of [contentType], or null when it is not accepted. */
export function toolkitExtension(contentType) {
  return isToolkitContentType(contentType) ? TOOLKIT_CONTENT_TYPES[contentType].extension : null;
}

/** The content type of an object key's extension, or null. */
export function contentTypeOfExtension(extension) {
  for (const [contentType, info] of Object.entries(TOOLKIT_CONTENT_TYPES)) {
    if (info.extension === extension) return contentType;
  }
  return null;
}

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const PNG_IEND = [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82];
const MAX_JPEG_TRAILING_ZEROS = 16;
const MAX_PNG_DIMENSION = 100000;

function startsWith(bytes, signature) {
  return bytes.length >= signature.length && signature.every((value, index) => bytes[index] === value);
}

function isPdfHead(bytes) {
  return bytes.length >= 8 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 &&
    bytes[3] === 0x46 && bytes[4] === 0x2d && (bytes[5] === 0x31 || bytes[5] === 0x32) &&
    bytes[6] === 0x2e && bytes[7] >= 0x30 && bytes[7] <= 0x39;
}

/** The format the leading bytes identify, or null. */
export function detectContentType(head) {
  if (isPdfHead(head)) return 'application/pdf';
  if (startsWith(head, [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith(head, PNG_SIGNATURE)) return 'image/png';
  return null;
}

function uint32(bytes, offset) {
  return ((bytes[offset] << 24) >>> 0) + (bytes[offset + 1] << 16) + (bytes[offset + 2] << 8) + bytes[offset + 3];
}

/**
 * Whether [head] (first bytes) and [tail] (last min(size, TAIL_BYTES) bytes) of
 * an object of [size] bytes are a complete [contentType] container.
 */
export function hasValidFraming(contentType, head, tail, size) {
  if (detectContentType(head) !== contentType) return false;
  switch (contentType) {
    case 'application/pdf': {
      if (size < 16) return false;
      let text = '';
      for (const byte of tail) text += String.fromCharCode(byte);
      return text.includes('%%EOF');
    }
    case 'image/jpeg': {
      if (size < 4) return false;
      let end = tail.length;
      let zeros = 0;
      while (end > 0 && tail[end - 1] === 0x00 && zeros < MAX_JPEG_TRAILING_ZEROS) {
        end -= 1;
        zeros += 1;
      }
      return end >= 2 && tail[end - 2] === 0xff && tail[end - 1] === 0xd9;
    }
    case 'image/png': {
      // signature, a 13-byte IHDR chunk with a real size, ... and a closing IEND.
      if (size < 57 || head.length < 24) return false;
      if (uint32(head, 8) !== 13 || head[12] !== 0x49 || head[13] !== 0x48 ||
          head[14] !== 0x44 || head[15] !== 0x52) return false;
      const width = uint32(head, 16);
      const height = uint32(head, 20);
      if (width < 1 || height < 1 || width > MAX_PNG_DIMENSION || height > MAX_PNG_DIMENSION) return false;
      return tail.length >= PNG_IEND.length &&
        PNG_IEND.every((value, index) => tail[tail.length - PNG_IEND.length + index] === value);
    }
    default:
      return false;
  }
}

/** Lower-case hex of a byte array. */
export function toHex(bytes) {
  let out = '';
  for (const byte of bytes) out += byte.toString(16).padStart(2, '0');
  return out;
}
