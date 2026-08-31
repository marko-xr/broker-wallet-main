// import 'package:flutter/material.dart';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:broker_wallet/src/services/storage_performance_monitor.dart';
// import 'dart:developer' as developer;

// /// Optimized network image widget with proper caching and sizing
// class FastNetworkImage extends StatelessWidget {
//   final String url;
//   final double? width;
//   final double? height;
//   final BoxFit fit;
//   final Widget? placeholder;
//   final Widget? errorWidget;
//   final bool enablePerformanceMonitoring;
//   final String? heroTag;
//   final BorderRadius? borderRadius;
//   final bool precacheNext;
//   final double? targetWidthPx;
//   final double? targetHeightPx;

//   const FastNetworkImage({
//     Key? key,
//     required this.url,
//     this.width,
//     this.height,
//     this.fit = BoxFit.cover,
//     this.placeholder,
//     this.errorWidget,
//     this.enablePerformanceMonitoring = false,
//     this.heroTag,
//     this.borderRadius,
//     this.precacheNext = false,
//     this.targetWidthPx,
//     this.targetHeightPx,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     if (url.isEmpty) {
//       return _buildErrorWidget();
//     }

//     // Calculate physical pixel sizes for optimal decoding
//     final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
//     final cacheWidth = targetWidthPx?.toInt() ??
//         (width != null ? (width! * devicePixelRatio).toInt() : null);
//     final cacheHeight = targetHeightPx?.toInt() ??
//         (height != null ? (height! * devicePixelRatio).toInt() : null);

//     Widget imageWidget = _buildCachedImage(
//       context: context,
//       cacheWidth: cacheWidth,
//       cacheHeight: cacheHeight,
//     );

//     // Wrap with border radius if provided
//     if (borderRadius != null) {
//       imageWidget = ClipRRect(
//         borderRadius: borderRadius!,
//         child: imageWidget,
//       );
//     }

//     // Wrap with hero if provided
//     if (heroTag != null) {
//       imageWidget = Hero(
//         tag: heroTag!,
//         child: imageWidget,
//       );
//     }

//     // Add performance monitoring if enabled
//     if (enablePerformanceMonitoring) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         StoragePerformanceMonitor.monitorImageLoad(
//           url: url,
//           context: context,
//           operationName: 'FastNetworkImage',
//           targetWidth: cacheWidth?.toDouble(),
//           targetHeight: cacheHeight?.toDouble(),
//         );
//       });
//     }

//     return SizedBox(
//       width: width,
//       height: height,
//       child: imageWidget,
//     );
//   }

//   Widget _buildCachedImage({
//     required BuildContext context,
//     int? cacheWidth,
//     int? cacheHeight,
//   }) {
//     return CachedNetworkImage(
//       imageUrl: url,
//       width: width,
//       height: height,
//       fit: fit,
//       memCacheWidth: cacheWidth,
//       memCacheHeight: cacheHeight,
//       placeholder: (context, url) => _buildPlaceholder(),
//       errorWidget: (context, url, error) => _buildErrorWidget(),
//       fadeInDuration: const Duration(milliseconds: 200),
//       fadeOutDuration: const Duration(milliseconds: 100),
//       useOldImageOnUrlChange: true,
//       imageBuilder: (context, imageProvider) {
//         // Precache next image if requested
//         if (precacheNext) {
//           _precacheNextImage(context, imageProvider);
//         }

//         return Image(
//           image: imageProvider,
//           width: width,
//           height: height,
//           fit: fit,
//         );
//       },
//     );
//   }

//   Widget _buildPlaceholder() {
//     if (placeholder != null) return placeholder!;

//     return Container(
//       width: width,
//       height: height ?? 160,
//       decoration: BoxDecoration(
//         color: Colors.grey[200],
//         borderRadius: borderRadius,
//       ),
//       child: const Center(
//         child: CircularProgressIndicator(
//           strokeWidth: 2,
//           valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
//         ),
//       ),
//     );
//   }

//   Widget _buildErrorWidget() {
//     if (errorWidget != null) return errorWidget!;

//     return Container(
//       width: width,
//       height: height ?? 160,
//       decoration: BoxDecoration(
//         color: Colors.grey[100],
//         borderRadius: borderRadius,
//       ),
//       child: Icon(
//         Icons.broken_image,
//         color: Colors.grey[400],
//         size: 32,
//       ),
//     );
//   }

//   void _precacheNextImage(BuildContext context, ImageProvider imageProvider) {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       try {
//         precacheImage(imageProvider, context);
//       } catch (e) {
//         developer.log('Failed to precache image: $e', name: 'FastNetworkImage');
//       }
//     });
//   }
// }

// /// Optimized image widget specifically for list items
// class ListImageWidget extends StatelessWidget {
//   final String url;
//   final double size;
//   final BoxFit fit;
//   final String? heroTag;
//   final VoidCallback? onTap;

//   const ListImageWidget({
//     Key? key,
//     required this.url,
//     this.size = 80,
//     this.fit = BoxFit.cover,
//     this.heroTag,
//     this.onTap,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final imageWidget = FastNetworkImage(
//       url: url,
//       width: size,
//       height: size,
//       fit: fit,
//       heroTag: heroTag,
//       borderRadius: BorderRadius.circular(8),
//       targetWidthPx: size * 2, // 2x for high-DPI displays
//       targetHeightPx: size * 2,
//     );

//     if (onTap != null) {
//       return GestureDetector(
//         onTap: onTap,
//         child: imageWidget,
//       );
//     }

//     return imageWidget;
//   }
// }

// /// Optimized image gallery widget for detail views
// class GalleryImageWidget extends StatelessWidget {
//   final String url;
//   final String? thumbnailUrl;
//   final double? width;
//   final double? height;
//   final VoidCallback? onTap;
//   final String? heroTag;

//   const GalleryImageWidget({
//     Key? key,
//     required this.url,
//     this.thumbnailUrl,
//     this.width,
//     this.height,
//     this.onTap,
//     this.heroTag,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     // Use thumbnail for initial display, then load full image
//     final displayUrl = thumbnailUrl ?? url;

//     final imageWidget = FastNetworkImage(
//       url: displayUrl,
//       width: width,
//       height: height,
//       fit: BoxFit.cover,
//       heroTag: heroTag,
//       borderRadius: BorderRadius.circular(12),
//       precacheNext:
//           thumbnailUrl != null, // Precache full image if using thumbnail
//       enablePerformanceMonitoring: true,
//     );

//     if (onTap != null) {
//       return GestureDetector(
//         onTap: onTap,
//         child: imageWidget,
//       );
//     }

//     return imageWidget;
//   }
// }

// /// Avatar widget with multiple size options
// class FastAvatarWidget extends StatelessWidget {
//   final String? url;
//   final double size;
//   final String? initials;
//   final VoidCallback? onTap;
//   final Color? backgroundColor;

//   const FastAvatarWidget({
//     Key? key,
//     this.url,
//     this.size = 40,
//     this.initials,
//     this.onTap,
//     this.backgroundColor,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     Widget avatar;

//     if (url != null && url!.isNotEmpty) {
//       avatar = ClipOval(
//         child: FastNetworkImage(
//           url: url!,
//           width: size,
//           height: size,
//           fit: BoxFit.cover,
//           targetWidthPx: size * 2, // 2x for crisp display
//           targetHeightPx: size * 2,
//           placeholder: _buildInitialsPlaceholder(),
//           errorWidget: _buildInitialsPlaceholder(),
//         ),
//       );
//     } else {
//       avatar = _buildInitialsPlaceholder();
//     }

//     if (onTap != null) {
//       return GestureDetector(
//         onTap: onTap,
//         child: avatar,
//       );
//     }

//     return avatar;
//   }

//   Widget _buildInitialsPlaceholder() {
//     return Container(
//       width: size,
//       height: size,
//       decoration: BoxDecoration(
//         shape: BoxShape.circle,
//         color: backgroundColor ?? Colors.grey[300],
//       ),
//       child: Center(
//         child: Text(
//           initials ?? '?',
//           style: TextStyle(
//             fontSize: size * 0.4,
//             fontWeight: FontWeight.bold,
//             color: Colors.white,
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// Preloader for images that will be needed soon
// class ImagePreloader {
//   static final Map<String, Future<void>> _preloadingCache = {};

//   /// Preload an image for smooth navigation
//   static Future<void> preloadImage(
//     BuildContext context,
//     String url, {
//     double? targetWidth,
//     double? targetHeight,
//   }) async {
//     if (url.isEmpty || _preloadingCache.containsKey(url)) {
//       return;
//     }

//     final future = _performPreload(context, url, targetWidth, targetHeight);
//     _preloadingCache[url] = future;

//     try {
//       await future;
//     } finally {
//       _preloadingCache.remove(url);
//     }
//   }

//   static Future<void> _performPreload(
//     BuildContext context,
//     String url,
//     double? targetWidth,
//     double? targetHeight,
//   ) async {
//     try {
//       await precacheImage(
//         CachedNetworkImageProvider(
//           url,
//           maxWidth: targetWidth?.toInt(),
//           maxHeight: targetHeight?.toInt(),
//         ),
//         context,
//       );
//       developer.log('✅ Preloaded image: $url', name: 'ImagePreloader');
//     } catch (e) {
//       developer.log('⚠️ Failed to preload image: $url - $e',
//           name: 'ImagePreloader');
//     }
//   }

//   /// Preload multiple images with limited concurrency
//   static Future<void> preloadImages(
//     BuildContext context,
//     List<String> urls, {
//     int maxConcurrent = 3,
//     double? targetWidth,
//     double? targetHeight,
//   }) async {
//     if (urls.isEmpty) return;

//     // Process in batches to avoid overwhelming the network
//     for (int i = 0; i < urls.length; i += maxConcurrent) {
//       final batch = urls.skip(i).take(maxConcurrent);
//       final futures = batch.map((url) => preloadImage(context, url,
//           targetWidth: targetWidth, targetHeight: targetHeight));

//       await Future.wait(futures);
//     }
//   }

//   /// Clear preloading cache
//   static void clearCache() {
//     _preloadingCache.clear();
//   }
// }

// /// Utility for choosing the right image size based on display context
// class ImageSizeSelector {
//   /// Select the best image URL based on target display size
//   static String selectBestSize({
//     required Map<String, String>
//         urls, // e.g., {'thumb320': 'url1', 'thumb640': 'url2', 'full': 'url3'}
//     required double targetWidth,
//     required double targetHeight,
//     double devicePixelRatio = 1.0,
//   }) {
//     if (urls.isEmpty) return '';

//     final targetPixelWidth = targetWidth * devicePixelRatio;
//     final targetPixelHeight = targetHeight * devicePixelRatio;
//     final targetPixels = targetPixelWidth * targetPixelHeight;

//     // Define size thresholds (in pixels)
//     const sizeThresholds = {
//       'thumb320': 320 * 320,
//       'thumb640': 640 * 640,
//       'medium': 800 * 800,
//       'large': 1200 * 1200,
//       'full': double.infinity,
//     };

//     String? bestSize;
//     double minWaste = double.infinity;

//     for (final entry in urls.entries) {
//       final sizeName = entry.key;
//       final threshold = sizeThresholds[sizeName] ?? double.infinity;

//       if (threshold >= targetPixels) {
//         final waste = threshold - targetPixels;
//         if (waste < minWaste) {
//           minWaste = waste;
//           bestSize = sizeName;
//         }
//       }
//     }

//     // If no size is large enough, use the largest available
//     if (bestSize == null) {
//       final sortedSizes = urls.keys.toList()
//         ..sort((a, b) =>
//             (sizeThresholds[b] ?? 0).compareTo(sizeThresholds[a] ?? 0));
//       bestSize = sortedSizes.first;
//     }

//     return urls[bestSize] ?? urls.values.first;
//   }

//   /// Get the next larger size for detail view
//   static String? getNextLargerSize({
//     required Map<String, String> urls,
//     required String currentSize,
//   }) {
//     const sizeOrder = ['thumb320', 'thumb640', 'medium', 'large', 'full'];
//     final currentIndex = sizeOrder.indexOf(currentSize);

//     if (currentIndex == -1 || currentIndex >= sizeOrder.length - 1) {
//       return null;
//     }

//     for (int i = currentIndex + 1; i < sizeOrder.length; i++) {
//       final nextSize = sizeOrder[i];
//       if (urls.containsKey(nextSize)) {
//         return urls[nextSize];
//       }
//     }

//     return null;
//   }
// }
