// The plan's upload and removal sequences: authorize, signed PUT, trusted
// confirm — in that order, under one stable upload id, and never reporting a
// plan as attached before the server confirmed it.

import 'dart:io';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_plan_transport.dart';

const _recordId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _draftId = '11111111-1111-4111-8111-111111111111';
const _otherId = '22222222-2222-4222-8222-222222222222';

Future<PlanAttachmentDraft> _draft({
  String id = _draftId,
  List<int> bytes = const [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37, 10],
  String contentType = PlanContentTypes.pdf,
  PlanAttachmentKind kind = PlanAttachmentKind.pdf,
  String? displayName = 'Plot 14 plan.pdf',
  int? declaredLength,
}) async {
  final dir = await Directory.systemTemp.createTemp('plan_workflow_test_');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}plan.bin');
  await file.writeAsBytes(bytes);
  return PlanAttachmentDraft(
    mediaObjectId: id,
    path: file.path,
    kind: kind,
    contentType: contentType,
    byteLength: declaredLength ?? bytes.length,
    displayName: displayName,
  );
}

Future<Object?> _caught(Future<void> Function() body) async {
  try {
    await body();
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  late FakePlanTransport transport;
  late PlanAttachmentWorkflow workflow;

  setUp(() {
    transport = FakePlanTransport();
    workflow = PlanAttachmentWorkflow(transport);
  });

  group('upload', () {
    test('authorizes, uploads, then confirms, under one stable upload id',
        () async {
      final draft = await _draft();
      final ref = await workflow.upload(
        parent: PlanParent.offer,
        parentId: _recordId,
        draft: draft,
        expectedMediaId: null,
      );

      expect(transport.calls, ['authorize', 'upload', 'confirm']);
      final authorize = transport.authorizeCalls.single;
      expect(authorize.parent, PlanParent.offer);
      expect(authorize.parentId, _recordId);
      expect(authorize.mediaObjectId, _draftId);
      expect(authorize.expectedMediaId, isNull);
      expect(authorize.contentType, PlanContentTypes.pdf);
      expect(authorize.contentLength, draft.byteLength);
      expect(authorize.originalFileName, 'Plot 14 plan.pdf');
      final confirm = transport.confirmCalls.single;
      expect(confirm.mediaObjectId, _draftId);
      expect(confirm.expectedMediaId, isNull);

      expect(ref.mediaObjectId, _draftId);
      expect(ref.kind, PlanAttachmentKind.pdf);
      expect(ref.displayName, 'Plot 14 plan.pdf');
      expect(ref.signedUrl, isNull, reason: 'no link is kept by an upload');
      expect(transport.current?.mediaObjectId, _draftId);
    });

    test('a replacement names the plan it replaces, for the server to check',
        () async {
      transport.current = const PlanAttachmentRef(
        mediaObjectId: _otherId,
        kind: PlanAttachmentKind.image,
        contentType: PlanContentTypes.jpeg,
      );
      await workflow.upload(
        parent: PlanParent.owner,
        parentId: _recordId,
        draft: await _draft(),
        expectedMediaId: _otherId,
      );
      expect(transport.authorizeCalls.single.expectedMediaId, _otherId);
      expect(transport.confirmCalls.single.expectedMediaId, _otherId);
      expect(transport.authorizeCalls.single.parent, PlanParent.owner);
      expect(transport.current?.mediaObjectId, _draftId);
    });

    test('an upload the server already holds is not sent again', () async {
      transport.alreadyReady = true;
      final ref = await workflow.upload(
        parent: PlanParent.offer,
        parentId: _recordId,
        draft: await _draft(),
        expectedMediaId: null,
      );
      expect(transport.calls, ['authorize']);
      expect(ref.mediaObjectId, _draftId);
    });

    test('a stale answer stops everything: nothing is uploaded or confirmed',
        () async {
      transport.current = const PlanAttachmentRef(
        mediaObjectId: _otherId,
        kind: PlanAttachmentKind.pdf,
        contentType: PlanContentTypes.pdf,
      );
      final draft = await _draft();
      final error = await _caught(() => workflow.upload(
            parent: PlanParent.offer,
            parentId: _recordId,
            draft: draft,
            expectedMediaId: null,
          ));
      expect(error, isA<PlanAttachmentException>());
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.staleReplacement);
      expect(transport.calls, ['authorize']);
      expect(transport.current?.mediaObjectId, _otherId,
          reason: 'the plan the record had is untouched');
    });

    test('a failed upload is never confirmed and leaves the old plan',
        () async {
      transport.current = const PlanAttachmentRef(
        mediaObjectId: _otherId,
        kind: PlanAttachmentKind.pdf,
        contentType: PlanContentTypes.pdf,
      );
      transport.uploadError =
          const PlanAttachmentException(PlanAttachmentFailure.interrupted);
      final error = await _caught(() async => workflow.upload(
            parent: PlanParent.offer,
            parentId: _recordId,
            draft: await _draft(),
            expectedMediaId: _otherId,
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.interrupted);
      expect(transport.calls, ['authorize', 'upload']);
      expect(transport.current?.mediaObjectId, _otherId);
    });

    test('a failed confirm leaves the old plan and can be retried safely',
        () async {
      transport.current = const PlanAttachmentRef(
        mediaObjectId: _otherId,
        kind: PlanAttachmentKind.pdf,
        contentType: PlanContentTypes.pdf,
      );
      final draft = await _draft();
      transport.confirmError =
          const PlanAttachmentException(PlanAttachmentFailure.unavailable);
      final error = await _caught(() => workflow.upload(
            parent: PlanParent.offer,
            parentId: _recordId,
            draft: draft,
            expectedMediaId: _otherId,
          ));
      expect(error, isA<PlanAttachmentException>());
      expect(transport.current?.mediaObjectId, _otherId);

      // The retry uses the same upload id, so nothing is ever duplicated.
      transport.confirmError = null;
      final ref = await workflow.upload(
        parent: PlanParent.offer,
        parentId: _recordId,
        draft: draft,
        expectedMediaId: _otherId,
      );
      expect(ref.mediaObjectId, _draftId);
      expect(
        transport.authorizeCalls.map((c) => c.mediaObjectId).toSet(),
        {_draftId},
      );
      expect(transport.current?.mediaObjectId, _draftId);
    });

    test('a file that is gone or changed since it was screened is never sent',
        () async {
      final changed = await _draft(declaredLength: 5000);
      final error = await _caught(() => workflow.upload(
            parent: PlanParent.offer,
            parentId: _recordId,
            draft: changed,
            expectedMediaId: null,
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.fileUnavailable);

      final gone = await _draft();
      await File(gone.path).delete();
      final missing = await _caught(() => workflow.upload(
            parent: PlanParent.offer,
            parentId: _recordId,
            draft: gone,
            expectedMediaId: null,
          ));
      expect((missing! as PlanAttachmentException).failure,
          PlanAttachmentFailure.fileUnavailable);
      expect(transport.calls, isEmpty);
    });
  });

  group('removal', () {
    test('removes the plan the caller believes is current', () async {
      transport.current = const PlanAttachmentRef(
        mediaObjectId: _otherId,
        kind: PlanAttachmentKind.pdf,
        contentType: PlanContentTypes.pdf,
      );
      await workflow.remove(
        parent: PlanParent.owner,
        parentId: _recordId,
        expectedMediaId: _otherId,
      );
      expect(transport.calls, ['remove']);
      expect(transport.removeCalls.single.parent, PlanParent.owner);
      expect(transport.removeCalls.single.expectedMediaId, _otherId);
      expect(transport.removeCalls.single.mediaObjectId, isNull);
      expect(transport.current, isNull);
    });

    test('a stale removal is refused and changes nothing', () async {
      transport.current = const PlanAttachmentRef(
        mediaObjectId: _otherId,
        kind: PlanAttachmentKind.pdf,
        contentType: PlanContentTypes.pdf,
      );
      final error = await _caught(() => workflow.remove(
            parent: PlanParent.offer,
            parentId: _recordId,
            expectedMediaId: _draftId,
          ));
      expect((error! as PlanAttachmentException).failure,
          PlanAttachmentFailure.staleReplacement);
      expect(transport.current?.mediaObjectId, _otherId);
    });

    test('withdrawing an unattached upload names it and never fails the caller',
        () async {
      await workflow.cancelCandidate(
        parent: PlanParent.offer,
        parentId: _recordId,
        expectedMediaId: null,
        mediaObjectId: _draftId,
      );
      expect(transport.calls, ['cancel']);
      expect(transport.removeCalls.single.mediaObjectId, _draftId);

      transport.removeError =
          const PlanAttachmentException(PlanAttachmentFailure.unavailable);
      await workflow.cancelCandidate(
        parent: PlanParent.offer,
        parentId: _recordId,
        expectedMediaId: null,
        mediaObjectId: _draftId,
      );
    });
  });
}
