import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:broker_wallet/src/config/r2_config.dart';

/// The result returned by the Worker after an upload is confirmed.
class R2ProfileUploadResult {
  const R2ProfileUploadResult({required this.profileMediaId});

  final String profileMediaId;
}

/// The current profile image metadata and its short-lived signed read URL.
class R2ProfileImage {
  const R2ProfileImage({
    this.profileMediaId,
    this.profileImageUrl,
    this.expiresInSeconds,
  });

  final String? profileMediaId;
  final String? profileImageUrl;

  /// Server-declared validity window for [profileImageUrl], in seconds.
  /// Comes directly from the Worker's `/profile-image-url` response
  /// (`expiresInSeconds`) — never guessed client-side.
  final int? expiresInSeconds;
}

/// An in-memory, process-lifetime cache entry for a resolved signed URL.
class _CachedSignedUrl {
  const _CachedSignedUrl({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}

/// Client boundary for the production profile-image Worker.
class R2ProfileUploadService {
  R2ProfileUploadService({
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

  /// In-memory signed-URL cache, keyed by the stable `profileMediaId`.
  /// Never persisted; cleared automatically when the process exits.
  final Map<String, _CachedSignedUrl> _urlCache = {};

  /// Safety margin subtracted from the Worker-declared TTL before a cached
  /// entry is treated as expired, so a resolution is never handed out right
  /// at the edge of the server's own signature validity window.
  static const Duration _expirySafetyMargin = Duration(seconds: 60);

  /// Resolve the signed read URL for [expectedMediaId], reusing an unexpired
  /// in-memory cache entry when possible instead of always calling the
  /// Worker. Returns null when there is no media, or when the Worker's
  /// current resolution turns out to be for a different media id than the
  /// one the caller expected (see the race-handling note below).
  Future<String?> resolveSignedUrl(String? expectedMediaId) async {
    if (expectedMediaId == null || expectedMediaId.isEmpty) return null;

    final cached = _urlCache[expectedMediaId];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached.url;
    }

    final image = await getCurrentProfileImage();
    final resolvedMediaId = image.profileMediaId;
    final url = image.profileImageUrl;
    if (resolvedMediaId == null || url == null || url.isEmpty) {
      return null;
    }

    final ttlSeconds = image.expiresInSeconds;
    final ttl = (ttlSeconds != null && ttlSeconds > 0)
        ? Duration(seconds: ttlSeconds)
        : Duration.zero;
    final safeTtl =
        ttl > _expirySafetyMargin ? ttl - _expirySafetyMargin : Duration.zero;
    _urlCache[resolvedMediaId] = _CachedSignedUrl(
      url: url,
      expiresAt: DateTime.now().add(safeTtl),
    );

    // Race guard: public.profiles.profile_media_id may have changed between
    // the caller's own database read and this request, since
    // /profile-image-url resolves whatever is canonical *now* rather than
    // taking a caller-supplied media id. Only hand back the URL when it
    // actually matches what the caller expected; otherwise the correct value
    // is now cached under resolvedMediaId for whoever asks for that id next.
    if (resolvedMediaId != expectedMediaId) {
      return null;
    }

    return url;
  }

  /// Authorize an upload using the current authenticated Supabase user.
  Future<R2UploadAuthorization> authorizeProfileImageUpload({
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    _validateContentType(contentType);
    _validateContentLength(contentLength);

    final auth = _currentAuth();
    final payload = await _post(
      '/authorize',
      auth.accessToken,
      {
        'userId': auth.user.id,
        'contentType': contentType,
        'contentLength': contentLength,
        if (originalFileName != null && originalFileName.trim().isNotEmpty)
          'originalFileName': originalFileName,
      },
    );

    final signedPutUrl = _requiredString(payload, 'presignedUrl');
    final mediaObjectId = _requiredString(payload, 'mediaObjectId');
    return R2UploadAuthorization(
      presignedUrl: signedPutUrl,
      mediaObjectId: mediaObjectId,
    );
  }

  /// Upload and confirm a profile image through the production Worker.
  Future<R2ProfileUploadResult> uploadProfileImage({
    required XFile imageFile,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final contentType = _contentTypeForFileName(imageFile.name);
    final authorization = await authorizeProfileImageUpload(
      contentType: contentType,
      contentLength: bytes.length,
      originalFileName: imageFile.name,
    );

    final putResponse = await _request(() => _http.put(
          Uri.parse(authorization.presignedUrl),
          headers: {'Content-Type': contentType},
          body: bytes,
        ));
    if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
      throw const R2UploadException('Profile image upload was rejected.');
    }

    final auth = _currentAuth();
    final payload = await _post(
      '/confirm',
      auth.accessToken,
      {'mediaObjectId': authorization.mediaObjectId},
    );
    final profileMediaId = _requiredString(payload, 'profileMediaId');
    return R2ProfileUploadResult(profileMediaId: profileMediaId);
  }

  /// Resolve the current profile image's short-lived signed read URL.
  Future<R2ProfileImage> getCurrentProfileImage() async {
    final auth = _currentAuth();
    final response = await _request(() => _http.get(
          _endpoint('/profile-image-url'),
          headers: {'Authorization': 'Bearer ${auth.accessToken}'},
        ));
    _ensureSuccess(response, '/profile-image-url');

    final payload = _decodeObject(response.body);
    return R2ProfileImage(
      profileMediaId: _optionalString(payload, 'profileMediaId'),
      profileImageUrl: _optionalString(payload, 'profileImageUrl'),
      expiresInSeconds: _optionalInt(payload, 'expiresInSeconds'),
    );
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
    final response = await _request(() => _http.post(
          _endpoint(path),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        ));
    _ensureSuccess(response, path);
    return _decodeObject(response.body);
  }

  Future<http.Response> _request(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on TimeoutException {
      throw const R2UploadException('The profile image request timed out.');
    } on http.ClientException {
      throw const R2UploadException('Could not reach the profile image service.');
    } catch (_) {
      throw const R2UploadException('Could not reach the profile image service.');
    }
  }

  void _ensureSuccess(http.Response response, String path) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw R2UploadException('Profile image service request failed (${response.statusCode}).');
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const R2UploadException('Profile image service returned an invalid response.');
  }

  Uri _endpoint(String path) => Uri.parse('${R2Config.workerUrl}$path');

  void _assertConfigured() {
    if (!R2Config.isConfigured) throw const R2WorkerNotConfiguredException();
  }

  void _validateContentType(String contentType) {
    if (!supportedContentTypes.contains(contentType)) {
      throw const R2UploadException('Unsupported profile image type.');
    }
  }

  void _validateContentLength(int contentLength) {
    if (contentLength < 1 || contentLength > maxImageBytes) {
      throw const R2UploadException('Profile image must be between 1 byte and 10 MiB.');
    }
  }

  String _contentTypeForFileName(String fileName) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
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
        throw const R2UploadException('Unsupported profile image type.');
    }
  }
}

class R2UploadAuthorization {
  const R2UploadAuthorization({
    required this.presignedUrl,
    required this.mediaObjectId,
  });

  final String presignedUrl;
  final String mediaObjectId;
}

class _CurrentAuth {
  const _CurrentAuth(this.user, this.accessToken);

  final User user;
  final String accessToken;
}

String _requiredString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is String && value.isNotEmpty) return value;
  throw const R2UploadException('Profile image service returned incomplete data.');
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
