// import 'package:flutter/material.dart';
// import 'package:video_player/video_player.dart';
// import 'package:chewie/chewie.dart';
// import 'package:broker_wallet/src/widgets/fast_network_image.dart';
// import 'package:broker_wallet/src/services/video_player_resource_manager.dart';
// import 'package:broker_wallet/src/services/video_converter_service.dart';
// import 'package:visibility_detector/visibility_detector.dart';
// import 'dart:developer' as developer;
// import 'dart:async';

// /// Optimized video player widget with HLS support, poster thumbnails, and smooth playback
// class OptimizedVideoPlayer extends StatefulWidget {
//   final String videoUrl;
//   final String? posterUrl;
//   final String? hlsUrl; // HLS manifest URL for adaptive streaming
//   final double? width;
//   final double? height;
//   final bool autoPlay;
//   final bool showControls;
//   final bool looping;
//   final VoidCallback? onVideoStarted;
//   final VoidCallback? onVideoEnded;
//   final Function(Duration position, Duration duration)? onProgressChanged;
//   final bool preloadNext;

//   const OptimizedVideoPlayer({
//     Key? key,
//     required this.videoUrl,
//     this.posterUrl,
//     this.hlsUrl,
//     this.width,
//     this.height,
//     this.autoPlay = false,
//     this.showControls = true,
//     this.looping = false,
//     this.onVideoStarted,
//     this.onVideoEnded,
//     this.onProgressChanged,
//     this.preloadNext = false,
//   }) : super(key: key);

//   @override
//   State<OptimizedVideoPlayer> createState() => _OptimizedVideoPlayerState();
// }

// class _OptimizedVideoPlayerState extends State<OptimizedVideoPlayer>
//     with WidgetsBindingObserver {
//   VideoPlayerController? _controller;
//   ChewieController? _chewieController;
//   bool _isInitialized = false;
//   bool _showPoster = true;
//   bool _isLoading = false;
//   String? _error;
//   Timer? _progressTimer;
//   final VideoPlayerResourceManager _resourceManager =
//       VideoPlayerResourceManager();
//   final VideoConverterService _converterService = VideoConverterService();

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _initializePlayer();
//   }

//   @override
//   void didUpdateWidget(covariant OptimizedVideoPlayer oldWidget) {
//     super.didUpdateWidget(oldWidget);

//     final oldSource = oldWidget.hlsUrl ?? oldWidget.videoUrl;
//     final newSource = widget.hlsUrl ?? widget.videoUrl;

//     if (newSource != oldSource) {
//       _reinitializeForNewSource();
//       return;
//     }

//     if (!widget.autoPlay && oldWidget.autoPlay) {
//       _pauseVideo();
//     } else if (widget.autoPlay && !oldWidget.autoPlay) {
//       if (_controller != null && _controller!.value.isInitialized) {
//         _playVideo();
//       }
//     }

//     if (widget.looping != oldWidget.looping && _controller != null) {
//       _controller!.setLooping(widget.looping);
//     }
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _disposePlayer();
//     _progressTimer?.cancel();
//     super.dispose();
//   }

//   Future<void> _disposePlayer() async {
//     if (_chewieController != null) {
//       _chewieController!.dispose(); // Remove await since dispose returns void
//       _chewieController = null;
//     }

//     // Use resource manager to properly release the controller
//     if (_controller != null) {
//       final videoUrl = widget.hlsUrl ?? widget.videoUrl;
//       await _resourceManager.releaseController(videoUrl);
//       _controller = null;
//     }
//   }

//   Future<void> _reinitializeForNewSource() async {
//     if (mounted) {
//       setState(() {
//         _isInitialized = false;
//         _isLoading = true;
//         _showPoster = true;
//         _error = null;
//       });
//     }

//     await _disposePlayer();

//     if (!mounted) {
//       return;
//     }

//     await _initializePlayer();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     super.didChangeAppLifecycleState(state);

//     // Pause video when app goes to background
//     if (state == AppLifecycleState.paused) {
//       _pauseVideo();
//     } else if (state == AppLifecycleState.resumed) {
//       // Optionally resume if it was playing
//     }
//   }

//   Future<void> _initializePlayer() async {
//     if (mounted) {
//       setState(() {
//         _isLoading = true;
//         _error = null;
//       });
//     }

//     try {
//       // Use HLS URL if available, otherwise fall back to regular video URL
//       final videoUrl = widget.hlsUrl ?? widget.videoUrl;

//       developer.log(
//         '🎬 Initializing video player for: $videoUrl',
//         name: 'OptimizedVideoPlayer',
//       );

//       // Use resource manager for better reliability and MediaCodec handling
//       _controller = await _resourceManager.getController(videoUrl);

//       if (_controller == null) {
//         throw Exception(
//             'Failed to create video controller. This may be due to unsupported video format (HEVC/H.265) or device compatibility issues.');
//       }

//       // Verify the controller is properly initialized
//       if (!_controller!.value.isInitialized) {
//         throw Exception(
//             'Video controller created but not properly initialized');
//       }

//       // Configure video settings
//       if (widget.looping) {
//         await _controller!.setLooping(true);
//       }

//       // Initialize Chewie controller if controls are needed
//       if (widget.showControls) {
//         _chewieController = ChewieController(
//           videoPlayerController: _controller!,
//           autoPlay: widget.autoPlay,
//           looping: widget.looping,
//           aspectRatio: _calculateAspectRatio(),
//           placeholder: _buildPosterWidget(),
//           autoInitialize: true,
//           showControls: true,
//           materialProgressColors: ChewieProgressColors(
//             playedColor: Theme.of(context).primaryColor,
//             handleColor: Theme.of(context).primaryColor,
//             backgroundColor: Colors.grey,
//             bufferedColor: Colors.grey[300]!,
//           ),
//           errorBuilder: (context, errorMessage) {
//             return Container(
//               color: Colors.black,
//               child: Center(
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(Icons.error, color: Colors.red, size: 48),
//                     SizedBox(height: 16),
//                     Text(
//                       'Video playback error: $errorMessage',
//                       style: TextStyle(color: Colors.white),
//                       textAlign: TextAlign.center,
//                     ),
//                   ],
//                 ),
//               ),
//             );
//           },
//         );
//       }

//       // Add listeners
//       _controller!.addListener(_onVideoPlayerEvent);

//       if (mounted) {
//         setState(() {
//           _isInitialized = true;
//           _isLoading = false;
//         });

//         // Auto-play if requested and no controls
//         if (widget.autoPlay && !widget.showControls) {
//           _playVideo();
//         }

//         // Start progress tracking
//         _startProgressTracking();
//       }

//       developer.log(
//         '✅ Video player fully configured: ${widget.videoUrl}',
//         name: 'OptimizedVideoPlayer',
//       );
//     } catch (e) {
//       developer.log(
//         '❌ Video player initialization failed: $e',
//         name: 'OptimizedVideoPlayer',
//       );

//       if (mounted) {
//         setState(() {
//           _error = _formatErrorMessage(e.toString());
//           _isLoading = false;
//         });
//       }
//     }
//   }

//   // Format error messages to be user-friendly
//   String _formatErrorMessage(String error) {
//     if (VideoPlayerResourceManager.isHEVCCompatibilityError(error) ||
//         error.contains('MediaCodecVideoRenderer') ||
//         error.contains('video/hevc') ||
//         error.contains('ExoPlaybackException')) {
//       return 'This video format (HEVC/H.265) is not supported on your device. Please use a different video or convert it to H.264 format.';
//     } else if (error.contains('timeout')) {
//       return 'Video loading timed out. Please check your connection and try again.';
//     } else if (error.contains('network') || error.contains('connection')) {
//       return 'Network error. Please check your internet connection.';
//     } else if (error.contains('HEVC video cannot be played')) {
//       return 'HEVC video format not supported on this device. Please use H.264 format instead.';
//     } else {
//       return 'Failed to load video. Please try again or use a different video format.';
//     }
//   }

//   double _calculateAspectRatio() {
//     if (widget.width != null && widget.height != null) {
//       return widget.width! / widget.height!;
//     }
//     return 16 / 9; // Default aspect ratio
//   }

//   void _onVideoPlayerEvent() {
//     if (_controller == null) return;

//     if (_controller!.value.isPlaying && _showPoster) {
//       _onVideoStarted();
//     }

//     if (_controller!.value.position == _controller!.value.duration &&
//         _controller!.value.duration > Duration.zero) {
//       widget.onVideoEnded?.call();
//     }
//   }

//   void _onVideoStarted() {
//     if (mounted && _showPoster) {
//       setState(() {
//         _showPoster = false;
//       });
//     }
//     widget.onVideoStarted?.call();
//   }

//   void _startProgressTracking() {
//     _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
//       if (!mounted) {
//         timer.cancel();
//         return;
//       }

//       if (_controller != null) {
//         try {
//           final position = _controller!.value.position;
//           final duration = _controller!.value.duration;
//           widget.onProgressChanged?.call(position, duration);
//         } catch (e) {
//           // Controller not ready yet
//         }
//       }
//     });
//   }

//   void _playVideo() {
//     if (_chewieController != null) {
//       _chewieController!.play();
//     } else if (_controller != null) {
//       _controller!.play();
//     }
//   }

//   void _pauseVideo() {
//     if (_chewieController != null) {
//       _chewieController!.pause();
//     } else if (_controller != null) {
//       _controller!.pause();
//     }
//   }

//   Widget _buildPosterWidget() {
//     if (widget.posterUrl == null) {
//       return Container(
//         width: widget.width,
//         height: widget.height,
//         color: Colors.black,
//         child: const Center(
//           child: Icon(
//             Icons.play_circle_fill,
//             color: Colors.white,
//             size: 64,
//           ),
//         ),
//       );
//     }

//     return FastNetworkImage(
//       url: widget.posterUrl!,
//       width: widget.width,
//       height: widget.height,
//       fit: BoxFit.cover,
//       placeholder: Container(
//         width: widget.width,
//         height: widget.height,
//         color: Colors.black,
//         child: const Center(
//           child: CircularProgressIndicator(color: Colors.white),
//         ),
//       ),
//     );
//   }

//   Widget _buildVideoPlayer() {
//     if (_chewieController != null) {
//       return Chewie(controller: _chewieController!);
//     } else if (_controller != null) {
//       return VideoPlayer(_controller!);
//     } else {
//       return Container(
//         width: widget.width,
//         height: widget.height,
//         color: Colors.black,
//       );
//     }
//   }

//   Widget _buildErrorWidget() {
//     return Container(
//       width: widget.width,
//       height: widget.height,
//       color: Colors.black,
//       child: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(
//               _isHEVCError() ? Icons.video_settings : Icons.error_outline,
//               color: _isHEVCError() ? Colors.orange : Colors.white,
//               size: 48,
//             ),
//             const SizedBox(height: 16),
//             Text(
//               _isHEVCError()
//                   ? 'Video Format Not Supported'
//                   : 'Video failed to load',
//               style: TextStyle(
//                 color: Colors.white,
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//             if (_error != null) ...[
//               const SizedBox(height: 8),
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 child: Text(
//                   _error!,
//                   style: const TextStyle(color: Colors.white70, fontSize: 12),
//                   textAlign: TextAlign.center,
//                 ),
//               ),
//             ],
//             if (_isHEVCError()) ...[
//               const SizedBox(height: 16),
//               Container(
//                 padding:
//                     const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                 margin: const EdgeInsets.symmetric(horizontal: 20),
//                 decoration: BoxDecoration(
//                   color: Color.fromARGB((0.2 * 255).round(), Colors.orange.red,
//                       Colors.orange.green, Colors.orange.blue),
//                   borderRadius: BorderRadius.circular(8),
//                   border: Border.all(color: Colors.orange, width: 1),
//                 ),
//                 child: Column(
//                   children: [
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         Icon(Icons.info_outline,
//                             color: Colors.orange, size: 16),
//                         SizedBox(width: 8),
//                         Text(
//                           'HEVC Format Not Supported',
//                           style: TextStyle(
//                             color: Colors.orange,
//                             fontSize: 12,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       'This device cannot play HEVC/H.265 videos. Please convert to H.264 format using apps like HandBrake or VLC.',
//                       style: TextStyle(
//                         color: Colors.white70,
//                         fontSize: 10,
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                     const SizedBox(height: 8),
//                     ElevatedButton(
//                       onPressed: () => _showHEVCHelpDialog(context),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.orange,
//                         padding:
//                             EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                       ),
//                       child: Text(
//                         'Learn More',
//                         style: TextStyle(color: Colors.white, fontSize: 10),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }

//   bool _isHEVCError() {
//     return _error != null &&
//         VideoPlayerResourceManager.isHEVCCompatibilityError(_error!);
//   }

//   void _showHEVCHelpDialog(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: Row(
//             children: [
//               Icon(Icons.video_settings, color: Colors.orange),
//               SizedBox(width: 8),
//               Text('HEVC Video Format'),
//             ],
//           ),
//           content: SingleChildScrollView(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text(
//                   'Your device doesn\'t support HEVC/H.265 video format.',
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(height: 12),
//                 Text('Solutions:'),
//                 SizedBox(height: 8),
//                 _buildSolutionItem('• Convert videos to H.264 format'),
//                 _buildSolutionItem(
//                     '• Use HandBrake (free) or VLC for conversion'),
//                 _buildSolutionItem('• Record new videos in H.264 format'),
//                 _buildSolutionItem('• H.264 works on all Android devices'),
//                 SizedBox(height: 12),
//                 Container(
//                   padding: EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: Color.fromARGB((0.1 * 255).round(), Colors.blue.red,
//                         Colors.blue.green, Colors.blue.blue),
//                     borderRadius: BorderRadius.circular(4),
//                   ),
//                   child: Text(
//                     'Tip: Most modern phones can record in H.264 by default in camera settings.',
//                     style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.of(context).pop(),
//               child: Text('Got It'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   Widget _buildSolutionItem(String text) {
//     return Padding(
//       padding: EdgeInsets.only(bottom: 4),
//       child: Text(text, style: TextStyle(fontSize: 14)),
//     );
//   }

//   Widget _buildLoadingWidget() {
//     return Container(
//       width: widget.width,
//       height: widget.height,
//       color: Colors.black,
//       child: const Center(
//         child: CircularProgressIndicator(color: Colors.white),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_error != null) {
//       return _buildErrorWidget();
//     }

//     if (_isLoading) {
//       return _buildLoadingWidget();
//     }

//     return SizedBox(
//       width: widget.width,
//       height: widget.height,
//       child: Stack(
//         fit: StackFit.expand,
//         children: [
//           // Video player (hidden behind poster initially)
//           if (_isInitialized) _buildVideoPlayer(),

//           // Poster overlay (shown until video starts playing)
//           if (_showPoster)
//             GestureDetector(
//               onTap: _playVideo,
//               child: _buildPosterWidget(),
//             ),

//           // Play button overlay (if showing poster and no custom controls)
//           if (_showPoster && !widget.showControls)
//             Positioned.fill(
//               child: Center(
//                 child: GestureDetector(
//                   onTap: _playVideo,
//                   child: Container(
//                     width: 80,
//                     height: 80,
//                     decoration: BoxDecoration(
//                       color: Colors.black54,
//                       shape: BoxShape.circle,
//                     ),
//                     child: const Icon(
//                       Icons.play_arrow,
//                       color: Colors.white,
//                       size: 48,
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }

// /// Video player type enumeration
// enum VideoPlayerType {
//   basic, // Use basic VideoPlayer widget
//   advanced, // Use Chewie widget with controls
//   auto, // Automatically choose based on content
// }

// /// List video player widget optimized for scrolling performance
// class ListVideoPlayer extends StatefulWidget {
//   final String videoUrl;
//   final String? posterUrl;
//   final String? hlsUrl;
//   final double width;
//   final double height;
//   final bool autoPlayOnVisible;
//   final VoidCallback? onTap;

//   const ListVideoPlayer({
//     Key? key,
//     required this.videoUrl,
//     this.posterUrl,
//     this.hlsUrl,
//     this.width = 120,
//     this.height = 80,
//     this.autoPlayOnVisible = false,
//     this.onTap,
//   }) : super(key: key);

//   @override
//   State<ListVideoPlayer> createState() => _ListVideoPlayerState();
// }

// class _ListVideoPlayerState extends State<ListVideoPlayer> {
//   bool _isVisible = false;
//   bool _hasStartedPlaying = false;
//   final VideoPlayerResourceManager _resourceManager =
//       VideoPlayerResourceManager();

//   @override
//   void dispose() {
//     final targetUrl = widget.hlsUrl ?? widget.videoUrl;
//     unawaited(_resourceManager.pauseController(targetUrl));
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     Widget player = OptimizedVideoPlayer(
//       videoUrl: widget.videoUrl,
//       posterUrl: widget.posterUrl,
//       hlsUrl: widget.hlsUrl,
//       width: widget.width,
//       height: widget.height,
//       autoPlay: _isVisible && widget.autoPlayOnVisible && !_hasStartedPlaying,
//       showControls: false,
//       onVideoStarted: () {
//         _hasStartedPlaying = true;
//       },
//     );

//     if (widget.onTap != null) {
//       player = GestureDetector(
//         onTap: widget.onTap,
//         child: player,
//       );
//     }

//     return VisibilityDetector(
//       key: Key(widget.videoUrl),
//       onVisibilityChanged: (info) {
//         final newVisibility = info.visibleFraction > 0.5;
//         if (newVisibility != _isVisible) {
//           setState(() {
//             _isVisible = newVisibility;
//             if (!newVisibility && widget.autoPlayOnVisible) {
//               _hasStartedPlaying = false;
//             }
//           });

//           if (!newVisibility) {
//             final targetUrl = widget.hlsUrl ?? widget.videoUrl;
//             unawaited(_resourceManager.pauseController(targetUrl));
//           }
//         }
//       },
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(8),
//         child: player,
//       ),
//     );
//   }
// }

// /// Gallery video player widget for detail views
// class GalleryVideoPlayer extends StatelessWidget {
//   final String videoUrl;
//   final String? posterUrl;
//   final String? hlsUrl;
//   final double? width;
//   final double? height;
//   final String? heroTag;
//   final VoidCallback? onFullscreen;

//   const GalleryVideoPlayer({
//     Key? key,
//     required this.videoUrl,
//     this.posterUrl,
//     this.hlsUrl,
//     this.width,
//     this.height,
//     this.heroTag,
//     this.onFullscreen,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     Widget player = OptimizedVideoPlayer(
//       videoUrl: videoUrl,
//       posterUrl: posterUrl,
//       hlsUrl: hlsUrl,
//       width: width,
//       height: height,
//       autoPlay: false,
//       showControls: true,
//     );

//     if (heroTag != null) {
//       player = Hero(
//         tag: heroTag!,
//         child: player,
//       );
//     }

//     return ClipRRect(
//       borderRadius: BorderRadius.circular(12),
//       child: player,
//     );
//   }
// }

// /// Video preloader for smooth navigation
// class VideoPreloader {
//   static final Map<String, VideoPlayerController> _preloadedControllers = {};

//   /// Preload a video for smooth playback
//   static Future<void> preloadVideo(String videoUrl) async {
//     if (_preloadedControllers.containsKey(videoUrl)) {
//       return; // Already preloaded
//     }

//     try {
//       final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
//       await controller.initialize();

//       _preloadedControllers[videoUrl] = controller;

//       developer.log(
//         '✅ Preloaded video: $videoUrl',
//         name: 'VideoPreloader',
//       );
//     } catch (e) {
//       developer.log(
//         '⚠️ Failed to preload video: $videoUrl - $e',
//         name: 'VideoPreloader',
//       );
//     }
//   }

//   /// Get preloaded controller or null
//   static VideoPlayerController? getPreloadedController(String videoUrl) {
//     return _preloadedControllers[videoUrl];
//   }

//   /// Clear preloaded videos to free memory
//   static void clearPreloadedVideos() {
//     for (final controller in _preloadedControllers.values) {
//       controller.dispose();
//     }
//     _preloadedControllers.clear();

//     developer.log(
//       '🗑️ Cleared all preloaded videos',
//       name: 'VideoPreloader',
//     );
//   }

//   /// Preload multiple videos with limited concurrency
//   static Future<void> preloadMultipleVideos(
//     List<String> videoUrls, {
//     int maxConcurrent = 2,
//   }) async {
//     for (int i = 0; i < videoUrls.length; i += maxConcurrent) {
//       final batch = videoUrls.skip(i).take(maxConcurrent);
//       final futures = batch.map((url) => preloadVideo(url));
//       await Future.wait(futures);
//     }
//   }
// }
