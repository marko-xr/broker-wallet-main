import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_gallery_widget.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/views/Widgets/offer_media_upload_status.dart';
import 'package:broker_wallet/src/views/Widgets/offer_video_poster.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Full-screen media viewer with swipe navigation, zoom, and controls
class FullScreenMediaViewer extends StatefulWidget {
  /// Fully-described media, used instead of [mediaUrls] when given, so
  /// full-screen viewing reuses the same cache identity — and therefore the
  /// same already-downloaded bytes — as the inline gallery it opened from.
  final List<OfferMediaRef>? mediaRefs;

  final List<String> mediaUrls;
  final int initialIndex;
  final String? title;

  /// Offer media only: signs the media again and returns an item's new link,
  /// for a private video whose link has expired.
  final Future<String?> Function(String mediaObjectId)? refreshSignedUrl;

  /// The details screen's Share flow, preselected by durable media key.
  final void Function(String mediaKey)? onShareMedia;

  const FullScreenMediaViewer({
    super.key,
    this.mediaRefs,
    this.mediaUrls = const <String>[],
    this.initialIndex = 0,
    this.title,
    this.refreshSignedUrl,
    this.onShareMedia,
  });

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late List<MediaItem> _mediaItems;
  int _currentIndex = 0;
  bool _showControls = true;
  bool _isZoomed = false;

  // Animation controllers
  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsAnimation;

  // Video controllers cache
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, ChewieController> _chewieControllers = {};

  /// The viewer's own bars, measured so a private video is laid out between
  /// them: its player's seek bar and buttons are then never underneath the
  /// thumbnail strip, which would take every touch aimed at them.
  final GlobalKey _topControlsKey = GlobalKey();
  final GlobalKey _bottomControlsKey = GlobalKey();
  EdgeInsets _videoInsets = EdgeInsets.zero;

  void _measureControls() {
    if (!mounted) return;
    final top = _topControlsKey.currentContext?.size?.height ?? 0;
    final bottom = _bottomControlsKey.currentContext?.size?.height ?? 0;
    final insets = EdgeInsets.only(top: top, bottom: bottom);
    if (insets != _videoInsets) setState(() => _videoInsets = insets);
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _mediaItems = widget.mediaRefs?.map(MediaItem.fromOfferMedia).toList() ??
        widget.mediaUrls
            .map((url) => MediaItem(
                  url: url,
                  type: MediaItem.getMediaTypeFromUrl(url),
                  fileName: _extractFileName(url),
                ))
            .toList();

    _setupAnimations();
    _preloadCurrentVideo();
  }

  void _setupAnimations() {
    _controlsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _controlsAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controlsAnimationController,
      curve: Curves.easeInOut,
    ));

    _controlsAnimationController.forward();
  }

  /// Private Offer videos load only when the viewer taps to play them.
  bool get _isPrivateMedia => widget.mediaRefs != null;

  void _preloadCurrentVideo() {
    if (_isPrivateMedia) return;
    if (_currentIndex < _mediaItems.length) {
      final currentItem = _mediaItems[_currentIndex];
      if (currentItem.type == MediaType.video) {
        _initializeVideo(currentItem.url);
      }
    }
  }

  Future<void> _initializeVideo(String url) async {
    if (_videoControllers.containsKey(url)) return;

    try {
      final VideoPlayerController videoController;

      // Check if we have a local file
      final localFile = await OfflineMediaService.instance.getVideoFile(url);
      if (localFile != null && localFile.existsSync()) {
        videoController = VideoPlayerController.file(localFile);
      } else {
        videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      }

      await videoController.initialize();

      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: false,
        looping: false,
        allowFullScreen: false,
        showControls: true,
        showControlsOnInitialize: false,
        aspectRatio: videoController.value.aspectRatio,
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
                    'Video failed to load',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      _videoControllers[url] = videoController;
      _chewieControllers[url] = chewieController;

      if (mounted) setState(() {});
    } catch (e) {}
  }

  Future<void> _pauseAllVideos({String? exceptUrl}) async {
    for (final entry in _videoControllers.entries) {
      if (exceptUrl != null && entry.key == exceptUrl) {
        continue;
      }

      final controller = entry.value;
      if (!controller.value.isInitialized) {
        continue;
      }

      if (!controller.value.isPlaying) {
        continue;
      }

      try {
        await controller.pause();
      } catch (e) {
        // Silently handle pause issues to avoid interrupting UX
        debugPrint('Failed to pause video: ${e.runtimeType}');
      }
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _controlsAnimationController.forward();
    } else {
      _controlsAnimationController.reverse();
    }
  }

  void _onPageChanged(int index) {
    MediaItem? currentItem;
    MediaItem? nextItem;

    if (index >= 0 && index < _mediaItems.length) {
      currentItem = _mediaItems[index];
    }

    if (index + 1 < _mediaItems.length) {
      nextItem = _mediaItems[index + 1];
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_isPrivateMedia) {
        // Each private video's player pauses itself when its page goes.
        return;
      }

      if (currentItem != null && currentItem.type == MediaType.video) {
        _pauseAllVideos(exceptUrl: currentItem.url);
        _initializeVideo(currentItem.url);
      } else {
        _pauseAllVideos();
      }

      if (nextItem != null && nextItem.type == MediaType.video) {
        _initializeVideo(nextItem.url);
      }
    });

    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void dispose() {
    _controlsAnimationController.dispose();
    _pageController.dispose();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pauseAllVideos();
    });

    // Dispose video controllers
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    for (final controller in _chewieControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPrivateMedia) {
      // Only changes anything when the bars' size did (first layout,
      // rotation, text size).
      SchedulerBinding.instance.addPostFrameCallback((_) => _measureControls());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Main content
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _mediaItems.length,
              itemBuilder: (context, index) {
                return _buildMediaViewer(_mediaItems[index]);
              },
            ),

            // Top controls. Hidden controls are faded out, not removed, so
            // they must also stop taking touches meant for the page beneath.
            AnimatedBuilder(
              animation: _controlsAnimation,
              builder: (context, child) {
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Transform.translate(
                      offset: Offset(0, -60 * (1 - _controlsAnimation.value)),
                      child: Opacity(
                        opacity: _controlsAnimation.value,
                        child: KeyedSubtree(
                          key: _topControlsKey,
                          child: _buildTopControls(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Bottom controls
            AnimatedBuilder(
              animation: _controlsAnimation,
              builder: (context, child) {
                return Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Transform.translate(
                      offset: Offset(0, 80 * (1 - _controlsAnimation.value)),
                      child: Opacity(
                        opacity: _controlsAnimation.value,
                        child: KeyedSubtree(
                          key: _bottomControlsKey,
                          child: _buildBottomControls(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    final isRTL = Directionality.of(context) == TextDirection.rtl;
    final shareKey = _currentShareKey();

    return Container(
      padding: EdgeInsetsDirectional.only(
        top: MediaQuery.of(context).padding.top + 8,
        start: 4,
        end: 16,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              isRTL ? Icons.arrow_forward : Icons.arrow_back,
              color: Colors.white,
              size: 24,
            ),
          ),
          SizedBox(width: widget.onShareMedia == null ? 90 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.title != null)
                  Text(
                    widget.title!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Center(
              child: Text(
            '${_currentIndex + 1} of ${_mediaItems.length}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
          )),
          if (shareKey != null && widget.onShareMedia != null)
            IconButton(
              key: const ValueKey('viewer-share-media'),
              tooltip: AppLocalizations.of(context).translate('share'),
              onPressed: () => widget.onShareMedia!(shareKey),
              icon: const Icon(Icons.share_outlined, color: Colors.white),
            ),
        ],
      ),
    );
  }

  String? _currentShareKey() {
    if (_currentIndex < 0 || _currentIndex >= _mediaItems.length) return null;
    if (_mediaItems[_currentIndex].type != MediaType.image &&
        _mediaItems[_currentIndex].type != MediaType.video) {
      return null;
    }
    final refs = widget.mediaRefs;
    if (refs != null) {
      return _currentIndex < refs.length
          ? ShareMediaItem.keyFor(refs[_currentIndex])
          : null;
    }
    if (_currentIndex >= widget.mediaUrls.length) return null;
    return ShareMediaItem.keyFor(OfferMediaRef(
      mediaObjectId: '',
      cacheKey: null,
      signedUrl: widget.mediaUrls[_currentIndex],
    ));
  }

  Widget _buildBottomControls() {
    if (_mediaItems.length <= 1) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsetsDirectional.only(
        start: 16,
        end: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Media type indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getMediaIcon(_mediaItems[_currentIndex].type),
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _getMediaTypeLabel(_mediaItems[_currentIndex].type),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Thumbnail strip for navigation
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _mediaItems.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: index == _currentIndex
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _buildThumbnail(_mediaItems[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaViewer(MediaItem mediaItem) {
    if (_isPrivateMedia && mediaItem.isPendingUpload) {
      // A snapshot of the queue, so its state and never a stale percentage:
      // an item is not shown as uploaded before the server has accepted it.
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildPrivateMediaViewer(mediaItem),
          IgnorePointer(
            child: OfferMediaUploadStatus(
              phase: mediaItem.uploadPhase!,
              failureMessageKey: mediaItem.failureMessageKey,
            ),
          ),
        ],
      );
    }
    if (_isPrivateMedia) {
      // The same shape as above, so a video playing from its local copy is
      // not restarted when its item turns ready.
      return Stack(
        fit: StackFit.expand,
        children: [_buildPrivateMediaViewer(mediaItem)],
      );
    }
    switch (mediaItem.type) {
      case MediaType.image:
        return _buildImageViewer(mediaItem);
      case MediaType.video:
        return _buildVideoViewer(mediaItem);
      case MediaType.document:
        return _buildDocumentViewer(mediaItem);
      case MediaType.unknown:
        return _buildUnknownViewer(mediaItem);
    }
  }

  Widget _buildPrivateMediaViewer(MediaItem mediaItem) {
    switch (mediaItem.type) {
      case MediaType.video:
        final localVideo =
            mediaItem.isPendingUpload ? mediaItem.localFilePath : null;
        return Padding(
          padding: _videoInsets,
          child: OfferVideoTile(
            key: ValueKey('offer-video-full-'
                '${mediaItem.mediaObjectId ?? mediaItem.url}'),
            url: mediaItem.url,
            localPath: localVideo,
            mediaObjectId: mediaItem.mediaObjectId,
            controllerKey: mediaItem.cacheKey,
            posterPath: mediaItem.posterPath,
            durationMs: mediaItem.durationMs,
            playable: !mediaItem.isPendingUpload || localVideo != null,
            refreshSignedUrl: widget.refreshSignedUrl,
            fit: BoxFit.contain,
          ),
        );
      case MediaType.image:
      case MediaType.document:
      case MediaType.unknown:
        return _buildImageViewer(mediaItem);
    }
  }

  /// Prefers bytes this device already holds, then the shared disk cache
  /// keyed by the item's stable identity, and only then the network.
  ///
  /// This applies to private Offer media only — the items that carry a stable
  /// [MediaItem.cacheKey]. Everything else, Owner media included, keeps the
  /// plain `NetworkImage` it has always used: caching it was never needed for
  /// the Offer loading-delay correction, and changing an unrelated screen's
  /// image pipeline does not belong in that change.
  ImageProvider _imageProviderFor(MediaItem mediaItem) {
    // An Offer item still uploading is drawn from its queued copy.
    final pendingPath = mediaItem.localFilePath;
    if (mediaItem.isPendingUpload && pendingPath != null) {
      final file = File(pendingPath);
      if (file.existsSync()) return FileImage(file);
    }

    final cacheKey = mediaItem.cacheKey;
    if (cacheKey == null) return NetworkImage(mediaItem.url);

    final localPath =
        OfflineMediaService.instance.getLocalFilePathForMediaId(cacheKey);
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync()) return FileImage(file);
    }
    return CachedNetworkImageProvider(mediaItem.url, cacheKey: cacheKey);
  }

  Widget _buildImageViewer(MediaItem mediaItem) {
    return PhotoView(
      imageProvider: _imageProviderFor(mediaItem),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained * 0.8,
      maxScale: PhotoViewComputedScale.covered * 3.0,
      onScaleEnd: (context, details, controllerValue) {
        setState(() {
          _isZoomed = controllerValue.scale! > 1.0;
        });
      },
      loadingBuilder: (context, event) {
        return Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Image failed to load',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoViewer(MediaItem mediaItem) {
    final chewieController = _chewieControllers[mediaItem.url];

    if (chewieController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: chewieController.videoPlayerController.value.aspectRatio,
        child: Chewie(controller: chewieController),
      ),
    );
  }

  Widget _buildDocumentViewer(MediaItem mediaItem) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final fileName = mediaItem.fileName ?? loc.translate('document');

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.description,
              color: Colors.white,
              size: 80,
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                fileName,
                style: texts.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openDocument(
                mediaItem.url,
                displayName: mediaItem.fileName,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(loc.translate('openDocument')),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnknownViewer(MediaItem mediaItem) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.help_outline,
              color: Colors.white,
              size: 80,
            ),
            const SizedBox(height: 24),
            Text(
              'Unsupported Media Type',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => launchUrl(Uri.parse(mediaItem.url)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Externally'),
            ),
          ],
        ),
      ),
    );
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
      // Ignore decoding errors and continue with the sanitized value.
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

  Future<void> _openDocument(String url, {String? displayName}) async {
    final loc = AppLocalizations.of(context);
    final fallbackName =
        displayName ?? _extractFileName(url) ?? loc.translate('document');
    final lowerName = fallbackName.toLowerCase();

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
              title: fallbackName,
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
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: loc.translate('failedToOpenDocument'),
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Theme.of(context).colorScheme.error,
        textColor: Colors.white,
        fontSize: 14.0,
      );
    }
  }

  Widget _buildThumbnail(MediaItem mediaItem) {
    if (_isPrivateMedia) {
      final poster = mediaItem.posterPath;
      if (mediaItem.type == MediaType.image) {
        return Image(
          image: ResizeImage(_imageProviderFor(mediaItem), width: 120),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[800],
            child: const Icon(
              Icons.broken_image,
              color: Colors.white54,
              size: 24,
            ),
          ),
        );
      }
      if (mediaItem.type == MediaType.video) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Its own frame, the one kept for its media id, or one made
            // from the video when this device has none.
            OfferVideoPoster(
              cacheKey: mediaItem.cacheKey,
              signedUrl: mediaItem.url,
              posterPath: poster,
              cacheWidth: 120,
              placeholder: ColoredBox(
                color: Colors.grey[800]!,
                child: const Icon(
                  Icons.videocam,
                  color: Colors.white54,
                  size: 24,
                ),
              ),
            ),
            const Positioned(
              bottom: 4,
              right: 4,
              child: Icon(
                Icons.play_circle_filled,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
        );
      }
    }
    switch (mediaItem.type) {
      case MediaType.image:
        return Image.network(
          mediaItem.url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[800],
              child: const Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 24,
              ),
            );
          },
        );
      case MediaType.video:
        return Container(
          color: Colors.grey[800],
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.videocam,
                color: Colors.white54,
                size: 24,
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ],
          ),
        );
      case MediaType.document:
        return Container(
          color: Colors.grey[800],
          child: const Icon(
            Icons.description,
            color: Colors.white54,
            size: 24,
          ),
        );
      case MediaType.unknown:
        return Container(
          color: Colors.grey[800],
          child: const Icon(
            Icons.help_outline,
            color: Colors.white54,
            size: 24,
          ),
        );
    }
  }

  IconData _getMediaIcon(MediaType type) {
    switch (type) {
      case MediaType.image:
        return Icons.image;
      case MediaType.video:
        return Icons.videocam;
      case MediaType.document:
        return Icons.description;
      case MediaType.unknown:
        return Icons.help_outline;
    }
  }

  String _getMediaTypeLabel(MediaType type) {
    switch (type) {
      case MediaType.image:
        return 'Image';
      case MediaType.video:
        return 'Video';
      case MediaType.document:
        return 'Document';
      case MediaType.unknown:
        return 'Unknown';
    }
  }
}
