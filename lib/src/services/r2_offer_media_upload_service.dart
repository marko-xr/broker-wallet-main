import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:broker_wallet/src/services/offer_media_diagnostics.dart';
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
    this.durationMs,
    this.expiresAt,
  });

  final String mediaObjectId;
  final String role;
  final int ordinal;
  final String url;

  /// 'image' or 'video' as recorded server-side, or null from a Worker that
  /// predates video support (every item it lists is an image).
  final String? mediaType;

  /// A video's duration as the Worker measured it.
  final int? durationMs;

  /// When [url] stops working. Transport only: kept in memory, never stored.
  final DateTime? expiresAt;
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

/// What `/offer-media/authorize` answered for one logical upload.
class OfferMediaAuthorization {
  const OfferMediaAuthorization.pending({
    required this.mediaObjectId,
    required String this.presignedUrl,
  }) : isAlreadyReady = false;

  const OfferMediaAuthorization.ready({required this.mediaObjectId})
      : presignedUrl = null,
        isAlreadyReady = true;

  final String mediaObjectId;

  /// The short-lived signed PUT for the bytes. Transport only: never stored.
  final String? presignedUrl;

  /// The item was already attached, e.g. an earlier attempt succeeded but its
  /// response was lost. There is nothing to upload again.
  final bool isAlreadyReady;
}

/// What `/offer-media/confirm` answered.
class OfferMediaConfirmation {
  const OfferMediaConfirmation({this.ordinal, this.alreadyConfirmed = false});

  /// The item's position on the Offer, as the server chose it.
  final int? ordinal;
  final bool alreadyConfirmed;
}

/// What `/offer-media/remove` answered.
class OfferMediaRemoval {
  const OfferMediaRemoval({
    this.alreadyRemoved = false,
    this.cleanupPending = false,
  });

  final bool alreadyRemoved;

  /// Removed from the Offer, but deleting its bytes did not finish yet; the
  /// server's scheduled cleanup completes it.
  final bool cleanupPending;
}

/// The Media Worker operations one logical Offer upload consists of.
///
/// Every call is idempotent on the app-generated [mediaObjectId], which is
/// what lets the upload queue retry any step, after any failure or a restart,
/// without ever creating a second object.
abstract interface class OfferMediaTransport {
  Future<OfferMediaAuthorization> authorizeUpload({
    required String offerId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  });

  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
    required int length,
    void Function(int sentBytes, int totalBytes)? onProgress,
    Future<void>? cancel,
  });

  Future<OfferMediaConfirmation> confirmUpload({
    required String offerId,
    required String mediaObjectId,
  });

  Future<OfferMediaRemoval> removeMedia({
    required String offerId,
    required String mediaObjectId,
  });
}

/// Client boundary for the Offer-media routes on the same production Worker
/// that already serves profile images (see `R2ProfileUploadService`). The
/// bucket stays private throughout: every read is a fresh, short-lived
/// signed URL from the Worker, never a permanently public R2 URL, and
/// nothing here ever persists a signed URL as the canonical media identity —
/// only `mediaObjectId` (a `media_objects.id`) is durable.
class R2OfferMediaUploadService implements OfferMediaTransport {
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

  /// The Worker's signed-URL lifetime when a response does not state it.
  static const Duration _defaultReadUrlLifetime = Duration(seconds: 900);

  /// An upload is abandoned only when it stops making progress for this
  /// long, never merely for being large: a 100 MB video on a slow link can
  /// legitimately take many minutes.
  @visibleForTesting
  static Duration uploadStallTimeout = const Duration(seconds: 45);

  /// Time allowed for R2 to answer once every byte has been sent.
  static const Duration _uploadResponseTimeout = Duration(seconds: 60);

  /// Worker statuses whose stable `code` may name a user-actionable refusal.
  static const Set<int> _refusalStatuses = {400, 409, 410, 422};

  /// Uploads one file end to end: authorize, stream the bytes to private R2,
  /// confirm. [mediaObjectId] is this item's identity; when omitted, a new one
  /// is generated. Retrying with the same id resumes the same logical upload
  /// and never creates a second object. Ownership of [offerId] is verified
  /// server-side on every call — nothing here is a trusted owner id.
  ///
  /// The persistent upload queue drives these steps itself; this is the
  /// one-shot form of the same sequence.
  Future<R2OfferMediaUploadResult> uploadOfferMediaFile({
    required String offerId,
    required File file,
    String? mediaObjectId,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final check = await OfferMediaPolicy.check(file);
    if (!check.isAccepted) {
      throw OfferMediaRejectedException(check.rejection!);
    }
    final id = mediaObjectId ?? const Uuid().v4();

    final authorization = await authorizeUpload(
      offerId: offerId,
      mediaObjectId: id,
      contentType: check.contentType!,
      contentLength: check.length!,
      originalFileName: _fileName(file.path),
    );
    if (!authorization.isAlreadyReady) {
      await uploadBytes(
        presignedUrl: authorization.presignedUrl!,
        file: file,
        contentType: check.contentType!,
        length: check.length!,
        onProgress: onProgress,
      );
      await confirmUpload(offerId: offerId, mediaObjectId: id);
    }
    return R2OfferMediaUploadResult(mediaObjectId: id, kind: check.kind!);
  }

  @override
  Future<OfferMediaAuthorization> authorizeUpload({
    required String offerId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    final auth = _currentAuth();
    final payload = await _post('/offer-media/authorize', auth.accessToken, {
      'offerId': offerId,
      'mediaObjectId': mediaObjectId,
      'contentType': contentType,
      'contentLength': contentLength,
      if (originalFileName != null) 'originalFileName': originalFileName,
    });
    final returnedId = _requiredString(payload, 'mediaObjectId');
    if (returnedId.toLowerCase() != mediaObjectId.toLowerCase()) {
      // A Worker that predates app-generated ids answered with an id of its
      // own. Continuing would change this item's identity mid-upload, so the
      // step fails instead and is retried once the Worker is current.
      throw const R2UploadException(
          'The offer media service does not support resumable uploads yet.');
    }
    if (payload['status'] == 'ready') {
      return OfferMediaAuthorization.ready(mediaObjectId: mediaObjectId);
    }
    return OfferMediaAuthorization.pending(
      mediaObjectId: mediaObjectId,
      presignedUrl: _requiredString(payload, 'presignedUrl'),
    );
  }

  /// PUTs [file] to R2 as a stream: the body is the file's own lazy read
  /// stream, so bytes leave the disk only as fast as the socket accepts them.
  /// A watchdog aborts the request when no byte has moved for
  /// [uploadStallTimeout] (a dead network, or the OS suspending the app), or
  /// when R2 has not answered [_uploadResponseTimeout] after the last byte —
  /// never merely because a large video takes a long time. Completing
  /// [cancel] aborts it at once.
  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
    required int length,
    void Function(int sentBytes, int totalBytes)? onProgress,
    Future<void>? cancel,
  }) async {
    final abort = Completer<void>();
    var sent = 0;
    var lastProgress = DateTime.now();
    DateTime? bodyDoneAt;
    String? abortReason;

    cancel?.then((_) {
      if (!abort.isCompleted) {
        abortReason = 'cancelled';
        abort.complete();
      }
    });

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
      if (stalled) {
        abortReason = done == null ? 'stalled' : 'no-response';
        abort.complete();
      }
    });

    try {
      final response = await _http.send(request);
      await response.stream.drain<void>().timeout(_uploadResponseTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // R2's answer (an expired or refused signature is 403). The next
        // attempt authorizes again and gets a fresh signed URL.
        throw R2UploadException('Offer media upload was rejected.',
            cause: 'put-http:${response.statusCode}');
      }
    } on R2UploadException {
      rethrow;
    } catch (error) {
      // An abort, a dropped connection or a timeout. Nothing was confirmed,
      // so the same id is simply uploaded again.
      final category = error is http.ClientException
          ? _clientCause(error)
          : OfferMediaDiagnostics.categorize(error);
      throw OfferMediaRejectedException(
        OfferMediaRejection.interrupted,
        cause: '${abortReason ?? category} sent=$sent/$length',
      );
    } finally {
      watchdog.cancel();
    }
  }

  /// A loggable category for a failed request; the exception's message may
  /// name the host or carry the request URL, so it is only pattern-matched.
  static String _clientCause(http.ClientException error) {
    final message = error.message.toLowerCase();
    if (message.contains('failed host lookup')) return 'dns';
    if (message.contains('connection reset')) return 'reset';
    if (message.contains('connection refused')) return 'refused';
    if (message.contains('network is unreachable')) return 'unreachable';
    if (message.contains('connection closed')) return 'closed';
    if (message.contains('timed out')) return 'timeout';
    if (message.contains('abort')) return 'aborted';
    if (message.contains('handshake') || message.contains('certificate')) {
      return 'tls';
    }
    return 'client';
  }

  @override
  Future<OfferMediaConfirmation> confirmUpload({
    required String offerId,
    required String mediaObjectId,
  }) async {
    final auth = _currentAuth();
    final payload = await _post('/offer-media/confirm', auth.accessToken, {
      'offerId': offerId,
      'mediaObjectId': mediaObjectId,
    });
    return OfferMediaConfirmation(
      ordinal: _optionalInt(payload, 'ordinal'),
      alreadyConfirmed: payload['alreadyConfirmed'] == true,
    );
  }

  @override
  Future<OfferMediaRemoval> removeMedia({
    required String offerId,
    required String mediaObjectId,
  }) async {
    final auth = _currentAuth();
    final payload = await _post('/offer-media/remove', auth.accessToken, {
      'offerId': offerId,
      'mediaObjectId': mediaObjectId,
    });
    return OfferMediaRemoval(
      alreadyRemoved: payload['alreadyRemoved'] == true,
      cleanupPending: payload['cleanupPending'] == true,
    );
  }

  /// The offer's confirmed media, each with a fresh short-lived signed read
  /// URL. Ownership of [offerId] is verified server-side by the Worker.
  Future<List<R2OfferMediaItem>> getOfferMedia(String offerId) async {
    final auth = _currentAuth();
    final requestedAt = DateTime.now();
    final response = await _request(() => _http.get(
          _endpoint('/offer-media')
              .replace(queryParameters: {'offerId': offerId}),
          headers: {'Authorization': 'Bearer ${auth.accessToken}'},
        ).timeout(_metadataRequestTimeout));
    _ensureSuccess(response);

    final payload = _decodeObject(response.body);
    final rawMedia = payload['media'];
    if (rawMedia is! List) return const [];
    final lifetimeSeconds = _optionalInt(payload, 'expiresInSeconds');
    // Measured from when the request was sent, so the estimate can only err
    // on the early side.
    final expiresAt = requestedAt.add(lifetimeSeconds == null
        ? _defaultReadUrlLifetime
        : Duration(seconds: lifetimeSeconds));

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
        durationMs: _optionalInt(entry, 'durationMs'),
        expiresAt: expiresAt,
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
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decodeObject(response.body);
    }
    final code = _workerCode(response);
    final rejection = _refusalStatuses.contains(response.statusCode)
        ? OfferMediaRejection.fromWorkerCode(code)
        : null;
    if (rejection != null) {
      throw OfferMediaRejectedException(
        rejection,
        cause: 'http:${response.statusCode}',
      );
    }
    throw R2OfferMediaHttpException(response.statusCode, code: code);
  }

  /// The Worker's stable `code` field. Its free-text message is never read.
  String? _workerCode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final code = decoded['code'];
        return code is String && code.isNotEmpty ? code : null;
      }
    } catch (_) {}
    return null;
  }

  Future<http.Response> _request(
      Future<http.Response> Function() request) async {
    try {
      return await request();
    } on TimeoutException {
      throw const R2UploadException('The offer media request timed out.',
          cause: 'timeout');
    } on http.ClientException catch (error) {
      throw R2UploadException('Could not reach the offer media service.',
          cause: _clientCause(error));
    } catch (error) {
      throw R2UploadException('Could not reach the offer media service.',
          cause: OfferMediaDiagnostics.categorize(error));
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw R2OfferMediaHttpException(
        response.statusCode,
        code: _workerCode(response),
      );
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
  const R2UploadException(this.message, {this.cause});

  final String message;

  /// A fixed, loggable category for what went wrong (see
  /// `OfferMediaDiagnostics.categorize`), never provider text or a URL.
  final String? cause;

  @override
  String toString() => 'R2UploadException: $message';
}

/// A non-success answer from the media Worker, carrying its status code and
/// its stable `code`, when it sent one.
///
/// The status is what lets the caller tell an authoritative "this account has
/// no such Offer" from a session problem or an upstream failure — a
/// distinction that decides whether locally held private bytes may be deleted.
/// It extends [R2UploadException] so every existing handler still catches it.
///
/// The Worker's own message is deliberately dropped: it is provider text and
/// can name internal detail. Only the status and the stable code are carried.
class R2OfferMediaHttpException extends R2UploadException {
  R2OfferMediaHttpException(this.statusCode, {this.code})
      : super('Offer media service request failed ($statusCode).',
            cause: 'http:$statusCode');

  final int statusCode;
  final String? code;

  /// The Worker reached this only after its ownership query succeeded and
  /// returned no row (an upstream failure answers 502), so it is trustworthy.
  bool get isAccessDenied => statusCode == 404 || statusCode == 403;

  bool get isUnauthenticated => statusCode == 401;
}

/// A file refused as Offer media for a reason the user can act on, from the
/// local pre-check or from the Media Worker. Carries only the reason, never a
/// file path, byte content or provider text.
class OfferMediaRejectedException extends R2UploadException {
  const OfferMediaRejectedException(this.rejection, {super.cause})
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
