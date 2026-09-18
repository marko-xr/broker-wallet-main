import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:broker_wallet/src/config/r2_config.dart';

/// One piece of confirmed, displayable Offer media: a short-lived signed
/// read URL plus the stable identifiers needed to correlate it, never the
/// bucket path or any credential.
class R2OfferMediaItem {
  const R2OfferMediaItem({
    required this.mediaObjectId,
    required this.role,
    required this.ordinal,
    required this.url,
  });

  final String mediaObjectId;
  final String role;
  final int ordinal;
  final String url;
}

/// The result of successfully uploading and confirming one Offer media file.
class R2OfferMediaUploadResult {
  const R2OfferMediaUploadResult({required this.mediaObjectId});

  final String mediaObjectId;
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

  static const int maxImageBytes = 10 * 1024 * 1024;
  static const Set<String> supportedContentTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
  };

  final http.Client _http;
  final SupabaseClient _supabase;

  static const Duration _metadataRequestTimeout = Duration(seconds: 15);
  static const Duration _uploadRequestTimeout = Duration(seconds: 60);

  /// Authorize an upload for [file] against [offerId] using the current
  /// authenticated Supabase user, upload it directly to private R2, then
  /// confirm it and attach it to the offer with [role]/[ordinal]. Ownership
  /// of the offer is verified server-side by the Worker on both the
  /// authorize and confirm calls — this method never sends anything the
  /// server treats as a trusted owner id.
  Future<R2OfferMediaUploadResult> uploadOfferMediaFile({
    required String offerId,
    required File file,
    String role = 'gallery',
    int ordinal = 0,
  }) async {
    final bytes = await file.readAsBytes();
    final contentType = _contentTypeForFileName(file.path);
    _validateContentType(contentType);
    _validateContentLength(bytes.length);

    final auth = _currentAuth();
    final authPayload =
        await _post('/offer-media/authorize', auth.accessToken, {
      'offerId': offerId,
      'contentType': contentType,
      'contentLength': bytes.length,
      'originalFileName': _fileName(file.path),
    });
    final presignedUrl = _requiredString(authPayload, 'presignedUrl');
    final mediaObjectId = _requiredString(authPayload, 'mediaObjectId');

    final putResponse = await _request(() => _http
        .put(
          Uri.parse(presignedUrl),
          headers: {'Content-Type': contentType},
          body: bytes,
        )
        .timeout(_uploadRequestTimeout));
    if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
      throw const R2UploadException('Offer image upload was rejected.');
    }

    final confirmAuth = _currentAuth();
    await _post('/offer-media/confirm', confirmAuth.accessToken, {
      'offerId': offerId,
      'mediaObjectId': mediaObjectId,
      'role': role,
      'ordinal': ordinal,
    });

    return R2OfferMediaUploadResult(mediaObjectId: mediaObjectId);
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
    _ensureSuccess(response, path);
    return _decodeObject(response.body);
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
      throw R2UploadException(
          'Offer media service request failed (${response.statusCode}).');
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

  void _validateContentType(String contentType) {
    if (!supportedContentTypes.contains(contentType)) {
      throw const R2UploadException('Unsupported offer image type.');
    }
  }

  void _validateContentLength(int contentLength) {
    if (contentLength < 1 || contentLength > maxImageBytes) {
      throw const R2UploadException(
          'Offer image must be between 1 byte and 10 MiB.');
    }
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/') ? normalized.split('/').last : normalized;
  }

  String _contentTypeForFileName(String path) {
    final name = _fileName(path);
    final extension =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        throw const R2UploadException('Unsupported offer image type.');
    }
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
