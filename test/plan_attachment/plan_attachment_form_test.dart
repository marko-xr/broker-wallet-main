// The plan section's controller: what the form shows and sends for a record's
// land / plot plan. Pure: a fake server slot, real screening and workflow.
//
// The promises under test: nothing reaches the server until the record itself
// was saved; a failed replacement leaves the plan the record already had; a
// failed upload never undoes the record and can be retried under the same
// upload id; removal is explicit; and cancelling mutates nothing hosted.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_selection.dart'
    show HeifToJpegConverter;
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_screening.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_workflow.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_plan_transport.dart';
import 'plan_bytes.dart';

const _recordId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _oldId = '99999999-9999-4999-8999-999999999999';
const _otherDeviceId = '88888888-8888-4888-8888-888888888888';

final List<int> _pdf = utf8.encode('%PDF-1.7\n1 0 obj\n%%EOF');
final List<int> _jpeg = [0xff, 0xd8, 0xff, ...List<int>.filled(61, 0)];
final List<int> _exe = [0x4d, 0x5a, ...List<int>.filled(62, 0)];

PlanAttachmentRef _serverPlan(String id, {String name = 'Old plan.pdf'}) =>
    PlanAttachmentRef(
      mediaObjectId: id,
      kind: PlanAttachmentKind.pdf,
      contentType: PlanContentTypes.pdf,
      displayName: name,
      byteLength: 2048,
    );

/// Waits for [condition] (real time, up to five seconds): the controller reads
/// the chosen file from disk, which takes more than one turn of the event loop.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for the condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Rig {
  _Rig({this.parent = PlanParent.offer}) {
    controller = PlanAttachmentFormController(
      parent: parent,
      transport: transport,
      workflow: PlanAttachmentWorkflow(transport),
      screen: (file, {displayName}) => screenPlanFile(
        file,
        displayName: displayName,
        newMediaObjectId: () =>
            'bbbbbbbb-bbbb-4bbb-8bbb-${(++_ids).toString().padLeft(12, '0')}',
      ),
      onChanged: () => changes += 1,
    );
    addTearDown(controller.dispose);
  }

  final PlanParent parent;
  final FakePlanTransport transport = FakePlanTransport();
  late final PlanAttachmentFormController controller;
  int changes = 0;
  int _ids = 0;

  Future<File> file(String name, List<int> bytes) async {
    final dir = await Directory.systemTemp.createTemp('plan_form_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Picks [name]/[bytes] and returns the draft's upload id.
  Future<String> pick(String name, List<int> bytes) async {
    final rejection = await controller.addPicked(
      await file(name, bytes),
      displayName: name,
    );
    expect(rejection, isNull, reason: 'the pick of $name was refused');
    return 'bbbbbbbb-bbbb-4bbb-8bbb-${_ids.toString().padLeft(12, '0')}';
  }
}

void main() {
  group('a new record', () {
    test(
        'choosing a file changes nothing on the server until the record is saved',
        () async {
      final rig = _Rig();
      rig.controller.start();
      expect(rig.controller.view.display, PlanDisplay.none);
      expect(rig.controller.hasPlan, isFalse);
      expect(rig.controller.hasPendingChange, isFalse);

      await rig.pick('Plot 14 plan.pdf', _pdf);

      final view = rig.controller.view;
      expect(view.display, PlanDisplay.draft);
      expect(view.kind, PlanAttachmentKind.pdf);
      expect(view.displayName, 'Plot 14 plan.pdf');
      expect(view.byteLength, _pdf.length);
      expect(view.hasServerPlan, isFalse);
      expect(rig.controller.hasPlan, isTrue,
          reason: 'a chosen plan counts as the record\'s content');
      expect(rig.controller.hasPendingChange, isTrue);
      expect(rig.transport.calls, isEmpty);
      expect(rig.changes, greaterThan(0));
    });

    test('Save sends it after the record: authorize, upload, confirm',
        () async {
      final rig = _Rig();
      rig.controller.start();
      final id = await rig.pick('plan.pdf', _pdf);

      final outcome = await rig.controller.commit(recordId: _recordId);

      expect(outcome.status, PlanCommitStatus.done);
      expect(outcome.isComplete, isTrue);
      expect(rig.transport.calls, ['authorize', 'upload', 'confirm'],
          reason: 'a new record has no plan to look up first');
      expect(rig.transport.authorizeCalls.single.mediaObjectId, id);
      expect(rig.transport.authorizeCalls.single.parent, PlanParent.offer);
      expect(rig.transport.authorizeCalls.single.parentId, _recordId);
      expect(rig.transport.current?.mediaObjectId, id);
      expect(rig.controller.view.display, PlanDisplay.existing);
      expect(rig.controller.hasPendingChange, isFalse);
      expect(rig.controller.isWorking, isFalse);
    });

    test('with nothing chosen Save has nothing to send', () async {
      final rig = _Rig();
      rig.controller.start();
      final outcome = await rig.controller.commit(recordId: _recordId);
      expect(outcome.status, PlanCommitStatus.nothing);
      expect(outcome.isComplete, isTrue);
      expect(rig.transport.calls, isEmpty);
    });

    test('an Owner\'s plan goes through the Owner routes', () async {
      final rig = _Rig(parent: PlanParent.owner);
      rig.controller.start();
      await rig.pick('plan.pdf', _pdf);
      await rig.controller.commit(recordId: _recordId);
      expect(rig.transport.authorizeCalls.single.parent, PlanParent.owner);
      expect(rig.transport.confirmCalls.single.parent, PlanParent.owner);
    });

    test(
        'a failed upload keeps the file, never undoes the record and retries under the same id',
        () async {
      final rig = _Rig();
      rig.controller.start();
      final id = await rig.pick('plan.pdf', _pdf);
      rig.transport.authorizeError =
          const PlanAttachmentException(PlanAttachmentFailure.unavailable);

      final failed = await rig.controller.commit(recordId: _recordId);

      expect(failed.status, PlanCommitStatus.failed);
      expect(failed.isComplete, isFalse);
      expect(failed.failure, PlanAttachmentFailure.unavailable);
      final view = rig.controller.view;
      expect(view.display, PlanDisplay.failed);
      expect(view.failure, PlanAttachmentFailure.unavailable);
      expect(view.displayName, 'plan.pdf', reason: 'the chosen file is kept');
      expect(rig.controller.hasPlan, isTrue);
      expect(rig.controller.isWorking, isFalse);
      expect(rig.transport.current, isNull);

      rig.transport.authorizeError = null;
      final retried = await rig.controller.retry();
      expect(retried.status, PlanCommitStatus.done);
      expect(
        rig.transport.authorizeCalls.map((call) => call.mediaObjectId).toSet(),
        {id},
        reason: 'one upload id for the whole life of the choice',
      );
      expect(rig.transport.current?.mediaObjectId, id);
      expect(rig.controller.view.display, PlanDisplay.existing);
    });

    test(
        'while a change is being sent the section shows it and refuses a second one',
        () async {
      final rig = _Rig();
      rig.controller.start();
      await rig.pick('plan.pdf', _pdf);
      rig.transport.uploadGate = Completer<void>();

      final first = rig.controller.commit(recordId: _recordId);
      await _until(() => rig.transport.calls.contains('upload'));
      expect(rig.controller.isWorking, isTrue);
      expect(rig.controller.view.display, PlanDisplay.working);
      expect(rig.controller.view.isRemoval, isFalse);

      // A second Save is answered at once; it must never start another upload
      // (which, with the first still in flight, would only hang here).
      final second = await rig.controller.commit(recordId: _recordId).timeout(
          const Duration(seconds: 2),
          onTimeout: () => const PlanCommitOutcome.nothing());
      expect(second.status, PlanCommitStatus.failed);
      expect(rig.transport.authorizeCalls, hasLength(1));

      // Nothing can be picked or removed while it is in flight.
      expect(await rig.controller.addPicked(await rig.file('b.pdf', _pdf)),
          isNull);
      rig.controller.removeSelection();
      expect(rig.controller.view.display, PlanDisplay.working);

      rig.transport.uploadGate!.complete();
      expect((await first).status, PlanCommitStatus.done);
      expect(rig.controller.view.display, PlanDisplay.existing);
    });
  });

  group('editing a record that has a plan', () {
    test('shows the server\'s plan as soon as it is read', () async {
      final rig = _Rig();
      rig.transport.current = _serverPlan(_oldId);
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();

      final view = rig.controller.view;
      expect(view.display, PlanDisplay.existing);
      expect(view.displayName, 'Old plan.pdf');
      expect(view.kind, PlanAttachmentKind.pdf);
      expect(view.hasServerPlan, isTrue);
      expect(rig.controller.hasPlan, isTrue);
      expect(rig.controller.hasPendingChange, isFalse);
      expect(rig.transport.calls, ['fetch']);
    });

    test(
        'a replacement waits for Save and the old plan stays until it is confirmed',
        () async {
      final rig = _Rig();
      rig.transport.current = _serverPlan(_oldId);
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();
      final id = await rig.pick('new plan.jpg', _jpeg);

      final view = rig.controller.view;
      expect(view.display, PlanDisplay.replacing);
      expect(view.hasServerPlan, isTrue);
      expect(view.kind, PlanAttachmentKind.image);
      expect(view.localPath, isNotNull);
      expect(rig.transport.current?.mediaObjectId, _oldId,
          reason: 'choosing never touches the server');

      final outcome = await rig.controller.commit(recordId: _recordId);
      expect(outcome.status, PlanCommitStatus.done);
      expect(rig.transport.authorizeCalls.single.expectedMediaId, _oldId);
      expect(rig.transport.confirmCalls.single.expectedMediaId, _oldId);
      expect(rig.transport.current?.mediaObjectId, id);
      expect(rig.controller.view.display, PlanDisplay.existing);
      expect(rig.controller.view.displayName, 'new plan.jpg');
    });

    test(
        'a failed replacement leaves the old plan, and discarding it brings the old plan back',
        () async {
      final rig = _Rig();
      rig.transport.current = _serverPlan(_oldId);
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();
      final id = await rig.pick('new.jpg', _jpeg);
      rig.transport.uploadError =
          const PlanAttachmentException(PlanAttachmentFailure.interrupted);

      final failed = await rig.controller.commit(recordId: _recordId);

      expect(failed.status, PlanCommitStatus.failed);
      expect(rig.controller.view.display, PlanDisplay.failed);
      expect(rig.controller.view.hasServerPlan, isTrue);
      expect(rig.transport.current?.mediaObjectId, _oldId,
          reason: 'the plan the record had is untouched');
      expect(rig.transport.calls, isNot(contains('remove')));

      // The user gives up on the new file: the old plan is what shows again,
      // and the half-sent upload is withdrawn so it holds no place.
      rig.controller.removeSelection();
      await pumpEventQueue();
      expect(rig.controller.view.display, PlanDisplay.existing);
      expect(rig.controller.view.displayName, 'Old plan.pdf');
      expect(rig.controller.view.failure, isNull);
      expect(rig.transport.calls, contains('cancel'));
      expect(rig.transport.removeCalls.last.mediaObjectId, id);
      expect(rig.transport.current?.mediaObjectId, _oldId);
    });

    test(
        'choosing another file replaces the first choice and withdraws what was sent',
        () async {
      final rig = _Rig();
      rig.controller.start();
      final first = await rig.pick('first.pdf', _pdf);
      rig.transport.authorizeError =
          const PlanAttachmentException(PlanAttachmentFailure.unavailable);
      await rig.controller.commit(recordId: _recordId);
      rig.transport.authorizeError = null;

      final second = await rig.pick('second.jpg', _jpeg);
      await pumpEventQueue();

      expect(second, isNot(first));
      expect(rig.controller.view.displayName, 'second.jpg');
      expect(rig.controller.view.display, PlanDisplay.draft);
      expect(rig.controller.view.failure, isNull);
      expect(rig.transport.removeCalls.single.mediaObjectId, first);
    });
  });

  group('removing', () {
    test('is marked, taken back, and only sent when the record is saved',
        () async {
      final rig = _Rig();
      rig.transport.current = _serverPlan(_oldId);
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();

      rig.controller.removeSelection();
      expect(rig.controller.view.display, PlanDisplay.removalPending);
      expect(rig.controller.hasPlan, isFalse);
      expect(rig.controller.hasPendingChange, isTrue);
      expect(rig.transport.current?.mediaObjectId, _oldId);

      rig.controller.keepExisting();
      expect(rig.controller.view.display, PlanDisplay.existing);
      expect(rig.controller.hasPlan, isTrue);
      expect(rig.controller.hasPendingChange, isFalse);

      rig.controller.removeSelection();
      final outcome = await rig.controller.commit(recordId: _recordId);
      expect(outcome.status, PlanCommitStatus.done);
      expect(rig.transport.calls, ['fetch', 'remove']);
      expect(rig.transport.removeCalls.single.expectedMediaId, _oldId);
      expect(rig.transport.current, isNull);
      expect(rig.controller.view.display, PlanDisplay.none);
    });

    test('a failed removal is reported as one and leaves the plan', () async {
      final rig = _Rig();
      rig.transport.current = _serverPlan(_oldId);
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();
      rig.controller.removeSelection();
      rig.transport.removeError =
          const PlanAttachmentException(PlanAttachmentFailure.unavailable);

      final failed = await rig.controller.commit(recordId: _recordId);

      expect(failed.status, PlanCommitStatus.failed);
      expect(rig.controller.view.display, PlanDisplay.failed);
      expect(rig.controller.view.isRemoval, isTrue);
      expect(rig.transport.current?.mediaObjectId, _oldId);

      rig.controller.keepExisting();
      expect(rig.controller.view.display, PlanDisplay.existing);
      expect(rig.controller.view.failure, isNull);
    });

    test('removing a chosen file drops it at once and never touches the server',
        () async {
      final rig = _Rig();
      rig.controller.start();
      await rig.pick('plan.pdf', _pdf);
      rig.controller.removeSelection();
      await pumpEventQueue();
      expect(rig.controller.view.display, PlanDisplay.none);
      expect(rig.controller.hasPlan, isFalse);
      expect(rig.transport.calls, isEmpty,
          reason: 'it was never sent, so there is nothing to withdraw');
    });
  });

  group('screening', () {
    test('a file that is not a plan is refused and changes nothing', () async {
      final rig = _Rig();
      rig.controller.start();
      final rejection = await rig.controller
          .addPicked(await rig.file('plan.pdf', _exe), displayName: 'plan.pdf');
      expect(rejection, PlanAttachmentRejection.unsupportedType);
      expect(rig.controller.view.display, PlanDisplay.none);
      expect(rig.controller.hasPlan, isFalse);

      // A refused file does not displace one already chosen.
      await rig.pick('good.pdf', _pdf);
      final second = await rig.controller
          .addPicked(await rig.file('bad.docx', _pdf), displayName: 'bad.docx');
      expect(second, PlanAttachmentRejection.unsupportedType);
      expect(rig.controller.view.displayName, 'good.pdf');
    });
  });

  group('the record changed on another device', () {
    test(
        'a stale replacement is refused, shows what the plan is now, and retries against it',
        () async {
      final rig = _Rig();
      rig.transport.current = _serverPlan(_oldId);
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();
      final id = await rig.pick('mine.jpg', _jpeg);
      // Meanwhile another device replaced the plan.
      rig.transport.current =
          _serverPlan(_otherDeviceId, name: 'Their plan.pdf');

      final failed = await rig.controller.commit(recordId: _recordId);
      expect(failed.failure, PlanAttachmentFailure.staleReplacement);
      expect(rig.transport.current?.mediaObjectId, _otherDeviceId,
          reason: 'the newer plan was not overwritten');
      await pumpEventQueue();
      expect(rig.controller.view.hasServerPlan, isTrue);

      final retried = await rig.controller.retry();
      expect(retried.status, PlanCommitStatus.done);
      expect(rig.transport.authorizeCalls.last.expectedMediaId, _otherDeviceId,
          reason: 'the retry names the plan as it is now');
      expect(rig.transport.current?.mediaObjectId, id);
    });
  });

  group('when the plan cannot be read', () {
    test(
        'Save never guesses what the plan is: it looks first, and waits if it cannot',
        () async {
      final rig = _Rig();
      rig.transport.current = _serverPlan(_oldId);
      rig.transport.fetchError =
          const PlanAttachmentException(PlanAttachmentFailure.unavailable);
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();
      expect(rig.controller.view.display, PlanDisplay.none,
          reason: 'nothing is invented while the read fails');
      await rig.pick('mine.jpg', _jpeg);

      final failed = await rig.controller.commit(recordId: _recordId);
      expect(failed.failure, PlanAttachmentFailure.unavailable);
      expect(rig.transport.calls, isNot(contains('authorize')));
      expect(rig.transport.current?.mediaObjectId, _oldId);

      rig.transport.fetchError = null;
      final retried = await rig.controller.retry();
      expect(retried.status, PlanCommitStatus.done);
      expect(rig.transport.authorizeCalls.single.expectedMediaId, _oldId);
    });
  });

  group('leaving the form', () {
    test('cancelling with a file that was never sent touches nothing hosted',
        () async {
      final rig = _Rig();
      rig.controller.start(editRecordId: _recordId);
      await pumpEventQueue();
      await rig.pick('plan.pdf', _pdf);
      final callsBefore = List<String>.of(rig.transport.calls);

      rig.controller.dispose();
      await pumpEventQueue();

      expect(rig.transport.calls, callsBefore);
      expect(rig.transport.current, isNull);
    });

    test('closing after a failed upload withdraws the half-sent upload',
        () async {
      final rig = _Rig();
      rig.controller.start();
      final id = await rig.pick('plan.pdf', _pdf);
      rig.transport.uploadError =
          const PlanAttachmentException(PlanAttachmentFailure.interrupted);
      await rig.controller.commit(recordId: _recordId);

      rig.controller.dispose();
      await pumpEventQueue();

      expect(rig.transport.removeCalls.single.mediaObjectId, id);
      expect(rig.transport.current, isNull);
    });

    test('a controller that was closed ignores everything afterwards',
        () async {
      final rig = _Rig();
      rig.controller.start();
      rig.controller.dispose();
      final changesBefore = rig.changes;
      expect(await rig.controller.addPicked(await rig.file('p.pdf', _pdf)),
          isNull);
      expect((await rig.controller.commit(recordId: _recordId)).status,
          PlanCommitStatus.nothing);
      rig.controller.removeSelection();
      expect(rig.changes, changesBefore);
    });
  });

  group('the standard wiring', () {
    test(
        'a HEIC photo is converted by the gallery\'s own converter, which the '
        'plan reaches through its production method', () async {
      final original = HeifToJpegConverter.convert;
      addTearDown(() => HeifToJpegConverter.convert = original);
      final area = PlanTempDir();
      addTearDown(area.dispose);
      final heic = area.write('IMG_0001.heic', planHeicBytes(2000));
      final jpeg = area.write('converted.jpg', planJpegBytes(1500));
      final converted = <String>[];
      HeifToJpegConverter.convert = (source) async {
        converted.add(source.path);
        return jpeg;
      };
      final controller = createPlanAttachmentForm(
        parent: PlanParent.offer,
        onChanged: () {},
        transport: FakePlanTransport(),
      );
      addTearDown(controller.dispose);

      expect(await controller.addPicked(heic, displayName: 'IMG_0001.heic'),
          isNull);

      expect(converted, [heic.path]);
      final view = controller.view;
      expect(view.display, PlanDisplay.draft);
      expect(view.kind, PlanAttachmentKind.image);
      expect(view.localPath, jpeg.path,
          reason: 'the JPEG is what would be sent, not the HEIC');
      expect(view.displayName, 'IMG_0001.heic');
      expect(heic.existsSync(), isTrue,
          reason: 'the original is never touched');
    });
  });
}
