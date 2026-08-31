import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:broker_wallet/src/constants/location_colors.dart';

class CustomMapPin extends StatelessWidget {
  final LocationFilter type;
  final Color color;
  final String? iconAsset;
  final IconData? icon;
  final double size;

  const CustomMapPin({
    super.key,
    required this.type,
    required this.color,
    this.iconAsset,
    this.icon,
    this.size = 60.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pin background shape
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
            ),
          ),

          // Icon
          Container(
            width: size * 0.5,
            height: size * 0.5,
            child: iconAsset != null
                ? SvgPicture.asset(
                    iconAsset!,
                    width: size * 0.5,
                    height: size * 0.5,
                    color: Colors.white,
                  )
                : Icon(
                    icon ?? Icons.location_on,
                    color: Colors.white,
                    size: size * 0.5,
                  ),
          ),

          // Small pin pointer at bottom
          Positioned(
            bottom: -5,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MapPinHelper {
  // Cache for generated pins to avoid regenerating the same pin multiple times
  static final Map<String, BitmapDescriptor> _pinCache = {};

  /// Creates a cluster pin showing multiple item types
  static Future<BitmapDescriptor> createClusterPin({
    required List<LocationFilter> types,
    double size = 92.0,
  }) async {
    // Create cache key from all types
    final typeKeys = types.map((t) => t.toString().split('.').last).join('_');
    final cacheKey = 'cluster_${typeKeys}_$size';

    if (_pinCache.containsKey(cacheKey)) {
      // Using cached cluster pin for ${types.length} types (log removed)
      return _pinCache[cacheKey]!;
    }

    // 🎨 Creating NEW cluster pin for ${types.length} item types (log removed)

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Pin dimensions (larger for clusters)
      final pinWidth = size;
      final pinHeight = size * 1.2;
      final headRadius = pinWidth * 0.42; // Slightly larger head
      final headCenterX = pinWidth / 2;
      final headCenterY = headRadius + 6;

      // Draw shadow
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(
          Offset(headCenterX + 2, headCenterY + 2), headRadius, shadowPaint);

      // Draw pointer shadow
      final shadowPointerPath = Path();
      shadowPointerPath.moveTo(
          headCenterX - headRadius * 0.3 + 2, headCenterY + headRadius + 2);
      shadowPointerPath.lineTo(headCenterX + 2, pinHeight + 2);
      shadowPointerPath.lineTo(
          headCenterX + headRadius * 0.3 + 2, headCenterY + headRadius + 2);
      shadowPointerPath.close();
      canvas.drawPath(shadowPointerPath, shadowPaint);

      // Use gradient for cluster pins (purple gradient)
      final gradientPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(headCenterX, headCenterY - headRadius),
          Offset(headCenterX, headCenterY + headRadius),
          [
            const ui.Color(0xFFDE2F07), // Purple
            const ui.Color(0xFFDF300D),
          ],
        );

      // Draw round head with gradient
      canvas.drawCircle(
          Offset(headCenterX, headCenterY), headRadius, gradientPaint);

      // Draw pointed bottom
      final pointerPath = Path();
      pointerPath.moveTo(
          headCenterX - headRadius * 0.3, headCenterY + headRadius);
      pointerPath.lineTo(headCenterX, pinHeight);
      pointerPath.lineTo(
          headCenterX + headRadius * 0.3, headCenterY + headRadius);
      pointerPath.close();
      canvas.drawPath(pointerPath, gradientPaint);

      // Draw white border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(
          Offset(headCenterX, headCenterY), headRadius - 1.75, borderPaint);

      // Draw white background circle for icons
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(headCenterX, headCenterY),
        headRadius * 0.85,
        bgPaint,
      );

      // Load and draw multiple icons in a grid
      final uniqueTypes = types.toSet().toList();
      final iconCount = uniqueTypes.length > 4 ? 4 : uniqueTypes.length;

      if (iconCount == 1) {
        // Single icon (centered)
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[0],
          headCenterX,
          headCenterY,
          headRadius * 1.3,
        );
      } else if (iconCount == 2) {
        // Two icons (side by side)
        final spacing = headRadius * 0.6;
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[0],
          headCenterX - spacing,
          headCenterY,
          headRadius * 0.9,
        );
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[1],
          headCenterX + spacing,
          headCenterY,
          headRadius * 0.9,
        );
      } else if (iconCount == 3) {
        // Three icons (triangle)
        final spacing = headRadius * 0.55;
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[0],
          headCenterX,
          headCenterY - spacing * 0.6,
          headRadius * 0.8,
        );
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[1],
          headCenterX - spacing,
          headCenterY + spacing * 0.4,
          headRadius * 0.8,
        );
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[2],
          headCenterX + spacing,
          headCenterY + spacing * 0.4,
          headRadius * 0.8,
        );
      } else {
        // Four icons (2x2 grid)
        final spacing =
            headRadius * 0.4; // Reduced from 0.5 to keep icons inside
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[0],
          headCenterX - spacing,
          headCenterY - spacing,
          headRadius * 0.65, // Reduced from 0.7
        );
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[1],
          headCenterX + spacing,
          headCenterY - spacing,
          headRadius * 0.65,
        );
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[2],
          headCenterX - spacing,
          headCenterY + spacing,
          headRadius * 0.65,
        );
        await _drawIconAtPosition(
          canvas,
          uniqueTypes[3],
          headCenterX + spacing,
          headCenterY + spacing,
          headRadius * 0.65,
        );
      }

      // Draw count badge if more than 1 item - TOP CENTER POSITION
      if (types.length > 1) {
        final badgeSize = headRadius * 0.35; // Slightly smaller
        final badgeX =
            headCenterX; // Centered horizontally (same distance from left and right)
        final badgeY = headCenterY - headRadius * 0.85; // Top offset

        // Badge background
        final badgePaint = Paint()..color = const Color(0xFFFF5722); // Orange
        canvas.drawCircle(Offset(badgeX, badgeY), badgeSize, badgePaint);

        // Badge border
        final badgeBorderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawCircle(Offset(badgeX, badgeY), badgeSize, badgeBorderPaint);

        // Badge text (count)
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${types.length}',
            style: TextStyle(
              color: Colors.white,
              fontSize: badgeSize * 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            badgeX - textPainter.width / 2,
            badgeY - textPainter.height / 2,
          ),
        );
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(pinWidth.toInt(), pinHeight.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final descriptor = BitmapDescriptor.fromBytes(bytes);
      _pinCache[cacheKey] = descriptor;

      // ✅ Cluster pin created with ${types.length} items (log removed)
      return descriptor;
    } catch (e) {
      // ❌ Error creating cluster pin: $e (log removed)
      return BitmapDescriptor.defaultMarker;
    }
  }

  // Helper to draw icon at specific position
  static Future<void> _drawIconAtPosition(
    Canvas canvas,
    LocationFilter type,
    double x,
    double y,
    double size,
  ) async {
    final categoryInfo = _getCategoryInfo(type);
    final color = LocationColors.getColor(type);

    try {
      final byteData = await rootBundle.load(categoryInfo.iconAsset);
      final bytes = byteData.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: size.toInt(),
        targetHeight: size.toInt(),
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final iconSize = size;
      final iconX = x - iconSize / 2;
      final iconY = y - iconSize / 2;

      // Draw icon with color tint
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(iconX, iconY, iconSize, iconSize),
        Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
      );

      image.dispose();
    } catch (e) {
      // ❌ Error drawing icon for $type: $e (log removed)
    }
  }

  /// Creates a custom map pin with category image and color
  static Future<BitmapDescriptor> createCategoryPin({
    required LocationFilter type,
    required Color color,
    double size = 82.0,
  }) async {
    final cacheKey = '${type.toString()}_${color.value}_$size';

    if (_pinCache.containsKey(cacheKey)) {
      // Using cached pin for $type (log removed)
      return _pinCache[cacheKey]!;
    }

    // Creating new pin for $type with color ${color.value} (log removed)

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Pin dimensions
      final pinWidth = size;
      final pinHeight = size * 1.2; // Taller to accommodate the pointer
      final headRadius = pinWidth * 0.40; // Round head radius
      final headCenterX = pinWidth / 2;
      final headCenterY = headRadius + 6; // Slightly offset from top

      // Get category info and icon asset path
      final categoryInfo = _getCategoryInfo(type);

      // Draw shadow for the entire pin
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      // Shadow for round head
      canvas.drawCircle(
          Offset(headCenterX + 2, headCenterY + 2), headRadius, shadowPaint);

      // Shadow for pointer
      final shadowPointerPath = Path();
      shadowPointerPath.moveTo(
          headCenterX - headRadius * 0.3 + 2, headCenterY + headRadius + 2);
      shadowPointerPath.lineTo(headCenterX + 2, pinHeight + 2);
      shadowPointerPath.lineTo(
          headCenterX + headRadius * 0.3 + 2, headCenterY + headRadius + 2);
      shadowPointerPath.close();
      canvas.drawPath(shadowPointerPath, shadowPaint);

      // Draw main pin shape
      final mainPaint = Paint()..color = color;

      // Draw round head
      canvas.drawCircle(
          Offset(headCenterX, headCenterY), headRadius, mainPaint);

      // Draw pointed bottom
      final pointerPath = Path();
      pointerPath.moveTo(
          headCenterX - headRadius * 0.3, headCenterY + headRadius);
      pointerPath.lineTo(headCenterX, pinHeight);
      pointerPath.lineTo(
          headCenterX + headRadius * 0.3, headCenterY + headRadius);
      pointerPath.close();
      canvas.drawPath(pointerPath, mainPaint);

      // Draw white border for round head
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(
          Offset(headCenterX, headCenterY), headRadius - 1.5, borderPaint);

      // Draw white border for pointer
      final borderPointerPath = Path();
      borderPointerPath.moveTo(
          headCenterX - headRadius * 0.3 + 2, headCenterY + headRadius - 1);
      borderPointerPath.lineTo(headCenterX, pinHeight - 2);
      borderPointerPath.lineTo(
          headCenterX + headRadius * 0.3 - 2, headCenterY + headRadius - 1);
      borderPaint.style = PaintingStyle.stroke;
      borderPaint.strokeWidth = 2;
      canvas.drawPath(borderPointerPath, borderPaint);

      // Load and draw PNG marker icon
      try {
        final byteData = await rootBundle.load(categoryInfo.iconAsset);
        final bytes = byteData.buffer.asUint8List();
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: (headRadius * 1.4).toInt(),
          targetHeight: (headRadius * 1.4).toInt(),
        );
        final frame = await codec.getNextFrame();
        final markerImage = frame.image;

        // Calculate icon size and position (center it in the round head)
        final iconSize = headRadius * 1.4; // Make icon fit well in the head
        final iconX = headCenterX - iconSize / 2;
        final iconY = headCenterY - iconSize / 2;

        // Create a circular clipping path for the icon
        canvas.save();
        final clipPath = Path()
          ..addOval(Rect.fromCenter(
            center: Offset(headCenterX, headCenterY),
            width: headRadius * 1.6,
            height: headRadius * 1.6,
          ));
        canvas.clipPath(clipPath);

        // Draw the PNG image centered in the round head with white background
        final iconPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

        // Draw white background circle for better contrast
        canvas.drawCircle(
          Offset(headCenterX, headCenterY),
          headRadius * 0.8,
          iconPaint,
        );

        // Draw the actual PNG image with color filter matching the pin color
        final colorFilter = ColorFilter.mode(
          color, // Use the pin color from LocationColors
          BlendMode
              .srcIn, // This will replace the image color with our pin color
        );

        canvas.drawImageRect(
          markerImage,
          Rect.fromLTWH(0, 0, markerImage.width.toDouble(),
              markerImage.height.toDouble()),
          Rect.fromLTWH(iconX, iconY, iconSize, iconSize),
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true
            ..colorFilter =
                colorFilter, // Apply color filter to match pin color
        );

        canvas.restore();
        markerImage.dispose();

        // Successfully loaded PNG marker: ${categoryInfo.iconAsset} with color: ${color.value} (log removed)
      } catch (e) {
        // Error loading PNG marker: $e, falling back to letter (log removed)
        // Fallback to letter if PNG loading fails
        final textPainter = TextPainter(
          text: TextSpan(
            text: categoryInfo.letter,
            style: TextStyle(
              color: Colors.white,
              fontSize: headRadius * 0.8,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            headCenterX - textPainter.width / 2,
            headCenterY - textPainter.height / 2,
          ),
        );
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(pinWidth.toInt(), pinHeight.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final descriptor = BitmapDescriptor.fromBytes(bytes);
      _pinCache[cacheKey] = descriptor;

      return descriptor;
    } catch (e) {
      // Error creating category pin: $e (log removed)
      return BitmapDescriptor.defaultMarker;
    }
  }

  /// Creates a more detailed custom pin with icon
  static Future<BitmapDescriptor> createIconPin({
    required LocationFilter type,
    required Color color,
    IconData? icon,
    double size = 52.0,
  }) async {
    final cacheKey =
        'icon_${type.toString()}_${color.value}_${icon?.codePoint}_$size';

    if (_pinCache.containsKey(cacheKey)) {
      return _pinCache[cacheKey]!;
    }

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final pinSize = size;

      // Draw shadow
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, 2, pinSize, pinSize * 0.8),
          Radius.circular(pinSize * 0.3),
        ),
        shadowPaint,
      );

      // Draw main rounded rectangle pin shape
      final mainPaint = Paint()..color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, pinSize, pinSize * 0.8),
          Radius.circular(pinSize * 0.3),
        ),
        mainPaint,
      );

      // Draw white border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1.25, 1.25, pinSize - 2.5, pinSize * 0.8 - 2.5),
          Radius.circular(pinSize * 0.3),
        ),
        borderPaint,
      );

      // Draw icon or category letter
      if (icon != null) {
        // Draw icon (simplified - just a circle for now since drawing IconData is complex)
        final iconPaint = Paint()..color = Colors.white;
        canvas.drawCircle(
          Offset(pinSize / 2, pinSize * 0.4),
          pinSize * 0.15,
          iconPaint,
        );
      } else {
        // Draw category letter
        final categoryInfo = _getCategoryInfo(type);
        final textPainter = TextPainter(
          text: TextSpan(
            text: categoryInfo.letter,
            style: TextStyle(
              color: Colors.white,
              fontSize: pinSize * 0.3,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            (pinSize - textPainter.width) / 2,
            (pinSize * 0.8 - textPainter.height) / 2,
          ),
        );
      }

      // Draw bottom pointer
      final pointerPath = Path();
      pointerPath.moveTo(pinSize / 2 - 6, pinSize * 0.8);
      pointerPath.lineTo(pinSize / 2, pinSize);
      pointerPath.lineTo(pinSize / 2 + 6, pinSize * 0.8);
      pointerPath.close();

      final pointerPaint = Paint()..color = color;
      canvas.drawPath(pointerPath, pointerPaint);

      final picture = recorder.endRecording();
      final img = await picture.toImage(pinSize.toInt(), pinSize.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final descriptor = BitmapDescriptor.fromBytes(bytes);
      _pinCache[cacheKey] = descriptor;

      return descriptor;
    } catch (e) {
      // Error creating icon pin: $e (log removed)
      return BitmapDescriptor.defaultMarker;
    }
  }

  /// Get category information including letter and asset path
  static CategoryInfo _getCategoryInfo(LocationFilter type) {
    CategoryInfo info;
    switch (type) {
      case LocationFilter.offers:
        info = CategoryInfo(
          letter: 'O',
          iconAsset: 'assets/icons/markers/offer-marker.png',
        );
        break;
      case LocationFilter.owners:
        info = CategoryInfo(
          letter: 'P',
          iconAsset: 'assets/icons/markers/owner-marker.png',
        );
        break;
      case LocationFilter.offices:
        info = CategoryInfo(
          letter: 'R',
          iconAsset: 'assets/icons/markers/office-marker.png',
        );
        break;
      case LocationFilter.watchmen:
        info = CategoryInfo(
          letter: 'W',
          iconAsset: 'assets/icons/markers/watchman-marker.png',
        );
        break;
      case LocationFilter.all:
        info = CategoryInfo(
          letter: 'A',
          iconAsset: 'assets/icons/markers/offer-marker.png',
        );
        break;
    }
    // Getting category info for $type: ${info.iconAsset} (log removed)
    return info;
  }

  /// Clears the pin cache (useful for memory management)
  static void clearCache() {
    _pinCache.clear();
  }
}

class CategoryInfo {
  final String letter;
  final String iconAsset;

  CategoryInfo({
    required this.letter,
    required this.iconAsset,
  });
}
