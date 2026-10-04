import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_cache_manager.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_loading_placeholder.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_diagnostics.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/video_player_resource_manager.dart';
import 'package:broker_wallet/src/views/Widgets/offer_media_upload_status.dart';
import 'package:broker_wallet/src/views/Widgets/offer_video_poster.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'dart:async';
import 'dart:io';

// The Offer-media cache identity now lives in the service layer so upload,
// read and display all agree on one key; re-exported here so existing
// importers of this file are unchanged.
export 'package:broker_wallet/src/services/offer_media_cache_identity.dart'
    show OfferMediaRef, offerMediaCacheKey;

// Keep the existing MediaType and MediaItem classes
enum MediaType { image, video, document, unknown }

class MediaItem {
  final String url;
  final MediaType type;
  final String? fileName;
  final String? mimeType;

  /// Stable identity behind [url] (e.g. Offer media's `mediaObjectId`).
  final String? mediaObjectId;

  /// Account-scoped cache key derived from [mediaObjectId]. Null when the
  /// caller has no safe stable identity, preserving URL-keyed behavior.
  final String? cacheKey;

  /// Offer media only: this device's copy of the bytes, a video's still
  /// frame and length, and — for an item still in the upload queue — its
  /// upload state. Null for every other caller.
  final String? localFilePath;
  final String? posterPath;
  final int? durationMs;
  final OfferMediaUploadPhase? uploadPhase;
  final double? uploadProgress;
  final String? failureMessageKey;

  MediaItem({
    required this.url,
    required this.type,
    this.fileName,
    this.mimeType,
    this.mediaObjectId,
    this.cacheKey,
    this.localFilePath,
    this.posterPath,
    this.durationMs,
    this.uploadPhase,
    this.uploadProgress,
    this.failureMessageKey,
  });

  /// Whether this item is still on its way to the server.
  bool get isPendingUpload => uploadPhase != null;

  /// Describes one piece of private Offer media.
  ///
  /// The kind comes from the server's own record of the media object
  /// ([OfferMediaRef.isVideo]) rather than from the signed URL, which is a
  /// signing artefact. Only when that is absent — an item held locally before
  /// any resolution — does it fall back to the path, and an Offer item that
  /// cannot be classified is an image, which is what the upload contract
  /// accepted for the whole of this Offer feature's history.
  factory MediaItem.fromOfferMedia(OfferMediaRef ref) {
    final url = ref.signedUrl?.trim() ?? '';
    final local = ref.localFilePath?.trim() ?? '';
    final typeSource = url.isNotEmpty ? url : local;
    final detected = ref.isVideo
        ? MediaType.video
        : typeSource.isEmpty
            ? MediaType.image
            : MediaItem.getMediaTypeFromUrl(typeSource);
    return MediaItem(
      url: url,
      type: detected == MediaType.unknown ? MediaType.image : detected,
      mediaObjectId: ref.mediaObjectId.isEmpty ? null : ref.mediaObjectId,
      cacheKey: ref.cacheKey,
      localFilePath: local.isEmpty ? null : local,
      posterPath: ref.posterPath,
      durationMs: ref.durationMs,
      uploadPhase: ref.uploadPhase,
      uploadProgress: ref.progress,
      failureMessageKey: ref.failureMessageKey,
    );
  }

  static MediaType getMediaTypeFromUrl(String url) {
    final extension = mediaExtensionOf(url);

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

  /// The file extension of [url], read from its path only.
  ///
  /// A signed R2 URL carries a long query string, and splitting the whole
  /// string on '.' can land inside that query rather than on the file's own
  /// extension. Parsing the path first is what keeps '<id>.mp4?X-Amz-...'
  /// recognizable as a video.
  static String mediaExtensionOf(String url) {
    var path = url.split('#').first.split('?').first;
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.pathSegments.isNotEmpty) {
      path = parsed.pathSegments.last;
    }
    final name = path.split('/').last;
    return name.contains('.') ? name.split('.').last.toLowerCase() : '';
  }
}

class OptimizedMediaGalleryWidget extends StatefulWidget {
  /// Fully-described media, used instead of [mediaUrls] when given.
  ///
  /// Offer Details passes this because a private-media item can be renderable
  /// from locally held bytes while its signed URL is still being minted — a
  /// state a plain URL string cannot represent.
  ///
  /// Typed as the service-layer [OfferMediaRef] rather than [MediaItem] on
  /// purpose: this file is reached through two different import spellings
  /// (`src/Views/...` and `src/views/...`), which Dart treats as two
  /// libraries, so a [MediaItem] crossing this boundary would not be the same
  /// type on both sides.
  final List<OfferMediaRef>? mediaRefs;

  /// Drawn in place of an image whose bytes have not arrived yet.
  ///
  /// Supplied by callers that already showed a loading surface before this
  /// widget existed, so the hand-over from "resolving" to "downloading" does
  /// not swap one indicator for a different one. Defaults to this widget's own
  /// spinner for callers that do not.
  final Widget? imagePlaceholder;

  final List<String> mediaUrls;

  /// Stable identity for each entry in [mediaUrls], aligned by index. Pass
  /// null (the default) when no stable id is available; a length mismatch
  /// against [mediaUrls] is treated as "no ids" rather than misaligning any
  /// entry — see [_synchronizeMediaItems].
  final List<String>? mediaIds;
  final String? mediaOwnerId;
  final PageController? pageController;
  final Function(int)? onPageChanged;
  final int? initialIndex;
  final bool showControls;
  final bool autoPlay;
  final String? fallbackSvgPath; // For entities without media
  final VoidCallback? onRetry;

  /// Offer media only: Retry and Remove for an item whose upload failed,
  /// by its `mediaObjectId`.
  final void Function(String mediaObjectId)? onRetryUpload;
  final void Function(String mediaObjectId)? onRemoveUpload;

  /// Offer media only: signs the media again and returns the item's new
  /// link, for a private video whose link has expired. Null when none.
  final Future<String?> Function(String mediaObjectId)? refreshSignedUrl;

  /// Opens the record's Share Options from the full-screen current item.
  final void Function(String mediaKey)? onShareMedia;

  const OptimizedMediaGalleryWidget({
    super.key,
    this.mediaRefs,
    this.imagePlaceholder,
    this.mediaUrls = const <String>[],
    this.mediaIds,
    this.mediaOwnerId,
    this.pageController,
    this.onPageChanged,
    this.initialIndex,
    this.showControls = true,
    this.autoPlay = false,
    this.fallbackSvgPath,
    this.onRetry,
    this.onRetryUpload,
    this.onRemoveUpload,
    this.refreshSignedUrl,
    this.onShareMedia,
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

    final mediaChanged = !listEquals(oldWidget.mediaRefs, widget.mediaRefs) ||
        !listEquals(oldWidget.mediaUrls, widget.mediaUrls) ||
        !listEquals(oldWidget.mediaIds, widget.mediaIds) ||
        oldWidget.mediaOwnerId != widget.mediaOwnerId;
    final indexChanged = oldWidget.initialIndex != widget.initialIndex &&
        widget.initialIndex != null;

    if (mediaChanged || indexChanged) {
      setState(() {
        _synchronizeMediaItems(resetIndex: indexChanged);
      });

      // An upload's progress changes many times a second; only a change to
      // what the server holds needs the scroll and prefetch below.
      if (!indexChanged &&
          _sameServerMedia(oldWidget.mediaRefs, widget.mediaRefs) &&
          listEquals(oldWidget.mediaUrls, widget.mediaUrls) &&
          listEquals(oldWidget.mediaIds, widget.mediaIds) &&
          oldWidget.mediaOwnerId == widget.mediaOwnerId) {
        return;
      }

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

  /// Whether [a] and [b] name the same server-held items with the same links,
  /// whatever the upload queue's items are doing meanwhile.
  static bool _sameServerMedia(List<OfferMediaRef>? a, List<OfferMediaRef>? b) {
    if (a == null || b == null) return a == b;
    List<String> held(List<OfferMediaRef> refs) => [
          for (final ref in refs)
            if (ref.uploadPhase == null)
              '${ref.mediaObjectId} ${ref.signedUrl}',
        ];
    return listEquals(held(a), held(b));
  }

  void _prefetchInitialMedia() {
    if (_mediaItems.isEmpty) return;

    // Prefetch current and next 2 items
    final startIndex = _currentIndex;
    final endIndex = (_currentIndex + 3).clamp(0, _mediaItems.length);

    for (int i = startIndex; i < endIndex; i++) {
      final mediaItem = _mediaItems[i];
      // An item with no URL is one whose bytes are already held locally (or
      // whose signed URL has not been minted yet). Prefetching it would only
      // cache a placeholder against its real identity.
      if (mediaItem.url.isEmpty) continue;
      if (_warmStableIdentity(mediaItem)) continue;
      if (mediaItem.type == MediaType.image) {
        _cacheManager.getOptimizedImage(
          mediaItem.url,
          cacheKey: mediaItem.cacheKey,
        );
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
      if (mediaItem.url.isEmpty) continue;
      if (_warmStableIdentity(mediaItem)) continue;
      if (mediaItem.type == MediaType.image) {
        _cacheManager.getOptimizedImage(
          mediaItem.url,
          cacheKey: mediaItem.cacheKey,
        );
      } else if (mediaItem.type == MediaType.video) {
        _cacheManager.getOptimizedVideo(mediaItem.url);
      }
    }
  }

  /// Pulls a private media item's bytes into the shared cache under its own
  /// stable identity, and records where they landed so the next open can paint
  /// them before any signed URL exists.
  ///
  /// Returns true when it handled the item, which keeps it away from the
  /// URL-keyed prefetch: that path stores a second, resized copy under a
  /// different key and decodes it at a size nothing on screen uses.
  bool _warmStableIdentity(MediaItem mediaItem) {
    final cacheKey = mediaItem.cacheKey;
    if (cacheKey == null) return false;
    if (mediaItem.type == MediaType.image) {
      unawaited(OfflineMediaService.instance.ensureMediaIdCached(
        cacheKey: cacheKey,
        url: mediaItem.url,
      ));
    }
    return true;
  }

  void _synchronizeMediaItems({bool resetIndex = false}) {
    final provided = widget.mediaRefs;
    if (provided != null) {
      _adoptMediaItems(
        [for (final ref in provided) MediaItem.fromOfferMedia(ref)],
        resetIndex: resetIndex,
      );
      return;
    }

    // A length mismatch means the ids can't be trusted to align by index —
    // treat it as "no ids" rather than risk pairing an id with the wrong
    // URL, which would misattribute one item's cached bytes to another.
    final ids = widget.mediaIds;
    final hasAlignedIds = ids != null && ids.length == widget.mediaUrls.length;

    final newItems = <MediaItem>[
      for (var i = 0; i < widget.mediaUrls.length; i++)
        MediaItem(
          url: widget.mediaUrls[i],
          type: MediaItem.getMediaTypeFromUrl(widget.mediaUrls[i]),
          fileName: _extractFileName(widget.mediaUrls[i]),
          mediaObjectId: hasAlignedIds && ids[i].isNotEmpty ? ids[i] : null,
          cacheKey: offerMediaCacheKey(
            ownerId: widget.mediaOwnerId,
            mediaObjectId: hasAlignedIds && ids[i].isNotEmpty ? ids[i] : null,
          ),
        ),
    ];

    _adoptMediaItems(newItems, resetIndex: resetIndex);
  }

  void _adoptMediaItems(List<MediaItem> newItems, {required bool resetIndex}) {
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
                    _videoResourceManager.pauseAllExcept(
                        currentItem.cacheKey ?? currentItem.url);
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
              final item = _mediaItems[index];
              return RepaintBoundary(
                key: ValueKey(item.cacheKey ?? item.url),
                // Offer media keeps one shape whether or not the item is still
                // uploading, so a video playing from its local copy keeps
                // playing when the upload finishes and the item turns ready.
                child: widget.mediaRefs != null || item.isPendingUpload
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildMediaItem(item, context),
                          if (item.isPendingUpload) _buildUploadStatus(item),
                        ],
                      )
                    : _buildMediaItem(item, context),
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

  /// An upload's state over its page (Offer media only), with Retry and
  /// Remove when it failed.
  Widget _buildUploadStatus(MediaItem item) {
    final id = item.mediaObjectId;
    final retry = widget.onRetryUpload;
    final remove = widget.onRemoveUpload;
    return OfferMediaUploadStatus(
      phase: item.uploadPhase!,
      progress: item.uploadProgress,
      failureMessageKey: item.failureMessageKey,
      onRetry: id == null || retry == null ? null : () => retry(id),
      onRemove: id == null || remove == null ? null : () => remove(id),
      // Above the counter, page dots and "View All" drawn along the bottom.
      bottomInset: 36,
    );
  }

  /// Decode width for a full-width header image.
  int _headerCacheWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round();

  Widget _buildMediaItem(MediaItem mediaItem, BuildContext context) {
    // Private Offer media: local bytes first, and a video is never loaded
    // before the viewer asks to play it.
    if (widget.mediaRefs != null) {
      switch (mediaItem.type) {
        case MediaType.image:
          final local = mediaItem.localFilePath;
          if (mediaItem.isPendingUpload &&
              local != null &&
              File(local).existsSync()) {
            return Image.file(
              File(local),
              fit: BoxFit.cover,
              cacheWidth: _headerCacheWidth(context),
              gaplessPlayback: true,
            );
          }
          return _buildOptimizedImageViewer(
            mediaItem,
            context,
            cacheWidth: _headerCacheWidth(context),
          );
        case MediaType.video:
          final localVideo =
              mediaItem.isPendingUpload ? mediaItem.localFilePath : null;
          return OfferVideoTile(
            key: ValueKey(
                'offer-video-${mediaItem.mediaObjectId ?? mediaItem.url}'),
            url: mediaItem.url,
            localPath: localVideo,
            mediaObjectId: mediaItem.mediaObjectId,
            controllerKey: mediaItem.cacheKey,
            posterPath: mediaItem.posterPath,
            durationMs: mediaItem.durationMs,
            playable: !mediaItem.isPendingUpload || localVideo != null,
            refreshSignedUrl: widget.refreshSignedUrl,
          );
        case MediaType.document:
        case MediaType.unknown:
          break;
      }
    }
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

  Widget _buildOptimizedImageViewer(
    MediaItem mediaItem,
    BuildContext context, {
    int? cacheWidth,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: OfflineMediaService.instance.buildOfflineAwareImage(
        imageUrl: mediaItem.url,
        cacheKey: mediaItem.cacheKey,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        placeholder: widget.imagePlaceholder ??
            Container(
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
        errorWidget: Builder(
          builder: (errorContext) => Container(
            color: Theme.of(errorContext).colorScheme.errorContainer,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Theme.of(errorContext).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(errorContext)
                        .translate('failedToLoadImage'),
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(errorContext).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(errorContext)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                  ),
                  if (widget.onRetry != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: widget.onRetry,
                      child: Text(
                        AppLocalizations.of(errorContext).translate('retry'),
                      ),
                    ),
                  ],
                ],
              ),
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
          mediaRefs: widget.mediaRefs,
          mediaUrls: widget.mediaUrls,
          initialIndex: _currentIndex,
          title: 'Media Gallery',
          refreshSignedUrl: widget.refreshSignedUrl,
          onShareMedia: widget.onShareMedia,
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
      // Only indicates: never takes a touch meant for the page beneath.
      child: IgnorePointer(
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
      )),
    );
  }

  Widget _buildPageIndicator(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      // Only indicates: a portrait video reaches the bottom edge and these
      // dots lie exactly across its seek bar, so they must let touches through.
      child: IgnorePointer(
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
      )),
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

  /// A stable name for the player when [videoUrl] is not one (a private
  /// video's signed link). Null: the URL names it, as before.
  final String? controllerKey;

  /// Called instead of showing this widget's own error when the video could
  /// not be opened, so the caller can recover (e.g. sign a new link).
  final VoidCallback? onInitializationFailed;

  /// How many times the player may try to open [videoUrl].
  final int maxAttempts;

  const OptimizedVideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
    this.controllerKey,
    this.onInitializationFailed,
    this.maxAttempts = 3,
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

  /// Gives the controller back to the manager, which owns it: the player
  /// never disposes a controller itself, and releases one exactly once.
  void _releaseController() {
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_resourceManager.release(controller));
  }

  Future<void> _initializeVideo() async {
    if (!mounted) return;

    // A Retry: let go of the previous player and its controls first.
    _chewieController?.dispose();
    _chewieController = null;
    _releaseController();

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // Check if video format is supported
      if (!VideoPlayerResourceManager.isVideoFormatSupported(widget.videoUrl)) {
        final key = widget.controllerKey;
        if (key != null) {
          // Refused before any player exists: say so, rather than leaving
          // the caller a failure with no cause.
          _resourceManager.noteFailure(key, 'format-refused');
          OfferMediaDiagnostics.log('player-init-failed', fields: {
            'stage': 'format-check',
            'source': widget.videoUrl.startsWith('http') ? 'network' : 'local',
            'cause': 'format-refused',
          });
        }
        throw Exception(
            'Unsupported video format. Codec: ${VideoPlayerResourceManager.getVideoCodecInfo(widget.videoUrl)}');
      }

      // Get controller from resource manager
      final controller = await _resourceManager.getController(
        widget.videoUrl,
        key: widget.controllerKey,
        maxAttempts: widget.maxAttempts,
      );

      if (!mounted) {
        // Closed while the player was still starting: this widget holds it
        // now, so it must give it back rather than leave it held forever.
        if (controller != null) unawaited(_resourceManager.release(controller));
        return;
      }

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
      final onFailed = widget.onInitializationFailed;
      if (onFailed != null) {
        // A format refusal fails inside initState, while the caller is still
        // building; the caller rebuilds itself in response, so never then.
        scheduleMicrotask(() {
          if (mounted) onFailed();
        });
      }
    }
  }

  String get _controllerName => widget.controllerKey ?? widget.videoUrl;

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
    final name = _controllerName;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _resourceManager.pauseController(name);
    });
    super.deactivate();
  }

  @override
  void dispose() {
    // The controls first (they listen to the controller), then the
    // controller goes back to the manager, which disposes it only once no
    // other player shows it.
    _chewieController?.dispose();
    _chewieController = null;
    _releaseController();
    final name = _controllerName;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // A player still shown elsewhere (Details under full screen) stops too.
      _resourceManager.pauseController(name);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The caller shows its own recovery instead of this widget's error.
    if (_hasError && widget.onInitializationFailed != null) {
      return Container(color: Colors.black);
    }

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

/// One private Offer video.
///
/// Shows the still frame this device made (or a plain tile with the video's
/// length) until the viewer taps it, so no video is fetched before it is
/// wanted. A video still uploading plays from this device's own copy
/// ([localPath]) and never from the network, where it does not exist yet. A
/// ready video's player is named by the video's stable cache key rather than
/// by its signed link, which changes every time it is signed. When the link
/// fails (it may have expired), the video is signed again once,
/// automatically; after that the viewer gets a plain message and Retry.
class OfferVideoTile extends StatefulWidget {
  const OfferVideoTile({
    super.key,
    required this.url,
    this.localPath,
    this.mediaObjectId,
    this.controllerKey,
    this.posterPath,
    this.durationMs,
    this.playable = true,
    this.refreshSignedUrl,
    this.fit = BoxFit.cover,
  });

  final String url;

  /// This device's copy of a video still uploading, played instead of [url].
  final String? localPath;
  final String? mediaObjectId;
  final String? controllerKey;
  final String? posterPath;
  final int? durationMs;

  /// False while the video is uploading with no local copy to play.
  final bool playable;
  final Future<String?> Function(String mediaObjectId)? refreshSignedUrl;
  final BoxFit fit;

  @override
  State<OfferVideoTile> createState() => _OfferVideoTileState();
}

enum _VideoTilePhase { idle, refreshing, playing, failed }

class _OfferVideoTileState extends State<OfferVideoTile> {
  late String _url = widget.url;

  /// What the player was opened with: [_url], or the local copy.
  String _source = '';
  _VideoTilePhase _state = _VideoTilePhase.idle;
  bool _refreshedThisAttempt = false;

  bool get _playingLocal => _source.isNotEmpty && _source != _url;

  @override
  void didUpdateWidget(covariant OfferVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A newer link, from a refresh of the whole Offer, is taken up unless a
    // video is already playing from the older one.
    if (widget.url != oldWidget.url && _state != _VideoTilePhase.playing) {
      _url = widget.url;
    }
  }

  String? get _existingLocalCopy {
    final local = widget.localPath?.trim();
    if (local == null || local.isEmpty) return null;
    return File(local).existsSync() ? local : null;
  }

  void _log(String event, [Map<String, Object?>? fields]) {
    final id = widget.mediaObjectId;
    OfferMediaDiagnostics.log(event, id: id, fields: fields);
  }

  void _play() {
    if (!widget.playable) return;
    _refreshedThisAttempt = false;
    final local = _existingLocalCopy;
    if (local != null) {
      _log('play', {'source': 'local'});
      setState(() {
        _source = local;
        _state = _VideoTilePhase.playing;
      });
      return;
    }
    if (_url.trim().isEmpty) {
      unawaited(_refresh());
      return;
    }
    _log('play', {'source': 'network'});
    setState(() {
      _source = _url;
      _state = _VideoTilePhase.playing;
    });
  }

  void _onPlayerFailed() {
    if (!mounted) return;
    final key = widget.controllerKey;
    _log('play-failed', {
      'source': _playingLocal ? 'local' : 'network',
      'cause': key == null
          ? null
          : VideoPlayerResourceManager().lastFailureCategory(key),
      'afterRefresh': _refreshedThisAttempt,
    });
    // A local copy that cannot be opened is not helped by a new link.
    if (_refreshedThisAttempt || _playingLocal) {
      setState(() => _state = _VideoTilePhase.failed);
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    _refreshedThisAttempt = true;
    final id = widget.mediaObjectId;
    final refresh = widget.refreshSignedUrl;
    if (id == null || refresh == null) {
      setState(() => _state = _VideoTilePhase.failed);
      return;
    }
    setState(() => _state = _VideoTilePhase.refreshing);
    String? fresh;
    try {
      fresh = await refresh(id);
    } catch (_) {
      fresh = null;
    }
    if (!mounted) return;
    final link = fresh?.trim() ?? '';
    _log('play-link-refreshed', {'ok': link.isNotEmpty});
    setState(() {
      if (link.isEmpty) {
        _state = _VideoTilePhase.failed;
      } else {
        _url = link;
        _source = link;
        _state = _VideoTilePhase.playing;
      }
    });
  }

  static String _formatDuration(int milliseconds) {
    final total = (milliseconds / 1000).round();
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _VideoTilePhase.playing) {
      return OptimizedVideoPlayerWidget(
        key: ValueKey(_source),
        videoUrl: _source,
        autoPlay: true,
        controllerKey: widget.controllerKey,
        // One attempt: the recovery for a private link is a new link, which
        // the tile fetches itself, not the same request again.
        maxAttempts: 1,
        onInitializationFailed: _onPlayerFailed,
      );
    }

    final loc = AppLocalizations.of(context);
    final textStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600);
    final duration = widget.durationMs;

    final Widget centre;
    switch (_state) {
      case _VideoTilePhase.refreshing:
        centre = const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case _VideoTilePhase.failed:
        centre = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 40),
            const SizedBox(height: 8),
            Text(
              loc.translate('offerMediaVideoUnavailable'),
              style: textStyle,
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: _play,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(loc.translate('retry')),
            ),
          ],
        );
      case _VideoTilePhase.idle:
      case _VideoTilePhase.playing:
        centre = widget.playable
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    duration == null
                        ? loc.translate('offerMediaTapToPlay')
                        : '${loc.translate('offerMediaTapToPlay')} · '
                            '${_formatDuration(duration)}',
                    style: textStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : const Icon(Icons.videocam_rounded, color: Colors.white, size: 48);
    }

    return Semantics(
      button: widget.playable,
      label: loc.translate('offerMediaTapToPlay'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.playable && _state == _VideoTilePhase.idle ? _play : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Its own frame, the one kept for its media id, or — for a ready
            // video this device has none of — one made from the video.
            OfferVideoPoster(
              cacheKey: widget.controllerKey,
              signedUrl: _url,
              posterPath: widget.posterPath,
              fit: widget.fit,
              cacheWidth: (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
              placeholder: const ColoredBox(color: Colors.black87),
              loading: const MediaLoadingPlaceholder(),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: centre,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
