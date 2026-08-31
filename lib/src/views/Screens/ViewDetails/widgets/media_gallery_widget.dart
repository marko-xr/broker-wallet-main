import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_cache_manager.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/video_player_resource_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'dart:io';

// Keep the existing MediaType and MediaItem classes
enum MediaType { image, video, document, unknown }

class MediaItem {
  final String url;
  final MediaType type;
  final String? fileName;
  final String? mimeType;

  MediaItem({
    required this.url,
    required this.type,
    this.fileName,
    this.mimeType,
  });

  static MediaType getMediaTypeFromUrl(String url) {
    final extension = url.split('.').last.toLowerCase().split('?').first;

    // Image formats (including HEIC/HEIF from iOS)
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif']
        .contains(extension)) {
      return MediaType.image;
    } else if (['mp4', 'mov', 'avi', 'mkv', 'm4v', 'webm', '3gp']
        .contains(extension)) {
      return MediaType.video;
    } else if ([
      'pdf',
      'doc',
      'docx',
      'txt',
      'rtf',
      'xls',
      'xlsx',
      'ppt',
      'pptx'
    ].contains(extension)) {
      return MediaType.document;
    }

    return MediaType.unknown;
  }
}

class OptimizedMediaGalleryWidget extends StatefulWidget {
  final List<String> mediaUrls;
  final PageController? pageController;
  final Function(int)? onPageChanged;
  final int? initialIndex;
  final bool showControls;
  final bool autoPlay;
  final String? fallbackSvgPath; // For entities without media

  const OptimizedMediaGalleryWidget({
    super.key,
    required this.mediaUrls,
    this.pageController,
    this.onPageChanged,
    this.initialIndex,
    this.showControls = true,
    this.autoPlay = false,
    this.fallbackSvgPath,
  });

  @override
  State<OptimizedMediaGalleryWidget> createState() =>
      _OptimizedMediaGalleryWidgetState();
}

class _OptimizedMediaGalleryWidgetState
    extends State<OptimizedMediaGalleryWidget> {
  late PageController _pageController;
  late List<MediaItem> _mediaItems;
  int _currentIndex = 0;
  final _cacheManager = MediaCacheManager();
  final VideoPlayerResourceManager _videoResourceManager =
      VideoPlayerResourceManager();

  @override
  void initState() {
    super.initState();
    _pageController = widget.pageController ??
        PageController(initialPage: widget.initialIndex ?? 0);
    _currentIndex = widget.initialIndex ?? 0;
    _synchronizeMediaItems(resetIndex: true);

    // Prefetch initial and nearby media
    _prefetchInitialMedia();
  }

  @override
  void didUpdateWidget(covariant OptimizedMediaGalleryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pageController != oldWidget.pageController) {
      if (widget.pageController != null) {
        _pageController = widget.pageController!;
      } else if (oldWidget.pageController != null) {
        _pageController = PageController(initialPage: _currentIndex);
      }
    }

    final mediaChanged = !listEquals(oldWidget.mediaUrls, widget.mediaUrls);
    final indexChanged = oldWidget.initialIndex != widget.initialIndex &&
        widget.initialIndex != null;

    if (mediaChanged || indexChanged) {
      setState(() {
        _synchronizeMediaItems(resetIndex: indexChanged);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.pageController == null &&
            _pageController.hasClients &&
            _mediaItems.isNotEmpty) {
          _pageController.animateToPage(
            _currentIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
        _prefetchInitialMedia();
      });
    }
  }

  void _prefetchInitialMedia() {
    if (_mediaItems.isEmpty) return;

    // Prefetch current and next 2 items
    final startIndex = _currentIndex;
    final endIndex = (_currentIndex + 3).clamp(0, _mediaItems.length);

    for (int i = startIndex; i < endIndex; i++) {
      final mediaItem = _mediaItems[i];
      if (mediaItem.type == MediaType.image) {
        _cacheManager.getOptimizedImage(mediaItem.url);
      } else if (mediaItem.type == MediaType.video) {
        _cacheManager.getOptimizedVideo(mediaItem.url);
      }
    }
  }

  void _prefetchNearbyMedia(int currentIndex) {
    // Prefetch previous and next items
    final indices = [
      currentIndex - 1,
      currentIndex + 1,
      currentIndex + 2,
    ].where((i) => i >= 0 && i < _mediaItems.length);

    for (final index in indices) {
      final mediaItem = _mediaItems[index];
      if (mediaItem.type == MediaType.image) {
        _cacheManager.getOptimizedImage(mediaItem.url);
      } else if (mediaItem.type == MediaType.video) {
        _cacheManager.getOptimizedVideo(mediaItem.url);
      }
    }
  }

  void _synchronizeMediaItems({bool resetIndex = false}) {
    final newItems = widget.mediaUrls
        .map((url) => MediaItem(
              url: url,
              type: MediaItem.getMediaTypeFromUrl(url),
              fileName: _extractFileName(url),
            ))
        .toList();

    int nextIndex;
    if (newItems.isEmpty) {
      nextIndex = 0;
    } else if (resetIndex || _currentIndex >= newItems.length) {
      final desiredIndex = widget.initialIndex ?? 0;
      nextIndex = desiredIndex.clamp(0, newItems.length - 1);
    } else {
      nextIndex = _currentIndex.clamp(0, newItems.length - 1);
    }

    _mediaItems = newItems;
    _currentIndex = newItems.isEmpty ? 0 : nextIndex;
  }

  String? _extractFileName(String url) {
    var sanitized = url.trim();
    if (sanitized.isEmpty) return null;

    final queryIndex = sanitized.indexOf('?');
    if (queryIndex != -1) {
      sanitized = sanitized.substring(0, queryIndex);
    }

    final fragmentIndex = sanitized.indexOf('#');
    if (fragmentIndex != -1) {
      sanitized = sanitized.substring(0, fragmentIndex);
    }

    sanitized = sanitized.replaceAll('\\', '/');

    try {
      sanitized = Uri.decodeFull(sanitized);
    } catch (_) {
      // Ignore decoding issues and use the sanitized path as-is.
    }

    if (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }

    if (sanitized.isEmpty) return null;

    final segments = sanitized.split('/');
    String candidate = segments.isNotEmpty ? segments.last : sanitized;

    if (candidate.isEmpty && segments.length > 1) {
      candidate = segments[segments.length - 2];
    }

    return candidate.isEmpty ? null : candidate;
  }

  @override
  void dispose() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _videoResourceManager.pauseAll();
    });
    if (widget.pageController == null) {
      _pageController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_mediaItems.isEmpty && widget.fallbackSvgPath != null) {
      return _buildSvgFallback(context);
    }

    if (_mediaItems.isEmpty) {
      return _buildEmptyState(context);
    }

    return Stack(
      children: [
        GestureDetector(
          onTap: () => _openFullScreenViewer(context),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });

              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                if (index < _mediaItems.length) {
                  final currentItem = _mediaItems[index];
                  if (currentItem.type == MediaType.video) {
                    _videoResourceManager.pauseAllExcept(currentItem.url);
                  } else {
                    _videoResourceManager.pauseAll();
                  }
                } else {
                  _videoResourceManager.pauseAll();
                }
              });
              widget.onPageChanged?.call(index);
              _prefetchNearbyMedia(index);
            },
            itemCount: _mediaItems.length,
            itemBuilder: (context, index) {
              return RepaintBoundary(
                key: ValueKey(_mediaItems[index].url),
                child: _buildMediaItem(_mediaItems[index], context),
              );
            },
          ),
        ),
        if (widget.showControls && _mediaItems.length > 1)
          _buildPageIndicator(context),
        // Add "View All" button for easy access to full-screen gallery
        if (_mediaItems.length > 1) _buildViewAllButton(context),
        // Add media counter overlay
        _buildMediaCounter(context),
      ],
    );
  }

  Widget _buildSvgFallback(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer,
            colors.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: SvgPicture.asset(
          widget.fallbackSvgPath!,
          width: 120,
          height: 120,
          colorFilter: ColorFilter.mode(
            colors.onPrimaryContainer,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  Widget _buildMediaItem(MediaItem mediaItem, BuildContext context) {
    switch (mediaItem.type) {
      case MediaType.image:
        return _buildOptimizedImageViewer(mediaItem, context);
      case MediaType.video:
        return _buildOptimizedVideoViewer(mediaItem, context);
      case MediaType.document:
        return _buildDocumentViewer(mediaItem, context);
      case MediaType.unknown:
        return _buildUnknownTypeViewer(mediaItem, context);
    }
  }

  Widget _buildOptimizedImageViewer(MediaItem mediaItem, BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: OfflineMediaService.instance.buildOfflineAwareImage(
        imageUrl: mediaItem.url,
        fit: BoxFit.cover,
        placeholder: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        errorWidget: Container(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image,
                  size: 48,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'Image failed to load',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptimizedVideoViewer(MediaItem mediaItem, BuildContext context) {
    return FutureBuilder<File?>(
      future: OfflineMediaService.instance.getVideoFile(mediaItem.url),
      builder: (context, localFileSnapshot) {
        if (localFileSnapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          );
        }

        // Check if we have a local file
        if (localFileSnapshot.hasData && localFileSnapshot.data != null) {
          final localFile = localFileSnapshot.data!;

          return OptimizedVideoPlayerWidget(
            videoUrl: localFile.path,
            autoPlay: widget.autoPlay,
          );
        }

        // Fallback to network video
        return OptimizedVideoPlayerWidget(
          videoUrl: mediaItem.url,
          autoPlay: widget.autoPlay,
        );
      },
    );
  }

  // Keep existing document and unknown type viewers
  Widget _buildDocumentViewer(MediaItem mediaItem, BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            colors.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                _getDocumentIcon(mediaItem.fileName ?? ''),
                size: 64,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              mediaItem.fileName ?? loc.translate('document'),
              style: texts.titleLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openDocument(mediaItem.url),
              icon: const Icon(Icons.open_in_new),
              label: Text(loc.translate('openDocument')),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnknownTypeViewer(MediaItem mediaItem, BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            colors.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.help_outline,
                size: 64,
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              loc.translate('unknownFileType'),
              style: texts.titleLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openDocument(mediaItem.url),
              icon: const Icon(Icons.launch),
              label: Text(loc.translate('openInBrowser')),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            colors.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              loc.translate('noMediaAvailable'),
              style: texts.titleMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullScreenViewer(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _videoResourceManager.pauseAll();
    });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenMediaViewer(
          mediaUrls: widget.mediaUrls,
          initialIndex: _currentIndex,
          title: 'Media Gallery',
        ),
      ),
    );
  }

  Widget _buildViewAllButton(BuildContext context) {
    final double bottomOffset =
        widget.showControls && _mediaItems.length > 1 ? 8 : 24;

    return Positioned(
      right: 16,
      bottom: bottomOffset,
      child: Container(
        decoration: BoxDecoration(
          color: Color.fromARGB((0.6 * 255).round(), 0, 0, 0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openFullScreenViewer(context),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fullscreen,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'View All',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaCounter(BuildContext context) {
    final double bottomOffset =
        widget.showControls && _mediaItems.length > 1 ? 14 : 24;

    return Positioned(
      left: 16,
      bottom: bottomOffset,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Color.fromARGB((0.6 * 255).round(), 0, 0, 0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_currentIndex + 1}/${_mediaItems.length}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          _mediaItems.length,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: _currentIndex == index ? 12 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: _currentIndex == index
                  ? Colors.white
                  : Color.fromARGB((0.5 * 255).round(), 255, 255, 255),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getDocumentIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _openDocument(String url) async {
    final loc = AppLocalizations.of(context);
    final fileName = _extractFileName(url);
    final lowerName = (fileName ?? '').toLowerCase();

    try {
      File? localFile;
      final mappedPath = OfflineMediaService.instance.getLocalFilePath(url);
      if (mappedPath != null) {
        final file = File(mappedPath);
        if (await file.exists()) {
          localFile = file;
        }
      }

      if (lowerName.endsWith('.pdf')) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(
              localFile: localFile,
              networkUrl: localFile == null ? url : null,
              title: fileName ?? loc.translate('document'),
            ),
          ),
        );
        return;
      }

      if (localFile != null) {
        final fileUri = Uri.file(localFile.path);
        if (await canLaunchUrl(fileUri)) {
          await launchUrl(fileUri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      throw Exception('Cannot open document');
    } catch (e) {
      if (mounted) {
        final colors = Theme.of(context).colorScheme;
        _showToast(loc.translate('failedToOpenDocument'), colors.error);
      }
    }
  }
}

void _showToast(String message, Color bgColor) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM,
    timeInSecForIosWeb: 1,
    backgroundColor: bgColor,
    textColor: Colors.white,
  );
}

class OptimizedVideoPlayerWidget extends StatefulWidget {
  final String videoUrl; // Changed to URL instead of controller
  final bool autoPlay;

  const OptimizedVideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
  });

  @override
  State<OptimizedVideoPlayerWidget> createState() =>
      _OptimizedVideoPlayerWidgetState();
}

class _OptimizedVideoPlayerWidgetState
    extends State<OptimizedVideoPlayerWidget> {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  final VideoPlayerResourceManager _resourceManager =
      VideoPlayerResourceManager();

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // Check if video format is supported
      if (!VideoPlayerResourceManager.isVideoFormatSupported(widget.videoUrl)) {
        throw Exception(
            'Unsupported video format. Codec: ${VideoPlayerResourceManager.getVideoCodecInfo(widget.videoUrl)}');
      }

      // Get controller from resource manager
      final controller = await _resourceManager.getController(widget.videoUrl);

      if (!mounted) return;

      if (controller != null && controller.value.isInitialized) {
        _controller = controller;
        _createChewieController();
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      } else {
        throw Exception('Failed to initialize video player');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _createChewieController() {
    if (_controller == null || !mounted) return;

    setState(() {
      _chewieController = ChewieController(
        videoPlayerController: _controller!,
        autoPlay: widget.autoPlay,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.grey.shade300,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading video',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  @override
  void deactivate() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _resourceManager.pauseController(widget.videoUrl);
    });
    super.deactivate();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    // Note: Don't dispose _controller here as it's managed by the resource manager
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _resourceManager.pauseController(widget.videoUrl);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading video',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: _initializeVideo,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_chewieController != null) {
      return Chewie(controller: _chewieController!);
    }

    return Container(
      color: Colors.black,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }
}
