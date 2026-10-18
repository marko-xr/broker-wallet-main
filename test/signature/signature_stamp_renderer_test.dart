import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';
import 'package:broker_wallet/src/services/signature/signature_stamp_renderer.dart';

import 'signature_fixtures.dart';

/// The real renderer: dart:ui draws the ink and the text, so these run in a
/// widget-test binding and wait for the engine with `runAsync`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const renderer = FlutterStampRenderer();

  Future<T> run<T>(WidgetTester tester, Future<T> Function() action) async {
    late T result;
    await tester.runAsync(() async {
      result = await action();
    });
    return result;
  }

  img.Image decode(StampAsset asset) => img.decodePng(asset.png)!;

  bool transparent(img.Pixel pixel) => pixel.a == 0;

  group('ink', () {
    testWidgets('a signature is a transparent PNG with the pen\'s colour',
        (tester) async {
      final asset = await run(
          tester,
          () => renderer.renderDrawing(
                id: 'a',
                kind: StampKind.signature,
                drawing: drawingOf(colorValue: 0xFFFF0000),
              ));
      final header = readPngHeader(asset.png)!;
      expect(header.hasAlphaChannel, isTrue,
          reason: 'transparent, not a white box');
      expect(header.width, asset.pixelWidth);
      expect(header.height, asset.pixelHeight);
      final image = decode(asset);
      // The margin is transparent all the way round.
      for (var x = 0; x < image.width; x++) {
        expect(transparent(image.getPixel(x, 0)), isTrue);
        expect(transparent(image.getPixel(x, image.height - 1)), isTrue);
      }
      for (var y = 0; y < image.height; y++) {
        expect(transparent(image.getPixel(0, y)), isTrue);
        expect(transparent(image.getPixel(image.width - 1, y)), isTrue);
      }
      // There is ink, and what is solid is the pen's colour.
      var solid = 0;
      for (final pixel in image) {
        if (pixel.a > 200) {
          solid++;
          expect(pixel.r, greaterThan(200));
          expect(pixel.g, lessThan(60));
          expect(pixel.b, lessThan(60));
        }
      }
      expect(solid, greaterThan(50));
      expect(asset.colorValue, 0xFFFF0000);
      expect(asset.drawing, isNotNull,
          reason: 'the strokes are kept for editing');
    });

    testWidgets('it is drawn at several times the pad\'s resolution, uncropped',
        (tester) async {
      final drawing = drawingOf();
      final asset = await run(
          tester,
          () => renderer.renderDrawing(
              id: 'a', kind: StampKind.signature, drawing: drawing));
      final box = drawing.bounds!;
      final pad = drawing.strokeWidth + 2;
      final logicalW = (box.right - box.left) + pad * 2;
      final logicalH = (box.bottom - box.top) + pad * 2;
      expect(asset.pixelWidth,
          (logicalW * FlutterStampRenderer.inkPixelRatio).ceil());
      expect(asset.pixelHeight,
          (logicalH * FlutterStampRenderer.inkPixelRatio).ceil());
      expect(asset.aspect, closeTo(logicalW / logicalH, 0.01),
          reason: 'never stretched');
      // The first and the last point of the stroke are both inside the image.
      final image = decode(asset);
      bool inkNear(double x, double y) {
        final px =
            ((x - (box.left - pad)) * asset.pixelWidth / logicalW).round();
        final py =
            ((y - (box.top - pad)) * asset.pixelHeight / logicalH).round();
        for (var dy = -6; dy <= 6; dy++) {
          for (var dx = -6; dx <= 6; dx++) {
            final ix = px + dx;
            final iy = py + dy;
            if (ix < 0 || iy < 0 || ix >= image.width || iy >= image.height) {
              continue;
            }
            if (image.getPixel(ix, iy).a > 128) return true;
          }
        }
        return false;
      }

      expect(inkNear(20, 80), isTrue);
      expect(inkNear(250, 70), isTrue);
      // The curve passes through the middle of the first segment.
      expect(inkNear(85, 65), isTrue);
    });

    testWidgets('several strokes all appear', (tester) async {
      final drawing = drawingOf(twoStrokes: true);
      final asset = await run(
          tester,
          () => renderer.renderDrawing(
              id: 'a', kind: StampKind.signature, drawing: drawing));
      final image = decode(asset);
      final box = drawing.bounds!;
      final pad = drawing.strokeWidth + 2;
      final scaleX = asset.pixelWidth / ((box.right - box.left) + pad * 2);
      final scaleY = asset.pixelHeight / ((box.bottom - box.top) + pad * 2);
      // The second stroke runs along y = 100..105 near the bottom.
      final px = ((135 - (box.left - pad)) * scaleX).round();
      final py = ((102 - (box.top - pad)) * scaleY).round();
      var found = false;
      for (var dy = -8; dy <= 8; dy++) {
        if (image.getPixel(px, py + dy).a > 128) found = true;
      }
      expect(found, isTrue);
    });

    testWidgets('a stray dot or an empty pad is not a signature',
        (tester) async {
      final dot = SignatureDrawing(
        points: const [InkPoint(50, 50, isStrokeStart: true)],
        colorValue: 0xFF000000,
        strokeWidth: 3,
        canvasWidth: 300,
        canvasHeight: 120,
      );
      for (final drawing in [
        dot,
        dot.copyWith(points: const <InkPoint>[]),
      ]) {
        late Object error;
        await tester.runAsync(() async {
          try {
            await renderer.renderDrawing(
                id: 'a', kind: StampKind.signature, drawing: drawing);
          } catch (e) {
            error = e;
          }
        });
        expect(error, isA<SignatureException>());
        expect(
            (error as SignatureException).kind, SignatureFailure.stampFailed);
      }
    });

    testWidgets('a huge drawing is scaled down to the size limit',
        (tester) async {
      final huge = SignatureDrawing(
        points: const [
          InkPoint(0, 0, isStrokeStart: true),
          InkPoint(4000, 2000),
        ],
        colorValue: 0xFF000000,
        strokeWidth: 3,
        canvasWidth: 4000,
        canvasHeight: 2000,
      );
      final asset = await run(
          tester,
          () => renderer.renderDrawing(
              id: 'a', kind: StampKind.signature, drawing: huge));
      expect(
          asset.pixelWidth, lessThanOrEqualTo(SignatureLimits.maxStampPixels));
      expect(
          asset.pixelHeight, lessThanOrEqualTo(SignatureLimits.maxStampPixels));
      expect(
          asset.png.length, lessThanOrEqualTo(SignatureLimits.maxStampBytes));
      expect(asset.aspect, closeTo(2, 0.01));
    });
  });

  group('typed text', () {
    testWidgets('English and Arabic both make a transparent image',
        (tester) async {
      for (final text in ['Mohammed Ali', 'محمد أحمد', 'ABC', 'عقد 2026']) {
        final asset = await run(
            tester,
            () => renderer.renderText(
                id: 't',
                kind: StampKind.text,
                text: text,
                colorValue: 0xFF1565C0));
        expect(asset.label, text);
        expect(asset.pixelWidth, greaterThan(0));
        expect(asset.pixelHeight, greaterThan(0));
        final image = decode(asset);
        expect(transparent(image.getPixel(0, 0)), isTrue, reason: text);
        var ink = 0;
        for (final pixel in image) {
          if (pixel.a > 128) ink++;
        }
        expect(ink, greaterThan(20), reason: text);
      }
    });

    testWidgets('the colour chosen is the colour drawn', (tester) async {
      final asset = await run(
          tester,
          () => renderer.renderText(
              id: 't',
              kind: StampKind.date,
              text: '18/10/2026',
              colorValue: 0xFF00FF00));
      final image = decode(asset);
      var solidGreen = 0;
      for (final pixel in image) {
        if (pixel.a > 250 && pixel.g > 200 && pixel.r < 60 && pixel.b < 60) {
          solidGreen++;
        }
      }
      expect(solidGreen, greaterThan(20));
      expect(asset.colorValue, 0xFF00FF00);
    });

    testWidgets('initials are limited, text is limited, blank is refused',
        (tester) async {
      Future<SignatureFailure?> failure(StampKind kind, String text) async {
        SignatureFailure? kindOf;
        await tester.runAsync(() async {
          try {
            await renderer.renderText(
                id: 't', kind: kind, text: text, colorValue: 0xFF000000);
          } on SignatureException catch (e) {
            kindOf = e.kind;
          }
        });
        return kindOf;
      }

      expect(await failure(StampKind.initials, 'ABCDEFG'),
          SignatureFailure.stampFailed);
      expect(await failure(StampKind.initials, 'ABCDEF'), isNull);
      expect(
          await failure(StampKind.text, '   '), SignatureFailure.stampFailed);
      expect(await failure(StampKind.text, 'x' * 81),
          SignatureFailure.stampFailed);
      expect(await failure(StampKind.text, '\u202E\u200F'),
          SignatureFailure.stampFailed);
    });

    testWidgets('a long text is scaled to the size limit, not cut off',
        (tester) async {
      final asset = await run(
          tester,
          () => renderer.renderText(
              id: 't',
              kind: StampKind.text,
              text: 'W' * 80,
              colorValue: 0xFF000000));
      expect(
          asset.pixelWidth, lessThanOrEqualTo(SignatureLimits.maxStampPixels));
      expect(
          asset.pixelHeight, lessThanOrEqualTo(SignatureLimits.maxStampPixels));
      expect(asset.aspect, greaterThan(10), reason: 'a long single line');
    });

    testWidgets('text that reads right to left is told apart', (tester) async {
      expect(StampText.isRightToLeft('محمد'), isTrue);
      expect(StampText.isRightToLeft('Mohammed'), isFalse);
      final arabic = await run(
          tester,
          () => renderer.renderText(
              id: 't',
              kind: StampKind.text,
              text: 'محمد',
              colorValue: 0xFF000000));
      final latin = await run(
          tester,
          () => renderer.renderText(
              id: 't',
              kind: StampKind.text,
              text: 'ABCD',
              colorValue: 0xFF000000));
      // The test font draws every letter as a box, so the pictures cannot tell
      // the two apart; what is pinned here is that both are made, with the text
      // kept for editing, and that the direction is decided from the text.
      expect(arabic.label, 'محمد');
      expect(latin.label, 'ABCD');
      expect(arabic.pixelWidth, greaterThan(0));
      expect(latin.pixelWidth, greaterThan(0));
    });
  });
}
