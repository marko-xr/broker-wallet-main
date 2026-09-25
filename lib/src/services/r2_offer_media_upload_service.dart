import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';

/// One piece of confirmed, displayable Offer media: a short-lived signed
/// read URL plus the stable identifiers needed to correlate it, never the
/// bucket path or any credential.
class R2OfferMediaItem {
  const R2OfferMediaItem({
    required this.mediaObjectId,
    required this.role,
    required this.ordinal,
    required this.url,
    this.mediaType,
  });

  final String mediaObjectId;
  final String role;
  final int ordinal;
  final String url;

  /// 'image' or 'video' as recorded server-side, or null from a Worker that
  /// predates video support (every item it lists is an image).
  final String? mediaType;
}

/// The result of successfully uploading and confirming one Offer media file.
class R2OfferMediaUploadResult {
  const R2OfferMediaUploadResult({
    required this.mediaObjectId,
    this.kind = OfferMediaKind.image,
  });

  final String mediaObjectId;
  final OfferMediaKind kind;
}

/// Client boundary for the Offer-media routes on the same production Worker
/// that already serves profile images (see `R2ProfileUploadService`). The
/// bucket stays private throughout: every read is a fresh, short-lived
/// signed URL from the Worker, never a permanently public R2 URL, and
/// nothing here ever persists a signed URL as the canonical media identity —
/// only `mediaObjectId` (a `media_objects.id`) is durable.
class R2OfferMediaUploadService {
  R2OfferMediaUploadService({
    http.Client? httpClient,
    SupabaseClient? supabaseClient,
  })  : _http = httpClient ?? http.Client(),
        _supabase = supabaseClient ?? Supabase.instance.client;

  static const int maxImageBytes = OfferMediaPolicy.maxImageBytes;
  static const int maxVideoBytes = OfferMediaPolicy.maxVideoBytes;
  static Set<String> get supportedContentTypes =>
      OfferMediaPolicy.contentTypes.keys.toSet();

  final http.Client _http;
  final SupabaseClient _supabase;

  static const Duration _metadataRequestTimeout = Duration(seconds: 15);

  /// An upload is abandoned only when it stops making progress for this
  /// long, never merely for being large: a 100 MB video on a slow link can
  /// legitimately take many minutes.
  @visibleForTesting
  static Duration uploadStallTimeout = const Duration(seconds: 45);

  /// Time allowed for R2 to answer once every byte has been sent.
  static const Duration _uploadResponseTimeout = Duration(seconds: 60);

  /// Authorize an upload for [file] against [offerId] using the current
  /// authenticated Supabase user, upload it directly to private R2, then
  /// confirm it and attach it to the offer with [role]/[ordinal]. Ownership
  /// of the offer is verified server-side by the Worker on both the
  /// authorize and confirm calls — this method never sends anything the
  /// server treats as a trusted owner id.
  ///
  /// The file is never read into memory whole: its type comes from its first
  /// bytes and its body is streamed from disk to R2 with an exact
  /// Content-Length, so a 100 MB video costs the same memory as a photo.
  /// [onProgress] reports bytes handed to the network so far.
  Future<R2OfferMediaUploadResult> uploadOfferMediaFile({
    required String offerId,
    required File file,
    String role = 'gallery',
    int ordinal = 0,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final check = await OfferMediaPolicy.check(file);
    if (!check.isAccepted) {
      throw OfferMediaRejectedException(check.rejection!);
    }
    final contentType = check.contentType!;
    final length = check.length!;

    final auth = _currentAuth();
    final authPayload =
        await _post('/offer-media/authorize', auth.accessToken, {
      'offerId': offerId,
      'contentType': contentType,
      'contentLength': length,
      'originalFileName': _fileName(file.path),
    });
    final presignedUrl = _requiredString(authPayload, 'presignedUrl');
    final mediaObjectId = _requiredString(authPayload, 'mediaObjectId');

    await _streamToPresignedUrl(
      presignedUrl: presignedUrl,
      file: file,
      contentType: contentType,
      length: length,
      onProgress: onProgress,
    );

    final confirmAuth = _currentAuth();
    await _post('/offer-media/confirm', confirmAuth.accessToken, {
      'offerId': offerId,
      'mediaObjectId': mediaObjectId,
      'role': role,
      'ordinal': ordinal,
    });

    return R2OfferMediaUploadResult(
      mediaObjectId: mediaObjectId,
      kind: check.kind!,
    );
  }

  /// PUTs [file] to R2 as a stream: the body is the file's own lazy read
  /// stream, so bytes leave the disk only as fast as the socket accepts them.
  /// A watchdog aborts the request when no byte has moved for
  /// [uploadStallTimeout] (a dead network, or the OS suspending the app), or
  /// when R2 has not answered [_uploadResponseTimeout] after the last byte —
  /// never merely because a large video takes a long time.
  Future<void> _streamToPresignedUrl({
    required String presignedUrl,
    required File file,
    required String contentType,
    required int length,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final abort = Completer<void>();
    var sent = 0;
    var lastProgress = DateTime.now();
    DateTime? bodyDoneAt;

    final body = file.openRead().transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              sent += chunk.length;
              lastProgress = DateTime.now();
              onProgress?.call(sent, length);
              sink.add(chunk);
            },
            handleDone: (sink) {
              bodyDoneAt = DateTime.now();
              sink.close();
            },
          ),
        );
    final request = _FileUploadRequest(
      Uri.parse(presignedUrl),
      body,
      abortTrigger: abort.future,
    )
      ..contentLength = length
      ..headers['Content-Type'] = contentType;

    final watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (abort.isCompleted) return;
      final now = DateTime.now();
      final done = bodyDoneAt;
      final stalled = done == null
          ? now.difference(lastProgress) > uploadStallTimeout
          : now.difference(done) > _uploadResponseTimeout;
      if (stalled) abort.complete();
    });

    try {
      final response = await _http.send(request);
      await response.stream.drain<void>().timeout(_uploadResponseTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const R2UploadException('Offer media upload was rejected.');
      }
    } on R2UploadException {
      rethrow;
    } catch (_) {
      // An abort, a dropped connection or a timeout. Nothing was confirmed,
      // so the Worker's abandoned-upload cleanup removes any partial object.
      throw const OfferMediaRejectedException(OfferMediaRejection.interrupted);
    } finally {
      watchdog.cancel();
    }
  }

  /// The offer's confirmed media, each with a fresh short-lived signed read
  /// URL. Ownership of [offerId] is verified server-side by the Worker.
  Future<List<R2OfferMediaItem>> getOfferMedia(String offerId) async {
    final auth = _currentAuth();
    final response = await _request(() => _http.get(
          _endpoint('/offer-media')
              .replace(queryParameters: {'offerId': offerId}),
          headers: {'Authorization': 'Bearer ${auth.accessToken}'},
        ).timeout(_metadataRequestTimeout));
    _ensureSuccess(response, '/offer-media');

    final payload = _decodeObject(response.body);
    final rawMedia = payload['media'];
    if (rawMedia is! List) return const [];

    final items = <R2OfferMediaItem>[];
    for (final entry in rawMedia) {
      if (entry is! Map<String, dynamic>) continue;
      final mediaObjectId = _optionalString(entry, 'mediaObjectId');
      final url = _optionalString(entry, 'url');
      if (mediaObjectId == null || url == null) continue;
      items.add(R2OfferMediaItem(
        mediaObjectId: mediaObjectId,
        role: _optionalString(entry, 'role') ?? 'gallery',
        ordinal: _optionalInt(entry, 'ordinal') ?? 0,
        url: url,
        mediaType: _optionalString(entry, 'mediaType'),
      ));
    }
    return items;
  }

  _CurrentAuth _currentAuth() {
    _assertConfigured();
    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;
    final token = session?.accessToken;
    if (user == null || token == null || token.isEmpty) {
      throw const R2UploadException('No active Supabase session.');
    }
    return _CurrentAuth(user, token);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    final response = await _request(() => _http
        .post(
          _endpoint(path),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_metadataRequestTimeout));
    final rejection = _rejectionFrom(response);
    if (rejection != null) throw OfferMediaRejectedException(rejection);
    _ensureSuccess(response, path);
    return _decodeObject(response.body);
  }

  /// A refusal the user can act on, from the Worker's stable `code` field.
  /// Only known codes are read; the Worker's free-text message never is.
  OfferMediaRejection? _rejectionFrom(http.Response response) {
    const actionable = {400, 409, 422};
    if (!actionable.contains(response.statusCode)) return null;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return OfferMediaRejection.fromWorkerCode(decoded['code']);
      }
    } catch (_) {}
    return null;
  }

  Future<http.Response> _request(
      Future<http.Response> Function() request) async {
    try {
      return await request();
    } on TimeoutException {
      throw const R2UploadException('The offer media request timed out.');
    } on http.ClientException {
      throw const R2UploadException('Could not reach the offer media service.');
    } catch (_) {
      throw const R2UploadException('Could not reach the offer media service.');
    }
  }

  void _ensureSuccess(http.Response response, String path) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw R2OfferMediaHttpException(response.statusCode);
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const R2UploadException(
        'Offer media service returned an invalid response.');
  }

  Uri _endpoint(String path) => Uri.parse('${R2Config.workerUrl}$path');

  void _assertConfigured() {
    if (!R2Config.isConfigured) throw const R2WorkerNotConfiguredException();
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/') ? normalized.split('/').last : normalized;
  }

}

class _CurrentAuth {
  const _CurrentAuth(this.user, this.accessToken);

  final User user;
  final String accessToken;
}

String _requiredString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is String && value.isNotEmpty) return value;
  throw const R2UploadException(
      'Offer media service returned incomplete data.');
}

String? _optionalString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? _optionalInt(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

class R2WorkerNotConfiguredException implements Exception {
  const R2WorkerNotConfiguredException();
}

class R2UploadException implements Exception {
  const R2UploadException(this.message);

  final String message;

  @override
  String toString() => 'R2UploadException: $message';
}

/// A non-success answer from the media Worker, carrying its status code.
///
/// The status is what lets the caller tell an authoritative "this account has
/// no such Offer" from a session problem or an upstream failure — a
/// distinction that decides whether locally held private bytes may be deleted.
/// It extends [R2UploadException] so every existing handler still catches it.
///
/// The Worker's own message is deliberately dropped: it is provider text and
/// can name internal detail. Only the status is carried.
class R2OfferMediaHttpException extends R2UploadException {
  R2OfferMediaHttpException(this.statusCode)
      : super('Offer media service request failed ($statusCode).');

  final int statusCode;

  /// The Worker reached this only after its ownership query succeeded and
  /// returned no row (an upstream failure answers 502), so it is trustworthy.
  bool get isAccessDenied => statusCode == 404 || statusCode == 403;

  bool get isUnauthenticated => statusCode == 401;
}

/// A file refused as Offer media for a reason the user can act on, from the
/// local pre-check or from the Media Worker. Carries only the reason, never a
/// file path, byte content or provider text.
class OfferMediaRejectedException extends R2UploadException {
  const OfferMediaRejectedException(this.rejection)
      : super('Offer media was refused.');

  final OfferMediaRejection rejection;
}

/// A PUT whose body is streamed from [_body] (a file's lazy read stream)
/// rather than buffered, and which can be aborted by the upload watchdog.
class _FileUploadRequest extends http.BaseRequest with http.Abortable {
  _FileUploadRequest(Uri url, this._body, {this.abortTrigger})
      : super('PUT', url);

  final Stream<List<int>> _body;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
