import 'dart:math' as math;

/// A point, in whichever space the caller says (visible points, user space or
/// display pixels).
class PagePoint {
  const PagePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PagePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PagePoint($x, $y)';
}

/// A rectangle with a top-left origin and y pointing down: the way a page looks
/// on the screen. Used for placements (visible points) and, scaled, for display
/// pixels.
class PageRect {
  const PageRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
  double get aspect => height == 0 ? 1.0 : width / height;

  bool get isFinite =>
      left.isFinite && top.isFinite && width.isFinite && height.isFinite;

  PageRect translated(double dx, double dy) =>
      PageRect(left + dx, top + dy, width, height);

  PageRect scaledBy(double factor) =>
      PageRect(left * factor, top * factor, width * factor, height * factor);

  /// Whether every edge is within [tolerance] of [other]'s.
  bool isCloseTo(PageRect other, [double tolerance = 1e-6]) =>
      (left - other.left).abs() <= tolerance &&
      (top - other.top).abs() <= tolerance &&
      (width - other.width).abs() <= tolerance &&
      (height - other.height).abs() <= tolerance;

  @override
  bool operator ==(Object other) =>
      other is PageRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PageRect($left, $top, $width x $height)';
}

/// A rectangle in a PDF page's default user space: origin at the bottom left of
/// the unrotated page, y pointing up.
class UserRect {
  const UserRect(this.left, this.bottom, this.width, this.height);

  final double left;
  final double bottom;
  final double width;
  final double height;

  double get right => left + width;
  double get top => bottom + height;

  bool isCloseTo(UserRect other, [double tolerance = 1e-6]) =>
      (left - other.left).abs() <= tolerance &&
      (bottom - other.bottom).abs() <= tolerance &&
      (width - other.width).abs() <= tolerance &&
      (height - other.height).abs() <= tolerance;

  @override
  String toString() => 'UserRect($left, $bottom, $width x $height)';
}

/// A PDF box (MediaBox, CropBox) in user space, normalised so that `right` is
/// greater than `left` and `top` is greater than `bottom`.
class PdfBox {
  const PdfBox(this.left, this.bottom, this.right, this.top);

  /// A box from the four numbers of a PDF `[x0 y0 x1 y1]` array, whichever two
  /// opposite corners they name.
  factory PdfBox.fromCorners(double x0, double y0, double x1, double y1) =>
      PdfBox(math.min(x0, x1), math.min(y0, y1), math.max(x0, x1),
          math.max(y0, y1));

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;
  double get height => top - bottom;

  bool get isValid =>
      left.isFinite &&
      bottom.isFinite &&
      right.isFinite &&
      top.isFinite &&
      width > 0 &&
      height > 0;

  /// The part shared with [other], or null when they do not overlap.
  PdfBox? intersect(PdfBox other) {
    final l = math.max(left, other.left);
    final b = math.max(bottom, other.bottom);
    final r = math.min(right, other.right);
    final t = math.min(top, other.top);
    if (r <= l || t <= b) return null;
    return PdfBox(l, b, r, t);
  }

  @override
  bool operator ==(Object other) =>
      other is PdfBox &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, bottom, right, top);

  @override
  String toString() => 'PdfBox($left, $bottom, $right, $top)';
}

/// What decides how one page looks and where a point on it lives in the file: the
/// page's boxes and its `/Rotate`.
///
/// The visible page is the CropBox clipped to the MediaBox (the MediaBox when
/// there is no CropBox), turned clockwise by [rotation]. That is what a viewer
/// draws, and what the Signature editor shows. A placement is stored in the
/// visible page's own points (top-left origin, y down); [visibleToUser] and
/// [userRectOf] turn it into the unrotated, y-up user space the PDF content is
/// written in.
class PageGeometry {
  const PageGeometry({
    required this.mediaBox,
    this.cropBox,
    this.rotation = 0,
  }) : assert(rotation == 0 ||
            rotation == 90 ||
            rotation == 180 ||
            rotation == 270);

  final PdfBox mediaBox;
  final PdfBox? cropBox;

  /// The page's clockwise display rotation: 0, 90, 180 or 270.
  final int rotation;

  /// `/Rotate` as a PDF file may state it (any integer) to 0, 90, 180 or 270.
  /// A value that is not a multiple of 90 snaps to the nearest quarter turn.
  static int normalizeRotation(num rotate) {
    final quarters = (rotate / 90).round();
    return (((quarters % 4) + 4) % 4) * 90;
  }

  /// The visible box in user space: the CropBox clipped to the MediaBox.
  PdfBox get box {
    final crop = cropBox;
    if (crop == null) return mediaBox;
    return crop.intersect(mediaBox) ?? mediaBox;
  }

  /// False when the CropBox and the MediaBox share nothing (a viewer would show
  /// an empty page) or a box has no area.
  bool get hasUsableBoxes {
    if (!mediaBox.isValid) return false;
    final crop = cropBox;
    if (crop == null) return true;
    return crop.isValid && crop.intersect(mediaBox) != null;
  }

  bool get isQuarterTurned => rotation == 90 || rotation == 270;

  /// The visible page's width in points.
  double get width => isQuarterTurned ? box.height : box.width;

  /// The visible page's height in points.
  double get height => isQuarterTurned ? box.width : box.height;

  /// The point of user space shown at ([vx], [vy]) of the visible page.
  PagePoint visibleToUser(double vx, double vy) {
    final b = box;
    switch (rotation) {
      case 90:
        return PagePoint(b.left + vy, b.bottom + vx);
      case 180:
        return PagePoint(b.right - vx, b.bottom + vy);
      case 270:
        return PagePoint(b.right - vy, b.top - vx);
      default:
        return PagePoint(b.left + vx, b.top - vy);
    }
  }

  /// The point of the visible page at which user-space point ([ux], [uy]) is
  /// shown. The inverse of [visibleToUser].
  PagePoint userToVisible(double ux, double uy) {
    final b = box;
    switch (rotation) {
      case 90:
        return PagePoint(uy - b.bottom, ux - b.left);
      case 180:
        return PagePoint(b.right - ux, uy - b.bottom);
      case 270:
        return PagePoint(b.top - uy, b.right - ux);
      default:
        return PagePoint(ux - b.left, b.top - uy);
    }
  }

  /// The upright rectangle of user space that is shown as [visible].
  UserRect userRectOf(PageRect visible) {
    final a = visibleToUser(visible.left, visible.top);
    final c = visibleToUser(visible.right, visible.bottom);
    final left = math.min(a.x, c.x);
    final bottom = math.min(a.y, c.y);
    return UserRect(left, bottom, (a.x - c.x).abs(), (a.y - c.y).abs());
  }

  /// Whether this geometry and [other] describe the same page to within
  /// [tolerance] points.
  bool isCloseTo(PageGeometry other, [double tolerance = 0.01]) {
    bool boxClose(PdfBox? a, PdfBox? b) {
      if (a == null || b == null) return a == null && b == null;
      return (a.left - b.left).abs() <= tolerance &&
          (a.bottom - b.bottom).abs() <= tolerance &&
          (a.right - b.right).abs() <= tolerance &&
          (a.top - b.top).abs() <= tolerance;
    }

    return rotation == other.rotation &&
        boxClose(mediaBox, other.mediaBox) &&
        boxClose(cropBox, other.cropBox);
  }

  @override
  bool operator ==(Object other) =>
      other is PageGeometry &&
      other.mediaBox == mediaBox &&
      other.cropBox == cropBox &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(mediaBox, cropBox, rotation);

  @override
  String toString() => 'PageGeometry($mediaBox, $cropBox, rotate $rotation)';
}

/// How one visible page is laid out on the screen: its size in points, and the
/// width it is drawn at (which already includes any zoom). Every conversion
/// between a finger position and a page point goes through here, so a placement
/// is the same at every zoom, scroll position, orientation and pixel density.
class PageViewport {
  const PageViewport({
    required this.pageWidth,
    required this.pageHeight,
    required this.displayWidth,
  })  : assert(pageWidth > 0),
        assert(pageHeight > 0),
        assert(displayWidth > 0);

  /// The largest viewport with the page's aspect ratio that fits in
  /// [maxWidth] by [maxHeight].
  factory PageViewport.fit({
    required double pageWidth,
    required double pageHeight,
    required double maxWidth,
    required double maxHeight,
  }) {
    final byWidth = maxWidth;
    final byHeight = maxHeight * pageWidth / pageHeight;
    return PageViewport(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      displayWidth: math.min(byWidth, byHeight),
    );
  }

  final double pageWidth;
  final double pageHeight;
  final double displayWidth;

  /// Display pixels per page point.
  double get scale => displayWidth / pageWidth;
  double get displayHeight => pageHeight * scale;

  PageViewport zoomed(double factor) => PageViewport(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      displayWidth: displayWidth * factor);

  /// A display position (relative to the page's top-left corner) as a page point.
  PagePoint toPage(double dx, double dy) => PagePoint(dx / scale, dy / scale);

  /// A page point as a display position.
  PagePoint toDisplay(double x, double y) => PagePoint(x * scale, y * scale);

  /// A placement as the rectangle it covers on the screen.
  PageRect rectToDisplay(PageRect rect) => rect.scaledBy(scale);

  /// A rectangle on the screen as a placement.
  PageRect rectToPage(PageRect display) => display.scaledBy(1 / scale);
}

/// Which corner of a placed item a resize handle belongs to.
enum StampCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Moving, resizing and positioning placed items, always inside the page.
class StampLayout {
  const StampLayout._();

  /// The narrowest an item may be made, in points.
  static const double minWidth = 18;

  /// The largest share of the page's width an item may take.
  static const double maxWidthShare = 0.95;

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  /// [rect] kept inside the page: shrunk (same aspect) if it is larger than the
  /// page, then moved inside.
  static PageRect clamp(PageRect rect, double pageWidth, double pageHeight) {
    var w = rect.width;
    var h = rect.height;
    if (w > pageWidth || h > pageHeight) {
      final s = math.min(pageWidth / w, pageHeight / h);
      w *= s;
      h *= s;
    }
    return PageRect(
      _clamp(rect.left, 0, pageWidth - w),
      _clamp(rect.top, 0, pageHeight - h),
      w,
      h,
    );
  }

  /// [rect] moved by ([dx], [dy]) points, stopped at the page's edges.
  static PageRect move(
          PageRect rect, double dx, double dy, double pageW, double pageH) =>
      clamp(rect.translated(dx, dy), pageW, pageH);

  /// The widest an item of [aspect] (width over height) may be on a page of
  /// [pageW] by [pageH].
  static double maxWidthFor(double aspect, double pageW, double pageH) =>
      math.min(pageW * maxWidthShare, pageH * maxWidthShare * aspect);

  /// [rect] resized by dragging [corner] to [pointer] (a page point), keeping
  /// the opposite corner where it is and the aspect ratio, and never leaving
  /// the page or going below [minWidth].
  static PageRect resizeFromCorner({
    required PageRect rect,
    required StampCorner corner,
    required PagePoint pointer,
    required double pageW,
    required double pageH,
  }) {
    final aspect = rect.aspect;
    final double anchorX;
    final double anchorY;
    final double sx;
    final double sy;
    switch (corner) {
      case StampCorner.bottomRight:
        anchorX = rect.left;
        anchorY = rect.top;
        sx = 1;
        sy = 1;
      case StampCorner.topRight:
        anchorX = rect.left;
        anchorY = rect.bottom;
        sx = 1;
        sy = -1;
      case StampCorner.bottomLeft:
        anchorX = rect.right;
        anchorY = rect.top;
        sx = -1;
        sy = 1;
      case StampCorner.topLeft:
        anchorX = rect.right;
        anchorY = rect.bottom;
        sx = -1;
        sy = -1;
    }
    // Room between the anchor and the page's edge in each direction.
    final roomX = sx > 0 ? pageW - anchorX : anchorX;
    final roomY = sy > 0 ? pageH - anchorY : anchorY;
    final maxW = math.max(
        math.min(
            math.min(roomX, roomY * aspect), maxWidthFor(aspect, pageW, pageH)),
        0.0);
    final wanted = (pointer.x - anchorX) * sx;
    final width = _clamp(wanted, math.min(minWidth, maxW), maxW);
    final height = width / aspect;
    return PageRect(
      sx > 0 ? anchorX : anchorX - width,
      sy > 0 ? anchorY : anchorY - height,
      width,
      height,
    );
  }

  /// [rect] scaled about its centre by [factor] (a pinch), within the same
  /// limits as a corner resize, then moved inside the page.
  static PageRect scaleAroundCenter(
      PageRect rect, double factor, double pageW, double pageH) {
    final aspect = rect.aspect;
    final maxW = maxWidthFor(aspect, pageW, pageH);
    final width = _clamp(rect.width * factor, math.min(minWidth, maxW), maxW);
    final height = width / aspect;
    return clamp(
      PageRect(
          rect.centerX - width / 2, rect.centerY - height / 2, width, height),
      pageW,
      pageH,
    );
  }

  /// The same item on another page: the same size in points, centred at the
  /// same fraction of the page, kept inside it.
  static PageRect carryToPage({
    required PageRect rect,
    required double fromPageW,
    required double fromPageH,
    required double toPageW,
    required double toPageH,
  }) {
    final cx = rect.centerX / fromPageW * toPageW;
    final cy = rect.centerY / fromPageH * toPageH;
    return clamp(
      PageRect(
          cx - rect.width / 2, cy - rect.height / 2, rect.width, rect.height),
      toPageW,
      toPageH,
    );
  }

  /// Where a new item of [aspect] first appears on a page: centred, at a size
  /// that reads well for its kind.
  static PageRect initialPlacement({
    required StampSize size,
    required double aspect,
    required double pageW,
    required double pageH,
  }) {
    double width;
    switch (size) {
      case StampSize.signature:
        width = _clamp(pageW * 0.28, 90, 200);
      case StampSize.initials:
        width = _clamp(pageW * 0.12, 40, 90);
      case StampSize.line:
        width = lineHeight * aspect;
    }
    width = math.min(width, maxWidthFor(aspect, pageW, pageH));
    final cap = pageH * 0.4 * aspect;
    if (width > cap) width = cap;
    if (width < minWidth)
      width = math.min(minWidth, maxWidthFor(aspect, pageW, pageH));
    final height = width / aspect;
    return PageRect((pageW - width) / 2, (pageH - height) / 2, width, height);
  }

  /// The height, in points, of a line of typed text or a date when first placed.
  static const double lineHeight = 18;
}

/// How big a new item starts, by what it is.
enum StampSize { signature, initials, line }
