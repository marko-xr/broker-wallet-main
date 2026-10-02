// Client for the Quotation private-media routes of the Media Worker
// (POST /quotation-media/authorize|confirm|remove, GET /quotation-media).
//
// The bucket stays private. Every read is a fresh short-lived signed URL from
// the Worker; nothing here stores one, and only a media object's id is a
// durable identity. The client never holds an R2 or server credential: it
// sends the current Supabase access token and the Worker does the rest.
//
// A Quotation has one slot per role (`office_logo`, `quotation_pdf`). Every
// authorize, confirm and remove names the media id the caller believes the slot
// holds (`expectedMediaId`, null for an empty slot); the server refuses with
// `stale_replacement` when that is no longer true, so an older operation can
// never overwrite a newer one.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The two private-media slots of a Quotation.
enum QuotationMediaRole {
  officeLogo('office_logo'),
  quotationPdf('quotation_pdf');

  const QuotationMediaRole(this.wireName);

  /// The role name the Worker's API uses.
  final String wireName;
}

/// Why a Quotation media operation did not complete. A fixed category: never
/// provider text, a URL, an object key or a file path.
enum QuotationMediaFailure {
  /// No active Supabase session.
  notSignedIn,

  /// The Worker refused the session (401).
  unauthorized,

  /// The Quotation does not exist, is not this account's, or was deleted.
  quotationNotFound,

  /// The slot no longer holds what the caller expected: a newer operation won.
  staleReplacement,

  /// The file is not an accepted type for the role.
  unsupportedType,

  /// The file is larger than the role allows.
  tooLarge,

  /// The uploaded bytes are not the type that was declared.
  typeMismatch,

  /// The bytes had not arrived when confirm ran.
  uploadIncomplete,

  /// Private storage refused the signed upload (for example, it expired).
  uploadRejected,

  /// The connection dropped or timed out; nothing was confirmed.
  interrupted,

  /// The media service is unreachable or failing.
  unavailable,

  /// The media service answered with something this client cannot use.
  invalidResponse,

  /// The Worker address is not configured.
  notConfigured,

  /// Anything else.
  unknown,
}

class QuotationMediaException implements Exception {
  const QuotationMediaException(
    this.failure, {
    this.statusCode,
    this.workerCode,
  });

  final QuotationMediaFailure failure;

  /// The Worker's HTTP status, when it answered.
  final int? statusCode;

  /// The Worker's stable `code`, when it sent one.
  final String? workerCode;

  /// Whether the same request may succeed if simply repeated.
  bool get isRetryable =>
      failure == QuotationMediaFailure.interrupted ||
      failure == QuotationMediaFailure.unavailable ||
      failure == QuotationMediaFailure.uploadIncomplete ||
      failure == QuotationMediaFailure.uploadRejected;

  @override
  String toString() => 'QuotationMediaException(${failure.name}'
      '${statusCode == null ? '' : ', $statusCode'})';
}

/// What `/quotation-media/authorize` answered.
class QuotationMediaAuthorization {
  const QuotationMediaAuthorization.pending({
    required this.mediaObjectId,
    required String this.presignedUrl,
  }) : isAlreadyReady = false;

  const QuotationMediaAuthorization.ready({required this.mediaObjectId})
      : presignedUrl = null,
        isAlreadyReady = true;

  final String mediaObjectId;

  /// The short-lived signed PUT. Transport only: never stored.
  final String? presignedUrl;

  /// The id is already bound to the slot, so there is nothing to upload.
  final bool isAlreadyReady;
}

/// What `/quotation-media/confirm` answered.
class QuotationMediaConfirmation {
  const QuotationMediaConfirmation({
    this.previousMediaId,
    this.resultingVersion,
    this.alreadyConfirmed = false,
    this.cleanupPending = false,
  });

  /// The media this one replaced, if any.
  final String? previousMediaId;

  /// The Quotation's version after the slot changed.
  final int? resultingVersion;
  final bool alreadyConfirmed;

  /// The replaced bytes are still being retired by the server.
  final bool cleanupPending;
}

/// What `/quotation-media/remove` answered.
class QuotationMediaRemoval {
  const QuotationMediaRemoval({
    this.previousMediaId,
    this.resultingVersion,
    this.alreadyRemoved = false,
    this.cleanupPending = false,
  });

  final String? previousMediaId;
  final int? resultingVersion;
  final bool alreadyRemoved;
  final bool cleanupPending;
}

/// One bound item with a fresh short-lived signed read URL.
class SignedQuotationMedia {
  const SignedQuotationMedia({
    required this.mediaObjectId,
    required this.contentType,
    required this.url,
    required this.expiresAt,
  });

  final String mediaObjectId;
  final String contentType;

  /// Transport only: kept in memory, never stored.
  final String url;

  /// When [url] stops working (an estimate that errs early).
  final DateTime expiresAt;
}

/// The bound media of one Quotation, each with a signed read URL.
class QuotationSignedMedia {
  const QuotationSignedMedia({this.officeLogo, this.quotationPdf});

  final SignedQuotationMedia? officeLogo;
  final SignedQuotationMedia? quotationPdf;
}

/// The Worker operations a Quotation media change consists of. A seam so the
/// workflow can be exercised without a network.
abstract interface class QuotationMediaTransport {
  Future<QuotationMediaAuthorization> authorize({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  });

  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  });

  Future<QuotationMediaConfirmation> confirm({
    required String quotationId,
    required QuotationMediaRole role,
    required String mediaObjectId,
    required String? expectedMediaId,
  });

  Future<QuotationMediaRemoval> remove({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
  });

  Future<QuotationSignedMedia> fetchSigned(String quotationId);
}

class R2QuotationMediaService implements QuotationMediaTransport {
  R2QuotationMediaService({
    http.Client? httpClient,
    SupabaseClient? supabaseClient,
  })  : _http = httpClient ?? http.Client(),
        _customSupabase = supabaseClient;

  final http.Client _http;
  final SupabaseClient? _customSupabase;

  /// Resolved on use, so building this service never touches Supabase before
  /// it is initialized.
  SupabaseClient get _supabase => _customSupabase ?? Supabase.instance.client;

  static const Duration _metadataTimeout = Duration(seconds: 15);
  static const Duration _uploadTimeout = Duration(minutes: 2);
  static const Duration _defaultReadUrlLifetime = Duration(seconds: 900);

  @override
  Future<QuotationMediaAuthorization> authorize({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    final payload = await _post('/quotation-media/authorize', {
      'quotationId': quotationId,
      'role': role.wireName,
      'expectedMediaId': expectedMediaId,
      'mediaObjectId': mediaObjectId,
      'contentType': contentType,
      'contentLength': contentLength,
      if (originalFileName != null && originalFileName.isNotEmpty)
        'originalFileName': originalFileName,
    });
    final returnedId = _string(payload, 'mediaObjectId');
    if (returnedId == null ||
        returnedId.toLowerCase() != mediaObjectId.toLowerCase()) {
      throw const QuotationMediaException(
          QuotationMediaFailure.invalidResponse);
    }
    if (payload['status'] == 'ready') {
      return QuotationMediaAuthorization.ready(mediaObjectId: mediaObjectId);
    }
    final url = _string(payload, 'presignedUrl');
    if (url == null) {
      throw const QuotationMediaException(
          QuotationMediaFailure.invalidResponse);
    }
    return QuotationMediaAuthorization.pending(
      mediaObjectId: mediaObjectId,
      presignedUrl: url,
    );
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  }) async {
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      throw const QuotationMediaException(QuotationMediaFailure.interrupted);
    }
    try {
      final response = await _http
          .put(
            Uri.parse(presignedUrl),
            headers: {'Content-Type': contentType},
            body: bytes,
          )
          .timeout(_uploadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // R2's answer: an expired or refused signature is 403. The next
        // attempt authorizes again and gets a fresh signed URL.
        throw QuotationMediaException(
          QuotationMediaFailure.uploadRejected,
          statusCode: response.statusCode,
        );
      }
    } on QuotationMediaException {
      rethrow;
    } on TimeoutException {
      throw const QuotationMediaException(QuotationMediaFailure.interrupted);
    } catch (_) {
      throw const QuotationMediaException(QuotationMediaFailure.interrupted);
    }
  }

  @override
  Future<QuotationMediaConfirmation> confirm({
    required String quotationId,
    required QuotationMediaRole role,
    required String mediaObjectId,
    required String? expectedMediaId,
  }) async {
    final payload = await _post('/quotation-media/confirm', {
      'quotationId': quotationId,
      'role': role.wireName,
      'mediaObjectId': mediaObjectId,
      'expectedMediaId': expectedMediaId,
    });
    return QuotationMediaConfirmation(
      previousMediaId: _string(payload, 'previousMediaId'),
      resultingVersion: _int(payload, 'resultingVersion'),
      alreadyConfirmed: payload['alreadyConfirmed'] == true,
      cleanupPending: payload['cleanupPending'] == true,
    );
  }

  @override
  Future<QuotationMediaRemoval> remove({
    required String quotationId,
    required QuotationMediaRole role,
    required String? expectedMediaId,
  }) async {
    final payload = await _post('/quotation-media/remove', {
      'quotationId': quotationId,
      'role': role.wireName,
      'expectedMediaId': expectedMediaId,
    });
    return QuotationMediaRemoval(
      previousMediaId: _string(payload, 'previousMediaId'),
      resultingVersion: _int(payload, 'resultingVersion'),
      alreadyRemoved: payload['alreadyRemoved'] == true,
      cleanupPending: payload['cleanupPending'] == true,
    );
  }

  @override
  Future<QuotationSignedMedia> fetchSigned(String quotationId) async {
    final token = _accessToken();
    final requestedAt = DateTime.now();
    final response = await _send(() => _http.get(
          _endpoint('/quotation-media')
              .replace(queryParameters: {'quotationId': quotationId}),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(_metadataTimeout));
    _ensureSuccess(response);

    final payload = _decodeObject(response.body);
    final lifetimeSeconds = _int(payload, 'expiresInSeconds');
    // Measured from when the request was sent, so the estimate can only err
    // on the early side.
    final expiresAt = requestedAt.add(lifetimeSeconds == null
        ? _defaultReadUrlLifetime
        : Duration(seconds: lifetimeSeconds));
    final media = payload['media'];
    if (media is! Map) {
      throw const QuotationMediaException(
          QuotationMediaFailure.invalidResponse);
    }
    return QuotationSignedMedia(
      officeLogo: _signed(media['office_logo'], expiresAt),
      quotationPdf: _signed(media['quotation_pdf'], expiresAt),
    );
  }

  SignedQuotationMedia? _signed(Object? entry, DateTime expiresAt) {
    if (entry is! Map) return null;
    final id = entry['mediaObjectId'];
    final url = entry['url'];
    final type = entry['contentType'];
    if (id is! String || id.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    return SignedQuotationMedia(
      mediaObjectId: id,
      contentType: type is String ? type : '',
      url: url,
      expiresAt: expiresAt,
    );
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  String _accessToken() {
    if (!R2Config.isConfigured) {
      throw const QuotationMediaException(QuotationMediaFailure.notConfigured);
    }
    final token = _supabase.auth.currentSession?.accessToken;
    if (_supabase.auth.currentUser == null || token == null || token.isEmpty) {
      throw const QuotationMediaException(QuotationMediaFailure.notSignedIn);
    }
    return token;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final token = _accessToken();
    final response = await _send(() => _http
        .post(
          _endpoint(path),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_metadataTimeout));
    _ensureSuccess(response);
    return _decodeObject(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on TimeoutException {
      throw const QuotationMediaException(QuotationMediaFailure.interrupted);
    } catch (_) {
      // A refused, reset or unreachable connection. The error text can embed
      // the request URL, so only the category is kept.
      throw const QuotationMediaException(QuotationMediaFailure.unavailable);
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final code = _workerCode(response);
    throw QuotationMediaException(
      failureFor(response.statusCode, code),
      statusCode: response.statusCode,
      workerCode: code,
    );
  }

  /// The failure a Worker status and stable `code` stand for.
  @visibleForTesting
  static QuotationMediaFailure failureFor(int status, String? code) {
    switch (code) {
      case 'stale_replacement':
        return QuotationMediaFailure.staleReplacement;
      case 'quotation_not_found':
        return QuotationMediaFailure.quotationNotFound;
      case 'unsupported_media_type':
        return QuotationMediaFailure.unsupportedType;
      case 'media_too_large':
        return QuotationMediaFailure.tooLarge;
      case 'media_type_mismatch':
        return QuotationMediaFailure.typeMismatch;
      case 'upload_incomplete':
        return QuotationMediaFailure.uploadIncomplete;
    }
    if (status == 401) return QuotationMediaFailure.unauthorized;
    if (status >= 500) return QuotationMediaFailure.unavailable;
    return QuotationMediaFailure.unknown;
  }

  /// The Worker's stable `code`. Its free-text message is never read.
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

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const QuotationMediaException(QuotationMediaFailure.invalidResponse);
  }

  Uri _endpoint(String path) => Uri.parse('${R2Config.workerUrl}$path');

  static String? _string(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  static int? _int(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}
