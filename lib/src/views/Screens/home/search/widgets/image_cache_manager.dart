import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  // Cache for SVG assets
  final Map<String, void> _svgCache = {};
  bool _svgsPreloaded = false;

  // List of SVG assets to preload
  static const List<String> _svgAssets = [
    'assets/icons/requested-svg.svg',
    'assets/icons/offers-svg.svg',
    'assets/icons/owners-svg.svg',
    'assets/icons/offices-svg.svg',
    'assets/icons/brokers-svg.svg',
    'assets/icons/watchman-svg.svg',
    'assets/icons/marked-favorite.svg',
    'assets/icons/unmarked-favorite.svg',
  ];

  /// Preload all SVG assets at app startup
  Future<void> preloadSvgAssets() async {
    if (_svgsPreloaded) return;

    try {
      final futures = _svgAssets.map((asset) async {
        final loader = SvgAssetLoader(asset);
        final svg = await vg.loadPicture(loader, null);
        _svgCache[asset] = svg;
        return svg;
      });

      await Future.wait(futures);
      _svgsPreloaded = true;
    } catch (e) {
      debugPrint('Failed to preload SVG assets: $e');
    }
  }

  /// Prefetch network images for items that will be visible soon
  Future<void> prefetchImages(
    BuildContext context,
    List<String> imageUrls, {
    int maxConcurrent = 3,
  }) async {
    if (imageUrls.isEmpty) return;

    // Limit concurrent prefetching to avoid overwhelming the network
    final semaphore = <Future>[];

    for (final url in imageUrls.take(maxConcurrent)) {
      if (url.isNotEmpty) {
        final future = _prefetchSingleImage(context, url);
        semaphore.add(future);

        // Don't wait for completion, just track the futures
        future.catchError((e) {
          debugPrint('Failed to prefetch image: $url - $e');
        });
      }
    }
  }

  Future<void> _prefetchSingleImage(BuildContext context, String url) async {
    try {
      // Only use CachedNetworkImageProvider for valid network URLs
      if (!_isValidNetworkUrl(url)) {
        // Skip precaching for local:// URLs or invalid URLs
        return;
      }

      await precacheImage(
        CachedNetworkImageProvider(
          url,
          cacheKey: url,
          maxWidth: 400, // Limit size for faster loading
          maxHeight: 300,
        ),
        context,
      );
    } catch (e) {
      // Silently handle errors - fallback will be used
    }
  }

  /// Check if SVG is already cached
  bool isSvgCached(String asset) => _svgCache.containsKey(asset);

  /// Get cached SVG or null if not cached
  dynamic getCachedSvg(String asset) => _svgCache[asset];

  /// Helper method to validate if URL is suitable for CachedNetworkImage
  bool _isValidNetworkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }
}
