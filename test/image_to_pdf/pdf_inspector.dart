import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One picture drawn on a page, as the page's content stream says.
class DrawnImage {
  DrawnImage({
    required this.x,
    required this.top,
    required this.width,
    required this.height,
    required this.objectId,
  });

  /// Points from the page's left / top edge.
  final double x;
  final double top;
  final double width;
  final double height;
  final int objectId;

  double get right => x + width;
  double get bottom => top + height;
}

/// One page of an UNENCRYPTED PDF written by the engine: its size and what is
/// drawn on it. The PDF library cannot render, so tests read the file's own
/// structure instead.
class InspectedPage {
  InspectedPage(this.width, this.height, this.content, this.images);

  final double width;
  final double height;
  final String content;
  final List<DrawnImage> images;
}

class InspectedImage {
  InspectedImage(this.id, this.width, this.height, this.filter, this.data);

  final int id;
  final int width;
  final int height;
  final String filter;
  final Uint8List data;

  /// The decoded pixels of a DCT (JPEG) picture; null for other filters.
  img.Image? get decoded => filter == 'DCTDecode' ? img.decodeJpg(data) : null;
}

class PdfInspector {
  PdfInspector(Uint8List bytes)
      : _text = latin1.decode(bytes),
        _bytes = bytes {
    final pattern = RegExp(r'(?:^|[\r\n])(\d+) 0 obj([\s\S]*?)endobj');
    for (final m in pattern.allMatches(_text)) {
      _objects[int.parse(m.group(1)!)] = _Obj(m.start, m.group(2)!);
    }
  }

  final String _text;
  final Uint8List _bytes;
  final Map<int, _Obj> _objects = <int, _Obj>{};

  Uint8List get bytes => _bytes;

  /// Whether the file's raw bytes contain [text] (ASCII).
  bool containsRaw(String text) => _text.contains(text);

  bool get hasEncryptEntry => _text.contains('/Encrypt');

  List<InspectedPage> get pages {
    final ids = _objects.entries
        .where((e) => RegExp(r'/Type\s*/Page(?![a-z])').hasMatch(e.value.body))
        .map((e) => e.key)
        .toList()
      ..sort();
    return <InspectedPage>[for (final id in ids) _page(id)];
  }

  InspectedPage _page(int id) {
    final body = _objects[id]!.body;
    final content = StringBuffer();
    final contents =
        RegExp(r'/Contents\s*(\[[^\]]*\]|\d+ 0 R)').firstMatch(body);
    if (contents != null) {
      for (final ref in RegExp(r'(\d+) 0 R').allMatches(contents.group(1)!)) {
        content.writeln(_inflate(int.parse(ref.group(1)!)));
      }
    }
    final names = <String, int>{};
    final xo = RegExp(r'/XObject\s*<<([\s\S]*?)>>').firstMatch(body);
    if (xo != null) {
      for (final m in RegExp(r'/(\S+)\s+(\d+) 0 R').allMatches(xo.group(1)!)) {
        names[m.group(1)!] = int.parse(m.group(2)!);
      }
    }
    // The page size: its parent's MediaBox, or the page's own.
    final size = _mediaBox(id);
    final drawn = <DrawnImage>[];
    final text = content.toString();
    final pattern = RegExp(
        r'(-?[\d.]+) 0 0 (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) cm\s*/(\S+) Do');
    for (final m in pattern.allMatches(text)) {
      final w = double.parse(m.group(1)!);
      final h = double.parse(m.group(2)!);
      final x = double.parse(m.group(3)!);
      final y = double.parse(m.group(4)!);
      final object = names[m.group(5)!];
      if (object == null) continue;
      drawn.add(DrawnImage(
          x: x, top: -(y + h), width: w, height: h, objectId: object));
    }
    return InspectedPage(size.$1, size.$2, text, drawn);
  }

  (double, double) _mediaBox(int pageId) {
    var current = pageId;
    for (var depth = 0; depth < 6; depth++) {
      final body = _objects[current]?.body ?? '';
      final box = RegExp(
              r'/MediaBox\s*\[\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s*\]')
          .firstMatch(body);
      if (box != null) {
        return (
          double.parse(box.group(3)!) - double.parse(box.group(1)!),
          double.parse(box.group(4)!) - double.parse(box.group(2)!),
        );
      }
      final parent = RegExp(r'/Parent (\d+) 0 R').firstMatch(body);
      if (parent == null) break;
      current = int.parse(parent.group(1)!);
    }
    throw StateError('page $pageId has no MediaBox');
  }

  String _inflate(int id) {
    final raw = _streamOf(id);
    try {
      return latin1.decode(ZLibDecoder().convert(raw));
    } catch (_) {
      return latin1.decode(raw);
    }
  }

  Uint8List _streamOf(int id) {
    final obj = _objects[id]!;
    final start = obj.body.indexOf('stream');
    var from = start + 6;
    if (obj.body.codeUnitAt(from) == 13) from++;
    if (obj.body.codeUnitAt(from) == 10) from++;
    final length = RegExp(r'/Length (\d+)').firstMatch(obj.body);
    final to = length != null
        ? from + int.parse(length.group(1)!)
        : obj.body.lastIndexOf('endstream');
    return Uint8List.fromList(latin1.encode(obj.body.substring(from, to)));
  }

  InspectedImage image(int id) {
    final body = _objects[id]!.body;
    int number(String key) =>
        int.parse(RegExp('/$key (\\d+)').firstMatch(body)!.group(1)!);
    final filter = RegExp(r'/Filter\s*/(\w+)').firstMatch(body)!.group(1)!;
    return InspectedImage(
        id, number('Width'), number('Height'), filter, _streamOf(id));
  }

  /// All picture objects, in the order they were written.
  List<InspectedImage> get allImages {
    final ids = _objects.entries
        .where((e) => RegExp(r'/Subtype\s*/Image').hasMatch(e.value.body))
        .map((e) => e.key)
        .toList()
      ..sort();
    return <InspectedImage>[for (final id in ids) image(id)];
  }
}

class _Obj {
  _Obj(this.start, this.body);

  final int start;
  final String body;
}

/// Whether two colours are the same to within JPEG noise.
bool near(img.Pixel pixel, int r, int g, int b, {int tolerance = 14}) =>
    (pixel.r - r).abs() <= tolerance &&
    (pixel.g - g).abs() <= tolerance &&
    (pixel.b - b).abs() <= tolerance;
