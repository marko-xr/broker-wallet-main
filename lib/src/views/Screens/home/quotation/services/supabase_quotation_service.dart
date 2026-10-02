// Supabase adapter for the Quotation aggregate.
//
// Writes go through the hosted RPC `public.save_quotation`, the only path that
// may change a Quotation's header or children: it is atomic, owner-only and
// version-checked. Children are never written directly, and the media ids,
// owner, version and timestamps are never sent: the server owns them.
// Reads run with the current user's session, so RLS is the ownership boundary.
// Deleting is the soft `deleted_at` path; hard delete is not granted.

import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_supabase_mapper.dart';
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a Quotation operation failed. A fixed category: never SQL, provider
/// text or user content.
enum QuotationFailure {
  /// No active Supabase session.
  notSignedIn,

  /// The Quotation does not exist or is not this account's (PQT02).
  notFound,

  /// The Quotation was deleted and can no longer change (PQT03).
  deleted,

  /// The server holds a newer version than the one being saved (PQT04).
  versionConflict,

  /// The server refused the data (PQT05) — a value outside its limits.
  invalidPayload,

  /// The id already belongs to a different Quotation (PQT06).
  idConflict,

  /// The session may not do this (RLS / permission).
  permissionDenied,

  /// The connection failed or timed out.
  network,

  /// Anything else.
  unknown,
}

class QuotationException implements Exception {
  const QuotationException(this.failure);

  final QuotationFailure failure;

  @override
  String toString() => 'QuotationException(${failure.name})';
}

/// What `save_quotation` answered.
class QuotationSaveResult {
  const QuotationSaveResult({
    required this.quotationId,
    required this.version,
    required this.outcome,
  });

  final String quotationId;

  /// The server's version after the save.
  final int version;

  /// 'created', 'updated' or 'replayed' (an identical create repeated).
  final String outcome;
}

/// The identity of a Quotation's bound media and its version.
class QuotationMediaState {
  const QuotationMediaState({
    required this.version,
    this.officeLogoMediaId,
    this.pdfMediaId,
  });

  final int version;
  final String? officeLogoMediaId;
  final String? pdfMediaId;
}

/// The reads and writes the Quotation feature needs from the backend. A seam
/// so the service layer can be exercised without a network.
abstract interface class QuotationRemote {
  Future<QuotationSaveResult> save(
    QuotationModel quotation, {
    required String quotationId,
    int? expectedVersion,
  });

  Future<QuotationModel?> getQuotation(String quotationId);

  Future<QuotationMediaState?> getMediaState(String quotationId);

  /// The file name the account gave a bound media object, or null.
  Future<String?> getMediaFileName(String mediaId);

  Future<List<QuotationModel>> listQuotations();

  Stream<List<QuotationModel>> watchQuotations();

  Future<void> softDelete(String quotationId);
}

class SupabaseQuotationService implements QuotationRemote {
  SupabaseQuotationService({SupabaseClient? client}) : _customClient = client;

  final SupabaseClient? _customClient;

  /// Resolved on use, so constructing this never touches Supabase before it
  /// is initialized.
  SupabaseClient get _client => _customClient ?? Supabase.instance.client;

  void _requireSession() {
    final user = _client.auth.currentUser;
    if (user == null || user.id.isEmpty) {
      throw const QuotationException(QuotationFailure.notSignedIn);
    }
  }

  @override
  Future<QuotationSaveResult> save(
    QuotationModel quotation, {
    required String quotationId,
    int? expectedVersion,
  }) async {
    _requireSession();
    // May throw QuotationValidationException before any request is made.
    final payload = QuotationSupabaseMapper.toSavePayload(
      quotation,
      quotationId: quotationId,
      expectedVersion: expectedVersion,
    );
    try {
      final result = await _client.rpc(
        'save_quotation',
        params: payload.toRpcParams(),
      );
      final row = _firstRow(result);
      final id = row?['quotation_id']?.toString();
      final version = _asInt(row?['resulting_version']);
      if (row == null || id == null || version == null) {
        throw const QuotationException(QuotationFailure.unknown);
      }
      return QuotationSaveResult(
        quotationId: id,
        version: version,
        outcome: row['outcome']?.toString() ?? '',
      );
    } on QuotationException {
      rethrow;
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<QuotationModel?> getQuotation(String quotationId) async {
    _requireSession();
    try {
      final row = await _client
          .from('quotations')
          .select(QuotationSupabaseMapper.aggregateColumns)
          .eq('id', quotationId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return QuotationSupabaseMapper.aggregateFromRow(row);
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<QuotationMediaState?> getMediaState(String quotationId) async {
    _requireSession();
    try {
      final row = await _client
          .from('quotations')
          .select('version,office_logo_media_id,pdf_media_id')
          .eq('id', quotationId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      final version = _asInt(row['version']);
      if (version == null) return null;
      return QuotationMediaState(
        version: version,
        officeLogoMediaId: row['office_logo_media_id']?.toString(),
        pdfMediaId: row['pdf_media_id']?.toString(),
      );
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<String?> getMediaFileName(String mediaId) async {
    _requireSession();
    try {
      final row = await _client
          .from('media_objects')
          .select('original_file_name')
          .eq('id', mediaId)
          .maybeSingle();
      final name = row?['original_file_name']?.toString();
      return name == null || name.isEmpty ? null : name;
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<List<QuotationModel>> listQuotations() async {
    _requireSession();
    try {
      final rows = await _client
          .from('quotations')
          .select(QuotationSupabaseMapper.listColumns)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return rows
          .map((row) =>
              QuotationSupabaseMapper.headerFromRow(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } catch (error) {
      throw _translate(error);
    }
  }

  /// The rows now, then again after every core-entity mutation in this
  /// process (create, update, media change, delete). A failed re-read is
  /// delivered as an error event and the stream keeps listening; a failed
  /// first read ends the stream. Reads run one at a time.
  @override
  Stream<List<QuotationModel>> watchQuotations() {
    late final StreamController<List<QuotationModel>> controller;
    StreamSubscription<void>? mutations;
    var reading = false;
    var readAgain = false;
    var delivered = false;

    Future<void>? stopListening() {
      final subscription = mutations;
      mutations = null;
      return subscription?.cancel();
    }

    Future<void> read() async {
      if (reading) {
        readAgain = true;
        return;
      }
      reading = true;
      do {
        readAgain = false;
        try {
          final rows = await listQuotations();
          if (!controller.hasListener) return;
          delivered = true;
          controller.add(rows);
        } catch (error, stackTrace) {
          if (!controller.hasListener) return;
          controller.addError(error, stackTrace);
          if (!delivered) {
            unawaited(stopListening());
            unawaited(controller.close());
            return;
          }
        }
      } while (readAgain);
      reading = false;
    }

    controller = StreamController<List<QuotationModel>>(
      onListen: () {
        mutations =
            CoreEntityMutationNotifier.changes.listen((_) => unawaited(read()));
        unawaited(read());
      },
      onCancel: stopListening,
    );
    return controller.stream;
  }

  @override
  Future<void> softDelete(String quotationId) async {
    _requireSession();
    try {
      // The only column a client may change; the row's own live-row policy
      // decides whether this account may. Already deleted is a success.
      await _client
          .from('quotations')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', quotationId)
          .isFilter('deleted_at', null)
          .select('id');
    } catch (error) {
      throw _translate(error);
    }
  }

  // -------------------------------------------------------------------------
  // Errors
  // -------------------------------------------------------------------------

  /// The category a backend error stands for.
  static QuotationException translate(Object error) => _translate(error);

  static QuotationException _translate(Object error) {
    if (error is QuotationException) return error;
    if (error is PostgrestException) {
      switch (error.code) {
        case 'PQT01':
          return const QuotationException(QuotationFailure.notSignedIn);
        case 'PQT02':
          return const QuotationException(QuotationFailure.notFound);
        case 'PQT03':
          return const QuotationException(QuotationFailure.deleted);
        case 'PQT04':
          return const QuotationException(QuotationFailure.versionConflict);
        case 'PQT05':
          return const QuotationException(QuotationFailure.invalidPayload);
        case 'PQT06':
          return const QuotationException(QuotationFailure.idConflict);
        case '42501':
          return const QuotationException(QuotationFailure.permissionDenied);
      }
      return const QuotationException(QuotationFailure.unknown);
    }
    if (error is AuthException) {
      return const QuotationException(QuotationFailure.notSignedIn);
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error.runtimeType.toString().contains('ClientException')) {
      return const QuotationException(QuotationFailure.network);
    }
    return const QuotationException(QuotationFailure.unknown);
  }

  static Map<String, dynamic>? _firstRow(Object? result) {
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
