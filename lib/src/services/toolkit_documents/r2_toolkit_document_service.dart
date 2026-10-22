// Client for the Toolkit document routes of the Media Worker
// (POST /toolkit-documents/authorize|confirm|status|rename|remove and
// GET /toolkit-documents[/download]).
//
// The bucket stays private. Every read and write is a fresh short-lived signed
// URL from the Worker; nothing here stores one, and only a document's id is a
// durable identity: the client never learns, builds or sends an object key. It
// holds no R2 or server credential: it sends the current Supabase access token
// and the Worker does the rest, including the Single Active Device check.
//
// The service is bound to one account. A call made while another account is
// signed in fails with [ToolkitFailure.accountChanged] before anything leaves
// the phone.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_transport.dart';

class R2ToolkitDocumentService implements ToolkitDocumentTransport {
  /// [workerUrl] and [stagingKey] exist for tests only. The app passes neither:
  /// the address and the gate key then come from [R2Config], which applies the
  /// debug-only rules (see its Toolkit section).
  R2ToolkitDocumentService({
    required this.accountId,
    http.Client? httpClient,
    SupabaseClient? supabaseClient,
    String? workerUrl,
    String? stagingKey,
  })  : _http = httpClient ?? http.Client(),
        _customSupabase = supabaseClient,
        _workerUrl = workerUrl,
        _stagingKey = stagingKey;

  @override
  final String accountId;

  final http.Client _http;
  final SupabaseClient? _customSupabase;
  final String? _workerUrl;
  final String? _stagingKey;

  /// The Worker address for Toolkit routes, or null when there is none.
  String? _address() => _workerUrl ?? R2Config.toolkitWorkerUrl;

  /// Resolved on use, so building this service never touches Supabase before
  /// it is initialized.
  SupabaseClient get _supabase => _customSupabase ?? Supabase.instance.client;

  static const String _base = '/toolkit-documents';
  static const Duration _metadataTimeout = Duration(seconds: 15);
  static const Duration _uploadTimeout = Duration(minutes: 15);
  static const Duration _downloadTimeout = Duration(minutes: 10);
  static const Duration _defaultReadUrlLifetime = Duration(seconds: 900);

  @override
  Future<ToolkitUploadAuthorization> authorize({
    required String documentId,
    required ToolkitDocumentType type,
    required ToolkitContentType contentType,
    required String title,
    required int contentLength,
    required String contentSha256,
    required DateTime sourceCreatedAt,
    int? pageCount,
    bool acknowledgeStale = false,
  }) async {
    if (!contentType.allowedFor(type)) {
      throw const ToolkitDocumentException(ToolkitFailure.unsupported);
    }
    final payload = await _post('$_base/authorize', {
      'documentId': documentId,
      'documentType': type.wireName,
      'title': title,
      'contentType': contentType.mime,
      'contentLength': contentLength,
      'contentSha256': contentSha256,
      'sourceCreatedAt': sourceCreatedAt.toUtc().toIso8601String(),
      if (pageCount != null) 'pageCount': pageCount,
      if (acknowledgeStale) 'acknowledgeStale': true,
    });
    final returnedId = _string(payload, 'documentId');
    if (returnedId == null || returnedId != documentId) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    if (payload['status'] == 'ready') {
      return ToolkitUploadAuthorization.alreadyConfirmed(
          documentId: documentId);
    }
    final url = _string(payload, 'presignedUrl');
    if (payload['status'] != 'pending' || url == null) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return ToolkitUploadAuthorization.pending(
      documentId: documentId,
      presignedUrl: url,
      uploadHeaders: _uploadHeaders(payload),
    );
  }

  /// The headers the signed PUT needs. The Worker signs exactly one, the write-once
  /// guard; anything else is not something this client will send.
  Map<String, String> _uploadHeaders(Map<String, dynamic> payload) {
    final raw = payload['uploadHeaders'];
    if (raw == null) return const {};
    if (raw is! Map) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    final headers = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key.toString().toLowerCase() != 'if-none-match' ||
          entry.value != '*') {
        throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
      }
      headers['If-None-Match'] = '*';
    }
    return headers;
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required ToolkitContentType contentType,
    Map<String, String> headers = const {},
  }) async {
    _requireAccount();
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      throw const ToolkitDocumentException(ToolkitFailure.fileUnavailable);
    }
    try {
      // Streamed: a 100 MB document is never held in memory.
      final request = http.StreamedRequest('PUT', Uri.parse(presignedUrl))
        ..headers.addAll(headers)
        ..headers['Content-Type'] = contentType.mime
        ..contentLength = length;
      unawaited(
        file
            .openRead()
            .pipe(_SinkConsumer(request.sink))
            .catchError((Object e) {
          // An unreadable file ends the body with an error, so the request
          // fails instead of waiting for bytes that will never come.
          request.sink.addError(e);
          request.sink.close();
        }),
      );
      final response = await _http.send(request).timeout(_uploadTimeout);
      await response.stream.drain<void>();
      // Write-once PUT: 412 means an object is already stored under this key (an
      // earlier attempt of this same upload whose answer was lost, or a conflicting
      // object). Either way the confirm that follows judges it; nothing was replaced.
      if (response.statusCode == 412 && headers.containsKey('If-None-Match')) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // R2's answer: an expired or refused signature is 403. The next attempt
        // authorizes again and gets a fresh signed URL.
        throw ToolkitDocumentException(
          ToolkitFailure.uploadRejected,
          statusCode: response.statusCode,
        );
      }
    } on ToolkitDocumentException {
      rethrow;
    } on TimeoutException {
      throw const ToolkitDocumentException(ToolkitFailure.interrupted);
    } catch (_) {
      // The error text can embed the URL, so only the category is kept.
      throw const ToolkitDocumentException(ToolkitFailure.interrupted);
    }
  }

  @override
  Future<ToolkitConfirmation> confirm({required String documentId}) async {
    final payload = await _post('$_base/confirm', {'documentId': documentId});
    final version = _int(payload, 'version');
    if (version == null) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return ToolkitConfirmation(
      version: version,
      alreadyConfirmed: payload['alreadyConfirmed'] == true,
      sha256Verified: payload['sha256Verified'] == true,
    );
  }

  @override
  Future<ToolkitDocumentPage> listPage({
    String? cursor,
    int limit = ToolkitDocumentLimits.listPageSize,
    ToolkitDocumentType? type,
  }) async {
    final payload = await _get(_base, {
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
      if (type != null) 'documentType': type.wireName,
    });
    final raw = payload['documents'];
    if (raw is! List) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    final List<ToolkitDocumentMetadata> documents;
    try {
      documents = raw.map(ToolkitDocumentMetadata.fromWorkerJson).toList();
    } on FormatException {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    final next = payload['nextCursor'];
    if (next != null && (next is! String || next.isEmpty)) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return ToolkitDocumentPage(
      documents: documents,
      nextCursor: next as String?,
      usage: _usage(payload),
    );
  }

  @override
  Future<ToolkitRemoteStatuses> statuses(List<String> documentIds) async {
    if (documentIds.isEmpty ||
        documentIds.length > ToolkitDocumentLimits.statusBatchSize ||
        !documentIds.every(ToolkitDocumentIds.isCanonical)) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidRequest);
    }
    final payload = await _post('$_base/status', {'documentIds': documentIds});
    final documents = payload['documents'];
    final unknown = payload['unknownIds'];
    if (documents is! List || unknown is! List) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    final byId = <String, ToolkitRemoteState>{};
    for (final entry in documents) {
      final id = entry is Map ? entry['documentId'] : null;
      final state =
          ToolkitRemoteState.fromWire(entry is Map ? entry['state'] : null);
      if (id is! String || state == null) {
        throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
      }
      byId[id] = state;
    }
    for (final id in unknown) {
      if (id is! String) {
        throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
      }
      byId[id] = ToolkitRemoteState.unknown;
    }
    // Every id asked about must be answered, and nothing else.
    final asked = documentIds.toSet();
    if (!asked.every(byId.containsKey) ||
        byId.keys.any((id) => !asked.contains(id))) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return ToolkitRemoteStatuses(byId);
  }

  @override
  Future<ToolkitDownloadTicket> downloadTicket(String documentId) async {
    final requestedAt = DateTime.now();
    final payload = await _get('$_base/download', {'documentId': documentId});
    final type = ToolkitDocumentType.fromWire(payload['documentType']);
    final contentType = ToolkitContentType.fromMime(payload['contentType']);
    final title = _string(payload, 'title');
    final size = _int(payload, 'sizeBytes');
    final version = _int(payload, 'version');
    final url = _string(payload, 'url');
    final sha = payload['contentSha256'];
    final pages = payload['pageCount'];
    if (_string(payload, 'documentId') != documentId ||
        type == null ||
        contentType == null ||
        !contentType.allowedFor(type) ||
        title == null ||
        size == null ||
        size < 1 ||
        size > contentType.hardMaxBytes ||
        version == null ||
        url == null ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        (pages != null && (pages is! int || pages < 1))) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    final lifetime = _int(payload, 'expiresInSeconds');
    return ToolkitDownloadTicket(
      documentId: documentId,
      type: type,
      contentType: contentType,
      title: title,
      sizeBytes: size,
      version: version,
      pageCount: pages as int?,
      contentSha256: sha,
      sha256Verified: payload['sha256Verified'] == true,
      url: url,
      // Measured from when the request was sent, so the estimate can only err
      // on the early side.
      expiresAt: requestedAt.add(
        lifetime == null
            ? _defaultReadUrlLifetime
            : Duration(seconds: lifetime),
      ),
    );
  }

  @override
  Future<void> downloadToFile({
    required String url,
    required File target,
    required int maxBytes,
  }) async {
    IOSink? sink;
    try {
      final response = await _http
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(_downloadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw ToolkitDocumentException(
          ToolkitFailure.unavailable,
          statusCode: response.statusCode,
        );
      }
      final declared = response.contentLength;
      if (declared != null && declared > maxBytes) {
        throw const ToolkitDocumentException(ToolkitFailure.integrityMismatch);
      }
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(_downloadTimeout)) {
        received += chunk.length;
        if (received > maxBytes) {
          throw const ToolkitDocumentException(
              ToolkitFailure.integrityMismatch);
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on ToolkitDocumentException {
      await _discard(sink, target);
      rethrow;
    } on TimeoutException {
      await _discard(sink, target);
      throw const ToolkitDocumentException(ToolkitFailure.interrupted);
    } on FileSystemException catch (error) {
      await _discard(sink, target);
      throw ToolkitDocumentException(
        isDiskFull(error)
            ? ToolkitFailure.insufficientStorage
            : ToolkitFailure.fileUnavailable,
      );
    } catch (_) {
      // A refused, reset or unreachable connection. The error text can embed
      // the URL, so only the category is kept.
      await _discard(sink, target);
      throw const ToolkitDocumentException(ToolkitFailure.unavailable);
    }
  }

  /// Whether a file error means the disk is full (ENOSPC on Android, iOS and
  /// Linux is 28; ERROR_DISK_FULL on Windows is 112).
  @visibleForTesting
  static bool isDiskFull(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 28 || code == 112;
  }

  Future<void> _discard(IOSink? sink, File target) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await target.exists()) await target.delete();
    } catch (_) {}
  }

  @override
  Future<ToolkitRenameResult> rename({
    required String documentId,
    required String title,
    required int expectedVersion,
  }) async {
    final payload = await _post('$_base/rename', {
      'documentId': documentId,
      'title': title,
      'expectedVersion': expectedVersion,
    });
    final renamed = _string(payload, 'title');
    final version = _int(payload, 'version');
    if (renamed == null || version == null) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return ToolkitRenameResult(title: renamed, version: version);
  }

  @override
  Future<ToolkitRemoveResult> remove({required String documentId}) async {
    final payload = await _post('$_base/remove', {'documentId': documentId});
    if (payload['removed'] != true) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return ToolkitRemoveResult(
      alreadyRemoved: payload['alreadyRemoved'] == true,
      cleanupPending: payload['cleanupPending'] == true,
    );
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  void _requireAccount() {
    final address = _address();
    if (address == null || address.isEmpty) {
      throw const ToolkitDocumentException(ToolkitFailure.notConfigured);
    }
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const ToolkitDocumentException(ToolkitFailure.notSignedIn);
    }
    if (user.id != accountId) {
      throw const ToolkitDocumentException(ToolkitFailure.accountChanged);
    }
  }

  String _accessToken() {
    _requireAccount();
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const ToolkitDocumentException(ToolkitFailure.notSignedIn);
    }
    return token;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = _accessToken();
    final response = await _send(() => _http
        .post(
          _endpoint(path),
          headers: {
            ..._stagingHeaders(),
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_metadataTimeout));
    _ensureSuccess(response, token);
    return _decodeObject(response.body);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final token = _accessToken();
    final response = await _send(() => _http.get(
          _endpoint(path).replace(queryParameters: query),
          headers: {..._stagingHeaders(), 'Authorization': 'Bearer $token'},
        ).timeout(_metadataTimeout));
    _ensureSuccess(response, token);
    return _decodeObject(response.body);
  }

  /// The staging Worker's access gate, sent only to Worker routes (never to the
  /// signed storage URLs) and only by a debug build that was given the key and a
  /// Toolkit Worker address of its own (see [R2Config.toolkitStagingKey]).
  Map<String, String> _stagingHeaders() {
    final key = _stagingKey ?? R2Config.toolkitStagingKey;
    return key.isEmpty
        ? const <String, String>{}
        : <String, String>{'X-Broker-Wallet-Staging-Key': key};
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on TimeoutException {
      throw const ToolkitDocumentException(ToolkitFailure.interrupted);
    } catch (_) {
      // A refused, reset or unreachable connection. The error text can embed
      // the request URL, so only the category is kept.
      throw const ToolkitDocumentException(ToolkitFailure.unavailable);
    }
  }

  void _ensureSuccess(http.Response response, String accessToken) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final decoded = _decodeOrNull(response.body);
    final code =
        decoded?['code'] is String && (decoded!['code'] as String).isNotEmpty
            ? decoded['code'] as String
            : null;
    if (code == 'session_superseded') {
      AppSessionCoordinator.reportBackendError(code!, accessToken: accessToken);
    }
    throw ToolkitDocumentException(
      failureFor(response.statusCode, code),
      statusCode: response.statusCode,
      workerCode: code,
      retryAfter: _retryAfter(response),
      currentTitle:
          code == 'stale_version' && decoded?['currentTitle'] is String
              ? decoded!['currentTitle'] as String
              : null,
      currentVersion:
          code == 'stale_version' && decoded?['currentVersion'] is int
              ? decoded!['currentVersion'] as int
              : null,
    );
  }

  /// The failure a Worker status and stable `code` stand for.
  @visibleForTesting
  static ToolkitFailure failureFor(int status, String? code) {
    switch (code) {
      case 'unsupported_media_type':
      case 'unsupported_document_type':
        return ToolkitFailure.unsupported;
      case 'document_too_large':
        return ToolkitFailure.tooLarge;
      case 'invalid_request':
      case 'invalid_title':
        return ToolkitFailure.invalidRequest;
      case 'document_deleted':
        return ToolkitFailure.documentDeleted;
      case 'document_not_found':
        return ToolkitFailure.documentNotFound;
      case 'stale_document':
        return ToolkitFailure.staleDocument;
      case 'integrity_mismatch':
        return ToolkitFailure.integrityMismatch;
      case 'document_id_unavailable':
      case 'idempotency_mismatch':
      case 'document_mismatch':
        return ToolkitFailure.idConflict;
      case 'storage_limit_reached':
        return ToolkitFailure.storageLimit;
      case 'document_limit_reached':
        return ToolkitFailure.documentLimit;
      case 'too_many_pending_uploads':
        return ToolkitFailure.tooManyPending;
      case 'rate_limited':
        return ToolkitFailure.rateLimited;
      case 'upload_incomplete':
        return ToolkitFailure.uploadIncomplete;
      case 'upload_rejected':
        return ToolkitFailure.uploadRejected;
      case 'media_type_mismatch':
        return ToolkitFailure.typeMismatch;
      case 'stale_version':
        return ToolkitFailure.staleVersion;
      case 'object_missing':
        return ToolkitFailure.objectMissing;
      case 'object_changed':
        return ToolkitFailure.objectChanged;
      case 'deletion_in_progress':
        return ToolkitFailure.deletionInProgress;
      case 'session_superseded':
        return ToolkitFailure.sessionSuperseded;
      case 'document_not_ready':
      case 'session_check_unavailable':
        return ToolkitFailure.unavailable;
    }
    if (status == 401) return ToolkitFailure.unauthorized;
    if (status == 403) return ToolkitFailure.forbidden;
    if (status == 404) return ToolkitFailure.routeUnavailable;
    if (status == 429) return ToolkitFailure.rateLimited;
    if (status >= 500) return ToolkitFailure.unavailable;
    return ToolkitFailure.unknown;
  }

  Duration? _retryAfter(http.Response response) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    return seconds != null && seconds > 0 && seconds <= 86400
        ? Duration(seconds: seconds)
        : null;
  }

  Map<String, dynamic>? _decodeOrNull(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = _decodeOrNull(body);
    if (decoded == null) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return decoded;
  }

  ToolkitDocumentUsage? _usage(Map<String, dynamic> payload) {
    final usage = payload['usage'];
    if (usage is! Map) return null;
    final limits = payload['limits'];
    int? read(Map source, String key) {
      final value = source[key];
      return value is int && value >= 0 ? value : null;
    }

    final ready = read(usage, 'readyCount');
    final readyBytes = read(usage, 'readyBytes');
    final pending = read(usage, 'pendingCount');
    final pendingBytes = read(usage, 'pendingBytes');
    if (ready == null ||
        readyBytes == null ||
        pending == null ||
        pendingBytes == null) {
      throw const ToolkitDocumentException(ToolkitFailure.invalidResponse);
    }
    return ToolkitDocumentUsage(
      readyCount: ready,
      readyBytes: readyBytes,
      pendingCount: pending,
      pendingBytes: pendingBytes,
      documentBytesLimit: limits is Map ? read(limits, 'documentBytes') : null,
      imageBytesLimit: limits is Map ? read(limits, 'imageBytes') : null,
      accountBytesLimit: limits is Map ? read(limits, 'accountBytes') : null,
      accountDocumentsLimit:
          limits is Map ? read(limits, 'accountDocuments') : null,
    );
  }

  /// Toolkit routes only: Profile, Offer and plan media keep `R2Config.workerUrl`.
  Uri _endpoint(String path) {
    final base = _address();
    if (base == null || base.isEmpty) {
      throw const ToolkitDocumentException(ToolkitFailure.notConfigured);
    }
    return Uri.parse('$base$path');
  }

  static String? _string(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  static int? _int(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    return null;
  }
}

/// Lets a file's byte stream be piped into a [StreamedRequest]'s sink and ends
/// the request body when the file ends.
class _SinkConsumer implements StreamConsumer<List<int>> {
  _SinkConsumer(this._sink);

  final EventSink<List<int>> _sink;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _sink.add(chunk);
    }
  }

  @override
  Future<void> close() async {
    _sink.close();
  }
}
