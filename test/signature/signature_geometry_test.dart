import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/signature/signature_geometry.dart';

PageGeometry page(double w, double h, {int rotation = 0}) => PageGeometry(
      mediaBox: PdfBox(0, 0, w, h),
      rotation: rotation,
    );

void expectPoint(PagePoint actual, double x, double y, [double eps = 1e-9]) {
  expect(actual.x, closeTo(x, eps), reason: 'x of $actual');
  expect(actual.y, closeTo(y, eps), reason: 'y of $actual');
}

void expectUserRect(UserRect actual, UserRect expected) {
  expect(actual.isCloseTo(expected, 1e-9), isTrue,
      reason: 'got $actual, wanted $expected');
}

void main() {
  group('page sizes', () {
    // A3, A4, Letter, Legal and an arbitrary size, in points.
    const sizes = <String, List<double>>{
      'A3': [842, 1191],
      'A4': [595.276, 841.89],
      'Letter': [612, 792],
      'Legal': [612, 1008],
      'arbitrary': [333.3, 777.7],
    };

    test('the visible size follows the boxes, and turns with a quarter turn',
        () {
      sizes.forEach((name, size) {
        final upright = page(size[0], size[1]);
        expect(upright.width, closeTo(size[0], 1e-9), reason: name);
        expect(upright.height, closeTo(size[1], 1e-9), reason: name);
        for (final turned in [90, 270]) {
          final g = page(size[0], size[1], rotation: turned);
          expect(g.width, closeTo(size[1], 1e-9), reason: '$name $turned');
          expect(g.height, closeTo(size[0], 1e-9), reason: '$name $turned');
        }
        final upside = page(size[0], size[1], rotation: 180);
        expect(upside.width, closeTo(size[0], 1e-9), reason: name);
      });
    });

    test('a landscape page is simply wider than it is tall', () {
      final g = page(842, 595);
      expect(g.width, 842);
      expect(g.height, 595);
    });

    test('pages of different sizes in one document keep their own geometry',
        () {
      final document = <PageGeometry>[
        page(595, 842),
        page(842, 595),
        page(612, 792, rotation: 90),
      ];
      expect(document.map((g) => (g.width, g.height)).toList(), [
        (595.0, 842.0),
        (842.0, 595.0),
        (792.0, 612.0),
      ]);
    });
  });

  group('rotation', () {
    test('/Rotate snaps to a quarter turn, negatives and big values included',
        () {
      expect(PageGeometry.normalizeRotation(0), 0);
      expect(PageGeometry.normalizeRotation(90), 90);
      expect(PageGeometry.normalizeRotation(-90), 270);
      expect(PageGeometry.normalizeRotation(450), 90);
      expect(PageGeometry.normalizeRotation(360), 0);
      expect(PageGeometry.normalizeRotation(-180), 180);
      expect(PageGeometry.normalizeRotation(100), 90);
    });

    test('the four corners of the visible page land on the right user corners',
        () {
      // A4: media 595 x 842.
      final r0 = page(595, 842);
      expectPoint(r0.visibleToUser(0, 0), 0, 842);
      expectPoint(r0.visibleToUser(595, 842), 595, 0);

      // Turned clockwise a quarter: the page's bottom-left is shown top-left.
      final r90 = page(595, 842, rotation: 90);
      expectPoint(r90.visibleToUser(0, 0), 0, 0);
      expectPoint(r90.visibleToUser(842, 0), 0, 842);
      expectPoint(r90.visibleToUser(0, 595), 595, 0);
      expectPoint(r90.visibleToUser(842, 595), 595, 842);

      final r180 = page(595, 842, rotation: 180);
      expectPoint(r180.visibleToUser(0, 0), 595, 0);
      expectPoint(r180.visibleToUser(595, 842), 0, 842);

      // Turned counter-clockwise a quarter.
      final r270 = page(595, 842, rotation: 270);
      expectPoint(r270.visibleToUser(0, 0), 595, 842);
      expectPoint(r270.visibleToUser(842, 0), 595, 0);
      expectPoint(r270.visibleToUser(0, 595), 0, 842);
    });

    test('user and visible conversions are inverses for every rotation', () {
      for (final rotation in [0, 90, 180, 270]) {
        final g = PageGeometry(
          mediaBox: const PdfBox(-20, 30, 575, 872),
          cropBox: const PdfBox(10, 50, 500, 800),
          rotation: rotation,
        );
        for (final p in const [
          [0.0, 0.0],
          [12.5, 99.25],
          [100.0, 300.0],
          [400.0, 200.0],
        ]) {
          final user = g.visibleToUser(p[0], p[1]);
          final back = g.userToVisible(user.x, user.y);
          expectPoint(back, p[0], p[1], 1e-9);
        }
      }
    });

    test('the user rectangle of a placement, for each rotation (A4)', () {
      const rect = PageRect(50, 100, 200, 80);
      expectUserRect(
          page(595, 842).userRectOf(rect), const UserRect(50, 662, 200, 80));
      // A quarter turn swaps the rectangle's width and height in user space.
      expectUserRect(page(595, 842, rotation: 90).userRectOf(rect),
          const UserRect(100, 50, 80, 200));
      expectUserRect(page(595, 842, rotation: 180).userRectOf(rect),
          const UserRect(345, 100, 200, 80));
      expectUserRect(page(595, 842, rotation: 270).userRectOf(rect),
          const UserRect(415, 592, 80, 200));
    });

    test('the area of a placement is the same in every rotation', () {
      const rect = PageRect(33, 77, 120.5, 41.25);
      for (final rotation in [0, 90, 180, 270]) {
        final user = page(595, 842, rotation: rotation).userRectOf(rect);
        expect(user.width * user.height, closeTo(120.5 * 41.25, 1e-9));
      }
    });
  });

  group('CropBox and MediaBox', () {
    test('a CropBox with an origin shifts the visible page', () {
      const g = PageGeometry(
        mediaBox: PdfBox(0, 0, 612, 792),
        cropBox: PdfBox(100, 100, 500, 600),
      );
      expect(g.width, 400);
      expect(g.height, 500);
      expectPoint(g.visibleToUser(0, 0), 100, 600);
      expectPoint(g.visibleToUser(400, 500), 500, 100);
      expectUserRect(g.userRectOf(const PageRect(10, 20, 100, 50)),
          const UserRect(110, 530, 100, 50));
    });

    test('a CropBox larger than the MediaBox is clipped to it', () {
      const g = PageGeometry(
        mediaBox: PdfBox(0, 0, 612, 792),
        cropBox: PdfBox(-50, -50, 700, 900),
      );
      expect(g.box, const PdfBox(0, 0, 612, 792));
      expect(g.width, 612);
      expect(g.height, 792);
    });

    test('a MediaBox with an origin (and corners given in either order)', () {
      final box = PdfBox.fromCorners(595, 842, -20, 30);
      expect(box, const PdfBox(-20, 30, 595, 842));
      final g = PageGeometry(mediaBox: box);
      expect(g.width, 615);
      expect(g.height, 812);
      expectPoint(g.visibleToUser(0, 0), -20, 842);
    });

    test('a CropBox with the MediaBox turned a quarter', () {
      const g = PageGeometry(
        mediaBox: PdfBox(0, 0, 612, 792),
        cropBox: PdfBox(100, 100, 500, 600),
        rotation: 90,
      );
      expect(g.width, 500);
      expect(g.height, 400);
      expectPoint(g.visibleToUser(0, 0), 100, 100);
      expectPoint(g.visibleToUser(500, 400), 500, 600);
    });

    test('boxes that share nothing are not usable', () {
      const apart = PageGeometry(
        mediaBox: PdfBox(0, 0, 612, 792),
        cropBox: PdfBox(700, 0, 900, 100),
      );
      expect(apart.hasUsableBoxes, isFalse);
      const flat = PageGeometry(mediaBox: PdfBox(0, 0, 0, 792));
      expect(flat.hasUsableBoxes, isFalse);
      const fine = PageGeometry(mediaBox: PdfBox(0, 0, 612, 792));
      expect(fine.hasUsableBoxes, isTrue);
    });

    test('two geometries are close when boxes and rotation agree', () {
      const a = PageGeometry(mediaBox: PdfBox(0, 0, 612, 792));
      const b = PageGeometry(mediaBox: PdfBox(0, 0, 612.005, 792));
      const c = PageGeometry(mediaBox: PdfBox(0, 0, 612, 792), rotation: 90);
      expect(a.isCloseTo(b), isTrue);
      expect(a.isCloseTo(c), isFalse);
      expect(a.isCloseTo(const PageGeometry(mediaBox: PdfBox(0, 0, 613, 792))),
          isFalse);
    });
  });

  group('screen and page', () {
    const a4 = PageGeometry(mediaBox: PdfBox(0, 0, 595, 842));

    test('a finger position becomes the same page point at every zoom', () {
      final fitted = PageViewport(
          pageWidth: a4.width, pageHeight: a4.height, displayWidth: 297.5);
      expect(fitted.scale, 0.5);
      expect(fitted.displayHeight, closeTo(421, 1e-9));
      final p = fitted.toPage(100, 200);
      expectPoint(p, 200, 400);
      for (final zoom in [1.0, 1.5, 2.0, 3.0, 5.0]) {
        final zoomed = fitted.zoomed(zoom);
        // The finger on the same spot of the page: its display position scales
        // with the zoom, and the page point does not change.
        final shown = zoomed.toDisplay(p.x, p.y);
        final back = zoomed.toPage(shown.x, shown.y);
        expectPoint(back, p.x, p.y, 1e-9);
        expect(shown.x, closeTo(100 * zoom, 1e-9));
      }
    });

    test('pixel density does not matter, only the logical display width', () {
      // The same page shown 360 and 411 logical pixels wide: a finger a fixed
      // fraction across the page is the same page point.
      final narrow = PageViewport(
          pageWidth: a4.width, pageHeight: a4.height, displayWidth: 360);
      final wide = PageViewport(
          pageWidth: a4.width, pageHeight: a4.height, displayWidth: 411);
      final a = narrow.toPage(360 * 0.25, narrow.displayHeight * 0.5);
      final b = wide.toPage(411 * 0.25, wide.displayHeight * 0.5);
      expectPoint(a, b.x, b.y, 1e-9);
      expectPoint(a, 595 * 0.25, 842 * 0.5, 1e-9);
    });

    test('the page fits the area it is given in both orientations', () {
      final inLandscape = PageViewport.fit(
          pageWidth: 595, pageHeight: 842, maxWidth: 800, maxHeight: 400);
      expect(inLandscape.displayHeight, closeTo(400, 1e-9));
      expect(inLandscape.displayWidth, closeTo(400 * 595 / 842, 1e-9));
      final inPortrait = PageViewport.fit(
          pageWidth: 842, pageHeight: 595, maxWidth: 400, maxHeight: 800);
      expect(inPortrait.displayWidth, closeTo(400, 1e-9));
      expect(inPortrait.displayHeight, closeTo(400 * 595 / 842, 1e-9));
      // Neither overflows.
      expect(inLandscape.displayWidth, lessThanOrEqualTo(800));
      expect(inPortrait.displayHeight, lessThanOrEqualTo(800));
    });

    test('a rectangle converts to the screen and back without drift', () {
      const viewport =
          PageViewport(pageWidth: 612, pageHeight: 792, displayWidth: 377.3);
      const rect = PageRect(41.5, 120.25, 133.125, 48);
      final display = viewport.rectToDisplay(rect);
      final back = viewport.rectToPage(display);
      expect(back.isCloseTo(rect, 1e-9), isTrue);
      expect(display.width / display.height, closeTo(rect.aspect, 1e-9));
    });

    test('a screen turn keeps a placement where it is on the page', () {
      // Portrait phone then landscape phone: the display width changes, the
      // placement (in page points) does not, and the item covers the same
      // fraction of the page.
      const rect = PageRect(100, 200, 150, 60);
      final portrait =
          PageViewport(pageWidth: 595, pageHeight: 842, displayWidth: 360);
      final landscape =
          PageViewport(pageWidth: 595, pageHeight: 842, displayWidth: 240);
      final a = portrait.rectToDisplay(rect);
      final b = landscape.rectToDisplay(rect);
      expect(a.left / portrait.displayWidth,
          closeTo(b.left / landscape.displayWidth, 1e-9));
      expect(a.top / portrait.displayHeight,
          closeTo(b.top / landscape.displayHeight, 1e-9));
      expect(a.width / portrait.displayWidth,
          closeTo(b.width / landscape.displayWidth, 1e-9));
    });
  });

  group('moving and clamping', () {
    const w = 595.0;
    const h = 842.0;

    test('an item is kept inside the page', () {
      expect(StampLayout.clamp(const PageRect(-10, -5, 50, 20), w, h),
          const PageRect(0, 0, 50, 20));
      expect(StampLayout.clamp(const PageRect(590, 840, 50, 20), w, h),
          const PageRect(545, 822, 50, 20));
    });

    test('an item larger than the page is shrunk with its aspect kept', () {
      final r = StampLayout.clamp(const PageRect(10, 10, 800, 400), w, h);
      expect(r.width, closeTo(595, 1e-9));
      expect(r.height, closeTo(297.5, 1e-9));
      expect(r.aspect, closeTo(2, 1e-9));
      expect(r.left, closeTo(0, 1e-9));
    });

    test('a drag stops at every edge', () {
      const start = PageRect(100, 100, 100, 50);
      expect(StampLayout.move(start, -500, 0, w, h).left, 0);
      expect(StampLayout.move(start, 0, -500, w, h).top, 0);
      expect(StampLayout.move(start, 5000, 0, w, h).right, closeTo(w, 1e-9));
      expect(StampLayout.move(start, 0, 5000, w, h).bottom, closeTo(h, 1e-9));
      final free = StampLayout.move(start, 30, 40, w, h);
      expect(free, const PageRect(130, 140, 100, 50));
    });
  });

  group('resizing', () {
    const w = 595.0;
    const h = 842.0;
    const rect = PageRect(100, 100, 100, 50); // aspect 2

    PageRect resize(StampCorner corner, double x, double y) =>
        StampLayout.resizeFromCorner(
          rect: rect,
          corner: corner,
          pointer: PagePoint(x, y),
          pageW: w,
          pageH: h,
        );

    test('each corner moves while the opposite corner stays', () {
      final br = resize(StampCorner.bottomRight, 250, 400);
      expect(br, const PageRect(100, 100, 150, 75));
      final tl = resize(StampCorner.topLeft, 60, 10);
      expect(tl, const PageRect(60, 80, 140, 70));
      final tr = resize(StampCorner.topRight, 260, 0);
      expect(tr, const PageRect(100, 70, 160, 80));
      final bl = resize(StampCorner.bottomLeft, 80, 300);
      expect(bl, const PageRect(80, 100, 120, 60));
    });

    test('the aspect ratio is never changed', () {
      for (final corner in StampCorner.values) {
        for (final pointer in const [
          [10.0, 10.0],
          [300.0, 120.0],
          [590.0, 800.0],
          [-50.0, 900.0],
        ]) {
          final r = resize(corner, pointer[0], pointer[1]);
          expect(r.width / r.height, closeTo(2, 1e-9),
              reason: '$corner $pointer');
        }
      }
    });

    test('an item cannot be made larger than the page has room for', () {
      final r = resize(StampCorner.bottomRight, 5000, 5000);
      expect(r.right, lessThanOrEqualTo(w + 1e-9));
      expect(r.bottom, lessThanOrEqualTo(h + 1e-9));
      expect(r.left, 100);
      expect(r.top, 100);
      final leftward = resize(StampCorner.topLeft, -5000, -5000);
      expect(leftward.left, greaterThanOrEqualTo(-1e-9));
      expect(leftward.top, greaterThanOrEqualTo(-1e-9));
    });

    test('an item cannot be made narrower than the minimum', () {
      final r = resize(StampCorner.bottomRight, 101, 101);
      expect(r.width, StampLayout.minWidth);
      expect(r.height, StampLayout.minWidth / 2);
      // Dragging past the anchor does not flip or collapse it.
      final past = resize(StampCorner.bottomRight, 20, 20);
      expect(past.width, StampLayout.minWidth);
    });

    test('a pinch scales about the centre and stays inside the page', () {
      final doubled = StampLayout.scaleAroundCenter(rect, 2, w, h);
      expect(doubled, const PageRect(50, 75, 200, 100));
      final huge = StampLayout.scaleAroundCenter(rect, 1000, w, h);
      expect(
          huge.width, lessThanOrEqualTo(w * StampLayout.maxWidthShare + 1e-9));
      expect(huge.left, greaterThanOrEqualTo(0));
      expect(huge.right, lessThanOrEqualTo(w + 1e-9));
      final tiny = StampLayout.scaleAroundCenter(rect, 0.0001, w, h);
      expect(tiny.width, StampLayout.minWidth);
      expect(tiny.aspect, closeTo(2, 1e-9));
    });
  });

  group('carrying an item to another page', () {
    test('the same size, at the same fraction of the page', () {
      const rect = PageRect(100, 100, 100, 50);
      final landscape = StampLayout.carryToPage(
          rect: rect,
          fromPageW: 595,
          fromPageH: 842,
          toPageW: 842,
          toPageH: 595);
      expect(landscape.width, 100);
      expect(landscape.height, 50);
      expect(landscape.centerX, closeTo(150 / 595 * 842, 1e-9));
      expect(landscape.centerY, closeTo(125 / 842 * 595, 1e-9));
    });

    test('it is kept inside a page that is smaller than the item needs', () {
      const rect = PageRect(500, 780, 90, 40);
      final small = StampLayout.carryToPage(
          rect: rect,
          fromPageW: 595,
          fromPageH: 842,
          toPageW: 200,
          toPageH: 100);
      expect(small.left, greaterThanOrEqualTo(0));
      expect(small.top, greaterThanOrEqualTo(0));
      expect(small.right, lessThanOrEqualTo(200 + 1e-9));
      expect(small.bottom, lessThanOrEqualTo(100 + 1e-9));
    });
  });

  group('first placement', () {
    test('a signature starts centred at a readable width', () {
      final r = StampLayout.initialPlacement(
          size: StampSize.signature, aspect: 3, pageW: 595, pageH: 842);
      expect(r.width, closeTo(595 * 0.28, 1e-9));
      expect(r.aspect, closeTo(3, 1e-9));
      expect(r.centerX, closeTo(595 / 2, 1e-9));
      expect(r.centerY, closeTo(842 / 2, 1e-9));
    });

    test('initials are smaller and a line of text has a fixed height', () {
      final initials = StampLayout.initialPlacement(
          size: StampSize.initials, aspect: 1.5, pageW: 595, pageH: 842);
      expect(initials.width, closeTo(595 * 0.12, 1e-9));
      final line = StampLayout.initialPlacement(
          size: StampSize.line, aspect: 5, pageW: 595, pageH: 842);
      expect(line.height, closeTo(StampLayout.lineHeight, 1e-9));
      expect(line.width, closeTo(StampLayout.lineHeight * 5, 1e-9));
    });

    test('it always fits, even on a tiny page or with an extreme aspect', () {
      for (final size in StampSize.values) {
        for (final aspect in [0.2, 1.0, 3.0, 12.0]) {
          for (final page in const [
            [100.0, 100.0],
            [595.0, 842.0],
            [842.0, 595.0],
          ]) {
            final r = StampLayout.initialPlacement(
                size: size, aspect: aspect, pageW: page[0], pageH: page[1]);
            expect(r.left, greaterThanOrEqualTo(-1e-9));
            expect(r.top, greaterThanOrEqualTo(-1e-9));
            expect(r.right, lessThanOrEqualTo(page[0] + 1e-9),
                reason: '$size $aspect $page');
            expect(r.bottom, lessThanOrEqualTo(page[1] + 1e-9),
                reason: '$size $aspect $page');
            expect(r.aspect, closeTo(aspect, 1e-9));
          }
        }
      }
    });
  });
}
