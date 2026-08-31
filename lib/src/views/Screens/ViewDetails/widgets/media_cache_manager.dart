import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

class MediaCacheManager {
  static final MediaCacheManager _instance = MediaCacheManager._internal();
  factory MediaCacheManager() => _instance;
  MediaCacheManager._internal();

  final Map<String, ImageProvider> _imageCache = {};
  final Map<String, VideoPlayerController> _videoCache = {};
  final Map<String, String> _svgCache = {};

  static const List<String> _defaultSvgs = [
    'assets/icons/requested-svg.svg',
    'assets/icons/offers-svg.svg',
    'assets/icons/owners-svg.svg',
    'assets/icons/offices-svg.svg',
    'assets/icons/brokers-svg.svg',
    'assets/icons/watchman-svg.svg',
  ];

  // Initialize SVG cache at app start
  Future<void> initializeSvgCache() async {
    for (final svgPath in _defaultSvgs) {
      try {
        final svgString = await rootBundle.loadString(svgPath);
        _svgCache[svgPath] = svgString;

        // Precache SVG using proper flutter_svg API
        final loader = SvgAssetLoader(svgPath);
        await svg.cache.putIfAbsent(
          loader.cacheKey(null),
          () => loader.loadBytes(null),
        );
      } catch (e) {
        debugPrint('Failed to cache SVG: $svgPath - $e');
      }
    }
  }

  // Preload image with immediate return of cached version
  ImageProvider getOptimizedImage(String url) {
    if (_imageCache.containsKey(url)) {
      return _imageCache[url]!;
    }

    // Handle local or non-network URLs via OfflineMediaService
    if (!_isValidNetworkUrl(url)) {
      final provider = _getLocalImageProvider(url) ??
          const AssetImage('assets/icons/placeholder.png');

      _imageCache[url] = provider;
      return provider;
    }

    final imageProvider = CachedNetworkImageProvider(
      url,
      cacheKey: url,
      maxWidth: 800, // Optimize for performance
      maxHeight: 600,
    );

    _imageCache[url] = imageProvider;

    // Prefetch in background
    _prefetchImage(imageProvider);

    return imageProvider;
  }

  /// Helper method to validate if URL is suitable for CachedNetworkImage
  bool _isValidNetworkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  Future<void> _prefetchImage(ImageProvider imageProvider) async {
    try {
      // Try to get context from navigator key, but don't fail if it's not available
      final context = NavigationService.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        await precacheImage(imageProvider, context);
      } else {
        // If no context available, we'll still cache the image provider
        // It will be loaded when first used
        debugPrint('No context available for precaching image');
      }
    } catch (e) {
      // Silently handle network errors when offline
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('socketexception') ||
          errorMsg.contains('failed host lookup') ||
          errorMsg.contains('firebasestorage')) {
        // Normal offline behavior - don't log
        return;
      }
      debugPrint('Failed to prefetch image: $e');
    }
  }

  // Preload video controller
  Future<VideoPlayerController?> getOptimizedVideo(String url) async {
    if (_videoCache.containsKey(url)) {
      return _videoCache[url];
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );

      _videoCache[url] = controller;

      // Initialize in background without awaiting
      controller.initialize().catchError((error) {
        debugPrint('Failed to initialize video controller: $error');
      });

      return controller;
    } catch (e) {
      debugPrint('Failed to create video controller: $e');
      return null;
    }
  }

  // Get cached SVG
  String? getCachedSvg(String path) {
    return _svgCache[path];
  }

  // Cleanup
  void dispose() {
    for (final controller in _videoCache.values) {
      controller.dispose();
    }
    _videoCache.clear();
    _imageCache.clear();
  }

  // Prefetch media for upcoming items
  void prefetchMedia(List<String> urls) {
    for (final url in urls) {
      final mediaType = MediaItem.getMediaTypeFromUrl(url);
      switch (mediaType) {
        case MediaType.image:
          getOptimizedImage(url);
          break;
        case MediaType.video:
          getOptimizedVideo(url);
          break;
        default:
          break;
      }
    }
  }
}

// Navigation service for context access
class NavigationService {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

// import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// class MediaCacheManager {
//   static const key = 'media_cache';

//   static CacheManager instance = CacheManager(
//     Config(
//       key,
//       stalePeriod: const Duration(days: 7),

ImageProvider? _getLocalImageProvider(String url) {
  try {
    final localPath = OfflineMediaService.instance.getLocalFilePath(url);
    if (localPath == null) {
      return null;
    }

    final file = File(localPath);
    if (file.existsSync()) {
      return FileImage(file);
    }
  } catch (e) {
    debugPrint('Failed to resolve local image for $url: $e');
  }

  return null;
}
//       maxNrOfCacheObjects: 100,
//       repo: JsonCacheInfoRepository(databaseName: key),
//       fileService: HttpFileService(),
//     ),
//   );
// }
