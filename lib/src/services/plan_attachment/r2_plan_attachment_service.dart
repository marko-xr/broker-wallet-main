// Client for the plan routes of the Media Worker
// (POST /offer-plan/authorize|confirm|remove, GET /offer-plan, and the same
// under /owner-plan).
//
// The bucket stays private. Every read is a fresh short-lived signed URL from
// the Worker; nothing here stores one, and only a media object's id is a
// durable identity. The client never holds an R2 or server credential: it sends
// the current Supabase access token and the Worker does the rest, including the
// Single Active Device check.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';

class R2PlanAttachmentService implements PlanAttachmentTransport {
  R2PlanAttachmentService({
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
  static const Duration _transferTimeout = Duration(minutes: 3);
  static const Duration _defaultReadUrlLifetime = Duration(seconds: 900);

  @override
  Future<PlanAuthorization> authorize({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    required String mediaObjectId,
    required String contentType,
    required int contentLength,
    String? originalFileName,
  }) async {
    final payload = await _post('${parent.routePrefix}/authorize', {
      parent.idField: parentId,
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
      throw const PlanAttachmentException(
          PlanAttachmentFailure.invalidResponse);
    }
    if (payload['status'] == 'ready') {
      return PlanAuthorization.ready(mediaObjectId: mediaObjectId);
    }
    final url = _string(payload, 'presignedUrl');
    if (url == null) {
      throw const PlanAttachmentException(
          PlanAttachmentFailure.invalidResponse);
    }
    return PlanAuthorization.pending(
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
      throw const PlanAttachmentException(
          PlanAttachmentFailure.fileUnavailable);
    }
    try {
      final response = await _http
          .put(
            Uri.parse(presignedUrl),
            headers: {'Content-Type': contentType},
            body: bytes,
          )
          .timeout(_transferTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // R2's answer: an expired or refused signature is 403. The next
        // attempt authorizes again and gets a fresh signed URL.
        throw PlanAttachmentException(
          PlanAttachmentFailure.uploadRejected,
          statusCode: response.statusCode,
        );
      }
    } on PlanAttachmentException {
      rethrow;
    } on TimeoutException {
      throw const PlanAttachmentException(PlanAttachmentFailure.interrupted);
    } catch (_) {
      throw const PlanAttachmentException(PlanAttachmentFailure.interrupted);
    }
  }

  @override
  Future<PlanConfirmation> confirm({
    required PlanParent parent,
    required String parentId,
    required String mediaObjectId,
    required String? expectedMediaId,
  }) async {
    final payload = await _post('${parent.routePrefix}/confirm', {
      parent.idField: parentId,
      'mediaObjectId': mediaObjectId,
      'expectedMediaId': expectedMediaId,
    });
    return PlanConfirmation(
      previousMediaId: _string(payload, 'previousMediaId'),
      alreadyConfirmed: payload['alreadyConfirmed'] == true,
      cleanupPending: payload['cleanupPending'] == true,
    );
  }

  @override
  Future<PlanRemoval> remove({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    String? mediaObjectId,
  }) async {
    final payload = await _post('${parent.routePrefix}/remove', {
      parent.idField: parentId,
      'expectedMediaId': expectedMediaId,
      if (mediaObjectId != null) 'mediaObjectId': mediaObjectId,
    });
    return PlanRemoval(
      previousMediaId: _string(payload, 'previousMediaId'),
      alreadyRemoved: payload['alreadyRemoved'] == true,
      cleanupPending: payload['cleanupPending'] == true,
    );
  }

  @override
  Future<PlanAttachmentRef?> fetchCurrent({
    required PlanParent parent,
    required String parentId,
  }) async {
    final token = _accessToken();
    final requestedAt = DateTime.now();
    final response = await _send(() => _http.get(
          _endpoint(parent.routePrefix)
              .replace(queryParameters: {parent.idField: parentId}),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(_metadataTimeout));
    _ensureSuccess(response, token);

    final payload = _decodeObject(response.body);
    if (!payload.containsKey('plan')) {
      throw const PlanAttachmentException(
          PlanAttachmentFailure.invalidResponse);
    }
    final plan = payload['plan'];
    if (plan == null) return null;
    if (plan is! Map) {
      throw const PlanAttachmentException(
          PlanAttachmentFailure.invalidResponse);
    }
    final id = plan['mediaObjectId'];
    final contentType = plan['contentType'];
    final kind = PlanAttachmentKind.fromContentType(
        contentType is String ? contentType : null);
    final url = plan['url'];
    if (id is! String || id.isEmpty || contentType is! String || kind == null) {
      throw const PlanAttachmentException(
          PlanAttachmentFailure.invalidResponse);
    }
    final lifetimeSeconds = _int(payload, 'expiresInSeconds');
    // Measured from when the request was sent, so the estimate can only err on
    // the early side.
    final expiresAt = requestedAt.add(lifetimeSeconds == null
        ? _defaultReadUrlLifetime
        : Duration(seconds: lifetimeSeconds));
    final name = plan['fileName'];
    final size = plan['sizeBytes'];
    return PlanAttachmentRef(
      mediaObjectId: id,
      kind: kind,
      contentType: contentType,
      displayName: name is String && name.isNotEmpty ? name : null,
      byteLength: size is num ? size.toInt() : null,
      signedUrl: url is String && url.isNotEmpty ? url : null,
      signedUrlExpiresAt: url is String && url.isNotEmpty ? expiresAt : null,
    );
  }

  @override
  Future<void> download({
    required String url,
    required File target,
    required int maxBytes,
  }) async {
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await _http.send(request).timeout(_transferTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PlanAttachmentException(
          PlanAttachmentFailure.unavailable,
          statusCode: response.statusCode,
        );
      }
      final declared = response.contentLength;
      if (declared != null && declared > maxBytes) {
        throw const PlanAttachmentException(
            PlanAttachmentFailure.invalidResponse);
      }
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(_transferTimeout)) {
        received += chunk.length;
        if (received > maxBytes) {
          throw const PlanAttachmentException(
              PlanAttachmentFailure.invalidResponse);
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on PlanAttachmentException {
      await _discard(sink, target);
      rethrow;
    } on TimeoutException {
      await _discard(sink, target);
      throw const PlanAttachmentException(PlanAttachmentFailure.interrupted);
    } catch (_) {
      // A refused, reset or unreachable connection, or a file that cannot be
      // written. The error text can embed the URL, so only the category is kept.
      await _discard(sink, target);
      throw const PlanAttachmentException(PlanAttachmentFailure.unavailable);
    }
  }

  Future<void> _discard(IOSink? sink, File target) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await target.exists()) await target.delete();
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  String _accessToken() {
    if (!R2Config.isConfigured) {
      throw const PlanAttachmentException(PlanAttachmentFailure.notConfigured);
    }
    final token = _supabase.auth.currentSession?.accessToken;
    if (_supabase.auth.currentUser == null || token == null || token.isEmpty) {
      throw const PlanAttachmentException(PlanAttachmentFailure.notSignedIn);
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
    _ensureSuccess(response, token);
    return _decodeObject(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on TimeoutException {
      throw const PlanAttachmentException(PlanAttachmentFailure.interrupted);
    } catch (_) {
      // A refused, reset or unreachable connection. The error text can embed
      // the request URL, so only the category is kept.
      throw const PlanAttachmentException(PlanAttachmentFailure.unavailable);
    }
  }

  void _ensureSuccess(http.Response response, String accessToken) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final code = _workerCode(response);
    if (code == 'session_superseded') {
      AppSessionCoordinator.reportBackendError(code!, accessToken: accessToken);
    }
    throw PlanAttachmentException(
      failureFor(response.statusCode, code),
      statusCode: response.statusCode,
      workerCode: code,
    );
  }

  /// The failure a Worker status and stable `code` stand for.
  @visibleForTesting
  static PlanAttachmentFailure failureFor(int status, String? code) {
    switch (code) {
      case 'stale_replacement':
        return PlanAttachmentFailure.staleReplacement;
      case 'offer_not_found':
      case 'owner_not_found':
        return PlanAttachmentFailure.parentNotFound;
      case 'unsupported_media_type':
        return PlanAttachmentFailure.unsupportedType;
      case 'image_too_large':
        return PlanAttachmentFailure.imageTooLarge;
      case 'document_too_large':
        return PlanAttachmentFailure.documentTooLarge;
      case 'media_type_mismatch':
        return PlanAttachmentFailure.typeMismatch;
      case 'upload_incomplete':
        return PlanAttachmentFailure.uploadIncomplete;
      case 'upload_rejected':
      case 'idempotency_mismatch':
      case 'media_id_conflict':
      case 'media_mismatch':
      case 'invalid_state':
        return PlanAttachmentFailure.uploadRejected;
      case 'media_removed':
        return PlanAttachmentFailure.mediaRemoved;
      case 'plan_upload_limit':
        return PlanAttachmentFailure.tooManyPending;
      case 'session_superseded':
        return PlanAttachmentFailure.sessionSuperseded;
      case 'session_check_unavailable':
        return PlanAttachmentFailure.unavailable;
    }
    if (status == 401) return PlanAttachmentFailure.unauthorized;
    if (status >= 500) return PlanAttachmentFailure.unavailable;
    return PlanAttachmentFailure.unknown;
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
    throw const PlanAttachmentException(PlanAttachmentFailure.invalidResponse);
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
