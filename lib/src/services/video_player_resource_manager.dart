import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:video_player/video_player.dart';
import 'dart:developer' as developer;

import 'package:broker_wallet/src/services/offer_media_diagnostics.dart';

/// One platform player the manager holds, and who is using it.
class _PlayerEntry {
  _PlayerEntry(this.name, this.source, this.controller);

  /// The stable name of the video (a private video's cache key, or its URL).
  final String name;

  /// What the player was opened with: a URL or a local path.
  final String source;
  final VideoPlayerController controller;

  /// Widgets currently showing this player. It is never disposed while any
  /// holds it.
  int holders = 0;
  DateTime lastUsed = DateTime.now();
}

/// Shares video players between the widgets that show them and limits how
/// many exist at once.
///
/// **Ownership.** A widget that receives a controller from [getController]
/// holds it until it calls [release] with that controller — normally in its
/// own `dispose`. The manager disposes a controller only when no widget holds
/// it: a held controller is never evicted to make room for another video and
/// never replaced by a newer link of the same video. Disposing a controller
/// that a mounted player still used is what raised "A VideoPlayerController
/// was used after being disposed" on the test phone (2026-09-27): full screen
/// played a third video, and the manager disposed the paused player still
/// shown by Offer Details underneath.
///
/// Released players stay briefly as idle players (at most [_maxIdlePlayers])
/// so reopening the same video is instant; opening another video disposes
/// idle players first once [_maxConcurrentPlayers] exist. A disposed
/// controller is removed at once and never handed out again.
class VideoPlayerResourceManager {
  static const String _logName = 'VideoPlayerManager';
  static const int _maxConcurrentPlayers = 2; // Limit to 2 concurrent players
  static const int _maxIdlePlayers = 1;

  static final VideoPlayerResourceManager _instance =
      VideoPlayerResourceManager._internal();
  factory VideoPlayerResourceManager() => _instance;
  VideoPlayerResourceManager._internal();

  final List<_PlayerEntry> _entries = [];

  /// Players being opened, by name and source: a second request for the same
  /// one joins the first instead of opening another platform player.
  final Map<String, Future<_PlayerEntry?>> _opening = {};

  /// Why the last attempt for each keyed (private) video failed, as a fixed
  /// category — the raw error can contain the signed URL.
  final Map<String, String> _lastFailureCategories = {};

  /// The category of the last failure to open the video named [key].
  String? lastFailureCategory(String key) => _lastFailureCategories[key];

  /// Records why the video named [key] could not be opened before a player
  /// was even created (e.g. its format was refused).
  void noteFailure(String key, String category) =>
      _lastFailureCategories[key] = category;

  /// Players that exist now, held or idle.
  @visibleForTesting
  int get livePlayerCount => _entries.length;

  /// How many widgets hold [controller]; 0 when it is idle or gone.
  @visibleForTesting
  int holdersOf(VideoPlayerController controller) =>
      _entryFor(controller)?.holders ?? 0;

  _PlayerEntry? _entryFor(VideoPlayerController controller) {
    for (final entry in _entries) {
      if (identical(entry.controller, controller)) return entry;
    }
    return null;
  }

  /// A player for [videoUrl], held by the caller until it calls [release].
  ///
  /// [key] names the video when [videoUrl] is not a stable name for it — a
  /// private video's signed URL changes every time it is signed. The same
  /// video under the same source is shared; under a newer source it gets a
  /// new player, and the old one is disposed once nothing holds it.
  /// [maxAttempts] bounds how often the same source is tried.
  Future<VideoPlayerController?> getController(
    String videoUrl, {
    String? key,
    int maxAttempts = 3,
  }) async {
    final name = key ?? videoUrl;
    if (key != null) _lastFailureCategories.remove(key);

    for (final entry in _entries) {
      if (entry.name == name &&
          entry.source == videoUrl &&
          entry.controller.value.isInitialized) {
        entry.holders += 1;
        entry.lastUsed = DateTime.now();
        developer.log('♻️ Sharing player for: ${_describe(videoUrl)}',
            name: _logName);
        return entry.controller;
      }
    }

    final slot = '$name|$videoUrl';
    final opening =
        _opening[slot] ??= _openOnce(slot, videoUrl, name, key, maxAttempts);
    final entry = await opening;
    if (entry == null || !_entries.contains(entry)) return null;
    entry.holders += 1;
    entry.lastUsed = DateTime.now();
    return entry.controller;
  }

  Future<_PlayerEntry?> _openOnce(
    String slot,
    String videoUrl,
    String name,
    String? key,
    int maxAttempts,
  ) async {
    try {
      return await _open(videoUrl, name, key, maxAttempts);
    } finally {
      _opening.remove(slot);
    }
  }

  /// Gives back a controller from [getController]. When no widget holds it
  /// any more it is paused and becomes idle; idle players beyond
  /// [_maxIdlePlayers] are disposed, least recently used first. Releasing a
  /// controller the manager no longer holds does nothing.
  Future<void> release(VideoPlayerController controller) async {
    final entry = _entryFor(controller);
    if (entry == null) return;
    if (entry.holders > 0) entry.holders -= 1;
    entry.lastUsed = DateTime.now();
    if (entry.holders > 0) return;
    await _pause(entry);
    await _disposeIdle(keep: _maxIdlePlayers);
  }

  Future<_PlayerEntry?> _open(
    String videoUrl,
    String name,
    String? key,
    int maxAttempts,
  ) async {
    // An idle player of an older link of this video will not be used again.
    for (final stale in _entries
        .where((entry) =>
            entry.name == name &&
            entry.source != videoUrl &&
            entry.holders == 0)
        .toList()) {
      await _dispose(stale);
    }

    try {
      // Pre-check video format support and warn about HEVC
      if (!isVideoFormatSupported(videoUrl)) {
        developer.log(
            '⚠️ Unsupported video format detected: ${_describe(videoUrl)} (${getVideoCodecInfo(videoUrl)})',
            name: _logName);
      }

      if (isLikelyHEVCVideo(videoUrl)) {
        developer.log(
            '🔍 HEVC video detected: ${_describe(videoUrl)} - will attempt playback with fallback options',
            name: _logName);
      }

      // Make room from idle players, least recently used first. A held
      // player is never taken: past the limit, a held one simply stays.
      while (_entries.length >= _maxConcurrentPlayers) {
        final idle = _entries.where((entry) => entry.holders == 0).toList()
          ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
        if (idle.isEmpty) break;
        await _dispose(idle.first);
      }

      // Attempt controller creation with retry logic and HEVC handling
      VideoPlayerController? controller;
      String? lastError;
      bool isHEVCError = false;

      final attempts = maxAttempts < 1 ? 1 : maxAttempts;
      for (int attempt = 1; attempt <= attempts; attempt++) {
        try {
          developer.log(
              '🎬 Creating video controller (attempt $attempt) for: ${_describe(videoUrl)}',
              name: _logName);

          if (videoUrl.startsWith('http')) {
            // Enhanced network video configuration for better compatibility
            controller = VideoPlayerController.networkUrl(
              Uri.parse(videoUrl),
              httpHeaders: {
                'Accept': 'video/mp4,video/webm,video/x-msvideo,video/*',
                'User-Agent': 'BrokerWallet-Android/1.0',
                'Connection': 'keep-alive',
                'Range':
                    'bytes=0-', // Support partial content for better streaming
                'Cache-Control': attempt > 1
                    ? 'no-cache'
                    : 'max-age=3600', // Avoid cache on retry
              },
            );
          } else {
            controller = VideoPlayerController.file(File(videoUrl));
          }

          // Initialize with enhanced error handling and progressive timeout
          final timeoutDuration =
              Duration(seconds: 20 + (attempt * 10)); // 30s, 40s, 50s
          final initializationFuture = controller.initialize();
          final timeoutFuture = Future.delayed(timeoutDuration, () {
            throw TimeoutException(
                'Video controller initialization timed out', timeoutDuration);
          });

          await Future.any([initializationFuture, timeoutFuture]);

          if (controller.value.isInitialized &&
              controller.value.duration > Duration.zero) {
            final entry = _PlayerEntry(name, videoUrl, controller);
            _entries.add(entry);
            developer.log(
                '✅ Video controller initialized successfully (attempt $attempt) for: ${_describe(videoUrl)} (${controller.value.size.width}x${controller.value.size.height})',
                name: _logName);
            return entry;
          } else {
            throw Exception(
                'Controller initialized but has invalid video data');
          }
        } catch (e) {
          lastError = e.toString();
          developer.log(
              '❌ Video initialization attempt $attempt failed (${OfferMediaDiagnostics.playerErrorCategory(lastError)}) for: ${_describe(videoUrl)}',
              name: _logName);
          if (key != null) {
            // The player's own report, reduced to fixed categories: its raw
            // text can contain the signed link.
            final described = controller?.value.errorDescription;
            final category =
                OfferMediaDiagnostics.playerErrorCategory(lastError);
            _lastFailureCategories[key] = category;
            OfferMediaDiagnostics.log('player-init-failed', fields: {
              'source': videoUrl.startsWith('http') ? 'network' : 'local',
              'attempt': attempt,
              'error': e.runtimeType,
              'code': e is PlatformException ? e.code : null,
              'cause': category,
              'described': described == null
                  ? null
                  : OfferMediaDiagnostics.playerErrorCategory(described),
            });
          }

          // Clean up failed controller: it never reached any widget.
          if (controller != null) {
            try {
              await controller.dispose();
            } catch (disposeError) {
              developer.log(
                  '❌ Error disposing failed controller: ${disposeError.runtimeType}',
                  name: _logName);
            }
            controller = null;
          }

          // Check for specific MediaCodec HEVC errors
          if (lastError.contains('MediaCodecVideoRenderer') ||
              lastError.contains('ExoPlaybackException') ||
              lastError.contains('video/hevc') ||
              lastError.contains('hvc1')) {
            isHEVCError = true;
            developer.log(
                '🔧 MediaCodec HEVC compatibility issue detected. Device may not support H.265/HEVC codec.',
                name: _logName);

            // For HEVC errors, break early since retries won't help with codec issues
            developer.log(
                '⚠️ HEVC codec not supported on this device. Video cannot be played natively.',
                name: _logName);
            break;
          } else if (attempt < attempts) {
            // For other errors, wait progressively longer before retry
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }

      if (isHEVCError) {
        developer.log(
            '❌ HEVC video cannot be played on this device. MediaCodec does not support H.265/HEVC format.',
            name: _logName);
        return null; // Return null with specific HEVC error context
      }

      developer.log(
          '❌ Failed to create video controller after $attempts attempt(s). Last error: ${OfferMediaDiagnostics.playerErrorCategory(lastError ?? '')}',
          name: _logName);
      return null;
    } catch (e) {
      developer.log('❌ Error creating video controller: ${e.runtimeType}',
          name: _logName);
      return null;
    }
  }

  /// Pause every player of the video named [name] that is playing.
  Future<void> pauseController(String name) async {
    for (final entry
        in _entries.where((entry) => entry.name == name).toList()) {
      await _pause(entry);
    }
  }

  /// Pause all players except those of the video named [activeName].
  Future<void> pauseAllExcept(String? activeName) async {
    for (final entry in _entries.toList()) {
      if (activeName != null && entry.name == activeName) continue;
      await _pause(entry);
    }
  }

  /// Pause all players.
  Future<void> pauseAll() => pauseAllExcept(null);

  Future<void> _pause(_PlayerEntry entry) async {
    // Only players still held by the manager are ever touched: a disposed
    // one has been removed from [_entries] before it was disposed.
    if (!_entries.contains(entry)) return;
    final controller = entry.controller;
    if (!controller.value.isInitialized || !controller.value.isPlaying) return;
    try {
      await controller.pause();
      developer.log('⏸️ Paused player for: ${_describe(entry.name)}',
          name: _logName);
    } catch (e) {
      developer.log(
          '⚠️ Failed to pause player for ${_describe(entry.name)}: ${e.runtimeType}',
          name: _logName);
    }
  }

  /// Disposes the idle players of the video named [name]. Held players are
  /// left to their holders.
  Future<void> releaseController(String name) async {
    for (final entry in _entries
        .where((entry) => entry.name == name && entry.holders == 0)
        .toList()) {
      await _dispose(entry);
    }
  }

  /// Disposes idle players, least recently used first, until at most [keep]
  /// idle players remain. Held players are never disposed.
  Future<void> _disposeIdle({required int keep}) async {
    final idle = _entries.where((entry) => entry.holders == 0).toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    var excess = idle.length - keep;
    for (final entry in idle) {
      if (excess <= 0) break;
      await _dispose(entry);
      excess -= 1;
    }
  }

  /// Removes [entry] first, so it can never be handed out again, then
  /// disposes its controller.
  Future<void> _dispose(_PlayerEntry entry) async {
    if (!_entries.remove(entry)) return;
    try {
      await entry.controller.dispose();
      developer.log('✅ Player disposed for: ${_describe(entry.name)}',
          name: _logName);
    } catch (e) {
      developer.log('⚠️ Error disposing player: ${e.runtimeType}',
          name: _logName);
    }
  }

  /// Disposes every player (app shutdown, tests). Widgets must not hold any
  /// by then.
  Future<void> disposeAll() async {
    developer.log('🗑️ Disposing all video controllers', name: _logName);
    for (final entry in _entries.toList()) {
      await _dispose(entry);
    }
    developer.log('✅ All video controllers disposed', name: _logName);
  }

  /// Get current resource usage stats
  Map<String, dynamic> getResourceStats() {
    return {
      'activeControllers': _entries.length,
      'heldControllers': _entries.where((entry) => entry.holders > 0).length,
      'maxConcurrentPlayers': _maxConcurrentPlayers,
      'controllerUrls': [for (final entry in _entries) _describe(entry.name)],
    };
  }

  /// Check if a video format is supported to prevent codec issues
  static bool isVideoFormatSupported(String url) {
    final extension = _extensionOf(url);

    // Supported formats for most Android devices
    const supportedFormats = [
      'mp4', // H.264/AVC, H.265/HEVC (but HEVC may cause issues)
      'm4v', // H.264/AVC
      'webm', // VP8/VP9
      '3gp', // H.263, H.264
      'mkv', // Various codecs
      'avi', // Various codecs
      'mov', // QuickTime formats
    ];

    return supportedFormats.contains(extension);
  }

  /// Check if video likely uses HEVC codec which can cause MediaCodec issues
  static bool isLikelyHEVCVideo(String url) {
    // HEVC videos often have these characteristics in their path/name. Only
    // the path is read: a signed URL's query is a credential, not a name.
    final lowerUrl = _redact(url).toLowerCase();
    return lowerUrl.contains('hevc') ||
        lowerUrl.contains('h265') ||
        lowerUrl.contains('x265') ||
        lowerUrl.contains('hvc1');
  }

  /// Check if an error is specifically related to HEVC codec incompatibility
  static bool isHEVCCompatibilityError(String error) {
    final lowerError = error.toLowerCase();
    return lowerError.contains('mediacodecvideorenderer') &&
        (lowerError.contains('video/hevc') ||
            lowerError.contains('hvc1') ||
            lowerError.contains('h.265') ||
            lowerError.contains('hevc'));
  }

  /// Get video codec information for debugging
  static String getVideoCodecInfo(String url) {
    final extension = _extensionOf(url);

    String baseCodec;
    switch (extension) {
      case 'mp4':
      case 'm4v':
        baseCodec = 'H.264/AVC or H.265/HEVC';
        break;
      case 'webm':
        baseCodec = 'VP8/VP9';
        break;
      case '3gp':
        baseCodec = 'H.263/H.264';
        break;
      case 'mkv':
        baseCodec = 'Various (H.264/H.265/VP9)';
        break;
      case 'avi':
        baseCodec = 'Various (H.264/DivX/Xvid)';
        break;
      case 'mov':
        baseCodec = 'QuickTime (H.264/HEVC)';
        break;
      default:
        baseCodec = 'Unknown codec';
    }

    // Add HEVC warning if detected
    if (isLikelyHEVCVideo(url)) {
      baseCodec += ' ⚠️ HEVC detected - may cause compatibility issues';
    }

    return baseCodec;
  }
}

class TimeoutException implements Exception {
  final String message;
  final Duration timeout;

  TimeoutException(this.message, this.timeout);

  @override
  String toString() => 'TimeoutException: $message (${timeout.inSeconds}s)';
}

/// A media URL with its signature and every other query parameter removed, so
/// a private signed R2 URL is never written to the log. A signed GET URL is a
/// short-lived credential: anyone holding it can read that private object.
String _redact(String url) {
  final cut = url.indexOf('?');
  final withoutQuery = cut < 0 ? url : url.substring(0, cut);
  return cut < 0 ? withoutQuery : '$withoutQuery?<signature-hidden>';
}

/// How a video source is named in the log: its kind and the last six
/// characters of its name — for Offer media, the end of the stable media id.
///
/// Never the URL, its query, the object key, a local path or the account id:
/// a redacted signed link still spelled out `profiles/<account>/offers/<offer>`
/// and a cache key carries the account id.
String _describe(String source) {
  final kind = source.startsWith('http')
      ? 'network'
      : source.startsWith('offer-media:')
          ? 'media'
          : 'file';
  var name = source.split('#').first.split('?').first;
  name = name.split(RegExp(r'[/\\:]')).last;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll(RegExp(r'_(pending|pending_poster|poster)$'), '');
  final tail = name.length > 6 ? name.substring(name.length - 6) : name;
  return '$kind …$tail';
}

/// The file extension from a URL's path only — a signed URL's long query
/// string must never be mistaken for it.
///
/// Cuts the query and fragment from the URL itself. It must not reuse
/// [_redact]: that re-appends a `?<signature-hidden>` marker for the log, and
/// reading the extension from it turned every signed `….mp4?…` link into
/// `mp4?<signature-hidden>` — refused as an unsupported format before any
/// player was created (Samsung, 2026-09-26).
String _extensionOf(String url) {
  final path = url.split('#').first.split('?').first;
  final name = path.split('/').last;
  return name.contains('.') ? name.split('.').last.toLowerCase() : '';
}
