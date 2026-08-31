import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:broker_wallet/src/data/models/media_file_model.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:fluttertoast/fluttertoast.dart';

class UniversalMediaViewer extends StatefulWidget {
  final MediaFileModel media;
  final bool showControls;

  const UniversalMediaViewer({
    super.key,
    required this.media,
    this.showControls = true,
  });

  @override
  State<UniversalMediaViewer> createState() => _UniversalMediaViewerState();
}

class _UniversalMediaViewerState extends State<UniversalMediaViewer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    if (widget.media.mediaType == MediaFileType.video) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.media.downloadUrl),
    );

    await _videoController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: false,
      looping: false,
      aspectRatio: _videoController!.value.aspectRatio,
      showControls: widget.showControls,
      placeholder: Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.media.mediaType) {
      case MediaFileType.image:
        return _buildImageViewer();
      case MediaFileType.video:
        return _buildVideoViewer();
      case MediaFileType.pdf:
        return _buildPdfViewer();
      default:
        return _buildUnsupportedViewer();
    }
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: CachedNetworkImage(
        imageUrl: widget.media.downloadUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(),
        ),
        errorWidget: (context, url, error) => const Center(
          child: Icon(Icons.broken_image, size: 64),
        ),
      ),
    );
  }

  Widget _buildVideoViewer() {
    if (_chewieController == null || !_videoController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Chewie(controller: _chewieController!),
      ),
    );
  }

  Widget _buildPdfViewer() {
    return SfPdfViewer.network(
      widget.media.downloadUrl,
      canShowScrollHead: false,
      canShowScrollStatus: true,
      onDocumentLoadFailed: (details) {
        Fluttertoast.showToast(
          msg: 'Failed to load PDF: ${details.error}',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 14.0,
        );
      },
    );
  }

  Widget _buildUnsupportedViewer() {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64),
          const SizedBox(height: 16),
          Text(loc.translate('unsupportedFileType')),
        ],
      ),
    );
  }
}

/// Thumbnail tile for grid/list views
class MediaThumbnailTile extends StatelessWidget {
  final MediaFileModel media;
  final VoidCallback? onTap;
  final double size;

  const MediaThumbnailTile({
    super.key,
    required this.media,
    this.onTap,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildThumbnail(),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    switch (media.mediaType) {
      case MediaFileType.image:
        return CachedNetworkImage(
          imageUrl: media.thumbnailUrl ?? media.downloadUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => const Center(
            child: CircularProgressIndicator(),
          ),
          errorWidget: (context, url, error) => const Icon(Icons.broken_image),
        );

      case MediaFileType.video:
        return Stack(
          fit: StackFit.expand,
          children: [
            if (media.thumbnailUrl != null)
              CachedNetworkImage(
                imageUrl: media.thumbnailUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  color: Colors.black87,
                  child:
                      const Icon(Icons.videocam, color: Colors.white, size: 48),
                ),
              )
            else
              Container(
                color: Colors.black87,
                child:
                    const Icon(Icons.videocam, color: Colors.white, size: 48),
              ),
            const Center(
              child: Icon(
                Icons.play_circle_filled,
                color: Colors.white,
                size: 40,
              ),
            ),
          ],
        );

      case MediaFileType.pdf:
        return Container(
          color: Colors.red[50],
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf, color: Colors.red, size: 40),
              SizedBox(height: 8),
              Text('PDF', style: TextStyle(color: Colors.red)),
            ],
          ),
        );

      default:
        return const Icon(Icons.insert_drive_file);
    }
  }
}
