import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:broker_wallet/src/services/signature/signature_models.dart';

/// Turns what the user drew or typed into the transparent PNG that is placed on
/// a page. The same PNG is shown on the editor's page and written into the PDF,
/// so a placed item looks the same in the preview and in the saved file, and a
/// text in Arabic or English is shaped by the phone's own text engine.
abstract interface class StampRenderer {
  /// A signature or initials from strokes. Throws a [SignatureException]
  /// (`stampFailed`) when there is nothing to draw or the image cannot be made.
  Future<StampAsset> renderDrawing({
    required String id,
    required StampKind kind,
    required SignatureDrawing drawing,
  });

  /// A typed item: initials, a date or a text. Throws a [SignatureException]
  /// (`stampFailed`) when the text is empty or the image cannot be made.
  Future<StampAsset> renderText({
    required String id,
    required StampKind kind,
    required String text,
    required int colorValue,
  });
}

/// The production renderer. Images are made at several times their logical size
/// (3x for ink, 4x for text, less when that would pass
/// [SignatureLimits.maxStampPixels]) so a stamp stays sharp when it is enlarged
/// on the page or the screen is zoomed.
class FlutterStampRenderer implements StampRenderer {
  const FlutterStampRenderer();

  static const double inkPixelRatio = 3;
  static const double textPixelRatio = 4;

  /// The logical font size of a typed item; its size on the page is set by the
  /// placement, not by this.
  static const double textFontSize = 20;

  static const double _textPadX = 4;
  static const double _textPadY = 3;

  double _capRatio(double ratio, double logicalW, double logicalH) {
    final longest = math.max(logicalW, logicalH);
    if (longest <= 0) return ratio;
    return math.min(ratio, SignatureLimits.maxStampPixels / longest);
  }

  @override
  Future<StampAsset> renderDrawing({
    required String id,
    required StampKind kind,
    required SignatureDrawing drawing,
  }) async {
    final box = drawing.bounds;
    if (box == null || !drawing.hasMeaningfulInk) {
      throw const SignatureException(SignatureFailure.stampFailed,
          detail: 'empty');
    }
    final pad = drawing.strokeWidth + 2;
    final logicalW = (box.right - box.left) + pad * 2;
    final logicalH = (box.bottom - box.top) + pad * 2;
    final ratio = _capRatio(inkPixelRatio, logicalW, logicalH);
    final pixelW = math.max(1, (logicalW * ratio).ceil());
    final pixelH = math.max(1, (logicalH * ratio).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelW / logicalW, pixelH / logicalH);
    canvas.translate(-(box.left - pad), -(box.top - pad));
    final paint = ui.Paint()
      ..color = ui.Color(drawing.colorValue)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = drawing.strokeWidth
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..isAntiAlias = true;
    final dot = ui.Paint()
      ..color = ui.Color(drawing.colorValue)
      ..style = ui.PaintingStyle.fill
      ..isAntiAlias = true;
    for (final stroke in drawing.strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(ui.Offset(stroke.first.x, stroke.first.y),
            drawing.strokeWidth / 2, dot);
        continue;
      }
      final path = ui.Path()..moveTo(stroke.first.x, stroke.first.y);
      for (var i = 1; i < stroke.length - 1; i++) {
        final midX = (stroke[i].x + stroke[i + 1].x) / 2;
        final midY = (stroke[i].y + stroke[i + 1].y) / 2;
        path.quadraticBezierTo(stroke[i].x, stroke[i].y, midX, midY);
      }
      path.lineTo(stroke.last.x, stroke.last.y);
      canvas.drawPath(path, paint);
    }
    final png = await _toPng(recorder, pixelW, pixelH);
    return StampAsset(
      id: id,
      kind: kind,
      png: png,
      pixelWidth: pixelW,
      pixelHeight: pixelH,
      drawing: drawing,
      colorValue: drawing.colorValue,
    );
  }

  @override
  Future<StampAsset> renderText({
    required String id,
    required StampKind kind,
    required String text,
    required int colorValue,
  }) async {
    final cleaned = StampText.clean(text,
        maxRunes: kind == StampKind.initials
            ? StampText.maxInitialsRunes
            : StampText.maxTextRunes);
    if (cleaned == null) {
      throw const SignatureException(SignatureFailure.stampFailed,
          detail: 'text');
    }
    final rtl = StampText.isRightToLeft(cleaned);
    final painter = TextPainter(
      text: TextSpan(
        text: cleaned,
        style: TextStyle(
          color: ui.Color(colorValue),
          fontSize: textFontSize,
          fontFamily: rtl ? 'NotoNaskhArabic' : 'NotoSans',
          fontFamilyFallback: const <String>['NotoNaskhArabic', 'NotoSans'],
          fontStyle: kind == StampKind.initials && !rtl
              ? FontStyle.italic
              : FontStyle.normal,
          fontWeight:
              kind == StampKind.initials ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final logicalW = painter.width + _textPadX * 2;
    final logicalH = painter.height + _textPadY * 2;
    final ratio = _capRatio(textPixelRatio, logicalW, logicalH);
    final pixelW = math.max(1, (logicalW * ratio).ceil());
    final pixelH = math.max(1, (logicalH * ratio).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelW / logicalW, pixelH / logicalH);
    painter.paint(canvas, const ui.Offset(_textPadX, _textPadY));
    painter.dispose();
    final png = await _toPng(recorder, pixelW, pixelH);
    return StampAsset(
      id: id,
      kind: kind,
      png: png,
      pixelWidth: pixelW,
      pixelHeight: pixelH,
      label: cleaned,
      colorValue: colorValue,
    );
  }

  Future<Uint8List> _toPng(
      ui.PictureRecorder recorder, int width, int height) async {
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const SignatureException(SignatureFailure.stampFailed,
            detail: 'png');
      }
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.length > SignatureLimits.maxStampBytes) {
        throw const SignatureException(SignatureFailure.stampFailed,
            detail: 'size');
      }
      return bytes;
    } on SignatureException {
      rethrow;
    } catch (_) {
      throw const SignatureException(SignatureFailure.stampFailed,
          detail: 'render');
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }
}
