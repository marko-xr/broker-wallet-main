// An in-memory stand-in for the Media Worker's plan routes: it models the
// server's single plan slot, so tests can drive the real workflow, controller,
// loader and file layer through authorize, upload, confirm, replace, remove,
// stale answers and failures without a network.

import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';

class AuthorizeCall {
  const AuthorizeCall({
    required this.parent,
    required this.parentId,
    required this.expectedMediaId,
    required this.mediaObjectId,
    required this.contentType,
    required this.contentLength,
    required this.originalFileName,
  });

  final PlanParent parent;
  final String parentId;
  final String? expectedMediaId;
  final String mediaObjectId;
  final String contentType;
  final int contentLength;
  final String? originalFileName;
}

class ConfirmCall {
  const ConfirmCall(
      this.parent, this.parentId, this.mediaObjectId, this.expectedMediaId);

  final PlanParent parent;
  final String parentId;
  final String mediaObjectId;
  final String? expectedMediaId;
}

class RemoveCall {
  const RemoveCall(
      this.parent, this.parentId, this.expectedMediaId, this.mediaObjectId);

  final PlanParent parent;
  final String parentId;
  final String? expectedMediaId;

  /// Set when an upload that was never attached is being withdrawn.
  final String? mediaObjectId;
}

class FakePlanTransport implements PlanAttachmentTransport {
  /// What the server holds for the record under test (its single plan slot).
  PlanAttachmentRef? current;

  /// Every call in order: `authorize`, `upload`, `confirm`, `remove`,
  /// `cancel` (a remove naming an upload), `fetch`, `download`.
  final List<String> calls = <String>[];
  final List<AuthorizeCall> authorizeCalls = <AuthorizeCall>[];
  final List<ConfirmCall> confirmCalls = <ConfirmCall>[];
  final List<RemoveCall> removeCalls = <RemoveCall>[];
  final List<String> downloadedUrls = <String>[];

  /// The size limit each `download` was given.
  final List<int> downloadLimits = <int>[];

  /// The record each `fetchCurrent` asked about.
  final List<(PlanParent, String)> fetched = <(PlanParent, String)>[];

  Object? authorizeError;
  Object? uploadError;
  Object? confirmError;
  Object? removeError;
  Object? fetchError;
  Object? downloadError;

  /// Answer authorize as already done (a retry whose confirm went through).
  bool alreadyReady = false;

  /// Refuse an operation whose expected media id is not the slot's, as the
  /// server's compare-and-swap does.
  bool enforceExpected = true;

  /// When set, `uploadBytes` waits for it: the change is then "in flight".
  Completer<void>? uploadGate;

  /// The bytes `download` writes.
  List<int> downloadBytes = <int>[];

  /// When the read link of [current] stops working.
  DateTime Function() linkExpiry =
      () => DateTime.now().add(const Duration(minutes: 15));

  final Map<String, AuthorizeCall> _candidates = <String, AuthorizeCall>{};

  void _checkExpected(String? expected) {
    if (enforceExpected && current?.mediaObjectId != expected) {
      throw const PlanAttachmentException(
        PlanAttachmentFailure.staleReplacement,
        statusCode: 409,
        workerCode: 'stale_replacement',
      );
    }
  }

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
    calls.add('authorize');
    final call = AuthorizeCall(
      parent: parent,
      parentId: parentId,
      expectedMediaId: expectedMediaId,
      mediaObjectId: mediaObjectId,
      contentType: contentType,
      contentLength: contentLength,
      originalFileName: originalFileName,
    );
    authorizeCalls.add(call);
    final error = authorizeError;
    if (error != null) throw error;
    if (alreadyReady || current?.mediaObjectId == mediaObjectId) {
      return PlanAuthorization.ready(mediaObjectId: mediaObjectId);
    }
    _checkExpected(expectedMediaId);
    _candidates[mediaObjectId] = call;
    return PlanAuthorization.pending(
      mediaObjectId: mediaObjectId,
      presignedUrl: 'https://upload.example.test/put?sig=secret-put',
    );
  }

  @override
  Future<void> uploadBytes({
    required String presignedUrl,
    required File file,
    required String contentType,
  }) async {
    calls.add('upload');
    final gate = uploadGate;
    if (gate != null) await gate.future;
    final error = uploadError;
    if (error != null) throw error;
  }

  @override
  Future<PlanConfirmation> confirm({
    required PlanParent parent,
    required String parentId,
    required String mediaObjectId,
    required String? expectedMediaId,
  }) async {
    calls.add('confirm');
    confirmCalls
        .add(ConfirmCall(parent, parentId, mediaObjectId, expectedMediaId));
    final error = confirmError;
    if (error != null) throw error;
    if (current?.mediaObjectId == mediaObjectId) {
      return const PlanConfirmation(alreadyConfirmed: true);
    }
    _checkExpected(expectedMediaId);
    final candidate = _candidates[mediaObjectId];
    final previous = current?.mediaObjectId;
    current = PlanAttachmentRef(
      mediaObjectId: mediaObjectId,
      kind: PlanAttachmentKind.fromContentType(candidate?.contentType) ??
          PlanAttachmentKind.pdf,
      contentType: candidate?.contentType ?? PlanContentTypes.pdf,
      displayName: candidate?.originalFileName,
      byteLength: candidate?.contentLength,
    );
    return PlanConfirmation(previousMediaId: previous);
  }

  @override
  Future<PlanRemoval> remove({
    required PlanParent parent,
    required String parentId,
    required String? expectedMediaId,
    String? mediaObjectId,
  }) async {
    calls.add(mediaObjectId == null ? 'remove' : 'cancel');
    removeCalls
        .add(RemoveCall(parent, parentId, expectedMediaId, mediaObjectId));
    final error = removeError;
    if (error != null) throw error;
    if (mediaObjectId != null) {
      _candidates.remove(mediaObjectId);
      return const PlanRemoval();
    }
    if (current == null) return const PlanRemoval(alreadyRemoved: true);
    _checkExpected(expectedMediaId);
    final previous = current!.mediaObjectId;
    current = null;
    return PlanRemoval(previousMediaId: previous);
  }

  @override
  Future<PlanAttachmentRef?> fetchCurrent({
    required PlanParent parent,
    required String parentId,
  }) async {
    calls.add('fetch');
    fetched.add((parent, parentId));
    final error = fetchError;
    if (error != null) throw error;
    final plan = current;
    if (plan == null) return null;
    return PlanAttachmentRef(
      mediaObjectId: plan.mediaObjectId,
      kind: plan.kind,
      contentType: plan.contentType,
      displayName: plan.displayName,
      byteLength: plan.byteLength,
      signedUrl: 'https://read.example.test/get?sig=secret-get',
      signedUrlExpiresAt: linkExpiry(),
    );
  }

  @override
  Future<void> download({
    required String url,
    required File target,
    required int maxBytes,
  }) async {
    calls.add('download');
    downloadedUrls.add(url);
    downloadLimits.add(maxBytes);
    final error = downloadError;
    if (error != null) throw error;
    await target.writeAsBytes(downloadBytes);
  }
}
