import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  HEAD_BYTES,
  TAIL_BYTES,
  TOOLKIT_CONTENT_TYPES,
  contentTypeAllowedForTool,
  contentTypeOfExtension,
  detectContentType,
  hasValidFraming,
  isToolkitContentType,
  toHex,
  toolkitExtension,
} from '../toolkit_content.js';
import { jpegBytes, pdfBytes, pngBytes } from './toolkit_fakes.mjs';

function frame(contentType, bytes) {
  return hasValidFraming(
    contentType,
    bytes.slice(0, HEAD_BYTES),
    bytes.slice(Math.max(0, bytes.length - TAIL_BYTES)),
    bytes.length,
  );
}

test('exactly three formats are accepted, each with one extension', () => {
  assert.deepEqual(Object.keys(TOOLKIT_CONTENT_TYPES), ['application/pdf', 'image/jpeg', 'image/png']);
  assert.deepEqual(['application/pdf', 'image/jpeg', 'image/png'].map(toolkitExtension), ['pdf', 'jpg', 'png']);
  for (const bad of ['image/gif', 'IMAGE/PNG', 'image/png ', 'application/pdf; x=1', '', null, undefined, 3, '__proto__', 'toString']) {
    assert.equal(isToolkitContentType(bad), false, String(bad));
    assert.equal(toolkitExtension(bad), null, String(bad));
  }
  assert.equal(contentTypeOfExtension('jpg'), 'image/jpeg');
  assert.equal(contentTypeOfExtension('jpeg'), null);
  assert.equal(contentTypeOfExtension('PNG'), null);
});

test('only the Scanner may store an image; every tool may store a PDF', () => {
  for (const tool of ['scanner', 'combine_pdfs', 'image_to_pdf', 'signature']) {
    assert.equal(contentTypeAllowedForTool(tool, 'application/pdf'), true, tool);
    assert.equal(contentTypeAllowedForTool(tool, 'image/jpeg'), tool === 'scanner', tool);
    assert.equal(contentTypeAllowedForTool(tool, 'image/png'), tool === 'scanner', tool);
    assert.equal(contentTypeAllowedForTool(tool, 'image/gif'), false, tool);
  }
  assert.equal(contentTypeAllowedForTool('notes', 'application/pdf'), true, 'tool names are validated elsewhere');
  assert.equal(contentTypeAllowedForTool('scanner', undefined), false);
});

test('the leading bytes identify the format', () => {
  assert.equal(detectContentType(pdfBytes()), 'application/pdf');
  assert.equal(detectContentType(jpegBytes()), 'image/jpeg');
  assert.equal(detectContentType(pngBytes()), 'image/png');
  assert.equal(detectContentType(new TextEncoder().encode('GIF89a......')), null);
  assert.equal(detectContentType(new TextEncoder().encode('<html>')), null);
  assert.equal(detectContentType(new Uint8Array(0)), null);
  assert.equal(detectContentType(new TextEncoder().encode('%PDF-3.0\n')), null, 'only PDF 1.x and 2.x');
});

test('complete containers pass; every kind of truncation or splice fails', () => {
  assert.equal(frame('application/pdf', pdfBytes()), true);
  assert.equal(frame('image/jpeg', jpegBytes()), true);
  assert.equal(frame('image/png', pngBytes()), true);
  assert.equal(frame('image/jpeg', Uint8Array.from([...jpegBytes(), 0, 0, 0])), true, 'padding zeros');
  assert.equal(frame('image/jpeg', Uint8Array.from([...jpegBytes(), ...new Array(40).fill(0)])), false, 'too much padding');

  assert.equal(frame('application/pdf', pdfBytes().slice(0, -8)), false);
  assert.equal(frame('image/jpeg', jpegBytes().slice(0, -2)), false);
  assert.equal(frame('image/jpeg', Uint8Array.from([0xff, 0xd8, 0xff])), false, 'a bare signature');
  assert.equal(frame('image/png', pngBytes().slice(0, -1)), false);
  assert.equal(frame('image/png', pngBytes().slice(0, 30)), false);

  // The declared format must be the detected one.
  assert.equal(frame('application/pdf', jpegBytes()), false);
  assert.equal(frame('image/png', jpegBytes()), false);
  assert.equal(frame('image/jpeg', pngBytes()), false);
  assert.equal(frame('image/jpeg', pdfBytes()), false);
  assert.equal(frame('image/gif', pngBytes()), false);
});

test('polyglots: the header of one format with the ending of another is refused', () => {
  const eof = new TextEncoder().encode('\n%%EOF\n');
  assert.equal(frame('application/pdf', Uint8Array.from([...jpegBytes(), ...eof])), false, 'jpeg bytes ending like a PDF');
  assert.equal(frame('application/pdf', Uint8Array.from([...pngBytes(), ...eof])), false, 'png bytes ending like a PDF');
  assert.equal(frame('image/jpeg', Uint8Array.from([...pngBytes(), 0xff, 0xd9])), false, 'png bytes ending like a JPEG');
  assert.equal(frame('image/jpeg', Uint8Array.from([...pdfBytes(), 0xff, 0xd9])), false, 'pdf bytes ending like a JPEG');
  assert.equal(frame('image/png', Uint8Array.from([...jpegBytes(), 0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82])), false, 'jpeg bytes ending like a PNG');
});

test('PNG dimensions and the IHDR chunk are sane', () => {
  const huge = pngBytes();
  huge.set([0xff, 0xff, 0xff, 0xff], 16);
  assert.equal(frame('image/png', huge), false);
  const zeroHeight = pngBytes();
  zeroHeight.set([0, 0, 0, 0], 20);
  assert.equal(frame('image/png', zeroHeight), false);
  const wrongName = pngBytes();
  wrongName[12] = 0x58;
  assert.equal(frame('image/png', wrongName), false);
});

test('hex output is lower-case and fixed width', () => {
  assert.equal(toHex(Uint8Array.from([0, 1, 15, 16, 255])), '00010f10ff');
});
