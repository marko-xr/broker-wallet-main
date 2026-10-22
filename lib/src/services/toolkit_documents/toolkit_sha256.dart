// SHA-256 in plain Dart, so integrity checks of Toolkit documents need no new
// package (`crypto` is only a transitive dependency of this app). Streaming:
// a document is hashed chunk by chunk and never read into memory whole.

import 'dart:io';
import 'dart:typed_data';

/// Hashes a file; the app may supply one that runs off the UI isolate.
typedef ToolkitFileHasher = Future<String> Function(File file);

final class ToolkitSha256 {
  ToolkitSha256() {
    _h.setAll(0, _initial);
  }

  static const List<int> _initial = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final Uint32List _h = Uint32List(8);
  final Uint32List _w = Uint32List(64);
  final Uint8List _block = Uint8List(64);
  int _blockLength = 0;
  int _totalBytes = 0;
  bool _closed = false;

  /// Feeds [data]. Throws a [StateError] after [closeHex].
  void add(List<int> data) {
    if (_closed) throw StateError('The hash is already closed');
    _totalBytes += data.length;
    var index = 0;
    while (index < data.length) {
      final take = (64 - _blockLength) < (data.length - index)
          ? 64 - _blockLength
          : data.length - index;
      _block.setRange(_blockLength, _blockLength + take, data, index);
      _blockLength += take;
      index += take;
      if (_blockLength == 64) {
        _compress(_block);
        _blockLength = 0;
      }
    }
  }

  /// The lower-case hex digest. The hash cannot be used afterwards.
  String closeHex() {
    if (_closed) throw StateError('The hash is already closed');
    final bitLength = _totalBytes * 8;
    _closed = true;
    _block[_blockLength++] = 0x80;
    if (_blockLength > 56) {
      _block.fillRange(_blockLength, 64, 0);
      _compress(_block);
      _blockLength = 0;
    }
    _block.fillRange(_blockLength, 56, 0);
    for (var i = 0; i < 8; i++) {
      _block[63 - i] = (bitLength >> (8 * i)) & 0xff;
    }
    _compress(_block);
    final out = StringBuffer();
    for (final word in _h) {
      out.write(word.toRadixString(16).padLeft(8, '0'));
    }
    return out.toString();
  }

  static String hexOfBytes(List<int> bytes) {
    final hash = ToolkitSha256()..add(bytes);
    return hash.closeHex();
  }

  /// Hashes [file] as a stream.
  static Future<String> hexOfFile(File file) async {
    final hash = ToolkitSha256();
    await for (final chunk in file.openRead()) {
      hash.add(chunk);
    }
    return hash.closeHex();
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  void _compress(Uint8List b) {
    for (var i = 0; i < 16; i++) {
      final j = i * 4;
      _w[i] = (b[j] << 24) | (b[j + 1] << 16) | (b[j + 2] << 8) | b[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 =
          _rotr(_w[i - 15], 7) ^ _rotr(_w[i - 15], 18) ^ (_w[i - 15] >> 3);
      final s1 =
          _rotr(_w[i - 2], 17) ^ _rotr(_w[i - 2], 19) ^ (_w[i - 2] >> 10);
      _w[i] = _w[i - 16] + s0 + _w[i - 7] + s1;
    }
    var a = _h[0];
    var b2 = _h[1];
    var c = _h[2];
    var d = _h[3];
    var e = _h[4];
    var f = _h[5];
    var g = _h[6];
    var h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (h + s1 + ch + _k[i] + _w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b2) ^ (a & c) ^ (b2 & c);
      final t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b2;
      b2 = a;
      a = (t1 + t2) & 0xffffffff;
    }
    _h[0] += a;
    _h[1] += b2;
    _h[2] += c;
    _h[3] += d;
    _h[4] += e;
    _h[5] += f;
    _h[6] += g;
    _h[7] += h;
  }
}
