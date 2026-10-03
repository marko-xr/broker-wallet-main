import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';

/// The local file this device already holds for a media identity, or null.
typedef LocalMediaLookup = Future<String?> Function(String cacheKey);

/// A signed link for a media identity that is still safely valid, or null.
typedef CachedLinkLookup = String? Function(String cacheKey);

/// Asks the record's own authorized path for a fresh link to one media item, or
/// null when none could be had.
typedef LinkRefresher = Future<String?> Function(String mediaObjectId);

/// Gets the bytes of a photo or video of a private record onto this phone so
/// the file itself can be shared.
///
/// The order is always: bytes this device already holds → a download through a
/// link that is still valid → one fresh link from the record's authorized path.
/// The receiving app gets the file, never a link: a signed link is transport for
/// the download only, so it is never written into a message or a file name, never
/// logged and never kept.
///
/// A download is streamed to disk rather than held in memory (a video may be
/// 100 MB), is cut off at a generous size ceiling, gives up after a stalled
/// connection, and stops at once when the share is cancelled.
class ShareMediaFetcher {
  ShareMediaFetcher({
    required LocalMediaLookup localPath,
    required CachedLinkLookup cachedLink,
    http.Client Function()? clientFactory,
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
    this.maxImageBytes = defaultMaxImageBytes,
    this.maxVideoBytes = defaultMaxVideoBytes,
  })  : _localPath = localPath,
        _cachedLink = cachedLink,
        _clientFactory = clientFactory ?? http.Client.new;

  /// The most a photo or a video may be: the app's own upload limits
  /// (10 MB and 100 MB) with room for files an older version accepted.
  static const int defaultMaxImageBytes = 50 * 1024 * 1024;
  static const int defaultMaxVideoBytes = 150 * 1024 * 1024;

  final LocalMediaLookup _localPath;
  final CachedLinkLookup _cachedLink;
  final http.Client Function() _clientFactory;
  final Duration connectTimeout;
  final Duration idleTimeout;
  final int maxImageBytes;
  final int maxVideoBytes;

  int _downloads = 0;

  /// The attachment that gets [item]'s file, to be named [baseName].
  ShareAttachment attachmentFor(
    ShareMediaItem item, {
    required String baseName,
    LinkRefresher? refreshLink,
  }) =>
      ShareAttachment(
        key: item.key,
        kind: item.isVideo
            ? ShareAttachmentKind.video
            : ShareAttachmentKind.image,
        baseName: baseName,
        fetch: (scratch, cancel) => _fetch(item, scratch, cancel, refreshLink),
      );

  Future<FetchedShareFile> _fetch(
    ShareMediaItem item,
    Directory scratch,
    ShareCancelToken cancel,
    LinkRefresher? refreshLink,
  ) async {
    final ref = item.ref;

    final held = await _held(item);
    if (held != null) return FetchedShareFile(held);

    final links = <String>[
      if (ref.cacheKey != null) _cachedLink(ref.cacheKey!) ?? '',
      ref.signedUrl ?? '',
    ].where((link) => link.trim().isNotEmpty).toSet();
    for (final link in links) {
      final file = await _download(link, item, scratch, cancel);
      if (file != null) return FetchedShareFile(file, isTemporary: true);
    }

    // Every link held was refused or expired (or none was held): ask for a new
    // one through the record's own authorized path.
    final id = ref.mediaObjectId.trim();
    if (refreshLink == null || id.isEmpty) {
      throw const ShareFailure(ShareFailureKind.unavailable);
    }
    String? fresh;
    try {
      fresh = await refreshLink(id);
    } catch (_) {
      throw const ShareFailure(ShareFailureKind.network);
    }
    if (cancel.isCancelled) throw const ShareCancelled();
    if (fresh == null || fresh.trim().isEmpty) {
      // The record's own load failed: nothing says the file is gone, and it
      // can pass, so it is reported as something a retry may fix.
      throw const ShareFailure(ShareFailureKind.network);
    }
    final file = await _download(fresh, item, scratch, cancel);
    if (file == null) {
      throw const ShareFailure(ShareFailureKind.unavailable);
    }
    return FetchedShareFile(file, isTemporary: true);
  }

  /// A file this device already holds for [item], with no network at all.
  Future<File?> _held(ShareMediaItem item) async {
    final ref = item.ref;
    final direct = ref.localFilePath?.trim() ?? '';
    if (direct.isNotEmpty) {
      final file = File(direct);
      if (await file.exists() && await file.length() > 0) return file;
    }
    final key = ref.cacheKey;
    if (key == null) return null;
    String? mapped;
    try {
      mapped = await _localPath(key);
    } catch (_) {
      mapped = null;
    }
    if (mapped == null || mapped.trim().isEmpty) return null;
    final file = File(mapped);
    if (await file.exists() && await file.length() > 0) return file;
    return null;
  }

  /// Downloads [link] into [scratch]. Returns null when the link was refused
  /// (expired or no longer valid), so the caller can try another; throws a
  /// [ShareFailure] for everything else.
  Future<File?> _download(
    String link,
    ShareMediaItem item,
    Directory scratch,
    ShareCancelToken cancel,
  ) async {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw const ShareFailure(ShareFailureKind.unavailable);
    }

    final limit = item.isVideo ? maxVideoBytes : maxImageBytes;
    final target = File(
      '${scratch.path}${Platform.pathSeparator}download-${_downloads++}.part',
    );
    final client = _clientFactory();
    final stopListening = cancel.onCancel(client.close);
    IOSink? sink;
    var completed = false;
    try {
      final response =
          await client.send(http.Request('GET', uri)).timeout(connectTimeout);
      final status = response.statusCode;
      if (status == 401 || status == 403) {
        await response.stream.drain<void>();
        return null;
      }
      if (status != 200) {
        await response.stream.drain<void>();
        if (status == 404 || status == 410) {
          throw const ShareFailure(ShareFailureKind.unavailable);
        }
        if (status >= 500 || status == 408 || status == 429) {
          throw const ShareFailure(ShareFailureKind.network);
        }
        throw const ShareFailure(ShareFailureKind.unavailable);
      }
      final declared = response.contentLength;
      if (declared != null && declared > limit) {
        await response.stream.drain<void>();
        throw const ShareFailure(ShareFailureKind.unavailable);
      }

      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(idleTimeout)) {
        if (cancel.isCancelled) throw const ShareCancelled();
        received += chunk.length;
        if (received > limit) {
          throw const ShareFailure(ShareFailureKind.unavailable);
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0) throw const ShareFailure(ShareFailureKind.unavailable);
      completed = true;
      return target;
    } on ShareCancelled {
      rethrow;
    } on ShareFailure {
      rethrow;
    } on TimeoutException {
      throw const ShareFailure(ShareFailureKind.network);
    } on SocketException {
      throw const ShareFailure(ShareFailureKind.network);
    } on HandshakeException {
      throw const ShareFailure(ShareFailureKind.network);
    } on http.ClientException {
      // Closing the client is how a cancelled share stops an open transfer.
      if (cancel.isCancelled) throw const ShareCancelled();
      throw const ShareFailure(ShareFailureKind.network);
    } on FileSystemException {
      throw const ShareFailure(ShareFailureKind.generic);
    } catch (_) {
      if (cancel.isCancelled) throw const ShareCancelled();
      throw const ShareFailure(ShareFailureKind.generic);
    } finally {
      stopListening();
      client.close();
      try {
        await sink?.close();
      } catch (_) {
        // Already failing; the partial file is removed below.
      }
      if (!completed) {
        try {
          if (await target.exists()) await target.delete();
        } catch (_) {
          // The share's own folder is removed as a whole.
        }
      }
    }
  }
}
